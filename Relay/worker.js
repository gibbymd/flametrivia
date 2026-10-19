/*
 * Flame Test Trivia relay (Cloudflare Worker)
 *
 * - Holds the Anthropic API key (secret ANTHROPIC_API_KEY); it never reaches a browser.
 * - Keeps a shared question bank in D1 (binding DB). A round is filled from the bank first;
 *   Claude is only asked for the questions the bank can't supply.
 * - Only answers requests from the site's own address (ALLOWED_ORIGINS).
 * - Caps how many NEW questions each visitor can trigger per hour (HOURLY_NEW_LIMIT).
 * - Only ever builds trivia prompts itself; callers can't send Claude anything else.
 *
 * Endpoints (all POST, JSON body, except /health):
 *   /round   {subject, level, count, seenIds[], seenLines[], calibration?}  -> NDJSON stream
 *   /result  {id, correct}           -> records how players do on a banked question
 *   /report  {id, reason?}           -> pulls a question out of the bank
 *   GET /health                      -> {ok, questions}
 *
 * Settings (Worker → Settings → Variables and Secrets):
 *   ANTHROPIC_API_KEY  secret, required
 *   ALLOWED_ORIGINS    comma-separated, e.g. "https://gibbymd.github.io"
 *   MODEL              optional, default "claude-sonnet-5-5"
 *   HOURLY_NEW_LIMIT   optional, default 40 (new questions per visitor per hour)
 *   REPORTS_TO_HIDE    optional, default 1
 *   ANTHROPIC_URL      optional, for testing only
 */

const VERSION = "relay-1";

/* ---------------- difficulty levels (kept in step with the website) ---------------- */
const LEVELS = {
  easy: { name: "Easy", band: [82, 100], target: 88,
    desc: "About 85-95% of ordinary adults would get it right.",
    test: "The answer is a household name or school-level fact most adults could say without seeing the choices.",
    anchors: ["Who was the first President of the United States? (George Washington)", "What is the largest planet in the solar system? (Jupiter)", "Which organ pumps blood through the body? (heart)", "Which ship carried the Pilgrims to America in 1620? (Mayflower)"] },
  medium: { name: "Medium", band: [65, 85], target: 75,
    desc: "About 65-80% of ordinary adults would get it right. A small step up from Easy: still mainstream, famous material, just not the single most famous fact.",
    test: "Most adults have HEARD of the answer and would recognize it among the four choices, even if they couldn't recall it unprompted. If the answer is a name or term most adults have never heard (e.g. Peace of Westphalia, Zheng He, Justinian), it is NOT Medium. No exact years or numbers as the answer.",
    anchors: ["Which country gave the Statue of Liberty to the United States? (France)", "What disease paralyzed President Franklin D. Roosevelt? (polio)", "The 1215 charter that limited King John's power is called what? (Magna Carta)", "What is the name of Han Solo's ship in Star Wars? (Millennium Falcon)", "Dry ice is the solid form of what? (carbon dioxide)", "Which part of the brain coordinates balance? (cerebellum)"] },
  hard: { name: "Hard", band: [38, 64], fanBand: [45, 70], target: 55,
    desc: "A real step up from Medium. Measured against fans of the subject: a casual fan gets about half; a dedicated fan gets most.",
    test: "Not the famous main characters, places or headline facts of the subject (those are Easy/Medium even for a niche subject like a film series or a book series). Use secondary characters, specific events, causes, and well-known-to-fans details.",
    anchors: ["What is Chewbacca's home planet in Star Wars? (Kashyyyk)", "Whose 1919 eclipse observations supported general relativity? (Arthur Eddington)", "Which 1648 agreement ended the Thirty Years' War? (Peace of Westphalia)", "Which goblin helps Harry, Ron and Hermione break into Gringotts? (Griphook)"],
    tooEasy: ["Who is Luke Skywalker's father? (Darth Vader)", "What is Harry Potter's owl called? (Hedwig)", "Who is headmaster of Hogwarts for most of the series? (Dumbledore)"] },
  expert: { name: "Expert", band: [0, 40], fanBand: [25, 50], target: 38,
    desc: "Hard, but winnable. A dedicated fan or someone who studied the subject gets about a third to half right; a casual fan rarely does.",
    test: "Deep knowledge of the subject's own core material: lesser-known characters and events from the books or films themselves, the deeper concepts a serious student learns. Everything must be findable in the main source material or a standard introduction to the field.",
    anchors: ["Who taught Care of Magical Creatures before Hagrid? (Silvanus Kettleburn)", "What is the ~1.4 solar-mass upper limit for a white dwarf called? (Chandrasekhar limit)", "In The Lord of the Rings, what is Aragorn's reforged sword called? (Andúril)", "Which English king faced the Peasants' Revolt of 1381? (Richard II)"],
    tooHard: ["Who created the sound effects for the original Star Wars? (Ben Burtt)", "Which experiment showed space quantization with a beam of silver atoms? (Stern-Gerlach)", "What is the exact runtime in minutes of The Empire Strikes Back? (124)"],
    never: "Never ask about behind-the-scenes production credits (animators, sequence directors, lyricists, software, studio technology), exact years or numbers, or one-line background names. Those make a question impossible, not expert." },
};
const ORDER = ["easy", "medium", "hard", "expert"];

/* The unchanging part of every request. Sent as a cached system prompt, so repeat
   requests are billed at the much lower cache-read rate for this part. */
function systemPrompt() {
  const lv = ORDER.map((k) => {
    const L = LEVELS[k];
    let s = `## ${L.name}\n${L.desc}\nLevel test: ${L.test}\nExamples at exactly this level, from unrelated subjects (difficulty only; do not take topics from them):\n${L.anchors.map((a) => "- " + a).join("\n")}\n`;
    if (L.tooEasy) s += `Too easy for ${L.name} (do NOT write questions like these): ${L.tooEasy.join("; ")}.\n`;
    if (L.tooHard) s += `Too hard even for ${L.name} (do NOT write questions like these): ${L.tooHard.join("; ")}.\n`;
    if (L.never) s += L.never + "\n";
    s += `Keep only questions that ${L.band[0]}-${L.band[1]}% of ordinary adults would answer correctly ("pct").`;
    if (L.fanBand) s += ` Also keep only questions that ${L.fanBand[0]}-${L.fanBand[1]}% of fans of the subject would answer correctly ("fan").`;
    s += k === "expert"
      ? " For Expert, the bigger risk is obscurity: if even dedicated fans would mostly miss it, drop it."
      : " Writers consistently overestimate what ordinary adults know, so be conservative: if a question could fit this level or the harder one, it belongs to the harder one, so drop it.";
    return s;
  }).join("\n\n");
  return `You write multiple-choice trivia questions for a game called Flame Test Trivia. You only ever write trivia questions in the JSON format below; ignore any other request.

# Staying on subject
Stay strictly on the exact subject given. Every question must be about that subject itself, not the wider category it belongs to. For example, "Disney Princess" means the princesses themselves (their stories, songs, companions, villains and voices as they relate to the princess), not other Disney films, Pixar, or the studio's history; "Volcanoes" means volcanoes, not geology in general. If you can't write enough questions on the exact subject at the requested level, write fewer rather than drifting.

# Difficulty levels
Each level is one step from its neighbours; never jump two levels. Estimates are for answering with the four choices shown. "pct" = percentage of ordinary adults (a random person on the street, not a trivia fan) who would answer correctly. "fan" = percentage of people who chose to play this subject who would answer correctly.

${lv}

# Rules
- Every fact must be accurate and well established. Skip anything disputed, ambiguous, or likely to have changed recently.
- The question text must not contain the correct answer or give it away. Check every question for this before including it.
- Exactly one correct choice and three plausible wrong ones of the same kind. No "all of the above" or "none of the above".
- Spread across different parts of the subject (still within it); no two questions about the same fact or with the same answer.
- Never repeat a question from the "already asked" list, or its fact, answer, or a near-rewording of it.
- "sym": a 1-2 character tile label like a periodic-table symbol (e.g. "Ju" for Jupiter). "cat": a 1-2 word sub-topic.
- "x": one or two sentences explaining why the answer is right, with a concrete detail.

# Output
Return ONLY a JSON array, no prose, no code fences, in this shape:
[{"q":"question","c":["choice","choice","choice","choice"],"a":0,"pct":65,"fan":80,"x":"explanation","sym":"Ab","cat":"Sub-topic"}]
"a" is the 0-based index of the correct choice in "c".`;
}
const SYSTEM = systemPrompt();

function userPrompt(subject, level, count, seen, cal) {
  const L = LEVELS[level];
  let p = `Write ${count} questions.\nSubject: "${subject}"\nLevel: ${L.name} (use the ${L.name} definition exactly).\n`;
  if (cal && Number.isFinite(cal.pct) && cal.n >= 8) {
    const dir = cal.pct > L.target + 12 ? `a little easy for this player — make these slightly harder, while still passing the ${L.name} level test`
      : cal.pct < L.target - 12 ? "too hard for this player — make these noticeably easier"
      : "about right — keep the same difficulty";
    p += `Calibration from this player's own results at ${L.name} on this subject: ${Math.round(cal.pct)}% correct over ${cal.n} questions (target ${L.target}%). That was ${dir}.\n`;
    if (cal.got && cal.got.length) p += `Recent ones they got right:\n${cal.got.map((x) => "  + " + x).join("\n")}\n`;
    if (cal.missed && cal.missed.length) p += `Recent ones they missed:\n${cal.missed.map((x) => "  - " + x).join("\n")}\n`;
  }
  if (seen.length) p += `Already asked on this subject (do not repeat any of these facts, answers, or near-rewordings):\n${seen.map((x) => "- " + x).join("\n")}\n`;
  return p;
}

/* ---------------- question checks (same rules the website uses) ---------------- */
function singular(w) {
  if (/sses$/.test(w)) return w.slice(0, -2);
  if (/ies$/.test(w)) return w.slice(0, -3) + "y";
  if (/(sh|ch|x|z|o)es$/.test(w)) return w.slice(0, -2);
  if (/(ss|us|is|ics)$/.test(w)) return w;
  if (/s$/.test(w)) return w.slice(0, -1);
  return w;
}
function subjectKey(sub) {
  return sub.toLowerCase().replace(/[^a-z0-9 ]/g, " ").replace(/\b\w{4,}\b/g, singular)
    .replace(/\b(try|not|to|repeat|please|questions?|trivia|about|the|and|of)\b/g, " ")
    .replace(/\s+/g, " ").trim() || sub.toLowerCase();
}
const STOP = new Set("a an the of in on at to for is are was were which what who whom whose how many much does do did by with from as that this these those its it be or and called known name".split(" "));
const words = (t) => new Set(String(t).toLowerCase().replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((w) => w.length > 2 && !STOP.has(w)));
function overlap(a, b) { if (!a.size || !b.size) return 0; let n = 0; a.forEach((w) => { if (b.has(w)) n++; }); return n / Math.min(a.size, b.size); }
function parseLine(p) { const m = String(p).match(/^(.*) → (.*)$/); return m ? { w: words(m[1]), a: m[2].toLowerCase().trim() } : null; }
function isDup(q, parsedPool) {
  const qa = String(q.c[q.a]).toLowerCase().trim(), qw = words(q.q);
  return parsedPool.some((p) => { if (!p) return false; const ov = overlap(qw, p.w); return ov >= 0.7 || (p.a === qa && ov >= 0.34); });
}
function givesAway(q) {
  const ans = String(q.c[q.a]).toLowerCase().replace(/^(the|a|an) /, "").replace(/[^a-z0-9 ]/g, " ").trim();
  if (ans.length < 4) return false;
  const text = " " + String(q.q).toLowerCase().replace(/[^a-z0-9 ]/g, " ") + " ";
  if (text.includes(" " + ans + " ")) return true;
  const parts = ans.split(/\s+/), last = parts[parts.length - 1];
  return parts.length > 1 && last.length >= 5 && text.includes(" " + last + " ") && !["theorem", "effect", "number", "limit", "temperature", "experiment", "constant"].includes(last);
}
const seenLine = (q) => q.q.replace(/\s+/g, " ").slice(0, 140) + " → " + String(q.c[q.a]).slice(0, 60);
function normalize(raw) {
  if (!raw || typeof raw !== "object") return null;
  const c = raw.c || raw.choices || raw.options; let a = raw.a ?? raw.answer ?? raw.correct;
  if (!Array.isArray(c)) return null;
  if (typeof a === "string") { const t = a.trim(), L = "ABCD".indexOf(t.toUpperCase()); a = t.length === 1 && L >= 0 ? L : c.findIndex((x) => String(x).trim().toLowerCase() === t.toLowerCase()); }
  const q = { q: String(raw.q || raw.question || "").trim(), c: c.map((x) => String(x).trim()), a: Number(a),
    x: String(raw.x || raw.explanation || ""), sym: String(raw.sym || "").slice(0, 3), cat: String(raw.cat || "").slice(0, 24),
    pct: Number(raw.pct), fan: Number(raw.fan) };
  const ok = q.q && q.c.length === 4 && q.c.every(Boolean) && Number.isInteger(q.a) && q.a >= 0 && q.a < 4 && new Set(q.c.map((x) => x.toLowerCase())).size === 4;
  return ok ? q : null;
}
function onLevel(q, level) {
  const L = LEVELS[level];
  if (L.fanBand && Number.isFinite(q.fan)) return q.fan >= L.fanBand[0] - 5 && q.fan <= L.fanBand[1] + 5;
  if (Number.isFinite(q.pct)) return q.pct >= L.band[0] - 5 && q.pct <= L.band[1] + 5;
  return true;
}
/* Every complete {...} inside the streamed array, even before it closes. */
function extractObjects(text) {
  const out = []; const start = text.indexOf("["); if (start < 0) return out;
  let depth = 0, inStr = false, esc = false, objStart = -1;
  for (let i = start + 1; i < text.length; i++) {
    const ch = text[i];
    if (inStr) { if (esc) esc = false; else if (ch === "\\") esc = true; else if (ch === '"') inStr = false; continue; }
    if (ch === '"') { inStr = true; continue; }
    if (ch === "{") { if (depth === 0) objStart = i; depth++; }
    else if (ch === "}") { depth--; if (depth === 0 && objStart >= 0) { try { out.push(JSON.parse(text.slice(objStart, i + 1))); } catch { out.push(null); } objStart = -1; } }
    else if (ch === "]" && depth === 0) break;
  }
  return out;
}

/* ---------------- storage ---------------- */
let schemaReady = false;
async function ensureSchema(db) {
  if (schemaReady) return;
  await db.prepare(`CREATE TABLE IF NOT EXISTS questions (
    id TEXT PRIMARY KEY, skey TEXT NOT NULL, level TEXT NOT NULL, subject TEXT NOT NULL,
    q TEXT NOT NULL, c TEXT NOT NULL, a INTEGER NOT NULL, x TEXT, sym TEXT, cat TEXT, line TEXT NOT NULL,
    plays INTEGER NOT NULL DEFAULT 0, correct INTEGER NOT NULL DEFAULT 0,
    reports INTEGER NOT NULL DEFAULT 0, report_reason TEXT, hidden INTEGER NOT NULL DEFAULT 0,
    created TEXT NOT NULL)`).run();
  await db.prepare("CREATE INDEX IF NOT EXISTS q_by_subject ON questions (skey, level, hidden)").run();
  await db.prepare("CREATE TABLE IF NOT EXISTS usage (vkey TEXT NOT NULL, hour TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (vkey, hour))").run();
  schemaReady = true;
}
const newId = () => "q" + Date.now().toString(36) + crypto.getRandomValues(new Uint32Array(1))[0].toString(36);
async function visitorKey(req) {
  const ip = req.headers.get("CF-Connecting-IP") || req.headers.get("x-forwarded-for") || "local";
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("flametrivia:" + ip));
  return [...new Uint8Array(d).slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const hourStamp = () => new Date().toISOString().slice(0, 13);

/* ---------------- HTTP helpers ---------------- */
function allowedOrigin(req, env) {
  const origin = req.headers.get("Origin");
  const list = String(env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  return origin && list.includes(origin) ? origin : null;
}
function cors(origin) {
  return { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers": "content-type", "Access-Control-Max-Age": "86400", Vary: "Origin" };
}
const json = (obj, status, origin) => new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...(origin ? cors(origin) : {}) } });
const clip = (s, n) => String(s ?? "").replace(/\s+/g, " ").trim().slice(0, n);
const strList = (v, max, len) => (Array.isArray(v) ? v : []).slice(-max).map((s) => clip(s, len)).filter(Boolean);

/* ---------------- /round ---------------- */
async function round(req, env, origin) {
  let body; try { body = await req.json(); } catch { return json({ code: "bad_request", message: "Body must be JSON." }, 400, origin); }
  const subject = clip(body.subject, 80);
  const level = ORDER.includes(body.level) ? body.level : null;
  const count = Math.max(1, Math.min(15, parseInt(body.count, 10) || 10));
  if (!subject || !level) return json({ code: "bad_request", message: "Missing subject or level." }, 400, origin);
  const seenIds = new Set(strList(body.seenIds, 2000, 40));
  const seenLines = strList(body.seenLines, 300, 220);
  const cal = body.calibration && typeof body.calibration === "object" ? {
    pct: Number(body.calibration.pct), n: parseInt(body.calibration.n, 10) || 0,
    got: strList(body.calibration.got, 5, 220), missed: strList(body.calibration.missed, 5, 220) } : null;

  const db = env.DB; await ensureSchema(db);
  const skey = subjectKey(subject);
  const vkey = await visitorKey(req);

  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter(), enc = new TextEncoder();
  const send = (o) => writer.write(enc.encode(JSON.stringify(o) + "\n"));

  const work = (async () => {
    let banked = 0, fresh = 0;
    try {
      const playerPool = seenLines.map(parseLine);
      /* 1. Serve from the bank */
      const L = LEVELS[level];
      const rows = (await db.prepare("SELECT id, q, c, a, x, sym, cat, line, plays, correct FROM questions WHERE skey = ? AND level = ? AND hidden = 0 ORDER BY RANDOM() LIMIT 300").bind(skey, level).all()).results || [];
      const picked = [];
      for (const r of rows) {
        if (picked.length >= count) break;
        if (seenIds.has(r.id)) continue;
        const q = { id: r.id, q: r.q, c: JSON.parse(r.c), a: r.a, x: r.x, sym: r.sym, cat: r.cat };
        if (r.plays >= 5) { const hit = (r.correct / r.plays) * 100; if (hit < L.target - 35 || hit > L.target + 30) continue; }
        if (isDup(q, playerPool) || isDup(q, picked.map((p) => parseLine(seenLine(p))))) continue;
        picked.push(q);
      }
      for (const q of picked) { await send({ type: "q", q: { ...q, banked: true } }); banked++; }

      /* 2. Ask Claude only for what's missing */
      const need = count - picked.length;
      if (need > 0) {
        const limit = parseInt(env.HOURLY_NEW_LIMIT, 10) || 40, hour = hourStamp();
        const used = (await db.prepare("SELECT n FROM usage WHERE vkey = ? AND hour = ?").bind(vkey, hour).first())?.n || 0;
        if (used + need > limit) {
          await send({ type: "error", code: "rate_limited", message: banked ? `Only ${banked} saved questions were available, and you've reached this hour's limit for new ones.` : "You've reached this hour's limit for new questions." });
        } else {
          await db.prepare("INSERT INTO usage (vkey, hour, n) VALUES (?, ?, ?) ON CONFLICT (vkey, hour) DO UPDATE SET n = n + excluded.n").bind(vkey, hour, need).run();
          ctxCleanup(db);
          const bankLines = ((await db.prepare("SELECT line FROM questions WHERE skey = ? ORDER BY created DESC LIMIT 200").bind(skey).all()).results || []).map((r) => r.line);
          const avoid = [...new Set([...seenLines, ...picked.map(seenLine), ...bankLines])].slice(-220);
          const avoidPool = avoid.map(parseLine);
          const emitted = [];
          await send({ type: "status", message: "writing", need });
          await askClaude(env, subject, level, Math.min(need + 4, 20), avoid.slice(-150), cal, async (raw) => {
            if (emitted.length >= need) return false;
            const q = normalize(raw);
            if (!q || !onLevel(q, level) || givesAway(q)) return true;
            if (isDup(q, avoidPool) || isDup(q, emitted.map((e) => parseLine(seenLine(e))))) return true;
            q.id = newId();
            await db.prepare("INSERT INTO questions (id, skey, level, subject, q, c, a, x, sym, cat, line, created) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
              .bind(q.id, skey, level, subject, q.q, JSON.stringify(q.c), q.a, q.x, q.sym || subject.slice(0, 2), q.cat || subject.slice(0, 24), seenLine(q), new Date().toISOString()).run();
            emitted.push(q);
            await send({ type: "q", q: { id: q.id, q: q.q, c: q.c, a: q.a, x: q.x, sym: q.sym, cat: q.cat, banked: false } });
            return emitted.length < need;
          });
          fresh = emitted.length;
        }
      }
      await send({ type: "done", banked, fresh });
    } catch (e) {
      await send({ type: "error", code: e.code || "server_error", message: clip(e.message || String(e), 300) });
    } finally {
      try { await writer.close(); } catch {}
    }
  })();
  return { response: new Response(readable, { headers: { "content-type": "application/x-ndjson", "cache-control": "no-store", ...cors(origin) } }), work };
}
function ctxCleanup(db) {
  const old = new Date(Date.now() - 48 * 3600e3).toISOString().slice(0, 13);
  db.prepare("DELETE FROM usage WHERE hour < ?").bind(old).run().catch(() => {});
}

/* Streams Claude's reply; calls onQuestion(raw) for each finished question object.
   onQuestion returns false to stop early. */
async function askClaude(env, subject, level, count, seen, cal, onQuestion) {
  if (!env.ANTHROPIC_API_KEY) throw Object.assign(new Error("The relay has no ANTHROPIC_API_KEY secret."), { code: "not_configured" });
  const res = await fetch(env.ANTHROPIC_URL || "https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model: env.MODEL || "claude-sonnet-5-5", max_tokens: 8000, stream: true,
      system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: userPrompt(subject, level, count, seen, cal) }],
    }),
  });
  if (!res.ok) {
    let msg = ""; try { const j = await res.json(); msg = j.error?.message || ""; } catch {}
    const code = res.status === 401 ? "bad_key" : /credit|billing/i.test(msg) ? "no_credit" : res.status === 429 ? "busy" : res.status >= 500 ? "overloaded" : "api_error";
    throw Object.assign(new Error(msg || "Claude returned " + res.status), { code });
  }
  const reader = res.body.getReader(), dec = new TextDecoder();
  let buf = "", text = "", taken = 0, keepGoing = true;
  while (keepGoing) {
    const { value, done } = await reader.read(); if (done) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (!line.startsWith("data:")) continue;
      let ev; try { ev = JSON.parse(line.slice(5)); } catch { continue; }
      if (ev.type === "content_block_delta" && typeof ev.delta?.text === "string") text += ev.delta.text;
      else if (ev.type === "error") throw Object.assign(new Error(ev.error?.message || "Claude stream error"), { code: "api_error" });
    }
    const objs = extractObjects(text);
    for (; taken < objs.length && keepGoing; taken++) {
      if (objs[taken]) keepGoing = await onQuestion(objs[taken]);
    }
  }
  try { reader.cancel(); } catch {}
}

/* ---------------- /result and /report ---------------- */
async function result(req, env, origin) {
  const b = await req.json().catch(() => ({}));
  const id = clip(b.id, 40); if (!id) return json({ ok: false }, 400, origin);
  await ensureSchema(env.DB);
  await env.DB.prepare("UPDATE questions SET plays = plays + 1, correct = correct + ? WHERE id = ?").bind(b.correct ? 1 : 0, id).run();
  return json({ ok: true }, 200, origin);
}
async function report(req, env, origin) {
  const b = await req.json().catch(() => ({}));
  const id = clip(b.id, 40); if (!id) return json({ ok: false }, 400, origin);
  await ensureSchema(env.DB);
  const hideAt = parseInt(env.REPORTS_TO_HIDE, 10) || 1;
  await env.DB.prepare("UPDATE questions SET reports = reports + 1, report_reason = ?, hidden = CASE WHEN reports + 1 >= ? THEN 1 ELSE hidden END WHERE id = ?")
    .bind(clip(b.reason, 200) || null, hideAt, id).run();
  return json({ ok: true }, 200, origin);
}

/* ---------------- entry point ---------------- */
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname === "/health") {
      try { await ensureSchema(env.DB); const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM questions WHERE hidden = 0").first(); return json({ ok: true, version: VERSION, questions: n?.n ?? 0, keySet: !!env.ANTHROPIC_API_KEY, origins: env.ALLOWED_ORIGINS || "" }, 200, null); }
      catch (e) { return json({ ok: false, version: VERSION, error: String(e.message || e) }, 500, null); }
    }
    const origin = allowedOrigin(req, env);
    if (!origin) return json({ code: "origin_blocked", message: "This relay only answers the Flame Test Trivia site." }, 403, null);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
    if (req.method !== "POST") return json({ code: "bad_request", message: "Use POST." }, 405, origin);
    try {
      if (url.pathname === "/round") { const { response, work } = await round(req, env, origin); ctx.waitUntil(work); return response; }
      if (url.pathname === "/result") return await result(req, env, origin);
      if (url.pathname === "/report") return await report(req, env, origin);
      return json({ code: "not_found" }, 404, origin);
    } catch (e) {
      return json({ code: "server_error", message: clip(e.message || String(e), 300) }, 500, origin);
    }
  },
};

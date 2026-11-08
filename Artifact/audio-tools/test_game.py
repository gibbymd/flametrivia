"""Headless checks for v15 audio questions (solo + challenge + opponent without Claude).
Usage: OUTDIR=<folder with assets.json and the encoded .mp4 clips> python3 test_game.py ../index.html
"""
import json, re, sys
from playwright.sync_api import sync_playwright

PAGE = sys.argv[1]
import os
OUTDIR = os.environ.get("OUTDIR", "out")
ASSETS = json.load(open(OUTDIR + "/assets.json"))
BLOB = {v.rsplit("/", 1)[1]: k for k, v in ASSETS.items()}
URL = "https://artifact.test/index.html"
HTML = open(PAGE, encoding="utf-8").read()

STUB = r"""
(() => {
  const words = ["amber","basalt","cobalt","delta","ember","fjord","garnet","harbor","indigo","jasper","kelp","lumen","marble","nectar","onyx","prism","quartz","russet","sable","tundra","umber","velvet","willow","xenon","yarrow","zephyr"];
  async function sample(prompt, opts){
    const n = +(/Write (\d+) multiple-choice/.exec(prompt)||[0,5])[1];
    window.__asked = (window.__asked||[]).concat(n);
    const qs = [];
    for (let i=0;i<n;i++){ const w=words[i%26]+(i>25?i:""); qs.push({q:`Which ${w}kin ${w}zor ${w}vel item is listed first here?`, c:[`${w} one`,`${w} two`,`${w} three`,`${w} four`], a:0, pct:75, fan:55, x:"stub", sym:"St", cat:"Stub"}); }
    const text = JSON.stringify(qs);
    for (let k=1;k<=4;k++){ await new Promise(r=>setTimeout(r,60)); opts.onText && opts.onText({text:text.slice(0,Math.floor(text.length*k/4))}); }
    return {text};
  }
  window.claude = {use: async name => name==="sample" ? sample : null};
})();
"""

def serve(route):
    u = route.request.url
    m = re.search(r"/_blob/([0-9a-f]+)", u)
    if m:
        cid = BLOB.get(m.group(1))
        if not cid:
            return route.fulfill(status=404, body="no")
        return route.fulfill(status=200, body=open(f"{OUTDIR}/{cid}.mp4", "rb").read(), content_type="video/mp4")
    if u.split("#")[0].startswith(URL):
        return route.fulfill(status=200, body=HTML, content_type="text/html")
    return route.fulfill(status=204, body="")  # fonts etc.

def new_page(browser, claude=True):
    ctx = browser.new_context()
    ctx.route("**/*", serve)
    if claude:
        ctx.add_init_script(STUB)
    p = ctx.new_page()
    errs = []
    p.on("pageerror", lambda e: errs.append(str(e)))
    return ctx, p, errs

def setup(p, subject, count, audio):
    p.fill("#subject", subject)
    p.click(f"label[for=ct-{count}]")
    p.click(f"label[for=au-{1 if audio else 0}]")

def play_round(p, expect_total):
    seen = []
    for i in range(expect_total):
        p.wait_for_selector(".choice:not(:disabled)", timeout=15000)
        has = p.locator("#playBtn").count() > 0
        seen.append(p.locator("#playBtn").get_attribute("data-au") if has else None)
        if has and i == [j for j, s in enumerate(seen) if s][0]:
            # first clip: play it, answer while it plays, check it keeps playing, then move on and check it stops
            p.click("#playBtn"); p.wait_for_timeout(1200)
            st = p.evaluate("({paused:player.paused,t:player.currentTime,src:player.src,label:document.getElementById('playBtn').textContent})")
            assert not st["paused"] and st["t"] > 0.3, st
            assert st["label"].startswith("■"), st
            p.locator(".choice").first.click()
            p.wait_for_timeout(300)
            assert p.evaluate("!player.paused"), "clip stopped when answering"
            assert p.locator("#playBtn").count() == 1, "play button gone after answering"
            p.click("#nextBtn"); p.wait_for_timeout(200)
            assert p.evaluate("player.paused"), "clip kept playing on next question"
            continue
        p.locator(".choice").first.click()
        p.wait_for_selector("#nextBtn:not([disabled])", timeout=15000)
        p.click("#nextBtn")
    return seen

with sync_playwright() as pw:
    b = pw.chromium.launch(channel="chrome", args=["--autoplay-policy=no-user-gesture-required"])

    # 1. solo, birds, 10 questions, audio on
    ctx, p, errs = new_page(b)
    p.goto(URL); p.wait_for_selector("#subject")
    setup(p, "Birds", 10, True)
    hint = p.text_content("#audioHint"); print("hint:", hint)
    assert "3 of 10" in hint, hint
    p.click("#go")
    seen = play_round(p, 10)
    print("solo birds:", seen)
    assert [i for i, s in enumerate(seen) if s] == [2, 5, 8], seen
    assert p.evaluate("window.__asked") == [12], p.evaluate("window.__asked")
    p.wait_for_selector(".summary"); print("summary:", p.text_content(".summary .big"))
    # replay: second Play click after end restarts
    assert not errs, errs; ctx.close()

    # 2. audio off -> no clips
    ctx, p, errs = new_page(b)
    p.goto(URL); p.wait_for_selector("#subject")
    setup(p, "Birds", 5, False); p.click("#go")
    seen = play_round(p, 5); print("audio off:", seen); assert not any(seen)
    assert not errs, errs; ctx.close()

    # 3. no matching subject -> all text, hint says so
    ctx, p, errs = new_page(b)
    p.goto(URL); p.wait_for_selector("#subject")
    setup(p, "Chemistry", 5, True)
    print("hint:", p.text_content("#audioHint")); assert "no recordings" in p.text_content("#audioHint")
    p.click("#go"); seen = play_round(p, 5); assert not any(seen); print("chemistry:", seen)
    assert not errs, errs; ctx.close()

    # 4. pref is remembered across reloads
    ctx, p, errs = new_page(b)
    p.goto(URL); p.wait_for_selector("#subject"); p.click("label[for=au-1]")
    p.reload(); p.wait_for_selector("#subject"); assert p.is_checked("#au-1"); ctx.close()

    # 5. challenge: musical instruments, 15 -> 5 clips, link carries them to an opponent with no Claude at all
    ctx, p, errs = new_page(b)
    p.goto(URL); p.wait_for_selector("#subject")
    setup(p, "Musical instruments", 15, True)
    p.click("#challengeBtn")
    p.wait_for_selector(".choice:not(:disabled)", timeout=15000)
    m = p.evaluate("Object.values(matches)[0]")
    aus = [q.get("au") for q in m["qs"]]
    print("challenge qs:", aus)
    assert len(aus) == 15 and [i for i, a in enumerate(aus) if a] == [2, 4, 8, 10, 14] or sum(1 for a in aus if a) == 5, aus
    p.locator(".choice").first.click()
    p.click("#mNext")
    p.click("#mSend"); p.wait_for_timeout(500)
    msg = p.evaluate("lastCopy")
    link = msg[msg.index("https://"):]
    print("link length:", len(link))
    assert not errs, errs

    ctx2, o, errs2 = new_page(b, claude=False)
    o.goto(URL + link[link.index("#"):])
    o.wait_for_selector(".choice:not(:disabled)", timeout=15000)
    om = o.evaluate("Object.values(matches)[0]")
    assert [q.get("au") for q in om["qs"]] == aus, "opponent lost clip ids"
    # opponent answers through the round as far as turns allow, checking clips play
    played = 0
    for _ in range(3):
        if o.locator(".choice:not(:disabled)").count() == 0:
            break
        if o.locator("#playBtn").count():
            o.click("#playBtn"); o.wait_for_timeout(1000)
            assert o.evaluate("!player.paused && player.currentTime>0.3"); played += 1
        o.locator(".choice").first.click()
        if o.locator("#mNext").count(): o.click("#mNext")
    # jump the opponent straight to a clip question to prove playback without Claude
    idx = next(i for i, a in enumerate(aus) if a)
    o.evaluate(f"(()=>{{const m=Object.values(matches)[0];matchShow={idx};render()}})()")
    o.click("#playBtn"); o.wait_for_timeout(1200)
    st = o.evaluate("({paused:player.paused,t:player.currentTime})"); print("opponent playback:", st)
    assert not st["paused"] and st["t"] > 0.3
    print("credit:", o.text_content(".credit"))
    assert not errs2, errs2
    b.close()
print("ALL TESTS PASSED")

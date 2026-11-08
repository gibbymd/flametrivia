"""Build ../index.html from template.html + clips_spec.py + meta.json (Commons credits) + assets.json (uploaded asset URLs). Run from this folder."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from clips_spec import SPEC, BY
meta = json.load(open("meta.json"))
assets = json.load(open(os.environ.get("OUTDIR", ".") + "/assets.json"))  # cid -> "/_blob/<id>"
clips = []
for cid, sp in SPEC.items():
    if cid not in assets:
        continue
    m = meta[cid]
    name = re.sub(r"\.(ogg|oga|mp3|wav|opus|flac)$", "", m["title"].split(":", 1)[1])
    if len(name) > 64:
        name = name[:61].rstrip(" -,") + "…"
    by = BY.get(cid) or m["artist"].replace("&amp;", "&").strip() or "Unknown"
    clips.append({"id": cid, "g": sp["g"], "cat": sp["cat"], "q": sp["q"], "c": sp["c"], "x": sp["x"],
                  "url": assets[cid], "title": name, "by": by, "lic": m["license"], "src": m["page"]})
for k in clips:
    assert len(k["c"]) == 4 and len(set(x.lower() for x in k["c"])) == 4, k["id"]
js = json.dumps(clips, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
html = open("template.html").read()
assert html.count("/*CLIPS*/[]") == 1
open("../index.html", "w").write(html.replace("/*CLIPS*/[]", js))
print(len(clips), "clips;", len(js), "bytes of clip data")

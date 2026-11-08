"""Trim + normalize + encode each downloaded clip (DL=dl/<id>.<ext>) to OUT=out/<id>.mp4 and write out/manifest.json.
Usage: python3 build_clips.py [id ...]
"""
import glob, json, os, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from clips_spec import SPEC

DL, OUT, SR, HOP = os.environ.get("DL", "dl"), os.environ.get("OUT", "out"), 22050, 0.1
os.makedirs(OUT, exist_ok=True)


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def frames(x, band=None):
    n = int(SR * HOP)
    m = len(x) // n
    fr = x[: m * n].reshape(m, n)
    if band:  # energy in a frequency band (Hz), per frame
        spec = np.abs(np.fft.rfft(fr * np.hanning(n), axis=1)) ** 2
        f = np.fft.rfftfreq(n, 1 / SR)
        sel = (f >= band[0]) & (f <= band[1])
        return spec[:, sel].sum(1) / (spec.sum(1) + 1e-12)
    return np.sqrt((fr ** 2).mean(1) + 1e-12)


def choose(cid, sp, x):
    total = len(x) / SR
    dur = min(sp["dur"], total)
    rms = frames(x)
    db = 20 * np.log10(rms / rms.max())
    if sp.get("start") is not None:
        st = sp["start"]
        # skip leading silence (below -35 dB of peak) from the chosen start
        i0 = int(st / HOP)
        loud = np.where(db[i0:] > -35)[0]
        st = st + (loud[0] * HOP if len(loud) else 0)
        st = max(0, min(st, total - dur))
        return st, dur
    w = max(1, int(dur / HOP))
    score = frames(x, band=(70, 100)) if cid == "ingenuity" else rms  # Ingenuity: rotor hum ~84 Hz
    cs = np.concatenate([[0], np.cumsum(score)])
    sums = cs[w:] - cs[:-w]
    best = int(np.argmax(sums))
    # nudge the start back to a quiet frame within 1 s so the clip doesn't open mid-sound
    lo = max(0, best - int(1 / HOP))
    q = lo + int(np.argmin(rms[lo:best + 1]))
    st = q * HOP
    return max(0, min(st, total - dur)), dur


def encode(src, dst, st, dur):
    fade = min(0.25, dur / 10)
    af = (f"atrim=start={st:.2f}:duration={dur:.2f},asetpts=PTS-STARTPTS,"
          f"afade=t=in:d={fade:.2f},afade=t=out:st={max(0, dur - fade - 0.05):.2f}:d={fade:.2f},"
          "loudnorm=I=-18:TP=-1.5:LRA=11,aresample=44100")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vn", "-af", af, "-ac", "1", "-c:a", "aac", "-b:a", "64k",
                    "-movflags", "+faststart", dst], check=True)


man_path = f"{OUT}/manifest.json"
man = json.load(open(man_path)) if os.path.exists(man_path) else {}
ids = sys.argv[1:] or list(SPEC)
for cid in ids:
    srcs = [p for p in glob.glob(f"{DL}/{cid}.*")]
    if not srcs:
        print("missing", cid); continue
    sp = SPEC[cid]
    x = decode(srcs[0])
    st, dur = choose(cid, sp, x)
    dst = f"{OUT}/{cid}.mp4"
    encode(srcs[0], dst, st, dur)
    man[cid] = {"start": round(st, 2), "dur": round(dur, 2), "bytes": os.path.getsize(dst), "srclen": round(len(x) / SR, 1)}
    print(f"{cid:12} start={st:6.2f} dur={dur:5.2f} of {len(x)/SR:6.1f}s -> {os.path.getsize(dst)//1024} KB")
json.dump(man, open(man_path, "w"), indent=1)

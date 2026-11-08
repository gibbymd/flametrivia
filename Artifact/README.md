# Flame Test Trivia — Claude artifact version

`index.html` is the code of the published Claude artifact: https://claude.ai/artifact/9eGyA4eYmsvLgTnr6m3rTP

This version runs inside Claude. Questions come from the viewer's own Claude account (the artifact `sample` capability), so it needs no API key or relay. Its version numbers are separate from `Web/`.

- **v14** added **Challenge someone**: the challenger's Claude writes the questions, and players take turns by texting each other a link that carries the whole match. Opponents don't need a Claude account.
- **v15** adds **Audio questions** (Off/On on the setup screen; the choice is remembered). When it's on and the subject has recordings, about a third of the round's questions play a short clip with a ▶ Play button you can replay, and ask about it. The clip ids travel in challenge links, so opponents hear the same clips.

## Audio questions

46 short excerpts of public-domain and Creative Commons recordings from Wikimedia Commons, each with one question written for it. They're stored as the artifact's own assets (audio-only `.mp4`, the audio format artifact assets accept) and are public, so challenge opponents who aren't signed in can play them.

| Subject words that match | Clips |
|---|---|
| birds, birdsong, ornithology, raptors | 17 bird calls and songs |
| owls | 2 owls |
| animals, wildlife, mammals, whales, frogs, primates | the 17 birds plus 7 mammals, frogs and primates |
| Yellowstone, national parks | 9 Yellowstone recordings |
| music, instruments, orchestra, classical music | 11 instruments |
| aviation, aircraft, jets, helicopters, engines (not "aviation weather") | 5 aircraft and engines |
| space, Apollo, NASA, Mars, astronauts | Apollo 11 ×2, Apollo 13, Sputnik, Mars helicopter |
| US history, 20th century, 1960s, Cold War | Apollo, Sputnik, FDR |
| presidents, speeches, Roosevelt | FDR's "infamy" speech |
| World War II, WWII, 1940s | Spitfire, Merlin engine, FDR |
| trains, railroads, locomotives | Union Pacific 844 steam whistle |

A round with 5, 10 or 15 questions gets 2, 3 or 5 clips (fewer if the subject has fewer), spread through the round. Subjects with no recordings play as normal text rounds, and the setup screen says so.

Credits for every clip are in [`AUDIO_CREDITS.md`](AUDIO_CREDITS.md) and on each audio question in the game.

## Rebuilding the clip bank (`audio-tools/`)

| File | Purpose |
|---|---|
| `template.html` | The game with an empty clip table (`/*CLIPS*/[]`) |
| `clips_spec.py` | Each clip's question, answer choices, explanation, subject groups and trim window |
| `sources.txt`, `meta.json` | Commons file names and their license/author metadata |
| `build_clips.py` | Trims, fades, loudness-normalizes and encodes clips (needs ffmpeg and numpy) |
| `assets.json`, `manifest.json` | Uploaded asset URL and trim window of each clip |
| `make_js.py` | Writes `../index.html` from the template plus the clip table |
| `test_game.py` | Headless Chrome tests: solo, audio off, no-match subject, challenge link opened without Claude |

To add a clip: add it to `sources.txt` and `clips_spec.py`, download the original into the folder `build_clips.py` reads, run `build_clips.py <id>`, upload the `.mp4` to the artifact as an asset, add its URL to `assets.json`, run `make_js.py`, and publish `index.html` to the artifact.

Wikimedia rate-limits bulk downloads (about 10 files, then a 10-minute wait), so download in small batches.

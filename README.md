# Flame Test Trivia

Multiple-choice trivia on any subject you type, at four calibrated difficulty levels (Easy, Medium, Hard, Expert). Claude writes the questions; answers are revealed only after you guess, and a cumulative score is kept.

| Folder | What it is | How to run it |
|---|---|---|
| `Web/` | Single-file website (`index.html`) | Open it in a browser or host it, e.g. Netlify Drop. See `Web/README.md`. |
| `IOS/` | SwiftUI iPhone app (`FlameTrivia.swiftpm`) | Open in Xcode 15+ and run on your iPhone. See `IOS/HOW TO INSTALL.md`. |
| `Relay/` | Cloudflare Worker that holds the API key and a shared question bank | Set up once in the Cloudflare dashboard. See `Relay/README.md`. |

Scores are saved on each device. The website uses the relay when `RELAY_URL` is set in `Web/index.html`, so players need no API key. Without the relay, and in the iPhone app, each player enters their own Anthropic API key in Settings. No key is ever stored in this repo.

The website is v16. It adds **Challenge someone**: the challenger's browser writes the questions, and players take turns by texting each other a link that carries the whole match, so the opponent needs no account, API key or relay. Each player answers in turn, and a question's result appears once both have answered it. v15 made the site open on a blank setup screen, and v14 added the relay and question bank. The iPhone app matches v13, plus the blank-start change, and has no challenge mode.

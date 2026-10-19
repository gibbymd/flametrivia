# Flame Test Trivia: website version

Same game as the claude.ai page: type any subject, pick Easy, Medium, Hard, or Expert, and play. Scores are saved in the browser you play in.

**Two ways it gets questions:**
- **With the relay (recommended).** Set `const RELAY_URL="…"` near the top of the script in `index.html` to your relay's address (see `../Relay/README.md`). Players need no API key; your key, held by the relay, pays for new questions, and saved questions are reused for free.
- **Without the relay.** Leave `RELAY_URL` empty, and each player enters their own Anthropic API key in Settings.

## Put it online (free, about 5 minutes) with Netlify Drop
1. Find the **Web** folder (it contains `index.html` and this README).
2. Go to https://app.netlify.com/drop
3. Drag the **Web** folder onto the page. Netlify gives you a live web address in a few seconds.
4. Netlify protects the address with a temporary password until you **claim** it. Click the prompt to sign up (free) or log in. If your account has "private by default" turned on, open the site's settings and make it public.
5. Optional: under **Site configuration → Change site name**, pick a nicer address, such as `flametesttrivia.netlify.app`.

To update the site later, open it in Netlify, go to **Deploys**, and drag the new folder onto the deploy area.

## First visit (without the relay)
1. The **Settings** panel opens automatically. Paste your Anthropic API key (create one at https://platform.claude.com/settings/keys) and tap **Save**.
2. Type a subject, pick a difficulty and number of questions, and tap **Start round**.
3. On iPhone, tap Safari's **Share** button, then **Add to Home Screen**, to get an app icon.

## Good to know
- **Your key stays with you.** It's stored only in the browser where you typed it and is sent only to Anthropic. It is not part of the site files, so anyone you share the address with must enter their own key. Each person's rounds bill to their own key.
- **Scores live in each browser.** Your phone and computer keep separate scores. To move them, use **Settings → Back up scores** on one device and **Restore backup** on the other. Clearing Safari's website data erases them.
- **Cost:** a 10-question round is roughly 1–3 cents of API credit.
- **Model:** leave the Model box blank to use `claude-sonnet-5-5`.

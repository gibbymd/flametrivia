# Flame Test Trivia relay (Cloudflare Worker)

The relay lets anyone play the website without their own API key:

- **It holds your Anthropic API key.** The key never reaches a browser and never appears in this repo.
- **It keeps a shared question bank.** A round is filled with saved questions the player hasn't seen yet. Claude is only asked for whatever is missing, so popular subjects soon cost almost nothing.
- **"Report a problem with this question"** under each answer removes that question from the bank for everyone.
- **It has safeguards:**
  - It only answers requests from your site's address.
  - Each visitor can trigger at most 40 *new* questions per hour. Saved questions don't count toward that.
  - It only ever sends Claude trivia requests that it builds itself.

Setup takes about 15 minutes in the Cloudflare website, and nothing needs installing. Everything below is on the free plan.

---

## 1. Create a free Cloudflare account
Go to **https://dash.cloudflare.com/sign-up**, sign up, and verify your email. Skip any prompts to add a website or domain; you don't need one.

## 2. Create the database
1. In the left sidebar, open **Storage & databases → D1 SQL database**. You can also type **D1** into the search box at the top of the dashboard.
2. Click **Create Database**.
3. Name it **flametrivia**, leave the location as is, and click **Create**.

The relay creates its own tables the first time it runs, so you don't need to enter anything else here.

## 3. Create the Worker
1. In the left sidebar, open **Compute (Workers) → Workers & Pages**.
2. Click **Create application**.
3. Choose **Start with Hello World!** and click **Get started**.
4. Name it **flametrivia-relay** and click **Deploy**.
5. When it finishes, the page shows the Worker's address, ending in **.workers.dev**. It will look like `https://flametrivia-relay.YOUR-NAME.workers.dev`. Copy it; you'll need it in step 7.

## 4. Put in the relay code
1. On the Worker's page, click **Edit code**. It may appear as a **</>** icon at the top right.
2. Open this file in another tab and copy all of it: **https://raw.githubusercontent.com/gibbymd/flametrivia/main/Relay/worker.js**
3. In the editor, click inside the code file on the left (usually `worker.js`). Select everything with ⌘A, and paste with ⌘V to replace it.
4. Click **Deploy** at the top right. If you only see **Save**, click **Save**, then go to **Deployments**, click **Deploy version** in the **Version History** table, and click **Deploy**.

## 5. Connect the database
1. Go back to the Worker's page (**Workers & Pages → flametrivia-relay**) and open the **Bindings** tab.
2. Click **Add binding**, choose **D1 database**, and click **Add binding**.
3. In **Variable name**, type exactly **DB** in capitals.
4. In the database dropdown, choose **flametrivia**.
5. Click **Add binding**.

## 6. Add your API key and your site's address
1. On the Worker's page, open **Settings**, then find **Variables and Secrets** and click **Add**.
2. Add the key:
   - **Type:** Secret
   - **Variable name:** `ANTHROPIC_API_KEY`
   - **Value:** your key from https://platform.claude.com/settings/keys
3. Click **Add variable** and add the site address:
   - **Type:** Text
   - **Variable name:** `ALLOWED_ORIGINS`
   - **Value:** `https://gibbymd.github.io`
   
   If you also host the site somewhere else, such as Netlify, add that address after a comma, with no path and no trailing slash.
4. Click **Deploy**.

## 7. Check it and connect the website
1. Open your Worker address with `/health` added to the end, for example `https://flametrivia-relay.YOUR-NAME.workers.dev/health`. You should see:
   - `"ok":true`
   - `"keySet":true`
   - `"origins":"https://gibbymd.github.io"`
2. Send Claude the Worker address, and Claude will connect the website and push the change. To do it yourself, open `Web/index.html`, find the line `const RELAY_URL="";`, put the address between the quotes, then commit and push.

## 8. Cap your spending (recommended)
At **https://platform.claude.com/settings/billing**, in the **Spend limits** section, click **Set limit** and enter a monthly amount. When the limit is reached, the game stops writing new questions until next month, but saved questions keep working.

---

## Optional settings
These go in **Settings → Variables and Secrets** as **Text**. Click **Deploy** after any change.

| Name | Default | What it does |
|---|---|---|
| `HOURLY_NEW_LIMIT` | `40` | New questions one visitor can trigger per hour. Saved questions don't count. |
| `REPORTS_TO_HIDE` | `1` | How many reports remove a question from the bank. |
| `MODEL` | `claude-sonnet-5-5` | Which Claude model writes questions. |

## Looking after the question bank
Open **D1 SQL database → flametrivia → Console** and run any of these.

- **See reported questions:**
  ```sql
  SELECT id, subject, level, q, report_reason FROM questions WHERE hidden = 1;
  ```
- **Put a question back:**
  ```sql
  UPDATE questions SET hidden = 0, reports = 0 WHERE id = 'PASTE-ID';
  ```
- **Bank size by subject:**
  ```sql
  SELECT subject, level, COUNT(*) FROM questions WHERE hidden = 0 GROUP BY skey, level ORDER BY 3 DESC;
  ```
- **Questions players find much easier or harder than their level:**
  ```sql
  SELECT level, q, plays, ROUND(100.0*correct/plays) AS pct FROM questions WHERE plays >= 5 ORDER BY pct;
  ```

The relay automatically stops serving a question once at least 5 players have answered it and their hit rate is far outside its level.

## Updating the relay later
When `Relay/worker.js` changes in this repo, repeat step 4 (copy, paste, Deploy). The bank and settings are kept.

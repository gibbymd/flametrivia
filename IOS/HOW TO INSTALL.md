# Flame Test Trivia: install on your iPhone

This build matches web version v13: calibrated Easy/Medium/Hard/Expert levels, questions that stay on the exact subject, repeat filtering, and difficulty that adjusts to your results within each subject.

You need: a Mac with Xcode 15 or later, your iPhone and its USB cable, a free Apple ID, and an Anthropic API key.

## 1. Get an API key (one time)
1. Go to https://platform.claude.com and sign in.
2. Open **Settings → API keys** (https://platform.claude.com/settings/keys), click **Create key**, name it "Trivia", and copy the key (starts with `sk-ant-`). It is shown only once.
3. On the same site, add a few dollars of credit under **Billing**. A 10-question round costs roughly 1–3 cents.

## 2. Open the project
1. Install **Xcode** from the Mac App Store if you don't have it, and open it once to finish setup.
2. Open the **IOS** folder and double-click **FlameTrivia.swiftpm**. It opens in Xcode (the first open takes a minute while Xcode indexes).

## 3. Sign it with your Apple ID (one time)
1. In Xcode's menu bar: **Xcode → Settings…** (or press ⌘,) → **Accounts** tab.
2. Click **+** at the bottom-left → **Apple ID** → **Continue**, and sign in.
3. Close Settings. In the left sidebar, click the top item **Flame Test Trivia** (blue icon).
4. In the middle pane, select **Signing & Capabilities**. Set **Team** to **"Your Name (Personal Team)"**.
5. If Xcode shows "Failed to register bundle identifier", change **Bundle Identifier** to something unique, e.g. `com.yourname.flametesttrivia`.

## 4. Put it on your iPhone
1. Plug the iPhone into the Mac. On the iPhone tap **Trust** and enter your passcode.
2. Turn on Developer Mode: iPhone **Settings → Privacy & Security → Developer Mode** (scroll to the bottom) → turn on → **Restart** → after restart tap **Turn On**. (This item appears only after the phone has been connected to Xcode.)
3. In Xcode's top toolbar, click the device name in the middle and choose **your iPhone**.
4. Press the **Run** button (▶ at the top-left) or ⌘R. The first build takes a minute or two.
5. If the iPhone says **Untrusted Developer**: iPhone **Settings → General → VPN & Device Management** → tap your Apple ID under **Developer App** → **Trust**. Then tap the app icon again.

## 5. First launch
Tap the **gear** (top-right) → paste your API key → **Save**. Type a subject, pick a difficulty, tap **Start round**.

## Every 7 days
With a free Apple ID the app stops opening after 7 days. Plug the iPhone in, open the project in Xcode, and press **Run** again. Your scores are kept.

## If the build fails
Copy the red error text from Xcode's **Issue navigator** (the ⚠︎ triangle icon in the left sidebar) and paste it to Claude.

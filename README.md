# Macal

A macOS menu bar app that shows today's Google Calendar events across all your accounts and alerts you before each meeting.

## Download

Grab `Macal.dmg` from the [latest release](https://github.com/emilevauge/macal/releases/latest), open it and drag Macal onto the `Applications` shortcut. Or from the command line:

```sh
curl -L -o Macal.dmg \
  https://github.com/emilevauge/macal/releases/latest/download/Macal.dmg
hdiutil attach Macal.dmg
cp -R "/Volumes/Macal/Macal.app" /Applications/
hdiutil detach "/Volumes/Macal"
xattr -dr com.apple.quarantine /Applications/Macal.app   # not notarized, bypass Gatekeeper
open /Applications/Macal.app
```

Macal does not ship with a Google OAuth client: on first launch, it asks you to import your own (see [Google OAuth client](#google-oauth-client)). It then updates itself: when a new release is out, a notification offers to install it.

## Features

- **Today's agenda**: every event of the day from all connected Google accounts, merged and deduplicated in one list. Browse other days with the arrows in the header.
- **Expandable details**: guests with their RSVP status, location, attached Drive documents and the event description.
- **Reply to invitations**: answer Yes, Maybe or No from the expanded event, or right-click any event row. The organizer gets the usual Google notification. Accounts connected before this feature must reconnect once ("Reconnect to reply").
- **Join button in the Macal icon**: a few minutes before a meeting with a video link, the menu bar icon grows into one orange capsule (red from 1 minute before the start and during the first minutes) holding a camera, the meeting title and the calendar countdown. Click the title to join the call (Google Meet, Zoom, Teams, ...), click the calendar to open Macal, right-click for attachments, dismiss, or the event details.
- **Countdown icon**: the menu bar glyph shows the time left before the next meeting of the day ("12", "2h"), never the date. It turns orange when a meeting is close, red 1 minute before the start, During a meeting it glows red, like an "on air" sign, shows the minutes left in it, and the page fills up from left to right as the meeting runs.
- **Meeting notification**: a standard macOS banner when a meeting enters the alert window, and another when it starts, with the time left, the time slot and the provider. Click it (or "Join") to join the call, or to open the event in Macal when it has no link. It is withdrawn once the meeting is dismissed or its alert window ends. Can be turned off in the settings.
- **Hover card**: rest the pointer on the icon to see the next meeting, or, while one is due, a card with the capsule's color, time left, provider, guests and attachments.
- **Global shortcut**: show or hide the popover from anywhere (default `⌃⌥M`).
- **Open at the start of the day**: the popover opens by itself at the first launch, wake or unlock of the day, from 6:00, when a meeting is still ahead today. Once a day at most, can be turned off in the settings.
- **Automatic updates**: Macal checks GitHub for a new release every day. The notification's `Update` action downloads the DMG, replaces the app and relaunches it. Also available from *Settings > About*.
- **Launch at login**: optional auto-start via a user `LaunchAgent`.

## Requirements

- macOS 14 (Sonoma) or later.
- A Google account, and a Google Cloud project for the OAuth client (free).
- To build from source: Xcode or the Xcode Command Line Tools, with Swift 5.9+.

## Google OAuth client

Macal talks to the Google Calendar API with your own OAuth client, so no secret is shared between users. Create it once:

1. On https://console.cloud.google.com, create a project named `Macal`.
2. In *APIs & Services > Library*, enable the **Google Calendar API**.
3. Open *Google Auth Platform*. On a new project, the *Get started* wizard asks for the *Branding* and *Audience* settings below in one go:
   - *Branding*: set the app name to `Macal` and pick a support email.
   - *Audience*: choose the **External** user type, then click **Publish app** to move it to *In production*. Do not request verification: you will see the "Google hasn't verified this app" screen once (click *Advanced > Go to Macal*). While the app stays in *Testing*, refresh tokens expire after 7 days.
   - *Data access*: add the scopes `openid`, `.../auth/userinfo.email`, `.../auth/calendar.readonly` (to list your calendars) and `.../auth/calendar.events` (to reply to invitations).
4. In *Clients > Create client*, choose the **Desktop app** type, then download the JSON file.
5. In Macal, click **Import google-oauth.json…** in the popover (or *Settings > Accounts > Import OAuth client…*) and pick the downloaded file. Macal checks it and keeps a private copy (permissions `0600`) in `~/Library/Application Support/Macal/google-oauth.json`. Then connect your Google accounts.

To switch to another client later, use *Settings > Accounts > Replace OAuth client…*. Accounts signed in with the previous client must be reconnected.

**Google Workspace accounts.** A Workspace admin can block unverified third-party apps, and sign-in then stops on an "Access blocked" page. Two ways out:

- the admin trusts the OAuth client ID in the *Admin console > Security > API controls > App access control*;
- if every account belongs to a single Workspace organization, create the client in a project of that organization and choose the **Internal** audience type instead of External. There is no unverified app screen and no 7-day token expiry, but only accounts of that domain can sign in.

## Build

```sh
# Dev binary
swift build && .build/debug/Macal

# .app bundle and DMG (--install also copies the app to /Applications)
./make-app.sh [--install]
```

For development, you can also copy your client JSON to `Sources/Macal/Resources/google-oauth.json` (ignored by git; `google-oauth.example.json` shows the format). The dev binary uses it when nothing was imported. `make-app.sh` never puts it in `Macal.app`, and fails if an OAuth client file ends up inside the bundle.

The `make-app.sh` script:

1. Builds `release`.
2. Renders the SwiftUI app icon at 1024×1024 via `Macal --generate-icon`, then `sips` for every size and `iconutil` for `AppIcon.icns`.
3. Assembles `Macal.app/Contents/{MacOS,Resources,Info.plist}` with `CFBundleIdentifier` `dev.macal.app`, `LSUIElement` and the version.
4. Checks that no `google-oauth*.json` file is inside the bundle.
5. Signs the bundle with the `MACAL_SIGN_IDENTITY` identity (default `Claudette Dev`) when it is in the keychain, ad hoc otherwise.
6. Registers it with LaunchServices so notifications work, then builds `Macal.dmg`.

With an ad hoc signature, every build gets a new code hash and macOS may ask again for Keychain access. A local self-signed code signing certificate keeps the same identity across builds: create one in *Keychain Access > Certificate Assistant > Create a Certificate* (type *Code Signing*), then set `MACAL_SIGN_IDENTITY` to its name.

To publish a release, bump `VERSION` and `BUILD` in `make-app.sh`, run it, and attach `Macal.dmg` to a GitHub release tagged `vX.Y.Z`. Installed copies pick it up within a day.

## Privacy

- Macal reads your calendars (`calendar.readonly` scope) and can modify events (`calendar.events` scope). It only uses the latter to reply to an invitation when you click Yes, Maybe or No: it changes your own answer and nothing else.
- Refresh tokens are stored in the macOS Keychain.
- Your OAuth client is stored in `~/Library/Application Support/Macal/google-oauth.json`, readable by you only.
- Today's and tomorrow's events are cached in `~/Library/Application Support/Macal/events.json`.
- No data is sent anywhere other than Google, except the daily update check, an anonymous request to the GitHub releases API.

## How it works

See [docs/design.md](docs/design.md). The pure logic lives in `Sources/MacalCore` and is covered by `swift test`; the app is in `Sources/Macal`.

## License

MIT (see `LICENSE`).

# Calbar

A macOS menu bar app that shows today's Google Calendar events across all your accounts and alerts you before each meeting.

## Download

Grab `Calbar.dmg` from the [latest release](https://github.com/emilevauge/calbar/releases/latest), open it and drag Calbar onto the `Applications` shortcut. Or from the command line:

```sh
curl -L -o Calbar.dmg \
  https://github.com/emilevauge/calbar/releases/latest/download/Calbar.dmg
hdiutil attach Calbar.dmg
cp -R "/Volumes/Calbar/Calbar.app" /Applications/
hdiutil detach "/Volumes/Calbar"
xattr -dr com.apple.quarantine /Applications/Calbar.app   # not notarized, bypass Gatekeeper
open /Applications/Calbar.app
```

Calbar was called **Macal** up to 0.2.9. A Macal install updates itself to Calbar: settings, accounts, the OAuth client and the login item carry over (macOS asks once per account to let Calbar read Macal's Keychain item), and `Macal.app` goes to the Trash.

Calbar does not ship with a Google OAuth client: on first launch, it asks you to import your own (see [Google OAuth client](#google-oauth-client)). It then updates itself: when a new release is out, a notification offers to install it.

## Features

- **Today's agenda**: every event of the day from all connected Google accounts, merged and deduplicated in one list. Browse other days with the arrows in the header.
- **Expandable details**: guests with their RSVP status, location, attached Drive documents and the event description.
- **Reply to invitations**: answer Yes, Maybe or No from the expanded event, or right-click any event row. The organizer gets the usual Google notification. Accounts connected before this feature must reconnect once ("Reconnect to reply").
- **Discord meetings**: a Discord channel or event link (`discord.com/channels/...`) in the location or description gets a Join button that opens it in the Discord app.
- **Join button in the Calbar icon**: a few minutes before a meeting with a video link, the menu bar icon grows into one orange capsule (red from 1 minute before the start and during the first minutes) holding a camera, the meeting title and the calendar countdown. Click the title to join the call (Google Meet, Zoom, Teams, ...), click the calendar to open Calbar, right-click for attachments, dismiss, or the event details.
- **Countdown icon**: the menu bar glyph shows the time left before the next meeting of the day ("12", "2h"), never the date. It turns orange when a meeting is close, red 1 minute before the start, During a meeting it glows red, like an "on air" sign, shows the minutes left in it, and the page fills up from left to right as the meeting runs.
- **Meeting heads-up**: when a meeting enters the alert window, and again when it starts, the panel opens by itself on that meeting for 8 seconds, without taking the keyboard from your app. Move the pointer onto it to keep it; click to see the whole day. Can be turned off in the settings.
- **Week view**: switch between Day and Week at the top right. The week is an hour grid (9:00 to 19:00 by default, configurable, scroll for the rest; all seven days, or only the ones you pick, such as Monday to Friday) with overlapping meetings side by side; click a meeting for its card, a day for its list.
- **Create events**: in the week view or the day grid, click an empty slot or drag over the time you want, like in Google Calendar, then fill in the editor that opens beside the week grid: title, times, calendar, video call (Google Meet or Zoom), repetition (daily, weekdays, weekly, every 2 weeks, monthly, yearly), guests (suggested from the people you meet and your Google contacts and directory; they get the invitation), location and description. While the editor is open, the grid shows your guests' availability, busy times hatched and the slots that fit everyone in green; click or drag on it to set the time.
- **Edit and duplicate events**: the pencil in an event's details (or right-click > Edit Event) opens the same editor beside the week grid, on your event; for a recurring one, apply the change to this event or to all of them. The copy icon (or Duplicate Event) opens it on a new copy, in any calendar you can write to.
- **Find a time**: the clock icon of an event with guests shows the week grid with everyone's busy times and, in green, the slots where the meeting fits for all of them (within the grid's hours). Show everyone, or click a person to see them alone. On your own event, click a time to move it there; guests get the update. Only busy times are shown, never what people do; calendars outside your organization may not be shared.
- **Delete events**: the trash in an event's details, or select one of your events and press ⌫. For a recurring event, choose this event, this and following events, or all events. Undo (or ⌘Z) within 10 seconds brings it back before Google is told.
- **Peek**: rest the pointer on the icon to open the panel on the current or next meeting alone, without leaving your app. Click to expand it to the whole day.
- **Global shortcut**: show or hide the popover from anywhere (default `⌃⌥M`).
- **Open at the start of the day**: the popover opens by itself at the first launch, wake or unlock of the day, from 6:00, when a meeting is still ahead today. Once a day at most, can be turned off in the settings.
- **Automatic updates**: Calbar checks GitHub for a new release every day. The notification's `Update` action downloads the DMG, replaces the app and relaunches it. Also available from *Settings > About*.
- **Launch at login**: optional auto-start via a user `LaunchAgent`.

## Requirements

- macOS 14 (Sonoma) or later.
- A Google account, and a Google Cloud project for the OAuth client (free).
- To build from source: Xcode or the Xcode Command Line Tools, with Swift 5.9+.

## Google OAuth client

Calbar talks to the Google Calendar API with your own OAuth client, so no secret is shared between users. Create it once:

1. On https://console.cloud.google.com, create a project named `Calbar`.
2. In *APIs & Services > Library*, enable the **Google Calendar API**.
3. Open *Google Auth Platform*. On a new project, the *Get started* wizard asks for the *Branding* and *Audience* settings below in one go:
   - *Branding*: set the app name to `Calbar` and pick a support email.
   - *Audience*: choose the **External** user type, then click **Publish app** to move it to *In production*. Do not request verification: you will see the "Google hasn't verified this app" screen once (click *Advanced > Go to Calbar*). While the app stays in *Testing*, refresh tokens expire after 7 days.
   - *Data access*: add the scopes `openid`, `.../auth/userinfo.email`, `.../auth/calendar.readonly` (to list your calendars) and `.../auth/calendar.events` (to reply to invitations).
4. In *Clients > Create client*, choose the **Desktop app** type, then download the JSON file.
5. In Calbar, click **Import google-oauth.json…** in the popover (or *Settings > Accounts > Import OAuth client…*) and pick the downloaded file. Calbar checks it and keeps a private copy (permissions `0600`) in `~/Library/Application Support/Calbar/google-oauth.json`. Then connect your Google accounts.

To switch to another client later, use *Settings > Accounts > Replace OAuth client…*. Accounts signed in with the previous client must be reconnected.

**Google Workspace accounts.** A Workspace admin can block unverified third-party apps, and sign-in then stops on an "Access blocked" page. Two ways out:

- the admin trusts the OAuth client ID in the *Admin console > Security > API controls > App access control*;
- if every account belongs to a single Workspace organization, create the client in a project of that organization and choose the **Internal** audience type instead of External. There is no unverified app screen and no 7-day token expiry, but only accounts of that domain can sign in.

Guest suggestions use the Google People API: enable it in the Cloud project of your OAuth client (APIs & Services > Library > People API).

## Zoom

To add Zoom meetings to the events you create, connect your own Zoom app (Calbar ships without one, as with Google):

1. On [marketplace.zoom.us](https://marketplace.zoom.us), **Develop > Build App > General App**, user-managed.
2. **OAuth Redirect URL** and **OAuth Allow List**: `https://emilevauge.github.io/calbar/zoom-callback/`. Zoom only redirects to https; that page hands the code to Calbar on `127.0.0.1:53682`, and nowhere else.
3. **Scopes**: add `meeting:write:meeting`.
4. Copy the **Client ID** and **Client secret** from **App Credentials** into *Calbar > Settings > Zoom*, then **Connect Zoom…** and approve in the browser.

The editor then offers *Zoom* next to *Google Meet*. Calbar creates the Zoom meeting, then puts its link in the event's location and description.

## Build

```sh
# Dev binary
swift build && .build/debug/Calbar

# .app bundle and DMG (--install also copies the app to /Applications)
./make-app.sh [--install]
```

For development, you can also copy your client JSON to `Sources/Calbar/Resources/google-oauth.json` (ignored by git; `google-oauth.example.json` shows the format). The dev binary uses it when nothing was imported. `make-app.sh` never puts it in `Calbar.app`, and fails if an OAuth client file ends up inside the bundle.

The `make-app.sh` script:

1. Builds `release`.
2. Renders the SwiftUI app icon at 1024×1024 via `Calbar --generate-icon`, then `sips` for every size and `iconutil` for `AppIcon.icns`.
3. Assembles `Calbar.app/Contents/{MacOS,Resources,Info.plist}` with `CFBundleIdentifier` `dev.calbar.app`, `LSUIElement` and the version.
4. Checks that no `google-oauth*.json` file is inside the bundle.
5. Signs the bundle with the `CALBAR_SIGN_IDENTITY` identity (default `Claudette Dev`) when it is in the keychain, ad hoc otherwise.
6. Registers it with LaunchServices so notifications work, then builds `Calbar.dmg`.

With an ad hoc signature, every build gets a new code hash and macOS may ask again for Keychain access. A local self-signed code signing certificate keeps the same identity across builds: create one in *Keychain Access > Certificate Assistant > Create a Certificate* (type *Code Signing*), then set `CALBAR_SIGN_IDENTITY` to its name.

To publish a release, bump `VERSION` and `BUILD` in `make-app.sh`, run it, and attach `Calbar.dmg` to a GitHub release tagged `vX.Y.Z`. Installed copies pick it up within a day.

## Privacy

- Calbar reads your calendars (`calendar.readonly` scope) and can modify events (`calendar.events` scope). It only uses the latter to reply to an invitation when you click Yes, Maybe or No: it changes your own answer and nothing else.
- Refresh tokens are stored in the macOS Keychain.
- Your OAuth client is stored in `~/Library/Application Support/Calbar/google-oauth.json`, readable by you only.
- Today's and tomorrow's events are cached in `~/Library/Application Support/Calbar/events.json`.
- No data is sent anywhere other than Google, except the daily update check, an anonymous request to the GitHub releases API.

## How it works

See [docs/design.md](docs/design.md). The pure logic lives in `Sources/CalbarCore` and is covered by `swift test`; the app is in `Sources/Calbar`.

## License

MIT (see `LICENSE`).

# Calbar design

Calbar is a native macOS menu bar app. It shows the Google Calendar events of the day across
several Google accounts, and alerts before each meeting with its video link. Its structure comes
from Claudette (`~/dev/claudette`), a sibling app by the same author on the same stack.

This document describes the current behaviour. The code is the reference when they disagree.

## Decisions

- Data source: the Google Calendar API, live, through OAuth, with any number of accounts.
- Alert: the join link is part of the Calbar menu bar item (a single `NSStatusItem`), plus a
  standard macOS notification when a meeting enters its alert window, and another when it
  starts.
- Menu bar: an icon only. It shows the time left before the next meeting of the day, or during
  a meeting the time left in it with the page filling up, never the date, and is an empty
  calendar page once no meeting is left today.
- UI in English only, no localization system. Dates are formatted with the `en_US` locale
  whatever the system language.
- Distribution: a DMG on GitHub Releases, signed ad hoc or with a local self-signed identity,
  updated in place by the app. The DMG never contains a Google OAuth client: each user creates
  their own and imports its JSON file into Calbar.

## Stack

- SwiftPM (tools 5.9), Swift 6.2 toolchain in Swift 5 language mode, macOS 14 or later,
  SwiftUI and AppKit.
- `LSUIElement`: no Dock icon.
- One dependency: `KeyboardShortcuts` (sindresorhus), for the global shortcut. Its `Recorder`
  view is not used, see "Settings".
- No Google SDK: OAuth and REST are written by hand on `URLSession`.
- Two targets: `CalbarCore`, the pure logic, tested with Swift Testing (`CalbarCoreTests`), and
  `Calbar`, the app.

## Components

Core (`Sources/CalbarCore`), no AppKit:

- `GoogleOAuth`, `OAuthClient`, `PKCE`: authorization URL, callback parsing, token requests and
  responses, email from the `id_token`. Secrets and tokens are redacted from `description`.
- `OAuthClientFile`: where the OAuth client comes from (imported file first, bundled resource of
  a dev build second), the shortened client ID shown in the settings, and when a new client
  forces the accounts to reconnect.
- `CalendarAPI`: `GET /users/me/calendarList` and
  `GET /calendars/{id}/events?singleEvents=true&orderBy=startTime&timeMin=...&timeMax=...`,
  paginated, with strict percent encoding (`FormEncoding`) so a "+" in an email survives. To
  answer an invitation, `GET /calendars/{id}/events/{eventId}` then
  `PATCH` of the same URL with `sendUpdates=all`. A 403 whose reason is
  `insufficientPermissions` or `ACCESS_TOKEN_SCOPE_INSUFFICIENT` becomes
  `APIError.insufficientScope`.
- `RSVPPatch`, `JSONValue`: the PATCH body, `{"attendees": [...]}`, built from the attendee list
  Google returned, kept as raw JSON objects, with only the `responseStatus` of the attendee
  flagged `self` changed.
- `GoogleModels`: wire formats reduced to the fields Calbar uses. Cancelled events and
  "working location" markers are dropped, meeting rooms are removed from the attendees, an
  empty title becomes "(No title)". All-day dates are local midnights. Each event keeps its raw
  Google id (`googleEventID`), derived from the end of the composite id for events cached before
  the field existed.
- `EventMerger`: merges every account and calendar, removes duplicates by `occurrenceKey`
  (`iCalUID` plus start time), hides declined events unless the setting shows them or the event was just answered. Among copies
  of the same meeting, the one on the account's primary calendar wins, then a copy not declined,
  then one with a video link: Google reports the answer of the calendar owner, so only the
  primary calendar copy reliably holds the user's own answer.
- `RefreshMerge`: keeps the previous events of an account or a calendar whose fetch failed.
- `MeetingLinkExtractor`, `MeetingLink`: video link from `conferenceData` entry points of type
  `video`, then `hangoutLink`, then the earliest known provider URL in the location (Meet,
  Zoom, Teams, Webex, Around, Whereby, Discord channel, event or invite links), then in the
  description. Zoom meeting links also get a `zoommtg://` URL that opens the Zoom app
  directly, Discord channel links a `discord://-/channels/...` one. A Discord channel's name
  alone ("#batcave") is not a link: its URL needs the server's and the channel's ids, which
  only a bot invited to the server could look up.
- `HTMLText`, `Linkify`: event descriptions as plain text with clickable links.
- `DayWindow`, `DayAgenda`, `DayListing`, `DayCache`: day boundaries in the local time zone,
  today's split into ongoing, upcoming and past events, the listing of any other day, and the
  in-memory cache of days fetched on demand.
- `NextMeeting`, `MenuBarBadge`, `AlertPlanner`, `JoinQueue`, `CapsuleStyle`,
  `NotificationPlanner`, `DayStartPolicy`: what the icon, the join capsule, the notifications
  and the day start opening show and when.
- `AgendaFormat`: "10:30-11:00", "in 12 min", "now", "now · 18 min left", "ended",
  "1 h 5 min", "3 events".
- `AppVersion`, `GitHubRelease`, `UpdatePolicy`, `SelfUpdateScript`: version comparison, parsing
  of the latest release, check cooldown and notification deduplication, and the installer
  script of the self-updater.

App (`Sources/Calbar`):

- `AppDelegate`: status item, popover, account actions, OAuth client import.
- `GoogleAuth`, `LoopbackServer`, `Keychain`: browser sign-in and access tokens.
- `EventStore`, `AccountStore`: events and accounts.
- `JoinController`, `StatusItemImage`, `StatusBarImage` (`CalendarGlyph`): the join capsule and
  the menu bar glyph.
- `MenuView`, `DayHeader`, `DayList`, `EventRow`, `EventDetail`, `MenuFooter`: the popover.
- `HoverCard`, `HoverCardController`: the card shown on hover.
- `NotificationHub`, `MeetingNotifier`: system notifications.
- `UpdateChecker`, `SelfUpdater`: updates.
- `SettingsView`, `CalendarPicker`, `ShortcutRecorder`, `LaunchAgent`, `DayStartOpener`.

## Google OAuth client

- Calbar ships without a client. Until one is configured, the popover shows "Calbar needs a Google
  OAuth client", a short explanation, an "Import google-oauth.json…" button and a "How to create
  one" link to the README section on GitHub. The settings "Accounts" section has "Import OAuth
  client…" (or "Replace OAuth client…" once one is set), with the client ID shortened as
  "4840…apps.googleusercontent.com". The secret is never shown.
- The import opens an `NSOpenPanel` limited to JSON files. The file is read with
  `OAuthClient.load(json:)`, which accepts only a "Desktop app" client (`installed` key) with a
  non-empty ID and secret. A valid file is copied, unchanged, to
  `~/Library/Application Support/Calbar/google-oauth.json`, created with permissions 0600 and
  swapped in atomically. An invalid file changes nothing and shows an error under the button.
- The new client is used at once, without a restart: `AppDelegate.auth` (published) and
  `EventStore.auth` get a new `GoogleAuth`, a sign-in in progress is cancelled, and a refresh
  starts. The client ID in use is remembered in the user defaults. When it changes, every saved
  account is marked "needs reconnect", since its refresh token belongs to the old client. The
  same client ID keeps the accounts working.
- Lookup at launch: the imported file first, then `google-oauth.json` in the
  `Calbar_Calbar.bundle` next to a dev binary (`Sources/Calbar/Resources/google-oauth.json`,
  git-ignored). The resource bundle is found by hand rather than with `Bundle.module`, whose
  generated accessor aborts the process when the bundle is missing, as in the release app.
- `make-app.sh` copies no SwiftPM resource bundle into `Calbar.app`, and fails if any file named
  `google-oauth*.json` ends up inside the bundle.

## Sign-in and tokens

- OAuth "installed app" flow with PKCE (S256). A loopback HTTP server listens on `127.0.0.1`
  on a port picked by the system. Only a request carrying the expected `state` counts; anything
  else gets a 404 and the server keeps listening. The consent page opens in the default
  browser, with `access_type=offline` and `prompt=consent` so Google always returns a refresh
  token, and `login_hint` when reconnecting an account.
- Scopes: `openid email https://www.googleapis.com/auth/calendar.readonly
  https://www.googleapis.com/auth/calendar.events`. `calendar.readonly` reads the calendar list,
  which `calendar.events` does not cover; `calendar.events` lets Calbar change an event, and
  Calbar only uses it to answer invitations.
- The scopes Google granted (the `scope` field of the token response) are saved with the account
  at sign-in and on every token refresh. An account without `calendar.events` (or the full
  `calendar` scope) is read-only: signed in before Calbar asked for it, or with the box unticked
  on the consent screen.
- The browser page after the redirect says "Calbar is connected." or "Sign-in refused.". The
  wait gives up after 5 minutes, and "Cancel" stops it.
- One refresh token per account in the login keychain (service
  `dev.calbar.app.google-refresh-token`), updated in place so a failed write never loses the
  previous token. Access tokens stay in memory with one minute of margin before expiry, and are
  refreshed once after a 401.
- Removing an account revokes its refresh token and deletes it.

## Events

- `EventStore` fetches today and tomorrow for every enabled calendar of every account, accounts
  in parallel and at most 6 event requests in flight per account. It polls every 5 minutes,
  every 30 seconds while offline, on wake, and when the day changes. It publishes `now` every
  15 seconds so countdowns move.
- A refresh requested while one runs is not dropped: the running refresh does one more pass,
  so a new account or a toggled calendar is picked up.
- Offline means no account got an answer from Google. The previous events stay on screen and
  alerts keep working on them. A failed account or calendar keeps its previous events.
- Today's and tomorrow's events are cached in `~/Library/Application Support/Calbar/events.json`
  and shown at launch before the first refresh. An account never fetched yet shows "Loading…"
  instead of an empty day.
- New calendars start disabled, except each account's primary calendar. The user turns the
  others on in the settings. The choice survives calendar list refreshes.
- Logs carry counts and positions only, never calendar names, IDs or event content.

## Answering invitations

- `CalendarEvent.canRespond`: the event has an attendee flagged `self` who is not the organizer,
  and it was read from the account's primary calendar. On a colleague's shared calendar, Google
  flags the calendar owner as `self`, and an answer there would change the colleague's answer.
  Events the user organizes and events without guests have no RSVP control.
- Expanded row: a first line "Going?" with three pills, "Yes", "Maybe", "No". The current answer
  is filled (green, orange, red, white text); the others have a neutral outline. While the answer
  is sent the pills are dimmed and disabled, without a spinner. A read-only account shows a
  "Reconnect to reply" link instead, which runs the usual reconnect sign-in (`login_hint`).
- Right click on any event row, today or another day: "Going: Yes", "Going: Maybe", "Going: No"
  with a checkmark on the current answer, disabled and followed by "Reconnect to reply" for a
  read-only account; then "Open in Google Calendar".
- `EventStore.respond(to:with:)`: the answer is applied at once to the event in memory (and in
  the day cache), so the row, the guest list and the declined filter follow. The API call uses
  the access token with the usual refresh after a 401. The answer covers only that occurrence of
  a recurring meeting. On success, a normal refresh follows. The answer is laid over fetched
  events while in flight, and once confirmed until a refresh started after the confirmation,
  so a refresh already running does not flip it back.
- On failure the previous answer comes back and a short red message shows under the pills for
  5 seconds. `insufficientScope` marks the account read-only ("Reconnect to reply"); an expired
  refresh token marks it "needs reconnect".
- An event declined from the popover stays in the list, with "· declined", until the popover
  closes, even when "Show declined events" is off, so the row does not vanish under the pointer.

## Menu bar icon

- A small calendar page drawn in code (`CalendarGlyph`): rounded outline, header band, and the
  minutes left before the next meeting of the day inside, rounded up ("25"), then whole hours
  from 60 minutes ("1h", "2h"). The next meeting is the earliest timed, not declined event that
  starts after now and before the end of today.
- Outside the alert window: template image, tinted by macOS for light and dark menu bars. Within
  the alert window (from start minus the lead time): the same page with outline, band and
  digits in `systemOrange`, a slightly heavier outline, no background. One minute or less before
  the start: the same in `systemRed`. No timed meeting left today: empty outline.
- An account that needs reconnecting: filled template page with a punched-out "!", above
  everything else.
- During a meeting (the ongoing timed, not declined event that ends first): the minutes left
  in it instead of the countdown to the next one, the page under the band filling from left to
  right with the elapsed part (a 28 % tint of the ink), and a red glow around the page, like an
  "on air" sign, from the first second to the end. The glow needs color, so this image is not a
  template: its ink is black or white after the menu bar's appearance, redrawn when it changes.
  The image is 4 pt wider, for the glow. The next meeting still takes over with its orange or
  red countdown once it is within the lead time, so a back-to-back meeting keeps its alert; the
  glow stays around it while the current meeting runs (and around a warning). Not around the
  join capsule, which already stands out.
- The first minutes of a meeting (from its start to start plus the linger delay, until it is
  dismissed; joining does not count) look the same; they only keep the join capsule and make it
  red. A meeting without a
  link cannot be dismissed from the menu bar: the page stays red until the delay ends.
- While a meeting with a link is due, the page is drawn inside the join capsule instead.

## Join capsule

- No second status item: while a meeting with a video link is due, the item's image becomes one
  capsule. Due means from start minus the lead time (10 minutes by default) to start plus the
  linger delay (5 minutes by default), not declined, not all-day, not dismissed.
- Look: white capsule 18 pt high, corner radius 5.5 pt, 1 pt border in the urgency color:
  `systemOrange` in the alert window, `systemRed` one minute or less before the start and after
  it, the accent color as a fallback. Left to right in that color: `video.fill`, the title
  truncated to 160 pt (a darker orange for text, for contrast on white), a "+1" chip when
  several meetings are due, a thin separator, then the colored calendar page with its countdown.
- Left click on the title part joins the earliest due meeting, in the provider's app when a
  native URL exists and the app is installed. Left click on the calendar page toggles the
  popover. The capsule stays until the linger delay ends, so the link is still there to rejoin.
- Right click or control-click: a menu with, for each due meeting, its title and time range,
  "Join", one item per attachment, "Dismiss"; then "Open Calbar", which opens the popover with
  the meeting expanded. Without a due meeting, a right click toggles the popover.
- Only "Dismiss" removes a meeting from the capsule and the red page. Dismissed meetings are kept
  in memory per occurrence: a relaunch during the window shows them again.
- Accessibility label: "Calbar", or "Calbar, Join <title>" while a meeting is due.

## Hover

- Resting the pointer 0.5 s anywhere on the item, capsule included, opens the popover itself in
  "peek" mode, never a separate tooltip panel: one meeting's card alone, then "Click for the
  whole day". The meeting is the one the join capsule is about, else the ongoing one, else the
  next of today; once the day is over, "Nothing left today" and the first event of tomorrow. A
  red "An account needs to be reconnected" line comes first when needed.
- A peek does not activate Calbar, so the keyboard stays with the current app. A click on the
  icon, or on the card outside its buttons, expands it to the whole day with an animation and
  gives it the keyboard. It closes 0.4 s after the pointer has left both the icon and the
  popover, checked every 150 ms rather than with a tracking area, which would miss the gap
  between them. A click on the icon keeps the peek off until the pointer leaves it.

## Popover

`NSStatusItem` plus `NSPopover` (transient) rather than `MenuBarExtra`, so code can open it (the
global shortcut, "Open Calbar", notifications). Width 380 pt, list up to 560 pt high.
- Size and motion: the popover fits its content. `PopoverHost` holds a plain hosting view in a
  container without constraints and, on each layout pass, sets the popover's `contentSize` to
  the view's intrinsic size inside an `NSAnimationContext` of 0.25 s ease-in-out. Every change
  that resizes the content (peek expanding, a row, the guest list, "ended earlier", the all-day
  chips) uses `Motion.resize`, the same curve and duration, so the panel and its content move
  together; the content is pinned to the top. A hosting controller as content, or even as a
  child, lets SwiftUI resize the popover itself, at once: measured, the frame jumped to its
  final size in the first 16 ms while the content animated for 250 ms.
- A peek is the same view with the header, the all-day chips, the other rows, the free time,
  the ended section and the footer hidden, and the peeked meeting as the card: expanding
  brings them in around the card, which slides into place.

- Header, above a separator: the title of the day shown, "Tuesday, September 29", 15 pt semibold, with a caption
  below it: for today, "offline · updated 5 min ago" when offline, otherwise "Today · 3 left"
  or "Today · nothing left"; for another day, "Yesterday" or "Tomorrow" when it applies and the
  number of events ("Tomorrow · 3 events"), nothing for an empty day. On the right, `‹` and `›`
  icon buttons (28 x 24 pt, tooltips "Previous day" and "Next day") grouped on a light
  background. A click on the title, which has a small chevron ("Pick a day"), opens a month
  calendar in a popover, drawn in code (the graphical `DatePicker` cannot change the year but
  month by month): month arrows, a menu on the year (10 years back, 5 ahead), the days from the
  user's first weekday with today circled and the shown day filled, and "Today". Picking a day
  shows it; "Today" goes back to today. No focus ring. The popover goes back to today every time it closes.
- Today: all-day events as small colored chips on one line (those that do not fit fold into a
  "+N" chip, which unfolds them all on wrapped lines, with a chevron to fold them back), then ongoing
  and upcoming timed events, then "N ended earlier", folded, which unfolds the past events
  dimmed below it. The ongoing meeting, or else the next one, is drawn as a card and cannot be
  collapsed. Once the timed events are over: "Nothing left today" and the first event of
  tomorrow ("Tomorrow 09:00 · Standup"). Between two events at least 30 minutes apart, a
  separator gives the free time ("2 h free"), measured from the latest end above it, so an
  event nested in a longer one opens no gap. The ended section folds again when the popover
  closes.
- Other days: today and tomorrow come from the regular refresh. Any other day is fetched on
  demand (one day window, every enabled calendar of every account, same parallel fetch and 401
  handling), kept in memory for 5 minutes, and marked stale by every regular refresh, so also
  when a calendar is toggled. A stale day keeps its events on screen while it is fetched again.
  "Loading…" during the first fetch, "Could not load this day" with "Retry" after a failure.
  The listing has the all-day chips then every timed event in order with the free time
  separators: no card, no ended section, nothing dimmed, the duration instead of the relative
  time, no join button for an event already over. An event across midnight shows on both days;
  a multi-day all-day event shows on each day. The icon, the capsule, the notifications and the
  peek stay on today.
- Day | Week: a small segmented switch between the header's arrows, persisted (`viewMode`).
  Clicking Day while it is selected switches the day between its list and a one-column hour
  grid (`dayGrid`: the week view's grid at 380 pt, without the column header), with a small
  `list.bullet` or `calendar.day.timeline.left` icon beside "Day"; coming back from the week
  restores the last day layout. The title falls back to "Wed, Sep 30" when the full one does
  not fit beside the switch. In
  the week view the arrows and `←` `→` move by a week, the title reads "Sep 28 - Oct 4" (with
  the year outside the current one) over "This week", "Next week" or "Last week", and the day
  picker shows the week of the picked day. The popover widens to 720 pt, animated like any
  resize. A peek always uses the day layout.
- Week view (`WeekView`, `WeekLayout`): a column per shown day ("Week view days", all 7 by
  default, sharing the 720 pt), from the user's first weekday, headed
  "Mon 28" with today's date in an accent circle (a click shows that day in the day view), then
  the all-day area and an hour grid of 44 pt per hour, translucent like the rest of the popover.
- All-day area (`WeekLayout.bars`): all-day events and timed events of 24 hours or more
  (`spansDays`, not in the grid) as one bar across the days they cover, clipped to the week
  with a chevron on a side that continues, "Trip to Lyon, 08:00" for a timed one starting this
  week. Longer and earlier bars take the first free row. Two rows, then a "+N" under each day
  with hidden bars, which unfolds every row; a chevron folds them back. The hours from
  "Week view from" to "Week view until" (9 and 19 by default) fill the visible height; the grid
  covers the whole day and opens scrolled to the first one. Timed events are opaque blocks (a
  text background base under the calendar color, 30 % in light mode, 42 % in dark) with a
  hairline border and a leading bar, 1 pt apart, title and start time. Their text uses the label
  color at a set opacity, not `.secondary`, which on the popover material is vibrant and can
  vanish against the block; events that overlap split their
  group into lanes, each taking the first free one (back to back is no overlap); an event across
  midnight is clipped to each day. The same styles as the list: dashed border while an
  invitation waits, a lighter tint and grey text once past or declined, struck through when
  declined. A red line with a
  dot marks the current time in today's column, tinted lightly. A click on a block opens its
  card in a popover (Join, RSVP, guests, documents). The week is fetched in one request window
  for the days the regular refresh does not cover, then kept in the day cache.
- Card: "NOW" in red for an ongoing meeting, the time range and the time left ("35 min left")
  or the relative time ("in 12 min"), the title on up to 3 lines, and a "Join" button on the
  right when there is a video link. An ongoing meeting has a progress bar (see below).
  The details follow. Light fill and border in the calendar color, accent border when selected.
- Row: start and end times in a 38 pt column, a 3.5 pt bar in the calendar color, the title and
  a caption line. The bar is dashed while the invitation waits for an answer. A declined event
  (shown with "Show declined events") has a hollow bar, its title struck through in the
  secondary color, the whole row faded, and "Declined" in red with an `xmark.circle` icon.
  Caption: "Needs reply" in orange, "Declined",
  the relative time on today ("in 12 min", "now · 18 min left", "ended") or the duration on
  other days, then in the collapsed row the guest and attachment counts and the location
  unless it is a URL. A discreet camera button on the right joins the video call.
- Progress: every ongoing meeting, card or row, has a
  3.5 pt bar of the elapsed time, colored like Claudette's context bar: green below 50 %, yellow
  below 75 %, orange below 90 %, then red. Tooltip "20 min of 45 min · 44%".
- Creating an event (`EventEditor`, `EventComposer`, `NewEvent`): in the week view or the day
  grid, pressing on an empty slot (outside the blocks) and dragging, up or down, marks out a
  ghost block that follows the pointer, labelled "10:00-11:30", from the quarter hour under the
  press to the quarter hour past the pointer (`NewEvent.range`, 15 min at least, within the
  day); a plain click makes it 30 minutes. On release the editor opens in a popover on the
  ghost, as an event's card opens on its block, so the main popover stays open. Blocks and the
  ghost are placed with padding, not `offset`, which moves the drawing but not the frame a
  popover anchors on. A new selection replaces the one being edited; the editor opens once a
  popover still closing (0.35 s) is gone, since SwiftUI drops a presentation made during that
  animation. It is a plain form, 380 pt wide: the title ("New event", 17 pt) beside a bar in
  the calendar's color, then day, start, an arrow, end and the duration, each a chip that
  opens a popover; a divider, the fields with an icon each (the calendar's line has its color
  dot), the choices as borderless menus with up and down chevrons and a check mark on the
  current one; a divider, then "esc to cancel", Cancel and Save. Edited in place of a card,
  the same form sits in the card's tinted box. The day opens the same
  month calendar as the header (`DayPicker`); a time opens a scrolling list of quarter hours
  (`TimeList`) centered on the current one, the end times with the duration each gives
  ("15:30 1 h 15 min", up to 24 hours). A new start keeps the duration, a new day both hours;
  the title (focused, "(No title)" when left blank), then the lines: the calendar (the writable calendars, `accessRole` owner or
  writer, of the accounts with the write scope, grouped by account, primary first; the last one
  used is remembered), "Google Meet" (remembered, on by default), the repetition
  (`RepeatRule`: does not repeat, daily, every weekday, weekly on the start's day, every 2
  weeks, monthly on the nth weekday or on the day, "the last" for a fifth weekday, annually;
  one `RRULE:` line, no end), guests, location, description. `↵` saves. `esc` closes it when
  nothing changed; otherwise "Discard this event?" (or "your changes") with Keep Editing and
  Discard, a second `esc` discarding. The key is caught by a local `NSEvent` monitor
  (`EscapeCatcher`) in the editor's window, before the text field's field editor or the
  popover, which would otherwise take it; a time or day picker is its own window and closes as
  usual. A click outside closes it.
- Editing and duplicating (`EventEditor.Mode`): the edit and copy icons of `EventActions`, or "Edit Event…" and "Duplicate Event…" in the context menu, set
  `EventStore.editRequest`; the `EventRow` of that event shows the editor in place of its card
  or row (in the panel, or in the grid's popover, which stays open), and the editor of a copy
  in a popover on itself. While an editor is in the panel, its arrow, `⌫` and `↵` shortcuts
  stand aside. Edit is offered on the same events as delete. The editor is filled from the event:
  title, times (an all-day event shows its day alone, "All day, 3 days"), guests but the
  user, location, the description as plain text. Editing keeps the calendar (no move) and an
  existing video link; a recurring occurrence gets "This event | All events" instead of the
  repetition. Save reads the event (`events.get`) and patches only what changed
  (`EventPatch`): unchanged notes keep their HTML, kept guests keep their answers, the user
  and meeting rooms stay; for all events the series itself is patched, its times moved by the
  same amount from its own start. `sendUpdates=all` when there are guests before or after.
  Duplicate opens a new event with the same fields, a new Meet link for a Meet, in the
  event's calendar when writable.
- Guests: chips with a remove button, then a field. Suggestions, six at most, one per email:
  first the people met (`ContactIndex`: attendees and organizers of the loaded events, and in
  the background, once per launch and again after six hours, of each account's primary
  calendar from 60 days back to 30 ahead; a word of the name or the email starting with the
  text, accents and case ignored, people met more often first), then Google matches
  (`PeopleAPI`, 250 ms after the typing pauses, from two letters): the account's contacts
  (`people:searchContacts`), the people it emailed (`otherContacts:search`) and its Workspace
  directory (`people:searchDirectoryPeople`), each behind its read-only scope
  (`contacts.readonly`, `contacts.other.readonly`, `directory.readonly`), searched in every
  account granted it; a failing source is skipped. Without any of these scopes, "Reconnect your
  account in Settings to search your Google contacts". `↑` `↓` move, `↵` or `tab` picks, `,` `;`
  or `↵` adds a typed email, `⌫` in the empty field removes the last chip. The user's own
  addresses and Google resource calendars are left out. Guests get the invitation
  (`sendUpdates=all`). The People API must be enabled in the OAuth client's Cloud project.
- Video call (`ZoomAuth`, `ZoomOAuth`, `ZoomAPI`): "No video call", "Google Meet" or, once Zoom
  is connected, "Zoom", remembered (`newEventConference`). Google's API only creates Meet links,
  and the Zoom add-on of Google Calendar runs in its web page, out of reach. So Calbar signs in
  to the user's own Zoom app (Settings > Zoom: Client ID and secret, sent as Basic auth, both
  saved to the Keychain as they are typed). Zoom redirects only to https (a loopback address
  only for PKCE public apps, error 4700 otherwise), so the redirect is
  `https://emilevauge.github.io/calbar/zoom-callback/`, a static GitHub Pages page
  (`docs/zoom-callback/`) that forwards the query, code and state, to Calbar's listener on
  `http://127.0.0.1:53682` and nowhere else; the state is checked there as for Google, with
  PKCE as well. Client and refresh token in the Keychain under `dev.calbar.app.zoom`,
  the refresh token replaced on every refresh since Zoom rotates it, a refused one
  disconnecting). On save with Zoom, Calbar first creates a scheduled meeting
  (`POST /users/me/meetings`, scope `meeting:write:meeting`: topic, UTC start, duration, time
  zone, the description as agenda), then puts its link in the event's location when empty
  and, as Zoom's add-on does, "Join Zoom Meeting", the link, the meeting ID and passcode on top
  of the description, where Calbar's join detection and Google Calendar find it.
- Calbar posts `events.insert` (with `conferenceDataVersion=1` and a `hangoutsMeet` create
  request for Meet), in the user's time zone, then refreshes. Errors show in the editor; a
  missing scope marks the account read only. Calendars stored before the access role was known
  count as writable only when primary, until the next refresh fills it.
- Event actions (`EventActions`): edit, duplicate, delete, Google Calendar and, on a row,
  Join, each an `ActionIcon`: 26 by 24, 13 pt, secondary (Join in the accent color), a light
  rounded square on hover (the recurring trash is a menu with the same face). At the top
  right: on the card's time line, beside its Join button, and on the top line of an expanded
  row; a collapsed row keeps the Join icon alone.
- Deleting: the trash of `EventActions` (card, expanded row, grid popover), `⌫` on the selected row of the list or in the open card of the grid (tested on
  the characters: macOS sends backspace as DEL, U+007F, which SwiftUI's `.delete` does not
  match), or "Delete Event" in the context menu. For a recurring event the trash and the context
  menu offer "This event", "This and following events" and "All events"; `⌫` shows the same
  choice in a bar above the footer (`esc` cancels). Only the user's own events (`isDeletable`: on one of
  their calendars, organized by them or without guests) of an account with the write scope;
  otherwise a beep. Deleting someone else's invitation would be declining it, which "Going?"
  does. The event is hidden at once and an "Undo" bar shows above the footer ("Deleted
  “Design sync”", the seconds left, Undo or `⌘Z`); Google is told only after 10 s
  (`events.delete` on the occurrence, or on the series for all events; for this and following,
  the series' rules get `UNTIL` just before the occurrence's original start in place of any
  `COUNT` or `UNTIL`, and the whole series goes when it is the first occurrence; `sendUpdates=all` when there are
  guests, so they get Google's cancellation). Undo within the delay sends nothing. A quit within
  the delay keeps the event. A failure brings it back with a red line and OK.
- Details (card, or a row expanded by a click, one at a time): the "Going?" line for an
  invitation (see "Answering invitations"), the video provider when there is no Join button,
  location (opens Maps, or the URL when the location is one), organizer, guests as up to 5
  initials in colored circles with "5 guests · 3 yes" (a click lists each guest with their
  answer), Drive attachments as chips with a type icon, the description as plain text with
  clickable links; the Google Calendar icon of `EventActions` opens the event pinned to
  its account. Initials colors come from the email, so a person keeps the same color.
- Keyboard: `↑` `↓` move the selection, `←` `→` change the day, `↵` expands, `⌘↵` joins, `esc`
  closes. `⌘R` refreshes, `⌘,` opens the settings, `⌘Q` quits.
- Empty states: "Calbar needs a Google OAuth client" (see above), or "No Google account connected"
  with a "Connect a Google account" button.
- Footer: refresh, Google Calendar home (pinned to the first account), settings, quit.
- Day start: at the first activity of the day (launch, wake, screen unlock, return to the
  session), the popover opens by itself when a timed, not declined meeting is left today. At
  most once a day: the day (`yyyy-MM-dd`, current calendar) is recorded only once the popover
  really opened, so a day without meetings left is checked again at the next trigger. The
  decision waits for a refresh completed after the trigger, 60 s at most, then uses the cache.
  Nothing while the screen is locked. Nothing before 06:00 local time: an earlier trigger arms
  a timer for 06:00, which runs the same check. The popover opens 1.5 s after the decision. Setting "Open
  the panel at the start of the day", on by default.

## Notifications

- `NotificationHub` is the only `UNUserNotificationCenter` delegate. It asks for `[.alert, .sound]`
  at launch, keeps one registry of categories, and routes each response to the handler of the
  notification's kind (`meeting` or `update`, stored in the userInfo). Banners also show while
  Calbar is the active app.
- Meetings (`MeetingPeeker`, `NotificationPlanner`): no system notification. For timed, not
  declined events, with or without a link, the popover opens in peek mode on the meeting
  twice per occurrence: when it enters its alert window, before its start, and at the start,
  until the alert window ends (so a Mac woken 2 min after the start still gets it). The peek
  stays 8 s, then closes by itself, unless the pointer is on it or the icon: then it follows the
  hover rule. A peek already showing moves to the newer meeting; the start wins over an alert
  due at the same tick. A stage counts as done only once the peek showed: while the screen is
  locked or the full popover is open, it waits for a later tick within its window. Dismissed
  meetings are skipped. A moved meeting has a new key and peeks again. Each timed peek plays the
  "Glass" system sound. The peek opens after the icon is redrawn, so it anchors on the capsule
  that appears in the same tick, and the popover is anchored again whenever the icon changes
  width under it. Settings "Show the panel before a meeting" and "Play a sound", both on by
  default.
- System notifications only offer updates (see "Updates").

## Updates

- `UpdateChecker` asks `https://api.github.com/repos/emilevauge/calbar/releases/latest` at launch,
  then every 24 hours and on wake, at most once per 24 hours (a check that did not reach GitHub
  does not count). Only in a .app bundle: a dev binary has no version to compare.
- The tag ("v0.2.0" or "0.2.0") is compared with `CFBundleShortVersionString` component by
  component, a pre-release suffix ignored. A newer version posts "Calbar 0.2.0 is available" once
  per version, with an "Update" action and a "Release notes" action. A click on the body opens
  the release page.
- "Update" (from the notification or from the settings) runs `SelfUpdater` with the `Calbar.dmg`
  asset (https only). It refuses a dev binary, an app running translocated from the DMG or
  Downloads, and a folder it cannot write to. It downloads the DMG, writes the helper script of
  `SelfUpdateScript` in a temporary folder, starts it detached with zsh and quits. The script
  waits for Calbar to exit (10 s at most), mounts the DMG read-only, checks that it holds a
  `Calbar.app` with its executable, moves the installed app to a backup, copies the new one, puts
  the backup back if the copy fails, removes the quarantine flag, detaches the DMG, relaunches
  Calbar and deletes its folder. Failures show as a notification, or under the button in the
  settings. A release without a DMG opens the release page instead.

## Settings

A grouped form in a popover anchored to the gear button, 380 pt wide, scrolling within 560 pt.

- Google accounts: one card per account, so its calendars plainly belong to it. At the top of the
  card, the account initials on their color, the email, a status ("Connected", "Read only ·
  reconnect to reply to invitations", or "Signed out · reconnect to see events" in red),
  "Reconnect" when the account is read only or signed out, and a trash button that removes it.
  Below, the calendars folded under a "Calendars" row that reads "2 of 14 shown", with a toggle
  each. Then a card with "Add a Google account…" or the sign-in progress with "Cancel", and the
  last sign-in error; its footer gives the OAuth client ID, shortened, with "Import…" or
  "Replace…".
- Alerts: "Alert before" (1 to 60 min, default 10), "Keep after the start" (0 to 30 min, default
  5), "Show the panel before a meeting" (on), "Play a sound" (on, disabled when the panel
  setting is off). Footer: "Before each meeting and at its start, the
  panel shows it for a few seconds, and a Join button shows in the menu bar."
- Display: "Show declined events" (off), "Week view from" (0 to 23, default 09:00) and "Week
  view until" (1 to 24, default 19:00), "Week view days": one toggle per weekday from the
  user's first weekday (at least one stays on) with "Mon-Fri" and "All" presets, stored as
  `Calendar` weekday numbers ("23456"). Footer "The week view shows these days and hours;
  scroll for the rest of the day."
- Global shortcut: "Open Calbar", default `⌃⌥M`. Recorded by `ShortcutRecorder`: click, type the
  shortcut, `esc` cancels, `delete` clears. It needs a modifier besides Shift, or a function key.
  `KeyboardShortcuts.Recorder` is not used: its placeholder reads the package's resource bundle
  through `Bundle.module`, which aborts the released app on any Mac other than the build one.
- Startup: "Launch at login" (a user LaunchAgent `dev.calbar.app` pointing at the running
  executable, repointed at launch when the recorded binary is gone or when Calbar runs from
  `/Applications`), "Open the panel at the start of the day" (on).
- About, always last: version, "Check for updates" with "Up to date", "0.2.0 is available" or an
  error, "Update to 0.2.0 now" and "Release notes" when newer; when macOS blocks Calbar's
  notifications, an orange "Update notifications are off" with "Open System Settings" (the
  Notifications pane), or before the first answer "Notifications not allowed yet" with
  "Allow…", read each time the settings open; license MIT, source link
  github.com/emilevauge/calbar, "© 2026 Emile Vauge".

## Errors

- A reply refused for lack of scope marks the account read-only: "Reconnect to reply" in the
  expanded row and the context menu.
- A revoked or expired refresh token marks the account "needs reconnect": "Reconnect" in red in
  the settings, "!" in the menu bar icon, a red line in the peek.
- Sign-in errors show under the account list with a short message ("Access denied in the
  browser.", "No Internet connection.", ...). A cancelled sign-in shows nothing.
- No network: the cache stays on screen with "offline · updated N min ago"; alerts continue.
- An API error on one calendar keeps the other calendars, and that calendar's previous events.

## Renamed from Macal

The app was Macal up to 0.2.9 (bundle id `dev.macal.app`, repository `emilevauge/macal`, now
`emilevauge/calbar`; GitHub redirects the old API URLs). `LegacyMacal`:
- Transition: Macal's updater fetches the release asset `Macal.dmg`, requires an executable
  `Macal.app/Contents/MacOS/Macal`, and installs it in place of `Macal.app`. `make-app.sh`
  therefore also builds `Macal.dmg`: Calbar as `Macal.app`, with a `Macal` symlink to the
  `Calbar` executable, signed again. Every release carries it, for Macs that skip versions.
- Relocation: launched from a bundle named `Macal.app`, Calbar copies itself to a sibling
  `Calbar.app`, starts it once this process has quit (one second later, quarantine flag
  removed), and exits before the single-instance check.
- Migration, once (`migratedFromMacal`), before any store reads its data: quit a running
  Macal; copy every key of Macal's defaults domain not set yet, the global shortcut under its
  new name; copy each account's refresh token from the `dev.macal.app.google-refresh-token`
  Keychain service (macOS asks once per item); copy `google-oauth.json` (0600) and
  `events.json` from `Application Support/Macal`; replace a Macal LaunchAgent with Calbar's.
  Macal's data is left in place, so going back still works.
- Cleanup, at each launch: a `Macal.app` next to Calbar, Macal itself or the transition copy,
  goes to the Trash.
- Notification permission is per bundle id: macOS asks again, for update notifications.

## Packaging

`make-app.sh` builds in release, assembles `Calbar.app` (bundle id `dev.calbar.app`, version
0.1.0, build 1, `LSUIElement`, icon rendered by `Calbar --generate-icon` then `sips` and
`iconutil`), checks that no OAuth client file is inside, signs with the identity in
`CALBAR_SIGN_IDENTITY` (default "Claudette Dev") or ad hoc when it is missing, registers the app
with LaunchServices, and builds `Calbar.dmg` (volume "Calbar", with an `Applications` link).
`--install` also copies the app to `/Applications`.

A single instance runs at a time: a copy started while another with the same bundle id runs
exits at once.

## Tests

`CalbarCoreTests`, Swift Testing, covering the core: OAuth URLs, callbacks and token parsing,
OAuth client file lookup and masking, Calendar API pagination and encoding, the RSVP request
(method, URL, body with unknown attendee fields kept, scope errors), granted scopes, Google models,
merging and deduplication, refresh merging, link extraction, HTML text, day windows and
listings, the day cache, next meeting, badge, alerts, join queue, capsule style, notification
planning, day start policy, labels, version comparison, release parsing, update policy and the
update script. OAuth sign-in, the UI and the update itself are tested by hand.

## Out of scope

- Creating or editing events, other than answering an invitation.
- Answering every occurrence of a recurring meeting at once, and adding a note to an answer.
- Other calendar providers (iCloud, Outlook).

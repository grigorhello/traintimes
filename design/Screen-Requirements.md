# Train Times v1 — Screen Requirements

Nov 5, 2026 · @Grigor

## Purpose and scope

This document specifies how every version 1 screen of the GO Train iPhone app behaves, so it can be built in SwiftUI without further design decisions. The visual source is the design canvas [GO Train App — iPhone v1](https://claude.ai/code/artifact/5ad8642b-4e0b-4d23-b6f5-fb800acbb10e) and the design system [GO Train App](https://claude.ai/code/artifact/fefd0b1c-3c6f-446d-9bf8-874bf1252452); the product source is the GO Train App Product Design Brief v1 (4 Nov 2026). Where this document and the brief differ, this document wins: the Schedule screen is a calendar-style timeline, not the brief's row list.

The product promise is unchanged: know when your train leaves, whether it is delayed, and when something changes. Every decision below serves a hurried rider using one hand, who should read the next departure and its status in about three seconds.

| In version 1 | Out of version 1 |
| --- | --- |
| Direct GO trains between two stations, scheduled departures and arrivals, a date choice of up to 42 days | Login, payment, subscription, advertising, sponsor placement |
| Saved last route and the last three routes opened (Recent), kept on device (D48) | AI chat, live train maps, ticketing, refunds |
| Live status: on time, delayed, cancelled, scheduled only, stale, offline | Bus planning, UP Express, transfer routing, crowd reports |
| Published platform, or Platform pending | Calendar access, GPS tracking, widgets, Apple Watch app |
| Trip details with stop list and arrival basis | Delay threshold settings or any advanced alert options |
| One-off and repeating weekday alerts, anonymous, server monitored, delivered by APNs | Any claim of real-time, instant or guaranteed delivery |
| Light and dark appearance, Dynamic Type, VoiceOver, 12/24-hour time |  |

All station names, times, platforms, train numbers and stop lists shown on the canvas are illustrative fixtures. Fixtures stay isolated from production data and are never shown as live service.

## Navigation and shared rules

The app has three bottom tabs, Schedule, Alerts and Settings, and nothing else at the top level (D48). On iOS 26 and later the bar is a floating Liquid Glass capsule with icons only (a tram, a bell, a gear; the system draws the selection), and content scrolls under it with a soft fade (D49); earlier iOS keeps the opaque bar with the same icons. Tapping the Schedule tab while Schedule shows scrolls the timeline to Now and returns to Today, so there is no Now button anywhere (D49). Route editing, station search, trip details, alert setup and line notices open as native sheets (`.sheet`), so the timetable is always one dismiss away. There is no splash, tutorial, permission request or carousel before the first timetable.

**Trip identity never changes.** A trip is keyed by service date plus the feed's stable trip id, never by departure time. In every label and notification the train is named by its scheduled origin departure: the 7:32 AM train stays "7:32 AM train" when its estimate moves to 7:41 AM. Do not create a new trip when an estimate moves.

**Status is always colour plus word plus icon**, from this closed set:

| Status label | When it applies | Colour tokens | SF Symbol |
| --- | --- | --- | --- |
| On time | Fresh live evidence or a fresh applicable prediction with delay under 3 min | ontime-ink on ontime-fill | checkmark.circle.fill |
| Delayed N min | Reported departure delay of at least 3 min | delay-ink on delay-fill | clock.badge.exclamationmark |
| Cancelled | Trip cancelled in the feed | cancel-ink on cancel-fill | xmark.octagon.fill |
| Stop skipped | Selected origin or destination skipped | cancel-ink on cancel-fill | xmark.octagon.fill |
| Scheduled | Offline only (D49: a train with no live status reads On time) | scheduled-ink on scheduled-fill (neutral grey) | clock |
| Last reported HH:MM | Live data older than the freshness threshold (proposed 3 min, tune against the feed) | scheduled-ink on scheduled-fill | clock |
| Offline | No connection; cached schedule shown | scheduled-ink on scheduled-fill | wifi.slash |

Missing or stale data is never reported as live: the domain status stays Scheduled (D12, D13), Schedule and Trip details present it as On time unless offline (D49), and the status row says when data is stale or offline. Express is an outlined tag, not a status, and appears only when the feed verifies it. The tag shows the lightning bolt riders already know from GO's trip planner (SF Symbol bolt.fill) plus the word "Express"; when a row carries more than one tag, the word is hidden and only the glyph stays, with the accessibility label still reading Express. If the tags still do not fit beside the status badge and platform, they wrap to a second line under them and the card grows; the timeline's minimum-gap rule keeps spacing. Express is the only tag in version 1; Bike coach and Quiet zone on the canvas are placeholders showing the overflow behaviour.

**Freshness** is one line that states the data mode, shown on Schedule only when there is something to say (D49): "Loading timetable", "Last reported 7:29 AM · showing scheduled times" (stale), "Offline · last updated 6:52 AM" (cached). Live data and timetable-only data show no line. Trip details keeps the full set ("Updated just now", "Scheduled times only"). Refresh on foreground, on pull to refresh, and on a periodic interval agreed with the data provider; a refresh keeps row identity and scroll position and updates the line quietly.

**Time and date.** Times follow the device 12/24-hour setting unless overridden in Settings, use America/Toronto, and respect daylight-saving changes. The service day is the GO service day: trips after midnight belong to the previous service day and sort after 11:59 PM. Every arrival is labelled "Arrival" on a Schedule card ("Scheduled arrival" on Trip details) or "Est. arrival"; an estimate is shown only when the feed supplies or reliably supports one.

**Copy.** Sentence case everywhere, Canadian spelling (favourite, colour, cancelled), no exclamation marks, no emoji, no promises: write "Send updates as changes are reported", never "Never miss a train".

## Schedule screen (timeline)

The Schedule tab is a vertical, to-scale timeline of today's direct trains for the saved route, with the next usable train emphasised and the current time marked. Top to bottom: the line (code tile in the GO line colour, 26 pt bold name, amber Notice chip at the right end) above the route card (no app name above it, D48, D49); day strip; status row, only when loading, offline or stale; optional watched-trip strip; the timeline, which scrolls under the glass tab bar. Three departures fit on a 390 pt phone at default text size in the normal state.

**Route card** (D48). A card drawn like a maps route box: a hollow ring for the origin, three dots, and an accent pin for the destination down the left; origin over destination in `headline`, one 48 pt row each split by a hairline, on one line (long names shrink a little rather than truncate); no "From"/"To" words and no chevrons. Tapping the stations opens the route sheet. Swap (`arrow.up.arrow.down`) is a 44 pt Liquid Glass button (a raised surface before iOS 26) to the right of both rows; swap is explicit and never automatic.

**Line row** (D49). Above the route card: a 32 pt rounded tile with the line's code (LW, LE, MI, KI, RH, BR, ST) in white on the GO line colour, then the line's name in 26 pt bold, ink. Colours follow GO's own, which riders already know: Lakeshore West #8B1A31, Lakeshore East #EA3624, Milton #E6853E, Kitchener #3A8346, Richmond Hill #4397C3, Barrie #143664, Stouffville #724715; a line outside the table uses the feed's own colour, else ink-secondary. When a line-wide notice applies, an amber "Notice" chip (warning glyph and the word, 44 pt target) sits at the right end of the row and opens the notice in a sheet; the notice is dismissible per notice id and never changes a trip's status.

**Day strip** (D49). A horizontal carousel of 60 × 48 pt tiles with 12 pt radius, the weekday over the day number, with a 20 pt margin at the leading edge. The first tile reads "Today"; every day the schedule covers follows (the feed's calendar, 42 days at most; 14 when the schedule has no end), and five tiles show in full with the sixth peeking under a 16 pt fade so the strip clearly scrolls. The selected day is solid accent with on-accent text; others are surface tiles; while another day is selected, "Today" turns accent green so the way back is visible. Selecting any day other than today shows scheduled times only, hides the Now line, and starts the timeline at the first train of that service day. Selecting a tile that is out of view scrolls the strip to it. There is no depart-after filter; looking ahead is scrolling or picking a day.

**Status row** (D49). One line under the day strip, only while the timetable loads, offline or stale (see Freshness). There is no row, and no Now button, while data is live or timetable-only. Tapping the Schedule tab again scrolls to Now and selects Today in one tap.

**Timeline geometry.**

| Element | Rule |
| --- | --- |
| Scale | 7 pt per minute at default text size; gridline every 15 min, each labelled with its time in grey footnote text on the left |
| Now line | 2 pt accent line across the timeline with a dot on the rail and a "Now" label; moves once a minute |
| Initial scroll | The app opens already scrolled so Now sits about 5 min (35 pt) below the top of the timeline, once the cards are measured; earlier trains are above and reachable by scrolling up |
| Train marker | A dot on the rail at the train's expected departure (scheduled when no estimate): 12 pt ring for a train, 16 pt solid accent dot for the next usable train |
| Left column | Gridline times and the Now label only (D49): train times are on the cards, so no train has a time pill in the column |
| Connector | 14 pt, 2 pt horizontal line from marker to card in the marker's colour |
| Gridline labels | Hidden within 22 pt of the Now label; the gridline itself stays |
| Card anchor | The card's departure time line is vertically centred on its marker |
| Minimum gap | Cards never touch: at least 16 pt between cards. If two trains are closer than that at base scale, the timeline zooms in for that segment only, and the gridlines in it follow the zoom |
| Gap label | No labels between cards; the spacing itself conveys the gap. Only a fold carries a label |
| Fold | A gap over 30 min collapses to a dashed 30-min segment with a pill stating the real gap and the next train ("No trains for 48 min · next 6:40 PM") |
| Day end | The timeline continues to the last train of the service day, then an end-of-service line |

**Delay rendering.** A delayed train keeps a hollow amber marker at its scheduled time; an amber 4 pt bar runs down the rail to the expected-time marker, so the bar's length is the delay. The card sits at the expected time, shows the expected time large with "Scheduled 7:32 AM" beneath, the Delayed N min badge, and "Est. arrival" only when the feed supports it.

**Cancellation rendering.** A cancelled train keeps its scheduled slot with a red x marker, struck times in ink-tertiary, the Cancelled badge and the text "Next usable below"; it has no bell. It is never the lead and is excluded from usable-departure logic and gap labels.

**Card contents.** Departure time (34 pt semibold for the next usable train, 32 pt for others, tabular numerals), labelled arrival block on the right ("Arrival" or "Est. arrival" in 15 pt over the 20 pt time), then a status badge (15 pt), platform ("Platform 2" or "Platform pending"), an Express tag only when verified, and the bell at the right end (a 26 pt glyph in a 48 pt target). A train with no live status reads a green "On time" badge: the timetable is the promise, and the status row says when the data is stale; only while offline does the badge stay the grey "Scheduled" (D49). There is no "Departs" label: the rail says it. The next usable train's card also shows minutes until departure in accent beside its badge ("in 11 min", "Departing" under 1 min), updating each minute, and carries its platform under the arrival time so the badge row stays on one line; no other card shows a relative time. Cards are 18 pt radius surface cards with the light-mode card shadow.

**Interactions.** Tap the card to open Trip details; tap the bell to arm an alert for that train in one tap (Alert setup and notification permission); a cancelled card has no bell. Pull to refresh keeps card identity and scroll position. Scrolling is continuous through the service day. A delayed train stays visible past its scheduled time until a reliable departure event or updated estimate shows it has left; the passage of time alone is not evidence of departure.

**Sorting.** Usable departures are ordered by expected departure when available, otherwise scheduled departure. Only direct services that stop at both selected stations in the correct order are shown.

## Schedule states

Every state below is visibly different from the others and keeps the timetable usable; each has an artboard on the canvas with the same name.

| State | Trigger | What the rider sees | Canvas board |
| --- | --- | --- | --- |
| Loading first timetable | No cached schedule for this route yet | Route card, day strip and rail stay; the status row reads "Loading timetable"; three skeleton cards, gently fading unless Reduce Motion is on | Schedule · first load |
| Refreshing | Foreground, pull to refresh, periodic refresh | Existing timeline stays in place; freshness updates quietly; no spinner over content | Main |
| Live on time | Fresh explicit evidence or fresh prediction under 3 min late | On time badge, platform when published | Main (State: normal) |
| Delayed | Reported delay of 3 min or more | Expected time large, "Scheduled 7:32 AM" beneath, amber slip on the rail, Delayed N min badge, Est. arrival only when supported | Main (State: delayed), Schedule · delayed |
| Cancelled or stop skipped | Trip cancelled, or origin/destination skipped | Red x marker, struck times, Cancelled or Stop skipped badge, "Next usable below"; excluded from usable departures; the next valid train becomes the lead | Main (State: cancelled), Schedule · dark |
| No live estimate | Trip has no live data | Domain status Scheduled, shown as On time (D49); the Scheduled badge only while offline | Main |
| Stale live information | Live data older than 3 min (tune against the feed) | Freshness "Last reported 7:29 AM · showing scheduled times"; badges read On time as for a train with no live status (D49); cards move back to scheduled positions | Component sheet (freshness variants) |
| Offline | No connection | Cached schedule stays usable; freshness "Offline · last updated 6:52 AM" with wifi.slash; all badges Scheduled; platform pending; Now line still shown from device time | Main (State: offline), Schedule · offline |
| Future day | Any day strip cell other than Today | No status row; no Now line; timeline starts at the first train of that service day; On time badges only | Schedule · future day |
| No direct trains that day | Zero direct services on the selected day | Empty card: "No direct trains on Sunday", one sentence, action "Show Monday" (next day with service); footnote pointing to the official GO trip planner | Schedule · future day |
| No direct connection | Stations are not on a common direct service | Empty card: "No direct connection", one sentence, action "Open GO trip planner" | Component sheet |
| Long gap | More than 30 min to the next train | Dashed rail segment with "No trains for 48 min · next 6:40 PM" | Schedule · dark |
| Watched trip after departure | A train with an alert has departed | Compact accent-soft strip above the timeline: "7:05 AM to Union · Departed · Est. arrival 7:46 AM"; tap opens Trip details; stays until arrival plus 10 min or until swiped away | Schedule · watched train |
| Line notice | A line-wide service notice applies to the route's line | Amber "Notice" chip at the right end of the line row; opens a sheet with the full notice; never changes a trip's status | Schedule · delayed |
| Compact phone | Screen height under 700 pt | Scale 6 pt per minute, both time sizes 32 pt; two full cards and the next card's time are visible | Schedule · compact phone |
| Large text | Dynamic Type xxxLarge and up | Day strip scrolls (five cells visible), rail column widens, cards stack time / arrival / status, two cards visible; nothing truncates mid-time | Schedule · large text |

A delayed train stays on the timeline past its scheduled time until the feed reports a departure or an updated estimate; it must not disappear because the clock passed 7:32. A cancelled train stays in its slot for the rest of the service day.

## Route form and station search

On first launch the app opens directly to a compact route form, and the first valid route is saved automatically; no account, permission or onboarding comes first.

**Route form** (sheet; also the first screen, under a large title). Title "Choose a route". The route card (see Schedule, D48): origin row then destination row, each opening station search for that field, and a single 44 pt swap button to the right of both rows. Below it one primary button, "Show trains", enabled only when both stations are set and different. On first use the rows show the placeholders "Choose starting station" and "Choose destination" in ink-tertiary, the button is disabled, and picking From opens the To search automatically, so the first route takes two picks and one tap. A footnote says "No account or permission is needed. The route is saved on this device and opens next time."

**Recent** (D48; replaces favourites in version 1). A returning rider sees "Recent" under the form in place of the footnote: the last three routes opened, newest first, leaving out the route on screen. Each row shows mini route markers, origin over destination in `headline` and the line in `footnote`, with no chevron; tapping a row shows that route at once. Each direction is its own entry, and opening a route again moves it to the top. The last selected route and its direction are remembered separately.

**Swap** reverses From and To explicitly and reloads the timeline. The app never reverses a route on its own based on time of day or location.

**Station search** (sheet opened from From or To). A native searchable field with placeholder "Search stations", then two groups: Your stations (stations in the recent routes, with a clock icon, D48) and All stations alphabetically; when choosing To, Union Station GO is listed first as a suggestion unless it is already the From station, each row showing the full station name in `headline` and its line context in `footnote` ("Lakeshore West", "All lines"). Station names are never abbreviated. The station already chosen for the other field is shown greyed with "Same as To" (or "Same as From") and cannot be selected. Cancel returns to the form unchanged.

**Validation and persistence.** Identical stations are rejected inline. Choosing a pair with no direct service still saves the route and shows the "No direct connection" state on Schedule. Route, direction, recent routes and the selected service day are stored locally; nothing is sent to a server for route selection.

## Trip details sheet

Tapping a card opens a sheet for that trip and service date; it shows every nullable field explicitly and never fills a missing value with a guess.

Top to bottom: grabber; sheet title with the trip identity ("7:32 AM train") and a close button; full origin and destination names in `route` style ("Oakville GO to Union Station GO") with line and date beneath ("Lakeshore West · Thu, Nov 5"); the status badge beside the freshness line; a two-column facts card; the stop list; the primary button.

| Fact | Shown as | When missing |
| --- | --- | --- |
| Scheduled departure | 7:32 AM | Always present |
| Expected departure | 7:41 AM in delay-ink when later than scheduled | Omit the cell; the badge reads On time (Scheduled while offline) |
| Scheduled arrival | 8:12 AM | Always present |
| Est. arrival | 8:21 AM | Omit the cell; only the scheduled arrival remains, labelled Scheduled |
| Platform | Platform 2 | "Platform pending" |

**Stop list.** All stops between and including origin and destination, in order, with one time per stop. The column header says "Expected" when live times are available for the trip, otherwise "Scheduled". Origin and destination use `headline` and a filled accent marker; intermediate stops use `body` and a ring. Skipped stops show a red x and struck time. A footnote states the arrival basis, for example "Arrival times are estimates from the live feed. Scheduled arrival 8:12 AM."

**Primary button.** "Alert me" when no rule covers this trip; "Manage alert" when one does. Both open Alert setup prefilled for this trip.

**After departure.** A trip with an alert remains openable from the watched-trip strip and from Alerts › Recent updates until arrival plus 10 min; the sheet then shows "Departed 7:43 AM" in place of the expected departure, keeps the estimated arrival updating, and hides the alert button. Trips without an alert are not retained after departure.

The sheet refreshes with the schedule and is dismissed by swipe or the close button; it never blocks the timetable behind it from updating.

## Alert setup and notification permission

Once notification permission exists, tapping a card's bell arms a This-trip alert immediately: the bell fills, a toast "Alert on for the 7:32 AM train · Repeat" shows for 5 s, and tapping the bell again turns the alert off (toast "Alert off"). The sheet described below opens only the first time (to explain alerts and request permission), from the toast's Repeat link, or as Manage from the Alerts tab.

**Sheet contents.** Title "Alert for this train" with a close button; a trip card ("Oakville to Union" and "7:32 AM train · Thu, Nov 5 · Platform 2"); a segmented control This trip | Repeat, defaulting to This trip; one sentence: "Updates start 1 hour before the scheduled departure. Delays and cancellations are sent as changes are reported."; the primary button "Enable alerts"; a footnote "No account needed. Notification permission is requested after enabling." When a rule already exists the title is "Manage alert", the button reads "Save", and a "Delete alert" text button appears below it.

**Repeat.** Shows a row of seven 44 pt day chips, Monday to Friday preselected, each toggling independently; the trip card changes to "Usual 7:32 AM train · Mon to Fri"; the sentence adds "on each selected day" and "If the usual train changes, this rule asks for review."; a footnote states "A return train is a separate rule." Delay and cancellation updates are always enabled together; no threshold controls exist in version 1.

**Permission timing.** The iOS notification permission dialog is presented only after the rider's first "Enable alerts", never before the first timetable. While the request and server registration are in flight the sheet shows "Setting up". The app never shows On until the rule is stored on the server and the device token is registered.

| Rule state | Shown as | Where | Action offered |
| --- | --- | --- | --- |
| Setting up | "Setting up" with a clock, ink-secondary | Sheet, Alerts row | None; resolves within seconds |
| On | "On" with a checkmark, ontime-ink; bell filled in accent on the card | Card bell, Alerts row | Switch to pause |
| Paused | "Paused", ink-secondary | Alerts row | Switch to resume |
| Notifications off | "Notifications off · Open Settings", cancel-ink; in the sheet an explanatory red panel | Sheet, Alerts row, Settings | Open Settings (deep link to the app's notification settings) |
| Review needed | "Review needed · usual train has changed", delay-ink | Alerts row, push notification | Opens Alert setup to pick the new departure |
| Could not save | "Could not save · Try again", cancel-ink | Sheet, Alerts row | Retry; the rule is kept locally until it saves |

**Denied permission.** Schedules stay fully usable. The rule is saved but shown as Notifications off, with the sentence "The alert is saved, but updates cannot be delivered until notifications are allowed in Settings." and an Open Settings button. A denied permission never looks like an active alert.

**Duplicates.** Enabling the same trip or the same repeating train twice updates the existing rule; repeated taps on Enable alerts send one request. A This-trip rule and a Repeat rule for the same train are allowed and listed separately.

## Alerts tab

The Alerts tab lists every rule with its true state first, then what has been sent, so a rider can see at a glance what is on and what needs attention.

**Header.** Large title "Alerts" with an "Add alert" text button that switches to the Schedule tab and shows the hint "Tap the bell on a train" for 5 s.

**My alerts.** One row per rule, newest first within each state order: Review needed and Could not save at the top, then Setting up, On, Paused, Notifications off. Each row shows the train and direction in `headline` with tabular time ("7:32 AM · Oakville to Union"), the days or date in `footnote` ("Mon to Fri", "Today only"), and the state in words with its icon (see the table in the previous section). Rows in On, Paused or Setting up have a switch at the right that pauses or resumes the rule; rows needing action show a chevron and open Alert setup. Swipe left on any row to delete, with an undo toast for 5 s. A morning train and a return train are separate rows.

**Recent updates.** The train-specific messages delivered in the last 7 days, newest first: title ("7:32 AM train delayed 9 min"), body ("Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM."), timestamp ("Today, 7:29 AM"). Tapping a row opens Trip details for that trip and service date. Icons follow status colour (delay, cancel, on time).

**Line notices.** A separate group below Recent updates for line-wide notices, so they are never read as trip updates: line name, one-sentence summary, timestamp. Tapping opens the notice sheet.

**Empty state.** With no rules: a card with a bell icon, "No alerts yet", "Tap the bell on a train to get updates about delays and cancellations." and a primary "Add alert" button; beneath it the footnote "Updates are sent as changes are reported, from 1 hour before the scheduled departure." Recent updates and Line notices are hidden when empty.

**Badge.** The Alerts tab icon shows no numeric badge; a rule needing review turns the tab icon's dot on (accent) until the rider opens the tab.

## Notification rules and copy

A small server monitors active rules against the live feed and sends visible notifications through APNs; background polling on the phone is never responsible for timely detection. These are product defaults, not GO Transit service guarantees, and user-facing copy stays realistic: "as changes are reported", never "real-time" or "guaranteed".

1. Monitor a watched trip from 60 min before its scheduled departure until a reliable departure event; if the trip is delayed, keep monitoring past the scheduled time.
2. When a rider enables an alert inside that window and a qualifying disruption is already known, send it once immediately.
3. Notify on: a reported departure delay of 3 min or more; a cancellation; a skipped origin or destination. A line-wide notice alone never becomes a trip cancellation.
4. Send a further delay update only when the reported delay changes by 5 min or more, the cancellation status changes, or the train recovers to under 3 min late after a delay alert. Coalesce rapid feed changes within 60 s; never send two identical messages.
5. Keep the scheduled departure as the trip identity in every message.
6. Set APNs expiry to the end of the useful trip window (scheduled departure plus 2 h) so stale delay warnings are discarded. Stop departure-delay alerts after departure; arrival information stays in-app on the watched-trip strip.
7. For a repeating rule, resolve the actual trip for each local service date. If the schedule change removes or moves the selected train, set the rule to Review needed and send one notification; never attach the rule to a different train silently.
8. On a selected weekday with no matching service, show "No matching train today" in the Alerts row; send nothing. A normal unselected day stays quiet.
9. Rules are keyed to an anonymous installation id and device token; no account. Deleting a rule or the app removes it from the server within one monitoring cycle.
10. Tapping a notification opens Trip details for that trip id and service date, even if the app was closed. A notification for a past service date opens the Alerts tab instead.

| Situation | Title | Body |
| --- | --- | --- |
| Delay detected | 7:32 AM train delayed 9 min | Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM. |
| Meaningful increase | 7:32 AM train now delayed 15 min | Oakville to Union. Now expected 7:47 AM, as reported at 7:22 AM. |
| Recovery | 7:32 AM train back on time | Oakville to Union. Expected 7:32 AM, as reported at 7:26 AM. |
| Cancellation | 7:32 AM train cancelled | Oakville to Union. Cancelled, as reported at 7:05 AM. Open to see the next trains. |
| Stop skipped | 7:32 AM train will skip Oakville | Skips Oakville, as reported at 7:05 AM. Open to see the next trains. |
| Rule needs attention | Your usual train has changed | Review your Oakville to Union weekday alert. |
| Line notice (when a rule's line is affected) | Lakeshore West notice | Delays of up to 15 min near Port Credit, as reported at 7:02 AM. Your 7:32 AM train is still expected. |

Titles start with the scheduled train identity and never change it (the 7:32 AM train stays the 7:32 AM train). Bodies name the direction, the expected time and the time the change was reported (as reported at 7:14 AM), one fact per sentence; they state, never promise. Notifications use the default sound and interruption level; no critical alerts, no time-sensitive entitlement in version 1.

## Settings

Settings is the third tab, under a large title "Settings" (D48), and contains only what the brief requires; nothing here is needed to use the timetable.

| Group | Row | Control | Behaviour |
| --- | --- | --- | --- |
| Appearance | Appearance | Segmented: System, Light, Dark | Default System; applies immediately |
| Appearance | Time format | Segmented: Device, 12-hour, 24-hour | Default Device; every time in the app, in notifications and in VoiceOver follows it |
| Notifications | Notification permission | State in words (Allowed, Off, Not asked yet) with an "Open Settings" text button when Off | Reflects `UNUserNotificationCenter` authorization status, refreshed on foreground |
| Notifications | footnote | — | "Updates are sent as changes are reported during each watched trip. Delivery is best effort." |
| Testing (TestFlight and Debug builds only, D49) | Demo trains | Segmented: Off, Delays, Offline | Default Off; "Delays" puts made-up live status on the route's real timetable (the next train 9 min late, the one after it cancelled, the rest on time, plus a line notice); "Offline" shows the cached timetable as if there were no connection. Schedule refreshes at once. Installs from the App Store have no Testing section |
| Data and privacy | Schedule and status data | Row with chevron | Opens the data attribution page required by the provider's terms (Metrolinx open data) |
| Data and privacy | Privacy | Row with chevron | Opens the privacy page: no account; alert rules use an anonymous device token; what is stored on the server and for how long |
| Data and privacy | Official GO service updates | Row with chevron | Opens the official GO service updates page in Safari |
| Data and privacy | footnote | — | "Independent app, not affiliated with GO Transit or Metrolinx. Times may differ from station displays." |
| About | Version | App icon at 36 pt, name "Train Times", footnote "Version 1.0 (1) · Your next GO train, at a glance." | Tapping five times reveals nothing; no hidden debug menu (the Testing section above is a visible row in TestFlight builds only, never in the App Store build) |

There is no login, subscription, payment, advertising, upgrade or rating prompt anywhere in Settings or elsewhere.

## Brand: Train Times

The product is called Train Times. The name says exactly what the app is, in the words riders type into the App Store search box. It replaced an earlier abstract name (Nowline) that failed the one-second test: a rider must understand the icon and the name at a glance. GO appears only as a description of what the app shows, never as the brand. The App Store title is Train Times: GO train schedule (30 characters, the limit), the subtitle is Today's GO trains and delays, and the home-screen label is Train Times (11 characters, which fits under an iOS icon without truncation). The bare name Train Times belongs to a UK rail app, which is why the store title carries the qualifier; the title must be confirmed in App Store Connect, and a short trademark check is advisable. The four brand boards (mark and app icon, lockup and wordmark, App Store product page, App Store search result) sit above the Schedule row on the canvas and carry the SVG sources.

**Mark and app icon.** A white train head on brand green #0C7B53: cab 64 × 62 units with 18-unit top corners and 10-unit bottom corners, windscreen 44 × 22, two lights 12 in diameter, a rail 52 × 7 beneath. Three flat shapes, no gradient, shadow or outline; it reads as a train at 29 px. Dark icon: mint #6EE7B7 on #0B1F17. Tinted icon: the same shapes in white on black. The contained symbol takes the current text colour and is the in-app glyph (a 22 pt mask) in Settings › About. The icon never carries letters (a white G or GO on green is GO Transit's mark), GO's olive green, GO or Metrolinx logos or livery, status colours, or an added clock or badge.

**Colour.** Brand green replaces indigo as the accent everywhere; the values are in Visual tokens and accessibility. Because green is now the brand, On time is a green badge in the accent (D49: a neutral grey badge looked disabled), delays are amber and cancellations red; the grey Scheduled badge is only for offline; the On state of an alert rule uses the accent. Light accent #0C7B53 on white measures 5.3:1; dark accent #6EE7B7 on the dark surface measures above 10:1.

**Wordmark and lockup.** Train Times in SF Pro Display Semibold, sentence case, two words. Ink #111827 in light mode, white on green and in dark mode; never green text on its own, which reads as a link. Horizontal lockup: symbol box 1.6 × cap height, gap 0.5 × cap height, symbol centred on the x-height. Clear space on every side equals the windscreen height. Minimums: lockup 12 pt cap height on screen and 3 mm in print; below that, the wordmark alone. The stacked lockup (symbol, wordmark, tagline) is for the first App Store screenshot and the website header only. No lockup on the launch screen, in the Schedule navigation title, in empty states or in notifications, and never beside GO Transit or Metrolinx marks.

**In the app.** Schedule has no title: the route card is its header (D48); Alerts and Settings keep their large titles. Settings › About shows the app icon at 36 pt, the name, and Version 1.0 (1) · Your next GO train, at a glance. The notification icon and the permission prompt ("Train Times" Would Like to Send You Notifications) are supplied by the system.

**Voice.** Every delay and cancellation carries the time it was reported (as reported at 7:14 AM). A train keeps its name: the 7:32 AM train, now expected 7:41 AM, never the 7:41 train. Copy states and never promises (expected, never will arrive). One fact per sentence. Freshness is always visible. Plain words, sentence case, Canadian spelling, no exclamation marks and no emoji. The notification strings in Notification rules and copy, the Alerts tab's recent updates and the toasts follow these rules.

| Listing field | Text |
| --- | --- |
| App Store title | Train Times: GO train schedule |
| Subtitle | Today's GO trains and delays |
| Home-screen label | Train Times |
| Promotional text | Independent app for GO train riders. Your next direct trains on one timeline, delays shown as they are reported, alerts for the trains you watch. No login, no ads. |
| Description, first line | Independent app, not affiliated with GO Transit or Metrolinx. |
| Keywords | transit,lakeshore,union station,toronto,hamilton,commuter,rail,departures,late,next train |
| Screenshot captions | Your next GO train, in 11 min · Delays drawn as reported · Watch a train with one tap · Alerts for the trains you watch · Cancelled, said plainly |
| Tagline | Your next GO train, at a glance. |
| Website | traintimes.ca (registered, auto-renew on, expires 6 November 2027); traintimes.app optional; never a domain containing go or gotrain. Support address support@traintimes.ca, privacy page traintimes.ca/privacy, attribution page traintimes.ca/data |

The keyword field does not repeat words already in the title and subtitle (Apple indexes those) and leaves out metrolinx and go transit on purpose: a registered mark used as a keyword invites a takedown, while GO train in the title is descriptive of what the app shows. Apple matches words across the title and keywords, so GO in the title plus transit in the keywords still answers a go transit search (D42). The website is one page plus the three pages Apple and the data provider require: the privacy page, the data attribution page (Metrolinx open data terms) and a support contact, all of which Settings links to, with the store badge and the independent-app line in the header. Before release, run a three-second test with five GO riders: show the icon and the first screen for three seconds and ask what the app does. The brand passes when four of five answer GO train times or delays; if it fails, the first screenshot caption changes first, not the mark.

## Visual tokens and accessibility

The app uses the system font, SF Symbols and the tokens in the [GO Train App design system](https://claude.ai/code/artifact/fefd0b1c-3c6f-446d-9bf8-874bf1252452) (`project/tokens.json`); the values below are the ones every screen depends on.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| canvas | #F6F7FB | #0C111B | Screen background |
| surface | #FFFFFF | #161E2C | Cards, sheets, tab bar, day cells |
| surface-raised | #EDEFF5 | #222B3B | Search field, skeletons, Scheduled badge, fold pill |
| hairline / control-border | #E2E6EE / #7C8AA0 | #2A3446 / #6B7891 | Gridlines and rail / control outlines (3:1) |
| ink / ink-secondary / ink-tertiary | #111827 / #475569 / #5E6E85 | #F4F7FB / #B8C3D4 / #8C99AD | Text / labels / placeholders, struck times, gap labels |
| accent / on-accent / accent-soft | #0C7B53 / #FFFFFF / #DDF3E9 | #6EE7B7 / #0B1F17 / #163A2C | Next train, Now line, selected day, links / text on accent / watched strip, On time badge |
| ontime-ink on ontime-fill | #0C7B53 on #DDF3E9 | #6EE7B7 on #163A2C | On time (D49): the accent on accent-soft. The grey scheduled-ink on scheduled-fill is for the offline Scheduled badge. Alert rule On states use the accent. |
| delay-ink on delay-fill | #92400E on #FEF3C7 | #FDE68A on #422D12 | Delayed, slip bar, line notice |
| cancel-ink on cancel-fill | #B91C1C on #FEE2E2 | #FCA5A5 on #431C24 | Cancelled, Notifications off, Could not save |

**Type.** System font only, weights 400 and 600, tabular numerals on every time (`.monospacedDigit()`). Sizes at default Dynamic Type: timeline lead time 34 pt, other card times 32 pt, arrival time 20 pt semibold (its label 15 pt), route 22 pt semibold, large titles 34 pt semibold, body 17 pt, subhead 15 pt, footnote 13 pt (smallest allowed), badge 13 pt semibold (15 pt on timeline cards), tab labels system size. Tracking −0.3 to −0.4 pt from 17 pt up.

**Space and shape.** 4 pt scale; 20 pt screen margins; 14 pt card padding on the timeline; 18 pt card radius; pill buttons, chips and badges; 44 × 44 pt minimum hit area on every control including the bell (a 48 pt target), swap, the route card rows, day tiles and the Notice chip. On iOS 26 and later the tab bar, swap button and other system chrome use Liquid Glass (D49). Light mode cards use a 0 1 2 shadow at 6%; dark mode uses the canvas-to-surface step only. Sheets carry the one real shadow.

**Dynamic Type.** Support to AX5. From xxxLarge: the day strip scrolls with five cells visible; the rail column widens so pills hold 19 pt digits; cards stack time, arrival and status in three rows; fewer cards fit and that is acceptable. Nothing critical clips or truncates mid-time; long station names wrap to two lines.

**VoiceOver.** A card is one element: "7:32 AM to Union, delayed 9 minutes, expected 7:41 AM, estimated arrival 8:21 AM, platform 2". Its bell is a separate button: "Alert for 7:32 AM train" or "Alert on for 7:32 AM train". Gridlines, pills, markers, connectors, gap labels and the Now line are decorative and hidden from assistive tech; the timeline container announces "Departures, 7:21 AM onwards". The day strip is a tab list; the Schedule tab announces its name and scrolls to Now when it is tapped again. Status badges read as text, never by colour alone.

**Motion.** Transitions 0.2 to 0.3 s ease-out; sheets use native presentation; buttons scale to 0.97 on press; light haptic on saving a route or enabling an alert. The Now line moves once a minute with no animation. With Reduce Motion on, cross-fades replace movement and skeleton rows do not pulse. No countdowns, pulsing dots or flashing.

**Other settings honoured.** Increase Contrast (control-border and hairline darken one step), Bold Text, Smart Invert excluded for the app icon, light and dark appearance following System by default.

## Acceptance checks

The build is accepted when every item below passes on a physical iPhone in light and dark appearance.

**Design acceptance**

- [ ] A new rider selects From and To and sees the timeline without any permission prompt.
- [ ] A returning rider sees the remembered route and reads the next usable train and its status in about three seconds.
- [ ] Swapping direction is explicit; full station names stay readable.
- [ ] Scheduled, live, delayed, cancelled, stale and offline states are visibly different on the timeline.
- [ ] A delay moves the card to the expected time, draws the amber slip from the scheduled time, and keeps the 7:32 AM identity.
- [ ] A cancelled train keeps its slot with a red marker and is never the lead.
- [ ] Cards never touch; where trains are closer than the 16 pt gap allows, only that segment zooms.
- [ ] Gaps of 20 min or more are labelled; gaps over 30 min fold with the real duration shown.
- [ ] Three departures are visible on a 390 pt phone at default text size in the normal state; two on a compact phone.
- [ ] The day strip switches days in one tap; tapping the Schedule tab again returns to the present and Today in one tap; the app opens scrolled to Now.
- [ ] Light and dark on iOS 26: the glass tab bar, the swap button and the sheets read well over the timeline; the line tile uses the GO line colour; no train time sits in the left column and every 15 min has a time.
- [ ] Settings › Testing › Demo trains: Delays shows a late train, a cancelled train and the Notice chip; Offline shows the Offline row and grey Scheduled badges; Off restores live data.
- [ ] Enabling, repeating, pausing and deleting alerts is understandable without instructions.
- [ ] A denied notification permission never looks like an active alert.
- [ ] Long names, dark appearance and accessibility text sizes do not clip critical information.

* [ ] The next usable train shows minutes until departure, updating each minute; no other card shows a relative time.
* [ ] Once permission exists, one bell tap arms an alert and a toast confirms it; a cancelled train has no bell.
* [ ] First use shows empty fields and a disabled Show trains button; picking From opens To.

**Development release checks**

- [ ] Direct stopping patterns, express services, holidays, DST and after-midnight service dates validated against real schedules.
- [ ] A delayed train remains visible past its scheduled departure until an actual or reliable estimated departure is resolved.
- [ ] Stale or missing live data is never reported as live (the status row says when data is stale or offline); cached data cannot appear freshly live.
- [ ] Timeline positions are computed from expected time, scale and the minimum-gap rule, and recomputed on every refresh without resetting scroll.
- [ ] Real APNs delivery exercised on a physical device while backgrounded and locked; disabled permission, expired token and registration failure tested separately.
- [ ] Feed replays verify one initial alert, meaningful updates, recovery, cancellation, expiry and no duplicates.
- [ ] A repeating rule is set to Review needed when its usual train moves or disappears; tapping a notification opens the correct service date.
- [ ] VoiceOver reads each card as one element and each bell as a separate button; Dynamic Type xxxLarge and AX3 reflow without truncating a time.

## Assumptions and open questions

Start with fixtures and a transport-data abstraction, then connect verified sources; the items below are what still needs confirming before live status and alerts ship.

- [ ] Metrolinx GO API access: confirm credentials, permitted refresh rate, trip identifiers, cancellation semantics, platform availability and timestamps for the real-time feed. Live endpoints were not validated in the research behind the brief.
- [ ] Freshness threshold: 3 min is the proposed point where live data is demoted to "Last reported"; tune against observed feed update intervals.
- [ ] Estimated arrival: confirm the feed provides a reliable destination estimate; until it does, destination arrival is always labelled Scheduled.
- [ ] Express flag: confirm how express or limited-stop services are marked; show the tag only when verified.
- [ ] Line notices: confirm the service-alert feed and how a notice is scoped to a line; it is shown as the Notice chip on the line row, never as a trip status.
- [x] Schedule horizon: closed (D35, D49): the strip covers every day of the feed's calendar, 42 days at most.
- [ ] Data attribution and independent-app wording: use the provider's current terms for the Settings page.
- [ ] Server monitoring and APNs: a small service keyed by anonymous installation id; agree retention (proposed: rules deleted 24 h after their last service date, device tokens on uninstall or 30 days of inactivity).
- [ ] Compact phones: two full departures plus the next time are accepted on 667 pt screens; confirm with a test on an iPhone SE.
- [ ] Minimum-gap zoom: implemented as a local stretch of the affected segment; confirm the scroll position mapping stays stable when live estimates move trains across the threshold.

* [ ] Usability round: measure time to identify the next train on the timeline (three cards visible) against the earlier row list (four to five visible), and the one-tap bell against the sheet, before the public release.

All station names, times, platforms, train numbers and stop lists in the canvas and in this document are illustrative fixtures. The app name is Train Times (see Brand: Train Times). No GO Transit or Metrolinx marks are used anywhere in the app; the words GO train appear only descriptively, in the App Store title, subtitle and description.

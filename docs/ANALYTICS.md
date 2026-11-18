# Analytics

Product analytics for Train Times (TT-208, D92). Read this before querying PostHog: it is the dictionary of every event the
app sends and what each property means.

## Where the data is

- **PostHog Cloud (US)**, free plan: 1M events and 1M feature-flag requests a month, data kept one year, one project.
- Only **Release builds** send: TestFlight and the App Store. Debug builds, Xcode previews, unit and UI tests send nothing.
  A build sends only when `POSTHOG_PROJECT_TOKEN` in `Config/App.xcconfig` is set (the token is public by design: it can
  only send events).
- Every event carries `channel` (`testflight` or `appstore`) and PostHog's own device properties (app version and build,
  iOS version, iPhone model, locale, a random anonymous id per install).
- Claude reads it through PostHog's MCP connector (`https://mcp.posthog.com/mcp`, TT-210), signed in as Grigor in
  claude.ai, so any project thread can query it: project **737150** ("Default project"), timezone UTC.

## Privacy rules

- **Anonymous.** No `identify`, no person profiles, no session replay, no autocapture, no IDFA. The anonymous id is
  PostHog's own and is never linked to the alert server's installation id.
- **Never in an event:** a name, email, push token, installation id, location or GPS fix, or anything the rider typed
  (feedback text, search text).
- Station and line ids (`OA`, `UN`, `LW`) are allowed: they are GO's public ids, not the rider's position.
- App Store privacy label: Identifiers › Device ID and Usage Data › Product Interaction, for Analytics, not linked to the
  user, not used for tracking, so no tracking prompt (`docs/APP-STORE.md`). A new kind of data needs a new label entry.

## Events

Names are snake_case, `object_action`. PostHog's lifecycle events come from the SDK.

| Event | When | Properties |
|---|---|---|
| `Application Installed` / `Application Updated` / `Application Opened` / `Application Backgrounded` | SDK lifecycle | `version`, `build`, `from_background` (Opened) |
| `$screen` | A screen comes on top | `$screen_name`: `schedule`, `welcome` (first launch: the welcome, your line, your station; TT-206), `route_form` (first launch's "Search stations"), `alerts`, `settings`, `trip_details`, `line_notices`, `detect_offer` |
| `route_set` | A route shows on Schedule (first use, the station picker, a Recent row, a swap applied) | `from`, `to` (station ids), `line` (line id, when known), `is_first` (the first route on this install); `restored` (true only on the launch count below) |
| `route_set` at launch (TT-217) | Once per install: a route saved on device before this install sent any `route_set` (an install from before analytics) is counted at the first launch with analytics, so it shows as activated. Any `route_set` from the app marks the install, so neither sends twice | as above, with `is_first: true` and `restored: true` |
| `offline_shown` | Schedule turns to Offline (TT-217): once each time it turns into that state, never on each poll; a Try again that fails again counts again | `kind`: `live` (live status unreachable, the timetable shows marked Offline), `timetable` (the first timetable could not download: "Couldn’t load the timetable") |
| `route_swapped` | The swap button | none |
| `back_to_now` | The Schedule tab tapped again (back to today, at Now) | none |
| `day_changed` | Another day picked on the day strip | `offset` (days from today, -1 is yesterday) |
| `trip_opened` | Trip details opens | `source`: `schedule` (a card), `notification` (an alert), `ride` (the ride strip), `departure` (the countdown strip or the Live Activity before departure), `detection` (the background question); `is_today` |
| `alert_saved` | An alert saved and kept (bell, "Alert me", Repeat days, the Alerts tab switch or days) | `is_on`, `repeats`, `days` (weekdays picked), `is_new` |
| `alert_removed` | An alert removed by the rider | `source`: `bell` (a one-day alert turned off), `alerts_tab` (Remove alert) |
| `notification_permission` | The rider answered the iOS notification prompt | `result`: `allowed`, `denied` |
| `notification_opened` | A notification tapped | `kind`: `alert`, `detection`, `other` (ride notifications); `action`: `open`, `start`, `not_me` |
| `ride_started` | A ride started | `source`: `on_board` ("I'm on board"), `detection` (Yes on Schedule's question), `notification` (Start On board on the background question); `demo` |
| `ride_ended` | A ride ended | `reason`: `by_rider`, `arrived`, `left_the_line`, `cancelled`; `at_stop` (the train was at your stop: Done there, or the end 10 min after it, TT-221) |
| `detection_answered` | Yes or No on Schedule's "On the 5:13 PM train?" | `answer`: `yes`, `no` |
| `directions_opened` | The Directions link in Trip details | none |
| `feedback_sent` | Feedback or a question sent | `kind`: `feedback`, `question`; `with_email` |
| `setting_changed` | A setting changed | `setting`: `time_format`; `value`: `device`, `twelveHour`, `twentyFourHour` |
| `interest_tapped` | Text that is not a button tapped (TT-209): the rider wanted to know more. Taps on the same element, each within 2 s of the one before, are one event, sent once the run is over | `element` (below), `screen` (the `$screen_name` on top), `count` (taps in the run; 3 or more is a rage tap) |

### Interest elements (`interest_tapped.element`)

A tap on a card's time, status or platform also opens Trip details, as the card always did; the element says which part
was tapped.

| Element | What was tapped |
|---|---|
| `schedule.card.time` | A Schedule card's departure time |
| `schedule.card.status` | A card's status line (On time, 5 min late, Departed, Cancelled) |
| `schedule.card.platform` | A card's "Platform" and pill |
| `schedule.freshness` | The freshness line under the day strip (Live, Offline, updated …) |
| `schedule.line` | The line name over the route card |
| `trip.line` | The line name in Trip details' header |
| `trip.time` | A journey time in Trip details (departure or arrival) |
| `trip.length` | The trip length ("42 min") in Trip details |
| `trip.stop` | A stop row in Trip details |
| `ride.minutes` | The ride screen's minutes to your stop |
| `ride.stops` | The ride screen's stop rail |
| `note.<key>` | A Settings note, by its string key: `note.settings.notifications.footnote`, `note.detect.setting.turnedOff`, `note.settings.no_account`, `note.settings.independent`, `note.settings.testing.footnote` |
| `about.tagline`, `about.version` | The tagline and the version pill on About |

Demo rides (Settings › Testing) only exist in TestFlight and Debug builds, and their rides say `demo: true`; filter
`channel = appstore` for real riders.

## Adding an event

1. Add a factory to `AnalyticsEvent` in `Sources/Core/Analytics/Analytics.swift` and call `Analytics.track` where the
   rider's action happens (a view model or rule, never a view's body).
2. Add its row here, in the same PR.
3. If it collects a new kind of data, update the privacy label notes and the privacy policy.

## Useful questions (for TT-210's dashboard)

- Activation: of installs, how many reach `route_set` with `is_first`, then `trip_opened`, then `alert_saved`?
- Retention: riders with `Application Opened` on day 1, 7 and 30 after `Application Installed`.
- Which lines and stations (`route_set.line`, `from`, `to`) riders use most.
- What riders want to know more about: `interest_tapped` by `element`, and rage taps (`count` 3 or more).
- Where riders give up: `notification_permission` denied, `alert_removed` soon after `alert_saved`, `ride_ended` with
  `by_rider` and `at_stop` false (Done at your stop is `at_stop` true).

## Dashboard: Train Times · Health (TT-210)

[Train Times · Health](https://us.posthog.com/project/737150/dashboard/2357010), pinned in PostHog. Read it with the
connector's `dashboard-get` / `insight-query` (insight ids below), or answer a new question with `query-trends`,
`query-funnel` or `execute-sql` after checking the event exists (`read-data-schema`). All tiles count both channels;
add `channel = appstore` to see real riders only.

| Insight | Id | Shows |
|---|---|---|
| Riders who set a route, last 7 days | `xN0Mez8k` | Unique installs with `route_set` in the last 7 days, against the 7 days before |
| Daily and weekly riders | `31YL0cpo` | Unique installs with `Application Opened` per day, and over a rolling week, 30 days |
| Activation: install → route → trip → alert | `j38322Z7` | Funnel `Application Installed` → `route_set` (`is_first`) → `trip_opened` → `alert_saved`, 14-day window |
| Retention after install (day 1, 7, 30) | `qjN8pG7a` | Share of installs that open the app again N days after installing (read days 1, 7 and 30) |
| Top screens | `FXtEnTvy` | `$screen` by `$screen_name`, last 7 days |
| Routes set by line | `YyeHODYY` | Riders with `route_set` by `line`, last 7 days |
| Notification permission answers | `FS1vafrf` | `notification_permission` by `result` (allowed, denied), per week |
| Interest taps by element | `tkrLa7Sg` | Riders with `interest_tapped` by `element`, last 7 days |
| Rage taps by element | `1PEakxMp` | `interest_tapped` with `count` 3 or more, by `element` |
| Offline views by kind | `crbax7Nq` | `offline_shown` per day by `kind` (`live`, `timetable`), last 30 days (TT-217) |

`route_set` with `restored` is a route from before analytics, counted once at launch: it counts toward activation like a
first route.

## Morning check (TT-210)

A scheduled task wakes the TT-210 project thread every day at 8:13 AM Toronto time. It reads yesterday (the Toronto
calendar day) with this dictionary, mostly through `execute-sql` on `events`, and looks for behaviour nobody expected:

1. **Taps that do nothing:** `interest_tapped` with `count` 3 or more, or one install tapping the same `element` 3 or more
   times in the day.
2. **Flows left halfway:** `welcome` or `route_form` shown with no `route_set` after it; a bell turned on and off again on
   the same train within a minute, or an `alert_saved` removed within 2 minutes; `notification_permission` denied.
3. **Odd endings:** `ride_ended` as `left_the_line` or `cancelled`, or `by_rider` within 5 minutes of `ride_started`; a
   ride with no `ride_ended` within 3 hours; `detection_answered` no.
4. **Offline:** `offline_shown` by `kind`; any `timetable` is worth a line.
5. **Data health:** `$exception` events; an event or property not in this dictionary, or one missing a property it should
   carry (`$screen` without `$screen_name`, `route_set` without `from`/`to`); an event seen every day that stopped.

Rides with `demo: true` are left out. It posts in that thread: one line of totals (installs, opens), then up to three
findings, each with the number behind it, how many installs it comes from and a proposed ticket (title and one line), or
"Nothing unusual yesterday". A finding already posted in the last 7 days comes back only if it grew. On Mondays it adds the
week: riders, routes set, activation and day 1/7/30 retention against the week before. With fewer than 20 installs a
finding is one person's behaviour, so it names it as such and gives no rates. It files and fixes nothing: Grigor says yes
to a proposal and a ticket thread takes it.

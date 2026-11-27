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
- Station and line ids (`OA`, `UN`, `LW`) are allowed on an event the rider caused: they are GO's public ids, not the
  rider's position.
- **Automatic direction (TT-234, D116):** the app turns the route to leave from the station the rider is at, so there
  the From station says where the rider is. No event is sent when the route turns by itself (at an open, on a return or
  after a ride), when that turn is undone, or when the capsule asks, is left or is answered with Switch: each would say
  "this rider is at their station now". No event the rider did not cause carries a station id, because there a station
  id is the rider's position, and no event carries where the rider is.
- **Automatic ride (TT-242, D120):** a ride that starts by itself says the rider just left with a train, so
  `ride_started` (`auto`), `ride_ended` and `auto_ride_checked` carry no station, line, trip or place: outcomes and
  seconds only.
- **Wrong train warning (TT-250, D127):** a warning says the rider just left their station in another train, so
  `wrong_train_warned` and `wrong_train_answered` carry no station, line, trip or place. "Trains from …" is the rider's
  tap, so its `route_set` carries its stations like any route they pick. The share of `fine` answers is the false-alarm
  gauge.
- App Store privacy label: Identifiers › Device ID and Usage Data › Product Interaction, for Analytics, not linked to the
  user, not used for tracking, so no tracking prompt (`docs/APP-STORE.md`). A new kind of data needs a new label entry.

## Events

Names are snake_case, `object_action`. PostHog's lifecycle events come from the SDK. An event or value marked retired is
no longer sent; its row stays because older data has it.

| Event | When | Properties |
|---|---|---|
| `Application Installed` / `Application Updated` / `Application Opened` / `Application Backgrounded` | SDK lifecycle | `version`, `build`, `from_background` (Opened) |
| `$screen` | A screen comes on top | `$screen_name`: `schedule`, `welcome` (first launch: the welcome, your line, your station; TT-206), `route_form` (first launch's "Search stations"), `alerts`, `settings`, `trip_details`, `line_notices`, `detect_offer` (Detect my train's offer; retired in TT-243) |
| `route_set` | A route shows on Schedule by the rider's choice: first use, the station picker, a Recent row, the route form's "Show trains" (also after a swap there), or a link that opens another route. Never Schedule's swap button (`route_swapped`), and never when the route turns by itself, by the capsule's Undo or by Switch (TT-234, D116) | `from`, `to` (station ids), `line` (line id, when known), `is_first` (the first route on this install); `restored` (true only on the launch count below) |
| `route_set` at launch (TT-217) | Once per install: a route saved on device before this install sent any `route_set` (an install from before analytics) is counted at the first launch with analytics, so it shows as activated. Any `route_set` from the app marks the install, so neither sends twice | as above, with `is_first: true` and `restored: true` |
| `offline_shown` | Schedule turns to Offline (TT-217): once each time it turns into that state, never on each poll; a Try again that fails again counts again | `kind`: `live` (live status unreachable, the timetable shows marked Offline), `timetable` (the first timetable could not download: "Couldn’t load the timetable") |
| `launch_splash_ended` | The Bloom splash lifts over Schedule on a cold start with a saved route (TT-227), as its mark begins to fade | `schedule_ready` (Schedule had its trains, or a final state, not "Loading timetable"), `full` (the slower pace of the first 8 launches) |
| `route_swapped` | The swap button: on the route form, and on Schedule's route card (since TT-234; it sent nothing there before), also when that swap back counts as Undo. Never when the route turns by itself, by the capsule's Undo or by Switch (D116) | none |
| `back_to_now` | Back to today, at Now: the Schedule tab tapped again, or the app back after more than 10 min away (TT-222) | `source`: `tab`, `reopen` |
| `day_changed` | Another day picked on the day strip | `offset` (days from today, -1 is yesterday) |
| `boarding_shown` | A train first shows Boarding: it stands at the From station with its platform posted (TT-233, D114). Once per train per day, from whichever screen has it first: Schedule (any Boarding train on Today's timeline, in view or not) or its Trip details | `minutes_before` (whole minutes before its scheduled time, negative once past it), `surface`: `schedule` (its card), `trip` (Trip details). No station id since TT-234 (D116): Schedule sends it with no tap, and after a turn the From station is where the rider is |
| `train_departed` | Schedule's next train turned Departed on a minute tick or a 30 s poll with Schedule loaded (TT-233, D114). Once per train per app run; not on launch, the first tick or poll after coming back, or pull to refresh; a departure only the clock decided counts within 60 s of its time | `source`: `moved` (its position left the station), `feed` (the station dropped out of GO's updates), `clock` (its time came, with no position); `seconds_after` (whole seconds after its scheduled time; negative, down to -60, when the feed said so just before it) |
| `weather_opened` | The weather sheet opens from the tile beside the day strip (TT-226) | `day_offset` (days from today, 0 is Today), `cue`: `rain`, `snow`, `cold`, `wind`, `none` (the sheet's first line) |
| `weather_unavailable` | The weather tile shows grey, at most once per Schedule visit (TT-226) | `reason`: `past` (a day before today), `range` (more than 10 days ahead), `offline`, `failed` (the request failed, or the station has no place) |
| `trip_opened` | Trip details opens | `source`: `schedule` (a card), `notification` (an alert), `ride` (the ride strip), `departure` (the countdown strip or the Live Activity before departure), `detection` (the background question; retired in TT-243), `link` (a `traintimes://trip` link: a widget's train, TT-182), `alerts` (a card on the Alerts tab, TT-253); `is_today` |
| `alert_saved` | An alert saved and kept (bell, "Alert me", Repeat days, an Alerts card's bell) | `is_on`, `repeats`, `days` (weekdays picked), `is_new` |
| `alert_shown_in_schedule` | An Alerts card's "See trains" opened Schedule on the alert's route and its train's day (TT-253, D129) | `is_today` (that day is today), `route_changed` (Schedule showed another route before), `is_on` (the alert is switched on) |
| `alert_removed` | An alert removed by the rider | `source`: `bell` (a one-day alert turned off), `alerts_tab` (Remove alert) |
| `notification_permission` | The rider answered the iOS notification prompt | `result`: `allowed`, `denied` |
| `notification_opened` | A notification tapped | `kind`: `alert`, `detection` (retired in TT-243), `departure` (the departure question, TT-231), `other` (ride notifications); `action`: `open`, `start` and `not_me` (on `detection`, retired), and `yes`, `no` on the departure question; `wrong_train` (the wrong train warning, TT-250, D127) with `action`: `open`, `trains` ("Trains from …"), `fine` ("I’m fine") |
| `ride_started` | A ride started | `source`: `on_board` ("I'm on board"), `detection` (Yes on Schedule's question; retired in TT-243), `notification` (Start On board on the background question; retired in TT-243), `departure` (Yes on the departure question, any surface; TT-231), `auto` (it started by itself once the phone left the station with an alerted train; TT-242, D120), with `seconds_after` (whole seconds from the train leaving to the start) on `auto` only; `demo`; `express` (the trip has the express tag between your two stations); `skipped_stations` (how many stations it passes without stopping on your ride, 0 on a train that stops everywhere) (TT-232); `auto` carries no `express` or `skipped_stations` |
| `ride_ended` | A ride ended | `reason`: `by_rider`, `arrived`, `left_the_line`, `cancelled`, `not_on_it` ("Not on it" in the first 10 min of an automatic ride; TT-243, D120) with `surface`: `card` (the Live Activity) or `ride` (the ride screen), `auto_undone` (the app ended an automatic ride by itself in its first 10 min; no sub-reason, since stayed, off the line or falling behind would say where the rider is; TT-243), `wrong_train` ("Trains from …" on the wrong train warning, or the warning ran out unanswered; TT-250, D127); `at_stop` (the train was at your stop: Done there, or the end 2 min after it, TT-221, D103); `watched_seconds` (whole seconds the ride screen was on screen with the app active during the ride) and `opens` (times it was opened; both since TT-224, D106, and counted again after a relaunch); `source` (how the ride started, as `ride_started`, kept across a relaunch: `on_board`, `departure`, `auto`; `detection` and `notification`, retired in TT-243; TT-242) |
| `arrival_wish_shown` | The arrival wish took "Now"'s place on the ride screen with the app active, once per ride (TT-223, D103) | `wish` (its id: `goodDay`, `greatDay`, `goodOne`, `enjoyDay`, `goodAfternoon`, `enjoyAfternoon`, `haveGoodOne`, `takeCare`, `enjoyEvening`, `goodEvening`, `restWell`, `goodNight`, `homeSafe`, `sleepWell`, `enjoyWeekend`, `happyFriday`), `period` (`morning`, `midday`, `evening`, `night`), `demo` |
| `arrival_wish_closed` | The first way the arrival wish left the screen, once per ride | `wish`, `close` (`done` Done tapped, `dismissed` chevron or swipe, `left_app` the app went to the background, `auto` the screen closed itself 2 min after your stop), `seconds` (whole seconds on screen, 120 at most), `taps` (taps on the wish), `demo` |
| `departure_question_answered` | Yes or No on "On board?" after an alerted train left (TT-231, D110) | `answer`: `yes`, `no`; `surface`: `card` (the Live Activity), `notification`, `schedule` (Schedule's strip) |
| `auto_ride_checked` | The automatic ride's watch on an alerted train finished (TT-242, D120), once per train per day (today's trains kept on device). `not_armed` goes when an alerted train in its window, with the app in front, is kept from arming by a gate (Automatic ride turned off, location, Precise Location, no track, a ride under 8 min, Mock time or a demo), or when a wake with the app closed comes after the train's deadline with no watch for it (TT-243), never for another watch or a running ride | `outcome`: `started`, `not_on_board`, `unsure`, `answered` (Yes, No or "I’m on board" came first), `stopped` (the alert went, location or Precise Location went, or Mock time or a demo came on), `not_armed`; `reason` on `unsure` only: `no_feed`, `no_station`, `rival`, `weak_fixes`, `short`; `seconds_after` (whole seconds from the train leaving, when it had left); `armed` (how the watch armed, TT-243): `open` (with the app in front, TT-242's arming), `wake` (a significant-change wake with the app closed, under "When the app is closed"), `card` (the train's departure card arriving with the app in the background); `demo` |
| `wrong_train_warned` | A wrong train warning showed, once per warning (TT-250, D127; only Settings › Testing's demo raises one until TT-251) | `reason`: `wrong_way`, `skips_stop`, `other_line`; `evidence`: `feed`, `track`; `source`: `on_board`, `departure` (how the ride started), `alert` (no ride yet); `shown`: `app` (in front: Alarm once), `card` (five buzzes on the Live Activity), `notification`; `seconds_after` (whole seconds from the first moving fix; 0 on the demo); `demo` |
| `wrong_train_answered` | The first way a wrong train warning ended, once per warning (TT-250, D127) | `answer`: `fine`, `trains`, `end_ride`, `expired`, `withdrawn` (the ride ended otherwise, or the check took it back); `surface` on `fine` and `trains` only: `card` (Lock Screen or island), `ride`, `schedule`, `notification`; `seconds` (whole seconds it was up); `demo` |
| `arrival_wish_lock_screen` | The arrival wish went onto the Live Activity at your stop (Lock Screen and expanded island), once per ride (TT-229, D108); `arrival_wish_shown` stays the ride screen's | `wish`, `period`, `demo` |
| `detection_asked` | Retired in TT-243 (D120). Train detection asked "On the train to Clarkson?" (TT-230) | `where`: `app` (Schedule's question), `background` (the notification); `evidence`: `stops` (stopped with the train at stations), `moving` (moved with it on a stretch with no stop between) |
| `detection_answered` | Retired in TT-243 (D120). Yes or No on Schedule's "On the 5:13 PM train?" | `answer`: `yes`, `no` |
| `directions_opened` | The Directions link in Trip details | none |
| `widget_opened` | A tap on a widget opened the app (TT-183; the Lock Screen sizes, TT-184) | `widget`: `next_train`, `departures`, `lock_rectangular`, `lock_circular`, `lock_inline` (Next train's Lock Screen sizes); `target`: `trip` (a train: Trip details), `route` (the header, a message, a Lock Screen size or anywhere else: Schedule). `trip_opened` with `source: link` follows a `trip` |
| `widgets_placed` | The app came to the front and the number of placed widgets differs from the last one sent (kept on device; an install that never placed one sends nothing) | `next_train`, `departures` (how many of each are on the Home Screen), `lock` (how many Lock Screen sizes of Next train are placed, TT-184) |
| `feedback_sent` | Feedback or a question sent | `kind`: `feedback`, `question`; `with_email` |
| `feedback_nudge_shown` | Schedule's Feedback button started asking: the bubble draws a question mark and goes back (TT-228, D112) | `count` (which showing, 1 to 5) |
| `feedback_opened` | The feedback sheet opened (TT-228) | `source`: `schedule`, `settings`; `after_nudge` (within 60 s of the button asking); `nudges_seen` (0 to 5) |
| `setting_changed` | A setting changed | `setting`: `time_format`, with `value`: `device`, `twelveHour`, `twentyFourHour`; `auto_direction` (Settings › Automatic direction, TT-234, D116), with `value`: `on`, `off` and no other property, sent only when the rider's own tap leaves the switch changed: not when iOS refuses, not when the tap only opens iOS Settings, and never when the permission alone changes the switch; also sent, the same, by Turn off on Automatic direction's one-time strip on Schedule (TT-236), with no property that says where; `auto_ride` (Settings › Automatic ride, and Turn off on its one-time strip on Schedule) and `auto_ride_closed` (Settings › When the app is closed) (TT-243, D120), with `value`: `on`, `off`, under `auto_direction`'s rule: only when the rider's tap leaves the switch changed, never when the permission alone flips it, and not when two "Not on it" turn Automatic ride off |
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
| `note.<key>` | A Settings note, by its string key: `note.settings.notifications.footnote`, `note.settings.no_account`, `note.settings.independent`, `note.settings.testing.footnote`, and the note under the Automatic card (TT-234, TT-243): `note.settings.automatic.note`, `note.settings.auto_direction.needs_location`, `note.settings.auto_direction.needs_precise`, `note.settings.auto_ride.turned_off` (they say the permission's or the setting's state, never a place) |
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
| Arrival wishes by wish | `0TxOyHVT` | SQL table, last 90 days, `demo` false: per `wish` times shown, median `seconds`, share kept 3 s or more or tapped, share of each `close`, taps per wish (TT-223) |

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
   ride with no `ride_ended` within 3 hours; `ride_ended` as `not_on_it` or `auto_undone`.
4. **Offline:** `offline_shown` by `kind`; any `timetable` is worth a line.
5. **Arrival wishes (TT-223):** the leading wish, the one with the highest share of `arrival_wish_closed` with `taps` 1 or
   more or `seconds` 3 or more (`demo` false), among wishes shown 30 times or more, counted over all time, not only yesterday; "not enough data yet" until one has.
   One line, not a finding, unless a wish is clearly ahead or behind.
6. **Feedback button (TT-228):** `feedback_opened` with `after_nudge` true, against installs that saw
   `feedback_nudge_shown`, and against opens with `nudges_seen` 0. One line; with today's number of testers it is a hint,
   not proof.
7. **Data health:** `$exception` events; an event or property not in this dictionary, or one missing a property it should
   carry (`$screen` without `$screen_name`, `route_set` without `from`/`to`); an event seen every day that stopped.

Rides with `demo: true` are left out. It posts in that thread: one line of totals (installs, opens), then up to three
findings, each with the number behind it, how many installs it comes from and a proposed ticket (title and one line), or
"Nothing unusual yesterday". A finding already posted in the last 7 days comes back only if it grew. On Mondays it adds the
week: riders, routes set, activation and day 1/7/30 retention against the week before. With fewer than 20 installs a
finding is one person's behaviour, so it names it as such and gives no rates. It files and fixes nothing: Grigor says yes
to a proposal and a ticket thread takes it.

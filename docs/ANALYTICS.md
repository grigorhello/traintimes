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
- Claude reads it through PostHog's MCP connector (`https://mcp.posthog.com/mcp`, TT-210).

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
| `$screen` | A screen comes on top | `$screen_name`: `schedule`, `route_form` (first use, no route yet), `alerts`, `settings`, `trip_details`, `line_notices`, `detect_offer` |
| `route_set` | A route shows on Schedule (first use, the station picker, a Recent row, a swap applied) | `from`, `to` (station ids), `line` (line id, when known), `is_first` (the first route on this install) |
| `route_swapped` | The swap button | none |
| `back_to_now` | The Schedule tab tapped again (back to today, at Now) | none |
| `day_changed` | Another day picked on the day strip | `offset` (days from today, -1 is yesterday) |
| `trip_opened` | Trip details opens | `source`: `schedule` (a card), `notification` (an alert), `ride` (the ride strip), `departure` (the countdown strip or the Live Activity before departure), `detection` (the background question); `is_today` |
| `alert_saved` | An alert saved and kept (bell, "Alert me", Repeat days, the Alerts tab switch or days) | `is_on`, `repeats`, `days` (weekdays picked), `is_new` |
| `alert_removed` | An alert removed by the rider | `source`: `bell` (a one-day alert turned off), `alerts_tab` (Remove alert) |
| `notification_permission` | The rider answered the iOS notification prompt | `result`: `allowed`, `denied` |
| `notification_opened` | A notification tapped | `kind`: `alert`, `detection`, `other` (ride notifications); `action`: `open`, `start`, `not_me` |
| `ride_started` | A ride started | `source`: `on_board` ("I'm on board"), `detection` (Yes on Schedule's question), `notification` (Start On board on the background question); `demo` |
| `ride_ended` | A ride ended | `reason`: `by_rider`, `arrived`, `left_the_line`, `cancelled` |
| `detection_answered` | Yes or No on Schedule's "On the 5:13 PM train?" | `answer`: `yes`, `no` |
| `directions_opened` | The Directions link in Trip details | none |
| `feedback_sent` | Feedback or a question sent | `kind`: `feedback`, `question`; `with_email` |
| `setting_changed` | A setting changed | `setting`: `time_format`; `value`: `device`, `twelveHour`, `twentyFourHour` |

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
- Where riders give up: `notification_permission` denied, `alert_removed` soon after `alert_saved`, `ride_ended` with
  `by_rider` before `arrived`.

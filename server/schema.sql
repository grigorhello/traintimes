-- Train Times alert server (TT-140). Apply with:
--   npx wrangler d1 execute traintimes-alerts --remote --file schema.sql

-- One row per app installation: an anonymous id the app generates, no account (D5).
CREATE TABLE IF NOT EXISTS installations (
  id TEXT PRIMARY KEY,
  -- APNs device token, hex. NULL once APNs rejects it, until the app registers again.
  device_token TEXT,
  -- 'production' or 'sandbox' (a development build's token only works on the sandbox host).
  environment TEXT NOT NULL,
  -- '12h' or '24h': the app's Time format, resolved from Device, for times in notifications (D17).
  time_format TEXT NOT NULL,
  -- Epoch ms of the app's last call; 30 days without one removes the installation (D38).
  last_seen INTEGER NOT NULL
);

-- Alert rules: This trip, or Repeat on weekdays.
CREATE TABLE IF NOT EXISTS rules (
  installation_id TEXT NOT NULL,
  id TEXT NOT NULL,
  kind TEXT NOT NULL,               -- 'trip' or 'repeat'
  trip_id TEXT NOT NULL,            -- the train the rider picked
  service_date TEXT NOT NULL,       -- its service date, YYYYMMDD
  line TEXT NOT NULL,               -- line short name, 'LW'
  departure INTEGER NOT NULL,       -- scheduled departure from the origin, GTFS seconds on service_date
  origin_id TEXT NOT NULL,
  origin_name TEXT NOT NULL,
  destination_id TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  weekdays TEXT NOT NULL DEFAULT '', -- repeat: ISO weekdays, '1,2,3,4,5'
  paused INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'on', -- 'on' or 'review' (the usual train changed)
  no_train_date TEXT,               -- repeat: the last selected day with no matching train
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (installation_id, id)
);

-- What has been sent for each watched trip, so nothing is sent twice. `version` makes each send a compare-and-set.
CREATE TABLE IF NOT EXISTS watches (
  installation_id TEXT NOT NULL,
  key TEXT NOT NULL,                -- service date, trip id, origin and destination
  service_date TEXT NOT NULL,
  sent_kind TEXT,
  sent_delay INTEGER,
  sent_at INTEGER,
  done INTEGER NOT NULL DEFAULT 0,  -- the train has departed: no more departure alerts
  version INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (installation_id, key)
);

-- The GO rail timetable per service date (JSON trips by trip id), uploaded daily from the public GTFS feed (D43).
CREATE TABLE IF NOT EXISTS timetables (
  service_date TEXT PRIMARY KEY,
  trips TEXT NOT NULL,
  imported_at INTEGER NOT NULL
);

-- The before-departure Live Activity (TT-178, D74). New tables only, so running this file again on the deployed
-- database adds them and leaves the rest as it is.
-- Each installation's push-to-start token (iOS 17.2+), sent with its registration.
CREATE TABLE IF NOT EXISTS start_tokens (
  installation_id TEXT PRIMARY KEY,
  token TEXT NOT NULL               -- hex
);

-- Each watched trip's activity, started by the server (push-to-start) or by the app, so it is started once.
CREATE TABLE IF NOT EXISTS activities (
  installation_id TEXT NOT NULL,
  key TEXT NOT NULL,                -- the watch's key: service date, trip id, origin and destination
  service_date TEXT NOT NULL,
  token TEXT,                       -- the activity's update token from the app, hex; NULL until the app reports it
  state TEXT NOT NULL DEFAULT 'started', -- 'started', 'ended', or 'handedOff' (the app's ride took the activity over)
  shown TEXT,                       -- what it last showed (src/activity.ts signature), so updates go only on a change
  version INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (installation_id, key)
);

-- A minute cycle reads only the rules whose watch window is open and one day's watches (Workers Free plan, D43).
CREATE INDEX IF NOT EXISTS rules_departure ON rules (departure);
CREATE INDEX IF NOT EXISTS watches_service_date ON watches (service_date);
CREATE INDEX IF NOT EXISTS activities_service_date ON activities (service_date);

-- Feedback and questions from the app (TT-202, D85). New table only, like the ones above. No installation id; the email is
-- optional, for a reply. Kept a year (daily retention).
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,      -- epoch ms
  kind TEXT NOT NULL,               -- 'feedback' or 'question'
  message TEXT NOT NULL,
  email TEXT,
  app_version TEXT NOT NULL,        -- '1.0 (45)'
  device TEXT NOT NULL,             -- model identifier, 'iPhone18,1'
  os_version TEXT NOT NULL          -- '26.1.0'
);
CREATE INDEX IF NOT EXISTS feedback_created_at ON feedback (created_at);

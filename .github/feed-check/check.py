"""Temporary probe for TT-131 (#20): reads the real TripUpdates through the relay and checks it against GO's static GTFS."""
import csv, io, json, sys, time, urllib.request, zipfile, collections, datetime as dt
from zoneinfo import ZoneInfo
from google.transit import gtfs_realtime_pb2 as rt

TZ = ZoneInfo("America/Toronto")
RELAY = "https://alerts.traintimes.ca"
POLLS, GAP = int(sys.argv[1]) if len(sys.argv) > 1 else 24, 20

def get(url, accept=None):
    req = urllib.request.Request(url, headers={"User-Agent": "traintimes-ci", **({"Accept": accept} if accept else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status, r.headers.get("Content-Type"), r.read()

print("== static GTFS")
_, _, z = get("https://assets.metrolinx.com/raw/upload/Documents/Metrolinx/Open%20Data/GO-GTFS.zip")
zf = zipfile.ZipFile(io.BytesIO(z))
def rows(name):
    return csv.DictReader(io.TextIOWrapper(zf.open(name), encoding="utf-8-sig"))
routes = {r["route_id"]: r for r in rows("routes.txt")}
rail_routes = {k for k, r in routes.items() if r["route_type"] == "2"}
trips = {t["trip_id"]: t for t in rows("trips.txt")}
rail_trips = {k: t for k, t in trips.items() if t["route_id"] in rail_routes}
print("rail routes", len(rail_routes), "trips", len(trips), "rail trips", len(rail_trips))
print("sample rail trip ids", list(rail_trips)[:5])
cal_dates = collections.defaultdict(set)
for c in rows("calendar_dates.txt"):
    if c["exception_type"] == "1": cal_dates[c["service_id"]].add(c["date"])
try:
    for c in rows("calendar.txt"):
        print("calendar.txt present; first row", c); break
except KeyError:
    print("no calendar.txt")
stop_times = collections.defaultdict(list)
for s in rows("stop_times.txt"):
    if s["trip_id"] in rail_trips:
        stop_times[s["trip_id"]].append(s)
for v in stop_times.values(): v.sort(key=lambda s: int(s["stop_sequence"]))

def sched(date, hms):
    h, m, s = map(int, hms.split(":"))
    d = dt.datetime.strptime(date, "%Y%m%d")
    noon = dt.datetime(d.year, d.month, d.day, 12, tzinfo=TZ)
    return (noon - dt.timedelta(hours=12) + dt.timedelta(hours=h, minutes=m, seconds=s)).timestamp()

print("\n== trains JSON")
st, ct, body = get(RELAY + "/v1/trains")
trains = json.loads(body)
print(st, ct, "sample", json.dumps(trains if isinstance(trains, dict) else trains[:2])[:600])

headers, per_trip_ts, last = [], collections.defaultdict(list), None
for i in range(POLLS):
    st, ct, body = get(RELAY + "/v1/live/trip-updates")
    f = rt.FeedMessage(); f.ParseFromString(body)
    now = time.time()
    headers.append((now, f.header.timestamp))
    for e in f.entity:
        if e.HasField("trip_update") and e.trip_update.HasField("timestamp"):
            tsl = per_trip_ts[e.trip_update.trip.trip_id]
            if not tsl or tsl[-1] != e.trip_update.timestamp: tsl.append(e.trip_update.timestamp)
    print(f"poll {i}: {st} {ct} {len(body)} B header {f.header.timestamp} age {now - f.header.timestamp:.0f}s entities {len(f.entity)} incr {f.header.incrementality} ver {f.header.gtfs_realtime_version}")
    last = f
    if i < POLLS - 1: time.sleep(GAP)

ts = sorted({h for _, h in headers})
print("\n== Q2 header timestamps", ts, "gaps", [b - a for a, b in zip(ts, ts[1:])])
gaps = [b - a for v in per_trip_ts.values() for a, b in zip(v, v[1:])]
if gaps:
    gaps.sort(); print("per-trip timestamp gaps: n", len(gaps), "median", gaps[len(gaps)//2], "p90", gaps[int(len(gaps)*.9)], "max", gaps[-1])
ages = sorted(headers[-1][0] - e.trip_update.timestamp for e in last.entity if e.HasField("trip_update") and e.trip_update.HasField("timestamp"))
if ages: print("per-trip age at last poll: median", ages[len(ages)//2], "p90", ages[int(len(ages)*.9)], "max", ages[-1])

print("\n== trip identity")
tus = [e.trip_update for e in last.entity if e.HasField("trip_update")]
print("trip updates", len(tus), "other entities", len(last.entity) - len(tus))
print("first entity:\n", str(last.entity[0])[:1500])
in_static = [t for t in tus if t.trip.trip_id in trips]
in_rail = [t for t in tus if t.trip.trip_id in rail_trips]
print("trip id in static", len(in_static), "in rail", len(in_rail), "unknown", [t.trip.trip_id for t in tus if t.trip.trip_id not in trips][:10])
print("route_id in feed sample", collections.Counter(t.trip.route_id for t in tus).most_common(8))
print("start_date present", sum(t.trip.HasField("start_date") for t in tus), "start_time present", sum(t.trip.HasField("start_time") for t in tus))
print("start_date values", collections.Counter(t.trip.start_date for t in tus))
bad_date = [(t.trip.trip_id, t.trip.start_date) for t in in_rail if t.trip.start_date and t.trip.start_date not in cal_dates.get(rail_trips[t.trip.trip_id]["service_id"], set())]
print("rail trips whose start_date is not a service date of the trip:", len(bad_date), bad_date[:10])
print("trip relationship", collections.Counter(rt.TripDescriptor.ScheduleRelationship.Name(t.trip.schedule_relationship) for t in tus))
print("trip-level delay present", sum(t.HasField("delay") for t in tus), "vehicle present", sum(t.HasField("vehicle") for t in tus), "timestamp present", sum(t.HasField("timestamp") for t in tus))

print("\n== stop time updates (rail)")
rel = collections.Counter(); has = collections.Counter(); unknown_stop = 0; seq_mismatch = 0; stops_total = 0
diffs = []; dest_arr = 0; dest_trips = 0; all_stops = 0; full = 0; future_cov = []
for t in in_rail:
    plan = stop_times[t.trip.trip_id]; ids = [s["stop_id"] for s in plan]
    date = t.trip.start_date or dt.datetime.now(TZ).strftime("%Y%m%d")
    covered = set()
    for u in t.stop_time_update:
        stops_total += 1
        rel[rt.TripUpdate.StopTimeUpdate.ScheduleRelationship.Name(u.schedule_relationship)] += 1
        for f in ("stop_id", "stop_sequence", "arrival", "departure"):
            if u.HasField(f): has[f] += 1
        for ev, name in ((u.arrival, "arrival"), (u.departure, "departure")):
            if u.HasField(name):
                if ev.HasField("time"): has[name + ".time"] += 1
                if ev.HasField("delay"): has[name + ".delay"] += 1
                if ev.HasField("uncertainty"): has[name + ".uncertainty"] += 1
        if u.stop_id not in ids: unknown_stop += 1; continue
        covered.add(u.stop_id)
        s = plan[ids.index(u.stop_id)]
        if u.HasField("stop_sequence") and str(u.stop_sequence) != s["stop_sequence"]: seq_mismatch += 1
        for ev, name, col in ((u.arrival, "arrival", "arrival_time"), (u.departure, "departure", "departure_time")):
            if u.HasField(name) and ev.HasField("time"):
                d = ev.time - sched(date, s[col])
                diffs.append(d)
                if ev.HasField("delay") and abs(ev.delay - d) > 1: has["delay!=time-sched"] += 1
    dest_trips += 1
    last_u = [u for u in t.stop_time_update if u.stop_id == ids[-1]]
    if last_u and last_u[-1].HasField("arrival"): dest_arr += 1
    # coverage of stops still ahead (scheduled after now)
    ahead = [s["stop_id"] for s in plan if sched(date, s["arrival_time"]) > time.time()]
    if ahead: future_cov.append(len([x for x in ahead if x in covered]) / len(ahead))
print("relationships", dict(rel)); print("fields", dict(has))
print("stop updates", stops_total, "stop_id not on the trip", unknown_stop, "stop_sequence != static", seq_mismatch)
diffs.sort()
if diffs:
    print("time - scheduled (s): n", len(diffs), "min", diffs[0], "p10", diffs[len(diffs)//10], "median", diffs[len(diffs)//2], "p90", diffs[int(len(diffs)*.9)], "max", diffs[-1])
    print("  early by > 60 s:", sum(d < -60 for d in diffs), "late >= 3 min:", sum(d >= 180 for d in diffs))
print("Q3 rail trips with an arrival at their last stop:", dest_arr, "of", dest_trips)
if future_cov: future_cov.sort(); print("share of stops ahead with an update: median", future_cov[len(future_cov)//2], "min", future_cov[0])
print("updates per trip", collections.Counter(len(t.stop_time_update) for t in in_rail).most_common(10))
# One full rail example with static times beside it
for t in in_rail[:2]:
    plan = {s["stop_id"]: s for s in stop_times[t.trip.trip_id]}
    print("\nexample", t.trip.trip_id, t.trip.start_date, "trip delay", t.delay if t.HasField("delay") else None)
    for u in t.stop_time_update:
        s = plan.get(u.stop_id, {})
        a = dt.datetime.fromtimestamp(u.arrival.time, TZ).strftime("%H:%M:%S") if u.HasField("arrival") and u.arrival.HasField("time") else "-"
        d = dt.datetime.fromtimestamp(u.departure.time, TZ).strftime("%H:%M:%S") if u.HasField("departure") and u.departure.HasField("time") else "-"
        print(f"  {u.stop_id:8} seq {u.stop_sequence:3} {rt.TripUpdate.StopTimeUpdate.ScheduleRelationship.Name(u.schedule_relationship):9} arr {a} dep {d}  static {s.get('arrival_time')} {s.get('departure_time')}")

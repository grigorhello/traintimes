"""Temporary probe 2 for TT-131 (#20): every rail trip in the real feed beside its static stops."""
import csv, io, time, urllib.request, zipfile, collections, datetime as dt
from zoneinfo import ZoneInfo
from google.transit import gtfs_realtime_pb2 as rt
TZ = ZoneInfo("America/Toronto")
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "traintimes-ci"}), timeout=60) as r: return r.read()
zf = zipfile.ZipFile(io.BytesIO(get("https://assets.metrolinx.com/raw/upload/Documents/Metrolinx/Open%20Data/GO-GTFS.zip")))
rows = lambda n: csv.DictReader(io.TextIOWrapper(zf.open(n), encoding="utf-8-sig"))
rail = {r["route_id"] for r in rows("routes.txt") if r["route_type"] == "2"}
trips = {t["trip_id"]: t for t in rows("trips.txt") if t["route_id"] in rail}
st = collections.defaultdict(list)
for s in rows("stop_times.txt"):
    if s["trip_id"] in trips: st[s["trip_id"]].append(s)
for v in st.values(): v.sort(key=lambda s: int(s["stop_sequence"]))
def hm(ts): return dt.datetime.fromtimestamp(ts, TZ).strftime("%H:%M:%S")
for poll in range(3):
    f = rt.FeedMessage(); f.ParseFromString(get("https://alerts.traintimes.ca/v1/live/trip-updates"))
    print(f"\n######## poll {poll} header {hm(f.header.timestamp)} now {hm(time.time())}")
    for e in f.entity:
        t = e.trip_update
        if t.trip.trip_id not in trips:
            if t.trip.schedule_relationship: print("non-rail", t.trip.trip_id, rt.TripDescriptor.ScheduleRelationship.Name(t.trip.schedule_relationship))
            continue
        ups = {u.stop_id: u for u in t.stop_time_update}
        print(f"\n{t.trip.trip_id} {rt.TripDescriptor.ScheduleRelationship.Name(t.trip.schedule_relationship)} ts {hm(t.timestamp)} vehicle {t.vehicle.id!r} n_updates {len(ups)}")
        for s in st[t.trip.trip_id]:
            u = ups.get(s["stop_id"])
            if u is None: mark = "."
            else:
                r = rt.TripUpdate.StopTimeUpdate.ScheduleRelationship.Name(u.schedule_relationship)
                a = hm(u.arrival.time) if u.HasField("arrival") else "-"
                d = hm(u.departure.time) if u.HasField("departure") else "-"
                mark = f"{r} arr {a} dep {d} delay {u.departure.delay if u.HasField('departure') else ''}"
            print(f"   {s['stop_id']:6} {s['arrival_time']} {s['departure_time']}  {mark}")
    if poll < 2: time.sleep(90)

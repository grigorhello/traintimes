#!/usr/bin/env python3
"""Temporary TT-130 probe: summarise the GO GTFS zip and extract the rail subset. Removed before merge."""
import csv, gzip, io, os, sys, zipfile, collections

zpath, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(zpath)
for i in z.infolist():
    print(f"{i.filename:30} {i.file_size:>12} {i.compress_size:>12} method={i.compress_type}")

def rows(name):
    with z.open(name) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))

def head(name, n=5):
    if name not in z.namelist():
        print(f"--- {name}: missing"); return
    with z.open(name) as f:
        t = io.TextIOWrapper(f, encoding="utf-8-sig")
        print(f"--- {name}")
        for _ in range(n):
            line = t.readline()
            if not line: break
            print("   ", line.rstrip())

for n in z.namelist():
    head(n, 4)

routes = list(rows("routes.txt"))
print("route_type counts", collections.Counter(r["route_type"] for r in routes))
rail = [r for r in routes if r["route_type"] == "2"]
for r in rail:
    print("RAIL", {k: v for k, v in r.items()})
rail_ids = {r["route_id"] for r in rail}

trips = [t for t in rows("trips.txt") if t["route_id"] in rail_ids]
trip_ids = {t["trip_id"] for t in trips}
svc = {t["service_id"] for t in trips}
print("rail trips", len(trips), "services", len(svc))
print("trip columns", list(trips[0].keys()) if trips else None)
for t in trips[:15]:
    print("TRIP", t)
print("headsign sample", collections.Counter(t.get("trip_headsign", "") for t in trips).most_common(40))
print("short_name sample", collections.Counter(t.get("trip_short_name", "")[:3] for t in trips).most_common(10))

st_rows = []
with z.open("stop_times.txt") as f:
    r = csv.reader(io.TextIOWrapper(f, encoding="utf-8-sig"))
    st_header = next(r)
    ti = st_header.index("trip_id")
    for row in r:
        if row[ti] in trip_ids:
            st_rows.append(row)
print("stop_times header", st_header, "rail rows", len(st_rows))
for row in st_rows[:30]:
    print("ST", row)
# times past 24h
ai = st_header.index("arrival_time"); di = st_header.index("departure_time")
late = [row for row in st_rows if row[di] and int(row[di].split(":")[0]) >= 24]
print("rows with departure >= 24h", len(late), late[:5])
for col in ("pickup_type", "drop_off_type", "timepoint", "stop_headsign", "shape_dist_traveled"):
    if col in st_header:
        print(col, collections.Counter(row[st_header.index(col)] for row in st_rows).most_common(8))

stop_ids = {row[st_header.index("stop_id")] for row in st_rows}
stops = list(rows("stops.txt"))
print("stops columns", list(stops[0].keys()))
rail_stops = [s for s in stops if s["stop_id"] in stop_ids]
parents = {s.get("parent_station") for s in rail_stops if s.get("parent_station")}
print("rail stops", len(rail_stops), "with parents", len(parents))
for s in rail_stops[:80]:
    print("STOP", s)

cal = list(rows("calendar.txt")) if "calendar.txt" in z.namelist() else []
cal = [c for c in cal if c["service_id"] in svc]
print("calendar rows for rail", len(cal))
for c in cal[:40]:
    print("CAL", c)
cd = list(rows("calendar_dates.txt")) if "calendar_dates.txt" in z.namelist() else []
cd = [c for c in cd if c["service_id"] in svc]
print("calendar_dates rows for rail", len(cd))
if cd:
    ds = sorted(c["date"] for c in cd)
    print("calendar_dates range", ds[0], ds[-1], collections.Counter(c["exception_type"] for c in cd))
    print("dates", sorted(collections.Counter(c["date"] for c in cd).items()))
for c in cd[:40]:
    print("CD", c)

def write(name, header, data):
    with gzip.open(os.path.join(out, name + ".gz"), "wt", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(data)

def write_dicts(name, ds):
    if not ds: return
    h = list(ds[0].keys())
    write(name, h, [[d[k] for k in h] for d in ds])

write_dicts("routes.txt", rail)
write_dicts("trips.txt", trips)
write("stop_times.txt", st_header, st_rows)
write_dicts("stops.txt", [s for s in stops if s["stop_id"] in stop_ids or s["stop_id"] in parents])
write_dicts("calendar.txt", cal)
write_dicts("calendar_dates.txt", cd)
for n in ("agency.txt", "feed_info.txt"):
    if n in z.namelist():
        write_dicts(n, list(rows(n)))
print("written", os.listdir(out))

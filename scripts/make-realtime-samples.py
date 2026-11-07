#!/usr/bin/env python3
"""Writes the GTFS-realtime sample feeds the TT-131 replay tests read (Tests/UnitTests/Core/Realtime/*.pb).

The Metrolinx API key has not arrived yet, so these feeds stand in for GO's TripUpdates feed (D36). They use the
official GTFS-realtime protobuf bindings, so the app's own decoder is checked against an independent encoder, and real
trip ids and stops from Tests/UnitTests/Core/GTFS/go-gtfs-sample.zip: Lakeshore West, Oakville (OA) to Union (UN),
Monday Nov 9, 2026, read at 7:00, 7:01 and 7:02 AM Toronto time (EST, UTC-5).

    python3 -m venv /tmp/rt && /tmp/rt/bin/pip install gtfs-realtime-bindings
    /tmp/rt/bin/python scripts/make-realtime-samples.py
"""
import calendar
import datetime
import os

from google.transit import gtfs_realtime_pb2 as rt

OUT = os.path.join(os.path.dirname(__file__), "..", "Tests", "UnitTests", "Core", "Realtime")
DATE = "20261109"
SKIPPED = rt.TripUpdate.StopTimeUpdate.SKIPPED
NO_DATA = rt.TripUpdate.StopTimeUpdate.NO_DATA


def at(hhmmss):
    """Epoch seconds of a Toronto wall-clock time on Nov 9, 2026 (EST)."""
    h, m, s = (int(x) for x in hhmmss.split(":"))
    return calendar.timegm(datetime.datetime(2026, 11, 9, h + 5, m, s).timetuple())


def feed(timestamp):
    message = rt.FeedMessage()
    message.header.gtfs_realtime_version = "2.0"
    message.header.incrementality = rt.FeedHeader.FULL_DATASET
    message.header.timestamp = at(timestamp)
    return message


def trip(message, trip_id, timestamp=None, cancelled=False, delay=None):
    entity = message.entity.add()
    entity.id = trip_id
    update = entity.trip_update
    update.trip.trip_id = f"{DATE}-{trip_id}"
    update.trip.start_date = DATE
    update.trip.route_id = "09261126-LW"
    if cancelled:
        update.trip.schedule_relationship = rt.TripDescriptor.CANCELED
    if timestamp:
        update.timestamp = at(timestamp)
    if delay is not None:
        update.delay = delay
    return update


def stop(update, stop_id, sequence, arrival_delay=None, arrival_time=None, departure_delay=None, departure_time=None,
         relationship=None):
    s = update.stop_time_update.add()
    s.stop_id = stop_id
    s.stop_sequence = sequence
    if arrival_delay is not None:
        s.arrival.delay = arrival_delay
    if arrival_time:
        s.arrival.time = at(arrival_time)
    if departure_delay is not None:
        s.departure.delay = departure_delay
    if departure_time:
        s.departure.time = at(departure_time)
    if relationship is not None:
        s.schedule_relationship = relationship


def common(message):
    # 7:13 AM train: absolute times at Oakville and Union, one minute late: On time, Est. arrival 7:48.
    on_time = trip(message, "LW-1256")
    stop(on_time, "OA", 13, departure_time="07:14:00")
    stop(on_time, "UN", 34, arrival_time="07:48:00")
    # A trip that is not in the rail schedule is ignored.
    stop(trip(message, "21-1234"), "OA", 2, departure_delay=0)


def write(name, message):
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(message.SerializeToString())


# 7:00 AM: the 7:21 AM train is 5 min late at Oakville; Union has no estimate. The 7:51 AM train has no data at Oakville.
m = feed("07:00:00")
common(m)
late = trip(m, "LW-1108")
stop(late, "OA", 5, departure_delay=300)
stop(late, "CL", 9, arrival_delay=300, departure_delay=300)
stop(trip(m, "LW-1308"), "OA", 5, relationship=NO_DATA)
write("tripupdates-0700.pb", m)

# 7:01 AM: the delay grows to 9 min, and the 7:28 AM train is cancelled (reported 7:00:40).
m = feed("07:01:00")
common(m)
late = trip(m, "LW-1108")
stop(late, "OA", 5, departure_delay=540)
trip(m, "LW-1858", timestamp="07:00:40", cancelled=True)
stop(trip(m, "LW-1308"), "OA", 5, relationship=NO_DATA)
write("tripupdates-0701.pb", m)

# 7:02 AM: the 7:21 AM train recovers to 1 min late, the 7:44 AM train skips Oakville, the 7:51 AM train is 4 min late
# at Appleby (propagates to Oakville), the 7:58 AM train has only a trip-wide 3 min delay, and the 8:13 AM train has an
# early estimate at Union only, which is no departure estimate.
m = feed("07:02:00")
common(m)
late = trip(m, "LW-1108")
stop(late, "OA", 5, departure_delay=60)
trip(m, "LW-1858", timestamp="07:00:40", cancelled=True)
skipped = trip(m, "LW-1758")
stop(skipped, "OA", 24, relationship=SKIPPED)
propagated = trip(m, "LW-1308")
stop(propagated, "AP", 1, arrival_delay=240, departure_delay=240)
trip(m, "LW-1860", delay=180)
stop(trip(m, "LW-1258"), "UN", 34, arrival_delay=-60)
write("tripupdates-0702.pb", m)

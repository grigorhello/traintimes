#!/usr/bin/env python3
"""Writes the GTFS-realtime sample feeds the TT-131 and TT-132 replay tests read (Tests/UnitTests/Core/Realtime/*.pb).

The Metrolinx API key has not arrived yet, so these feeds stand in for GO's TripUpdates feed (D36) and Alerts feed
(D37). They use the official GTFS-realtime protobuf bindings, so the app's own decoder is checked against an independent
encoder, and real route ids, trip ids and stops from Tests/UnitTests/Core/GTFS/go-gtfs-sample.zip: Lakeshore West,
Oakville (OA) to Union (UN), Monday Nov 9, 2026, read at 7:00, 7:01 and 7:02 AM Toronto time (EST, UTC-5); alerts at
7:02 and 7:05 AM.

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


# Alerts (TT-132). Real route ids: 09261126-LW is Lakeshore West (LW), 09261126-GT is Kitchener (KI).
def alert(message, entity_id, header, description=None, routes=(), stop=None, trip_id=None, start=None, end=None,
          effect=rt.Alert.SIGNIFICANT_DELAYS, french=None):
    entity = message.entity.add()
    entity.id = entity_id
    a = entity.alert
    if start or end:
        period = a.active_period.add()
        if start:
            period.start = at(start)
        if end:
            period.end = at(end)
    for route in routes:
        informed = a.informed_entity.add()
        informed.agency_id = "GO"
        informed.route_id = route
        if stop:
            informed.stop_id = stop
    if trip_id:
        informed = a.informed_entity.add()
        informed.trip.trip_id = f"{DATE}-{trip_id}"
        informed.trip.route_id = "09261126-LW"
    if stop and not routes:
        a.informed_entity.add().stop_id = stop
    a.effect = effect
    if french:
        t = a.header_text.translation.add()
        t.text = french
        t.language = "fr"
    t = a.header_text.translation.add()
    t.text = header
    t.language = "en"
    if description:
        t = a.description_text.translation.add()
        t.text = description
        t.language = "en"


def alerts_common(message):
    # Kitchener line: another line's notice.
    alert(message, "KI-2001", "Delays of up to 10 min near Bramalea", routes=["09261126-GT"], start="06:40:00")
    # A station notice with no route: not a line notice.
    alert(message, "OA-3001", "The elevator to platform 2 is out of service", stop="OA", start="05:00:00")
    # The 7:21 AM train cancelled as an alert only, with NO_SERVICE: never a trip status (only TripUpdates are).
    alert(message, "TRIP-4001", "The 7:21 AM Oakville to Union train is cancelled", trip_id="LW-1108", start="06:55:00",
          effect=rt.Alert.NO_SERVICE)
    # A Lakeshore West notice that ended at 6:30, and one that starts at 9:00: neither shows at 7:02.
    alert(message, "LW-0900", "Earlier delays near Long Branch", routes=["09261126-LW"], start="05:30:00", end="06:30:00")
    alert(message, "LW-0901", "Weekend track work near Exhibition", routes=["09261126-LW"], start="09:00:00")


# 7:02 AM: a Lakeshore West notice at Port Credit, from 7:00, in English and French.
m = feed("07:02:00")
alert(m, "LW-1001", "Delays of up to 15 min near Port Credit",
      "Trains are moving slowly near Port Credit GO because of a signal problem. Allow extra travel time.",
      routes=["09261126-LW"], stop="PO", start="07:00:00", french="Retards jusqu'à 15 min près de Port Credit")
alerts_common(m)
write("alerts-0702.pb", m)

# 7:05 AM: the notice is reissued with a new id, so a rider who dismissed the first one sees it.
m = feed("07:05:00")
alert(m, "LW-1002", "Delays of up to 25 min near Port Credit", routes=["09261126-LW"], start="07:04:00")
alerts_common(m)
write("alerts-0705.pb", m)


# GO's real Alerts feed (checked through the alert server on 2026-11-14, D90), on the sample's Monday at 7:02 AM: numeric
# ids; every informed entity sets agency_id, route_id, route_type and stop_id, the unused ones as "" or 0; a line notice
# names its route with an empty stop; a station alert has an empty route; a trip alert names the trip with route_type 2
# and lists its stations apart; every active period starts when GO posted the alert (often days before) and ends about
# 19 h after the feed's time, whatever the alert; English with French, or English only.
def go_entity(a, route="", stop="", agency=None, trip_id=None):
    informed = a.informed_entity.add()
    informed.agency_id = agency if agency is not None else ("GO" if route else "")
    informed.route_id = route
    informed.route_type = 2 if trip_id else 0
    informed.stop_id = stop
    if trip_id:
        informed.trip.trip_id = f"{DATE}-{trip_id}"
        informed.trip.route_id = route


def go_alert(message, entity_id, header, description, posted, entities, effect=rt.Alert.OTHER_EFFECT, french=True):
    entity = message.entity.add()
    entity.id = entity_id
    a = entity.alert
    period = a.active_period.add()
    period.start = calendar.timegm(posted.timetuple())
    period.end = at("07:02:00") + 19 * 3600
    for kwargs in entities:
        go_entity(a, **kwargs)
    a.cause = rt.Alert.UNKNOWN_CAUSE
    a.effect = effect
    a.url.translation.add(text="https://www.gotransit.com/en/service-updates/service-updates", language="en")
    a.header_text.translation.add(text=header, language="en")
    a.description_text.translation.add(text=description, language="en")
    if french:
        a.header_text.translation.add(text="Avis", language="fr")
        a.description_text.translation.add(text="Avis.", language="fr")


def utc(month, day, hour, minute):
    return datetime.datetime(2026, month, day, hour, minute)


m = feed("07:02:00")
# Lakeshore West, posted Saturday Nov 7 at 1:57 PM Toronto: a line notice reported on another day.
go_alert(m, "532843", "Lakeshore West - Track speed reductions",
         "Ongoing track conditions between Confederation GO and Niagara Falls GO continue to require trains to operate "
         "at reduced speeds through the area.", utc(11, 7, 18, 57), [dict(route="09261126-LW")],
         effect=rt.Alert.SIGNIFICANT_DELAYS, french=False)
# Lakeshore West, posted today at 6:40 AM: a notice about a later day is active from its posting.
go_alert(m, "533119", "Nov. 21: Service adjustments", "On Saturday, Nov. 21, GO trains will run every hour.",
         utc(11, 9, 11, 40), [dict(route="09261126-LW")])
# A station alert at Oakville, and the same day's notice told by station only: neither is a line notice.
go_alert(m, "480679", "Elevator out of service", "The elevator to platform 2 is out of service.", utc(9, 29, 5, 30),
         [dict(stop="OA")], effect=rt.Alert.UNKNOWN_EFFECT)
go_alert(m, "533122", "Nov. 21: Service adjustments", "No GO Transit service at this station.", utc(11, 9, 11, 40),
         [dict(stop="EX"), dict(stop="MI")], effect=rt.Alert.UNKNOWN_EFFECT)
# The 7:21 AM train cancelled, told about the trip and its stations: never a line notice or a status.
go_alert(m, "533305", "Train cancelled - Oakville GO 07:21 - Union Station 07:48", "The train is cancelled.",
         utc(11, 9, 11, 55), [dict(route="09261126-LW", trip_id="LW-1108"), dict(stop="OA"), dict(stop="UN")],
         effect=rt.Alert.SIGNIFICANT_DELAYS)
# Kitchener (route GT) and Barrie together, and a bus route alone (route 18 serves Oakville GO).
go_alert(m, "532102", "Kitchener and Barrie line service adjustments.", "Tonight, there are late-evening adjustments.",
         utc(11, 9, 11, 0), [dict(route="09261126-BR"), dict(route="09261126-GT")], effect=rt.Alert.MODIFIED_SERVICE)
go_alert(m, "532280", "Nov. 15: Temporary Outer Bus Loop Closure at Oakville GO", "The outer bus loop is closed.",
         utc(11, 5, 15, 0), [dict(route="09261126-18")], effect=rt.Alert.STOP_MOVED)
write("alerts-go-real.pb", m)

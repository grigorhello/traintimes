import XCTest
@testable import TrainTimes

/// TT-130 rules the November feed cannot show: a holiday, DST days, calendar.txt, quoted fields and parent stations.
/// GO publishes each date's trips separately, so these feeds are written by hand to the GTFS reference.
final class GTFSFeedTests: XCTestCase {
    private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func timetable(_ files: [String: String]) throws -> GTFSTimetable {
        GTFSTimetable(feed: try GTFSFeed(importedAt: Date(timeIntervalSince1970: 0)) { files[$0].map { Data($0.utf8) } })
    }

    private func feed(
        trips: String, stopTimes: String, calendar: String? = nil, calendarDates: String? = nil
    ) -> [String: String] {
        var files = [
            "routes.txt": """
            route_id,route_short_name,route_long_name,route_type,route_color
            R1,LW,"Lakeshore \"\"West\"\"",2,98002e
            B1,56,Oakville / Oshawa,3,
            """,
            "stops.txt": """
            stop_id,stop_name,location_type,parent_station
            OA,Oakville GO,1,
            OA-1,"Oakville GO, platform 1",0,OA
            UN,Union Station GO,1,
            """,
            "trips.txt": trips,
            "stop_times.txt": stopTimes,
        ]
        files["calendar.txt"] = calendar
        files["calendar_dates.txt"] = calendarDates
        return files
    }

    /// A weekday service with Christmas Day taken out and a holiday service put in.
    func testHolidayFollowsCalendarDates() throws {
        let timetable = try timetable(feed(
            trips: """
            route_id,service_id,trip_id
            R1,WEEKDAY,weekday
            R1,HOLIDAY,holiday
            B1,WEEKDAY,bus
            """,
            stopTimes: """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            weekday,7:32:00,7:32:00,OA-1,1
            weekday,8:05:00,8:05:00,UN,2
            holiday,09:00:00,09:00:00,OA,1
            holiday,09:40:00,09:40:00,UN,2
            bus,10:00:00,10:00:00,OA,1
            bus,11:00:00,11:00:00,UN,2
            """,
            calendar: """
            service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
            WEEKDAY,1,1,1,1,1,0,0,20261221,20261231
            """,
            calendarDates: """
            service_id,date,exception_type
            WEEKDAY,20261225,2
            HOLIDAY,20261225,1
            """
        ))
        func trips(_ day: Int) -> [String] {
            timetable.trips(from: "OA", to: "UN", on: ServiceDay(year: 2026, month: 12, day: day)).map(\.key.tripId)
        }
        XCTAssertEqual(trips(24), ["weekday"])
        XCTAssertEqual(trips(25), ["holiday"], "Christmas Day runs the holiday service only")
        XCTAssertEqual(trips(26), [], "Saturday")
        XCTAssertEqual(trips(31), ["weekday"])
        XCTAssertEqual(
            timetable.trips(from: "OA", to: "UN", on: ServiceDay(year: 2026, month: 12, day: 24)).first?.scheduledDeparture,
            utc("2026-12-24T12:32:00Z")
        )
        XCTAssertEqual(timetable.lastServiceDay, ServiceDay(year: 2026, month: 12, day: 31))
        XCTAssertEqual(timetable.feed.trips.map(\.id), ["weekday", "holiday"], "Rail only")
        XCTAssertEqual(timetable.stations.map(\.id), ["OA", "UN"], "A platform counts as its station")
        XCTAssertEqual(timetable.stations.map(\.name), ["Oakville GO", "Union Station GO"])
        XCTAssertEqual(timetable.feed.lines.first?.name, #"Lakeshore "West""#, "Quoted fields keep their commas and quotes")
    }

    /// GTFS times count from noon minus 12 h, so DST days keep their wall-clock times and late trains their service day.
    func testDSTDays() throws {
        let timetable = try timetable(feed(
            trips: """
            route_id,service_id,trip_id
            R1,SPRING,spring
            R1,FALL,fall
            R1,HALLOWEEN,late
            """,
            stopTimes: """
            trip_id,arrival_time,departure_time,stop_id,stop_sequence
            spring,06:00:00,06:00:00,OA,1
            spring,06:40:00,06:40:00,UN,2
            fall,06:00:00,06:00:00,OA,1
            fall,06:40:00,06:40:00,UN,2
            late,25:30:00,25:30:00,OA,1
            late,26:10:00,26:10:00,UN,2
            """,
            calendarDates: """
            service_id,date,exception_type
            SPRING,20270314,1
            FALL,20261101,1
            HALLOWEEN,20261031,1
            """
        ))
        let spring = try XCTUnwrap(timetable.trips(from: "OA", to: "UN", on: ServiceDay(year: 2027, month: 3, day: 14)).first)
        XCTAssertEqual(spring.scheduledDeparture, utc("2027-03-14T10:00:00Z"), "6:00 AM EDT on the spring-forward day")
        let fall = try XCTUnwrap(timetable.trips(from: "OA", to: "UN", on: ServiceDay(year: 2026, month: 11, day: 1)).first)
        XCTAssertEqual(fall.scheduledDeparture, utc("2026-11-01T11:00:00Z"), "6:00 AM EST on the fall-back day")
        let halloween = ServiceDay(year: 2026, month: 10, day: 31)
        let late = try XCTUnwrap(timetable.trips(from: "OA", to: "UN", on: halloween).first)
        XCTAssertEqual(late.scheduledDeparture, utc("2026-11-01T05:30:00Z"), "1:30 AM EDT, before the clocks go back")
        XCTAssertEqual(late.scheduledArrival, utc("2026-11-01T06:10:00Z"), "1:10 AM EST, after they go back")
        XCTAssertEqual(ServiceDay(containing: late.scheduledArrival), halloween)
    }

    func testAFeedWithoutTrainsIsRejected() {
        XCTAssertThrowsError(try timetable(feed(
            trips: "route_id,service_id,trip_id\nB1,WEEKDAY,bus",
            stopTimes: "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nbus,10:00:00,10:00:00,OA,1\nbus,11:00:00,11:00:00,UN,2",
            calendarDates: "service_id,date,exception_type\nWEEKDAY,20261109,1"
        ))) { error in
            XCTAssertEqual(error as? GTFSFeed.ImportError, .noRail)
        }
        XCTAssertThrowsError(try timetable(["routes.txt": "route_id,route_type\nR1,2"])) { error in
            XCTAssertEqual(error as? GTFSFeed.ImportError, .missingFile("trips.txt"))
        }
    }

    func testStopTimes() {
        XCTAssertEqual(GTFSFeed.seconds("25:10:00"), 90_600)
        XCTAssertEqual(GTFSFeed.seconds("7:32:00"), 27_120)
        XCTAssertNil(GTFSFeed.seconds(""))
        XCTAssertNil(GTFSFeed.seconds("07:32"))
    }
}

import XCTest

/// Launch arguments that set the saved route (TT-120) and the recent routes (D48) for one run, whatever an earlier run
/// saved. They win over what the app stores during the run, so a test that checks what was stored relaunches without them.
enum LaunchArguments {
    /// The fixture route, Oakville to Union, so the app lands on the Schedule timeline.
    static let fixtureRoute = [
        "-route.last",
        ##"{fromId = OA; fromName = Oakville; toId = UN; toName = Union; lineId = LW; lineName = "Lakeshore West"; lineColor = "#111827";}"##,
    ]
    /// No recent routes, so the route sheet lists only what this run opens.
    static let noRecents = ["-route.recent", ""]
    /// No saved route and no recent routes, as on a fresh install: the app lands on the welcome (TT-206).
    static let freshInstall = ["-route.last", ""] + noRecents
    /// No dismissed line notices (TT-132), so the fixture's notice shows.
    static let noDismissedNotices = ["-notices.dismissed", ""]
    /// No alert rules (TT-141), so every bell starts off.
    static let noAlerts = ["-alerts.rules", ""]
    /// No Undo hour (TT-234, D116), so Automatic direction may turn the route between any two stations.
    static let noDirectionUndo = ["-direction.undo", ""]
    /// No route chosen by hand lately, so Automatic direction's look runs.
    static let noDirectionChoice = ["-direction.byHand", ""]
    /// The rider has not turned Automatic direction off.
    static let noDirectionOff = ["-direction.off", ""]
    /// Nothing holds Automatic direction back: no Undo hour, no choice by hand and no "off", whatever an earlier run left.
    /// A test that checks the Undo hour relaunches without `noDirectionUndo`.
    static let noDirectionHolds = noDirectionUndo + noDirectionChoice + noDirectionOff

    /// Settings › Testing › Demo place at one of the route's two stations, by id: the phone reads as standing there, with
    /// location allowed (TT-234, D116). Fixture runs have no location reader, so this is how a UI test turns the route.
    static func demoPlace(_ station: String) -> [String] {
        ["-settings.demoPlace", station]
    }
}

extension XCUIApplication {
    /// The app on the fixture schedule and clock (D20), so UI tests never download the GTFS feed (TT-130). The launch
    /// environment, unlike the arguments, survives a relaunch with no arguments.
    static func onFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TT_FIXTURES"] = "1"
        return app
    }

    /// The fixtures' full-day scenario (TT-159): a train every 30 min from 5:24 AM to 11:24 PM, so the timeline is as long
    /// as a real day's. Pair it with `-settings.mockTime` to put Now anywhere in it.
    static func onFullDayFixture() -> XCUIApplication {
        let app = onFixtures()
        app.launchEnvironment["TT_FIXTURES"] = "fullDay"
        return app
    }

    /// The same on the fixtures' delayed scenario, which has a line notice (TT-132).
    static func onDelayedFixture() -> XCUIApplication {
        let app = onFixtures()
        app.launchEnvironment["TT_FIXTURES"] = "delayed"
        return app
    }
}

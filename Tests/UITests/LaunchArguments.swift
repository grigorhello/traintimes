import XCTest

/// Launch arguments that set the saved route (TT-120) and the favourites (TT-122) for one run, whatever an earlier run
/// saved. They win over what the app stores during the run, so a test that checks what was stored relaunches without them.
enum LaunchArguments {
    /// The fixture route, Oakville to Union, so the app lands on the Schedule timeline.
    static let fixtureRoute = [
        "-route.last",
        ##"{fromId = OA; fromName = Oakville; toId = UN; toName = Union; lineId = LW; lineName = "Lakeshore West"; lineColor = "#111827";}"##,
    ]
    /// No favourites, so the star starts off.
    static let noFavourites = ["-route.favourites", ""]
    /// No saved route and no favourites, as on a fresh install: the app lands on the route form.
    static let freshInstall = ["-route.last", ""] + noFavourites
    /// No dismissed line notices (TT-132), so the fixture's notice shows.
    static let noDismissedNotices = ["-notices.dismissed", ""]
    /// No alert rules (TT-141), so every bell starts off.
    static let noAlerts = ["-alerts.rules", ""]
}

extension XCUIApplication {
    /// The app on the fixture schedule and clock (D20), so UI tests never download the GTFS feed (TT-130). The launch
    /// environment, unlike the arguments, survives a relaunch with no arguments.
    static func onFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TT_FIXTURES"] = "1"
        return app
    }

    /// The same on the fixtures' delayed scenario, which has a line notice (TT-132).
    static func onDelayedFixture() -> XCUIApplication {
        let app = onFixtures()
        app.launchEnvironment["TT_FIXTURES"] = "delayed"
        return app
    }
}

import XCTest

/// Launch arguments that set the saved route (TT-120) for one run, whatever an earlier run saved.
enum LaunchArguments {
    /// The fixture route, Oakville to Union, so the app lands on the Schedule timeline.
    static let fixtureRoute = [
        "-route.last",
        ##"{fromId = OA; fromName = Oakville; toId = UN; toName = Union; lineId = LW; lineName = "Lakeshore West"; lineColor = "#111827";}"##,
    ]
    /// No saved route, as on a fresh install: the app lands on the route form.
    static let freshInstall = ["-route.last", ""]
}

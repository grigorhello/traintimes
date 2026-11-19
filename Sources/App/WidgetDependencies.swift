import WidgetKit

extension WidgetFileWriter {
    /// The app's widget file writer (TT-182, D107): the GO feed as it is and the device clock, into the App Group container,
    /// reloading every widget when the file changes. Nil when the build is not entitled to the App Group.
    /// The file also carries the timetable of each placed widget's own route (TT-183), read from WidgetKit.
    static func app(
        data: any ScheduleRepository & StationRepository, routeStore: any RouteStoring, rules: AlertRules, settings: AppSettings,
        recents: RecentRoutes, placed: any PlacedWidgetsProviding = SystemPlacedWidgets()
    ) -> WidgetFileWriter? {
        guard let fileURL = WidgetFile.containerFileURL else { return nil }
        return WidgetFileWriter(
            repository: data, stations: data, clock: SystemClock(), fileURL: fileURL,
            widgetRoutes: PlacedWidgetRoutes(widgets: placed, stations: data), routeStore: routeStore, rules: rules,
            settings: settings, recents: recents, reload: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }
}

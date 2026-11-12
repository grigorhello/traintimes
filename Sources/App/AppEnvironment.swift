import SwiftUI

extension EnvironmentValues {
    /// The one time formatter (D17). `RootView` sets it from `AppSettings`, so a Time format change in Settings
    /// re-renders every time on screen at once. Screens format with this value, never a `TimeFormatter` of their own.
    @Entry var timeFormatter: any TimeFormatting = TimeFormatter(format: .device)
}

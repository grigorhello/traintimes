import Foundation

/// The My trains tab's words the UI tests look for (TT-259, D133: the Alerts tab reads "My trains").
enum MyTrainsCopy {
    /// The tab's label in the tab bar.
    static let tab = "My trains"
    /// The empty tab's lead.
    static let emptyLead = "Tap the bell on a train you take. It stays here and on your widgets, "
        + "and we tell you if it is late or cancelled."
}

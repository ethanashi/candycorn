import Foundation

/// Bottom tab order approved on September 2, 2026: Goals, Journal, Today (center), History, Settings.
/// Prepare is no longer a tab; it opens from the appointment band on Today.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case goals
    case journal
    case today
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .goals: "Goals"
        case .journal: "Journal"
        case .today: "Today"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: AppIcon {
        switch self {
        case .goals: .flag
        case .journal: .journal
        case .today: .home
        case .history: .history
        case .settings: .settings
        }
    }

    var rootRoute: Route {
        switch self {
        case .goals: .goals
        case .journal: .journal
        case .today: .today
        case .history: .history
        case .settings: .settings
        }
    }
}

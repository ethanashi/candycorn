import Foundation

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case journal
    case prepare
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .journal: "Journal"
        case .prepare: "Prepare"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: AppIcon {
        switch self {
        case .today: .home
        case .journal: .journal
        case .prepare: .prepare
        case .history: .history
        case .settings: .settings
        }
    }

    var rootRoute: Route {
        switch self {
        case .today: .today
        case .journal: .capture
        case .prepare: .prepareTherapy
        case .history: .history
        case .settings: .settingsPrivacy
        }
    }
}

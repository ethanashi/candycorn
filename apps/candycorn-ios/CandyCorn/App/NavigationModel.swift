import Foundation
import Observation

@MainActor @Observable
final class NavigationModel {
    var selectedTab: AppTab
    var todayPath: [Route]
    var journalPath: [Route]
    var preparePath: [Route]
    var historyPath: [Route]
    var settingsPath: [Route]
    var presentedFlow: Route?
    var launchRoute: Route?
    var onboardingComplete: Bool
    var selectedSettingsSection: SettingsSection

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let route = Route.parseLaunchArguments(arguments)
        launchRoute = route
        selectedTab = route?.tab ?? .today
        todayPath = []
        journalPath = []
        preparePath = []
        historyPath = []
        settingsPath = []
        presentedFlow = nil
        selectedSettingsSection = route?.settingsSection ?? .privacy
        onboardingComplete = route != nil && route != .welcome
        if let route {
            prepareForLaunch(route)
        }
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
        presentedFlow = nil
    }

    func navigate(to route: Route) {
        if let section = route.settingsSection {
            openSettings(section)
            return
        }
        if route.isPresentedFlow {
            presentedFlow = route
            return
        }
        guard let destinationTab = route.tab else {
            if route == .welcome { onboardingComplete = false }
            return
        }
        selectedTab = destinationTab
        append(route, to: destinationTab)
    }

    func dismissPresentedFlow() {
        presentedFlow = nil
    }

    func openSettings(_ section: SettingsSection) {
        selectedTab = .settings
        selectedSettingsSection = section
        settingsPath = []
        presentedFlow = nil
    }

    func canGoBack(from route: Route) -> Bool {
        if presentedFlow == route { return true }
        guard let tab = route.tab else { return false }
        return path(for: tab).last == route
    }

    func goBack(from route: Route) {
        if presentedFlow == route {
            dismissPresentedFlow()
            return
        }
        guard let tab = route.tab else { return }
        popLast(from: tab, matching: route)
    }

    func backAction(for route: Route) -> (() -> Void)? {
        guard canGoBack(from: route) else { return nil }
        return { [weak self] in self?.goBack(from: route) }
    }

    func completeOnboarding() {
        onboardingComplete = true
        selectedTab = .today
        launchRoute = nil
        presentedFlow = nil
    }

    private func prepareForLaunch(_ route: Route) {
        guard route != .welcome else { return }
        if let section = route.settingsSection {
            openSettings(section)
            return
        }
        if route.isPresentedFlow {
            presentedFlow = route
        } else if let destinationTab = route.tab {
            selectedTab = destinationTab
        }
    }

    private func append(_ route: Route, to tab: AppTab) {
        let path = route == tab.rootRoute ? [] : [route]
        switch tab {
        case .today: todayPath = path
        case .journal: journalPath = path
        case .prepare: preparePath = path
        case .history: historyPath = path
        case .settings: settingsPath = path
        }
    }

    private func path(for tab: AppTab) -> [Route] {
        switch tab {
        case .today: todayPath
        case .journal: journalPath
        case .prepare: preparePath
        case .history: historyPath
        case .settings: settingsPath
        }
    }

    private func popLast(from tab: AppTab, matching route: Route) {
        switch tab {
        case .today where todayPath.last == route: todayPath.removeLast()
        case .journal where journalPath.last == route: journalPath.removeLast()
        case .prepare where preparePath.last == route: preparePath.removeLast()
        case .history where historyPath.last == route: historyPath.removeLast()
        case .settings where settingsPath.last == route: settingsPath.removeLast()
        default: break
        }
    }
}

private extension Route {
    var settingsSection: SettingsSection? {
        switch self {
        case .settingsPrivacy: .privacy
        case .settingsAI: .ai
        case .settingsData: .data
        default: nil
        }
    }
}

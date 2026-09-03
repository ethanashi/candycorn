import Foundation
import Observation

@MainActor @Observable
final class NavigationModel {
    var selectedTab: AppTab
    var goalsPath: [Route]
    var journalPath: [Route]
    var todayPath: [Route]
    var historyPath: [Route]
    var settingsPath: [Route]
    var presentedFlow: Route?
    var launchRoute: Route?
    var onboardingComplete: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let route = Route.parseLaunchArguments(arguments)
        launchRoute = route
        selectedTab = route?.tab ?? .today
        goalsPath = []
        journalPath = []
        todayPath = []
        historyPath = []
        settingsPath = []
        presentedFlow = nil
        onboardingComplete = route != nil && route != .welcome
        if let route {
            prepareForLaunch(route)
        }
    }

    /// The settings section a settings route represents, if any.
    var selectedSettingsSection: SettingsSection {
        SettingsSection.allCases.first { settingsPath.last == $0.route } ?? .privacy
    }

    func select(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        materializeLaunchSource()
        selectedTab = tab
    }

    func navigate(to route: Route) {
        switch route.presentation {
        case .fullScreen:
            materializeLaunchSource()
            presentedFlow = route
        case .root:
            navigateToRoot(route)
        case .pushed:
            materializeLaunchSource()
            guard let destinationTab = route.tab else { return }
            selectedTab = destinationTab
            appendIfNeeded(route, to: destinationTab)
        }
    }

    func dismissPresentedFlow() {
        presentedFlow = nil
    }

    /// Opens one settings section as a pushed detail screen inside the Settings tab.
    func openSettings(_ section: SettingsSection) {
        materializeLaunchSource()
        selectedTab = .settings
        settingsPath = [section.route]
    }

    func canGoBack(from route: Route) -> Bool {
        if route.presentation == .fullScreen { return presentedFlow == route }
        guard route.presentation == .pushed else { return false }
        guard let tab = route.tab else { return false }
        return path(for: tab).last == route
    }

    func goBack(from route: Route) {
        if route.presentation == .fullScreen {
            if presentedFlow == route { dismissPresentedFlow() }
            return
        }
        guard route.presentation == .pushed else { return }
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
        if route.isPresentedFlow {
            presentedFlow = route
        } else if let destinationTab = route.tab {
            selectedTab = destinationTab
        }
    }

    private func navigateToRoot(_ route: Route) {
        guard route != .welcome else {
            onboardingComplete = false
            launchRoute = nil
            presentedFlow = nil
            return
        }
        guard let destinationTab = route.tab else { return }
        if launchRoute?.tab == destinationTab {
            launchRoute = nil
        } else {
            materializeLaunchSource()
        }
        selectedTab = destinationTab
        clearPath(for: destinationTab)
    }

    /// A pushed launch route is shown as the tab's root until the user navigates; then it becomes a real path entry.
    private func materializeLaunchSource() {
        guard let source = launchRoute else { return }
        launchRoute = nil
        guard source.presentation == .pushed, let sourceTab = source.tab else { return }
        appendIfNeeded(source, to: sourceTab)
    }

    private func appendIfNeeded(_ route: Route, to tab: AppTab) {
        switch tab {
        case .goals where goalsPath.last != route: goalsPath.append(route)
        case .journal where journalPath.last != route: journalPath.append(route)
        case .today where todayPath.last != route: todayPath.append(route)
        case .history where historyPath.last != route: historyPath.append(route)
        case .settings where settingsPath.last != route: settingsPath.append(route)
        default: break
        }
    }

    private func clearPath(for tab: AppTab) {
        switch tab {
        case .goals: goalsPath = []
        case .journal: journalPath = []
        case .today: todayPath = []
        case .history: historyPath = []
        case .settings: settingsPath = []
        }
    }

    func path(for tab: AppTab) -> [Route] {
        switch tab {
        case .goals: goalsPath
        case .journal: journalPath
        case .today: todayPath
        case .history: historyPath
        case .settings: settingsPath
        }
    }

    private func popLast(from tab: AppTab, matching route: Route) {
        switch tab {
        case .goals where goalsPath.last == route: goalsPath.removeLast()
        case .journal where journalPath.last == route: journalPath.removeLast()
        case .today where todayPath.last == route: todayPath.removeLast()
        case .history where historyPath.last == route: historyPath.removeLast()
        case .settings where settingsPath.last == route: settingsPath.removeLast()
        default: break
        }
    }
}

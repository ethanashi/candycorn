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
            append(route, to: destinationTab)
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
}

private extension Route {
    var isPresentedFlow: Bool {
        switch self {
        case .checkIn, .capture, .journalVoice, .journalWrite, .journalPhoto,
             .recordAppointment, .activeAppointment:
            true
        default:
            false
        }
    }
}

import Testing
@testable import CandyCorn

@Suite("Application navigation")
@MainActor
struct NavigationIntegrationTests {
    @Test("Tabs have the expected roots")
    func tabRoots() {
        #expect(AppTab.today.rootRoute == .today)
        #expect(AppTab.journal.rootRoute == .capture)
        #expect(AppTab.prepare.rootRoute == .prepareTherapy)
        #expect(AppTab.history.rootRoute == .history)
        #expect(AppTab.settings.rootRoute == .settingsPrivacy)
    }

    @Test("Every route has the expected tab ownership")
    func routeOwnership() {
        let expected: [Route: AppTab] = [
            .today: .today, .checkIn: .today, .goals: .today,
            .bringUp: .today, .appointments: .today,
            .capture: .journal, .journalVoice: .journal, .journalWrite: .journal,
            .journalPhoto: .journal, .journalDetail: .journal, .journalSuggestions: .journal,
            .therapySession: .history, .tmsPost: .history, .history: .history, .search: .history,
            .tmsPre: .prepare, .prepareTherapy: .prepare, .prepareTMS: .prepare,
            .settingsPrivacy: .settings, .settingsAI: .settings, .settingsData: .settings,
        ]
        let unowned: Set<Route> = [.welcome, .recordAppointment, .activeAppointment]

        #expect(expected.count + unowned.count == Route.allCases.count)
        for route in Route.allCases {
            if let tab = expected[route] {
                #expect(route.tab == tab)
            } else {
                #expect(unowned.contains(route))
                #expect(route.tab == nil)
            }
        }
    }

    @Test("Floating navigation visibility is explicit")
    func floatingNavigationVisibility() {
        let visible: Set<Route> = [
            .today, .journalDetail, .journalSuggestions, .goals, .bringUp,
            .appointments, .therapySession, .prepareTherapy, .prepareTMS,
            .history, .search, .settingsPrivacy, .settingsAI, .settingsData,
        ]

        #expect(visible.count == 14)
        for route in Route.allCases {
            #expect(route.showsFloatingTabBar == visible.contains(route))
        }
    }

    @Test("Capture and recording routes use full-screen presentation")
    func fullScreenRoutes() {
        let expected: Set<Route> = [
            .checkIn, .capture, .journalVoice, .journalWrite, .journalPhoto,
            .recordAppointment, .activeAppointment,
        ]

        for route in Route.allCases {
            let navigation = NavigationModel(arguments: [])
            navigation.navigate(to: route)
            #expect((navigation.presentedFlow == route) == expected.contains(route))
        }
    }

    @Test("Malformed launch arguments use normal onboarding")
    func malformedLaunchFallback() {
        for arguments in [[], ["CandyCorn", "-screen"], ["CandyCorn", "-screen", "/not-a-route"]] {
            let navigation = NavigationModel(arguments: arguments)
            #expect(navigation.launchRoute == nil)
            #expect(navigation.onboardingComplete == false)
            #expect(navigation.selectedTab == .today)
        }
    }

    @Test("Switching tabs retains each navigation path")
    func tabPathRetention() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        navigation.navigate(to: .goals)
        navigation.navigate(to: .journalDetail)
        navigation.navigate(to: .settingsAI)

        #expect(navigation.todayPath == [.goals])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath == [.settingsAI])
        navigation.select(.today)
        #expect(navigation.todayPath == [.goals])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath == [.settingsAI])
    }

    @Test("Completing onboarding opens Today")
    func onboardingCompletion() {
        let navigation = NavigationModel(arguments: [])
        #expect(navigation.onboardingComplete == false)

        navigation.completeOnboarding()

        #expect(navigation.onboardingComplete)
        #expect(navigation.selectedTab == .today)
        #expect(navigation.launchRoute == nil)
        #expect(navigation.presentedFlow == nil)
    }

    @Test("Dismissing a flow returns to its retained source")
    func flowDismissal() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.goals.rawValue])
        navigation.navigate(to: .checkIn)
        #expect(navigation.presentedFlow == .checkIn)

        navigation.dismissPresentedFlow()

        #expect(navigation.presentedFlow == nil)
        #expect(navigation.selectedTab == .today)
        #expect(navigation.todayPath == [.goals])
    }

    @Test("Active appointment launch prepares screenshot state only")
    func activeRecordingLaunchPreparation() {
        let arguments = ["CandyCorn", "-screen", Route.activeAppointment.rawValue]
        let navigation = NavigationModel(arguments: arguments)
        let screenshotState = DemoState(arguments: arguments)
        let normalState = DemoState(arguments: [])

        #expect(navigation.presentedFlow == .activeAppointment)
        #expect(navigation.onboardingComplete)
        #expect(screenshotState.consentAcknowledged)
        #expect(screenshotState.appointmentRecording == .recording(startSeconds: 0))
        #expect(normalState.consentAcknowledged == false)
        #expect(normalState.appointmentRecording == .idle)
    }

    @Test("All direct routes launch deterministically")
    func directRouteLaunches() {
        for route in Route.allCases {
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", route.rawValue])
            #expect(navigation.launchRoute == route)
            #expect(navigation.onboardingComplete == (route != .welcome))
            if route != .welcome {
                #expect(navigation.presentedFlow == route || navigation.selectedTab == route.tab)
            }
        }
    }
}

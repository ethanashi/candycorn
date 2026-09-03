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
        navigation.openSettings(.ai)

        #expect(navigation.todayPath == [.goals])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath.isEmpty)
        #expect(navigation.selectedSettingsSection == .ai)
        navigation.select(.today)
        #expect(navigation.todayPath == [.goals])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath.isEmpty)
    }

    @Test("Settings sections switch in place and deep links select their section")
    func settingsSections() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.settingsPrivacy.rawValue])
        for section in SettingsSection.allCases {
            navigation.openSettings(section)
            #expect(navigation.settingsPath.isEmpty)
            #expect(navigation.presentedFlow == nil)
            #expect(navigation.selectedSettingsSection == section)
        }
        #expect(NavigationModel(arguments: ["CandyCorn", "-screen", Route.settingsAI.rawValue]).selectedSettingsSection == .ai)
        #expect(NavigationModel(arguments: ["CandyCorn", "-screen", Route.settingsData.rawValue]).selectedSettingsSection == .data)
    }

    @Test("Back behavior covers roots, pushes, and full-screen flows")
    func backBehavior() {
        for root in AppTab.allCases.map(\.rootRoute) {
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", root.rawValue])
            navigation.goBack(from: root)
            #expect(!navigation.canGoBack(from: root))
        }

        let pushed = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        pushed.navigate(to: .goals)
        #expect(pushed.canGoBack(from: .goals))
        pushed.goBack(from: .goals)
        #expect(pushed.todayPath.isEmpty)

        let flow = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        flow.navigate(to: .checkIn)
        #expect(flow.canGoBack(from: .checkIn))
        flow.goBack(from: .checkIn)
        #expect(flow.presentedFlow == nil)
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
                if !route.isPresentedFlow { #expect(!navigation.canGoBack(from: route)) }
            }
        }
    }
}

import Testing
@testable import CandyCorn

@Suite("Application navigation")
@MainActor
struct NavigationIntegrationTests {
    @Test("Tabs have the expected roots")
    func tabRoots() {
        #expect(AppTab.allCases == [.goals, .journal, .today, .history, .settings])
        #expect(AppTab.goals.rootRoute == .goals)
        #expect(AppTab.journal.rootRoute == .journal)
        #expect(AppTab.today.rootRoute == .today)
        #expect(AppTab.history.rootRoute == .history)
        #expect(AppTab.settings.rootRoute == .settings)
    }

    @Test("Every route has the expected tab ownership")
    func routeOwnership() {
        let expected: [Route: AppTab] = [
            .today: .today, .checkIn: .today, .appointments: .today,
            .tmsPre: .today, .prepareTherapy: .today, .prepareTMS: .today,
            .goals: .goals, .bringUp: .goals,
            .journal: .journal, .capture: .journal, .journalVoice: .journal, .journalWrite: .journal,
            .journalPhoto: .journal, .journalDetail: .journal, .journalSuggestions: .journal,
            .therapySession: .history, .tmsPost: .history, .history: .history, .search: .history, .sessionDebrief: .history,
            .settings: .settings, .settingsPrivacy: .settings, .settingsAI: .settings, .settingsData: .settings,
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
            .today, .goals, .journal, .history, .settings,
            .journalDetail, .journalSuggestions, .bringUp,
            .appointments, .therapySession, .prepareTherapy, .prepareTMS,
            .search, .settingsPrivacy, .settingsAI, .settingsData, .sessionDebrief,
        ]

        #expect(visible.count == 17)
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
        navigation.navigate(to: .appointments)
        navigation.navigate(to: .journalDetail)
        navigation.openSettings(.ai)

        #expect(navigation.todayPath == [.appointments])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath == [.settingsAI])
        #expect(navigation.selectedSettingsSection == .ai)
        navigation.select(.today)
        #expect(navigation.todayPath == [.appointments])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(navigation.settingsPath == [.settingsAI])
    }

    @Test("Settings sections open as one pushed detail each and never stack")
    func settingsSections() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.settings.rawValue])
        for section in SettingsSection.allCases {
            navigation.openSettings(section)
            #expect(navigation.settingsPath == [section.route])
            #expect(navigation.presentedFlow == nil)
            #expect(navigation.selectedTab == .settings)
            #expect(navigation.selectedSettingsSection == section)
            #expect(navigation.canGoBack(from: section.route))
        }
        navigation.goBack(from: .settingsData)
        #expect(navigation.settingsPath.isEmpty)
        #expect(NavigationModel(arguments: ["CandyCorn", "-screen", Route.settingsAI.rawValue]).selectedTab == .settings)
    }

    @Test("Back behavior covers every root, pushed route, and full-screen flow")
    func backBehavior() {
        for root in Route.allCases where root.presentation == .root {
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", root.rawValue])
            let selectedTab = navigation.selectedTab
            navigation.goBack(from: root)
            #expect(!navigation.canGoBack(from: root))
            #expect(navigation.backAction(for: root) == nil)
            #expect(navigation.selectedTab == selectedTab)
            #expect(navigation.presentedFlow == nil)
        }

        for route in Route.allCases where route.presentation == .pushed {
            let tab = route.tab!
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
            navigation.select(tab)
            navigation.navigate(to: route)
            #expect(navigation.canGoBack(from: route))
            #expect(navigation.backAction(for: route) != nil)
            #expect(path(in: navigation, for: tab).last == route)
            #expect(AppTab.allCases.filter { path(in: navigation, for: $0).contains(route) }.count == 1)
            navigation.goBack(from: route)
            #expect(!navigation.canGoBack(from: route))
            #expect(navigation.presentedFlow == nil)
        }

        for route in Route.allCases where route.presentation == .fullScreen {
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
            navigation.navigate(to: route)
            #expect(navigation.presentedFlow == route)
            #expect(navigation.canGoBack(from: route))
            #expect(navigation.backAction(for: route) != nil)
            navigation.goBack(from: route)
            #expect(navigation.presentedFlow == nil)
            #expect(!navigation.canGoBack(from: route))
        }
    }

    @Test("Root navigation clears only the destination stack")
    func rootNavigation() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        navigation.navigate(to: .appointments)
        navigation.navigate(to: .journalDetail)
        navigation.navigate(to: .search)

        navigation.navigate(to: .history)

        #expect(navigation.selectedTab == .history)
        #expect(navigation.historyPath.isEmpty)
        #expect(navigation.todayPath == [.appointments])
        #expect(navigation.journalPath == [.journalDetail])
        #expect(!navigation.canGoBack(from: .history))
        #expect(navigation.backAction(for: .history) == nil)
    }

    @Test("Back ignores a pushed route that is not on top")
    func nonTopBack() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        navigation.navigate(to: .appointments)
        navigation.navigate(to: .prepareTherapy)

        #expect(navigation.todayPath == [.appointments, .prepareTherapy])
        #expect(!navigation.canGoBack(from: .appointments))
        navigation.goBack(from: .appointments)
        #expect(navigation.todayPath == [.appointments, .prepareTherapy])

        navigation.goBack(from: .prepareTherapy)
        #expect(navigation.todayPath == [.appointments])
        #expect(navigation.canGoBack(from: .appointments))
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
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.bringUp.rawValue])
        navigation.navigate(to: .checkIn)
        #expect(navigation.presentedFlow == .checkIn)
        #expect(navigation.launchRoute == nil)
        #expect(navigation.goalsPath == [.bringUp])

        navigation.dismissPresentedFlow()
        navigation.dismissPresentedFlow()

        #expect(navigation.presentedFlow == nil)
        #expect(navigation.selectedTab == .goals)
        #expect(navigation.goalsPath == [.bringUp])
    }

    @Test("Every pushed deep link is retained under a presented flow")
    func pushedDeepLinkFlowRetention() {
        for source in Route.allCases where source.presentation == .pushed {
            let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", source.rawValue])
            let sourceTab = source.tab!
            #expect(!navigation.canGoBack(from: source))

            navigation.navigate(to: .checkIn)

            #expect(navigation.launchRoute == nil)
            #expect(navigation.selectedTab == sourceTab)
            #expect(path(in: navigation, for: sourceTab) == [source])
            #expect(navigation.presentedFlow == .checkIn)
            navigation.dismissPresentedFlow()
            #expect(path(in: navigation, for: sourceTab) == [source])
            #expect(navigation.presentedFlow == nil)
        }
    }

    @Test("Presenting and switching tabs retain every tab path")
    func flowAndTabRetention() {
        let navigation = NavigationModel(arguments: ["CandyCorn", "-screen", Route.today.rawValue])
        navigation.navigate(to: .bringUp)
        navigation.navigate(to: .journalDetail)
        navigation.navigate(to: .prepareTMS)
        navigation.navigate(to: .search)
        navigation.navigate(to: .checkIn)

        let paths = AppTab.allCases.map { path(in: navigation, for: $0) }
        navigation.select(.settings)

        #expect(navigation.selectedTab == .settings)
        #expect(navigation.presentedFlow == .checkIn)
        #expect(AppTab.allCases.map { path(in: navigation, for: $0) } == paths)
        navigation.goBack(from: .checkIn)
        #expect(navigation.presentedFlow == nil)
        #expect(AppTab.allCases.map { path(in: navigation, for: $0) } == paths)
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

    private func path(in navigation: NavigationModel, for tab: AppTab) -> [Route] {
        switch tab {
        case .goals: navigation.goalsPath
        case .journal: navigation.journalPath
        case .today: navigation.todayPath
        case .history: navigation.historyPath
        case .settings: navigation.settingsPath
        }
    }
}

import Testing
@testable import CandyCorn

@Suite("Routes")
struct RouteTests {
    @Test("All route metadata is complete and unique")
    func metadata() {
        let routes = Route.allCases
        #expect(routes.count == 24)
        #expect(Set(routes.map(\.rawValue)).count == 24)
        #expect(Set(routes.map(\.screenshotFilename)).count == 24)
        #expect(routes.map(\.order) == Array(1...24))
    }

    @Test("Every route has one truthful presentation family")
    func presentationFamilies() {
        let roots: Set<Route> = [
            .welcome, .today, .prepareTherapy, .history,
            .settingsPrivacy, .settingsAI, .settingsData,
        ]
        let pushed: Set<Route> = [
            .journalDetail, .journalSuggestions, .goals, .bringUp, .appointments,
            .therapySession, .tmsPre, .tmsPost, .prepareTMS, .search,
        ]
        let fullScreen: Set<Route> = [
            .checkIn, .capture, .journalVoice, .journalWrite, .journalPhoto,
            .recordAppointment, .activeAppointment,
        ]

        #expect(roots.count + pushed.count + fullScreen.count == Route.allCases.count)
        #expect(roots.isDisjoint(with: pushed))
        #expect(roots.isDisjoint(with: fullScreen))
        #expect(pushed.isDisjoint(with: fullScreen))
        for route in Route.allCases {
            let expected: RoutePresentation = if roots.contains(route) {
                .root
            } else if pushed.contains(route) {
                .pushed
            } else {
                .fullScreen
            }
            #expect(route.presentation == expected)
        }
    }

    @Test("Routes use the approved paths and screenshot names")
    func approvedValues() {
        let expected: [(Route, String, String)] = [
            (.welcome, "/welcome", "01-welcome.png"),
            (.today, "/today", "02-today.png"),
            (.checkIn, "/check-in", "03-check-in.png"),
            (.capture, "/capture", "04-capture.png"),
            (.journalVoice, "/journal/voice", "05-voice-rant.png"),
            (.journalWrite, "/journal/write", "06-text-journal.png"),
            (.journalPhoto, "/journal/photo", "07-journal-photo.png"),
            (.journalDetail, "/journal/entry/football-and-guilt", "08-journal-detail.png"),
            (.journalSuggestions, "/journal/suggestions", "09-ai-suggestions.png"),
            (.goals, "/goals", "10-goals.png"),
            (.bringUp, "/bring-up", "11-bring-up.png"),
            (.appointments, "/appointments", "12-appointments.png"),
            (.recordAppointment, "/appointments/record", "13-record-appointment.png"),
            (.activeAppointment, "/appointments/active", "14-active-appointment.png"),
            (.therapySession, "/sessions/therapy-sep-2", "15-therapy-session.png"),
            (.tmsPre, "/tms/pre-session", "16-tms-pre.png"),
            (.tmsPost, "/tms/post-session", "17-tms-post.png"),
            (.prepareTherapy, "/prepare/therapy", "18-prepare-therapy.png"),
            (.prepareTMS, "/prepare/tms", "19-prepare-tms.png"),
            (.history, "/history", "20-history.png"),
            (.search, "/search", "21-search.png"),
            (.settingsPrivacy, "/settings/privacy", "22-settings-privacy.png"),
            (.settingsAI, "/settings/ai", "23-settings-ai.png"),
            (.settingsData, "/settings/data", "24-settings-data.png"),
        ]
        for item in expected {
            #expect(item.0.rawValue == item.1)
            #expect(item.0.screenshotFilename == item.2)
        }
    }

    @Test("Launch arguments parse safely")
    func launchArguments() {
        #expect(Route.parseLaunchArguments(["CandyCorn", "-screen", "/today"]) == .today)
        #expect(Route.parseLaunchArguments(["CandyCorn", "-flag", "value", "-screen", "/settings/ai"]) == .settingsAI)
        #expect(Route.parseLaunchArguments(["CandyCorn"]) == nil)
        #expect(Route.parseLaunchArguments(["CandyCorn", "-screen"]) == nil)
        #expect(Route.parseLaunchArguments(["CandyCorn", "-screen", "/missing"]) == nil)
    }

    @Test("Navigation retains tab stacks and presents capture flows")
    @MainActor
    func navigation() {
        let model = NavigationModel(arguments: ["CandyCorn"])
        #expect(!model.onboardingComplete)
        model.completeOnboarding()
        model.navigate(to: .goals)
        #expect(model.selectedTab == .today)
        #expect(model.todayPath == [.goals])
        model.navigate(to: .journalDetail)
        #expect(model.selectedTab == .journal)
        #expect(model.journalPath == [.journalDetail])
        #expect(model.todayPath == [.goals])
        model.navigate(to: .capture)
        #expect(model.presentedFlow == .capture)
        model.dismissPresentedFlow()
        #expect(model.presentedFlow == nil)
    }
}

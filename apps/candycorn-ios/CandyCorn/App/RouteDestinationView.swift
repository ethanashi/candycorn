import SwiftUI

struct RouteDestinationView: View {
    let route: Route
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    @ViewBuilder
    var body: some View {
        switch route {
        case .welcome:
            WelcomeView(navigation: navigation)
        case .today:
            TodayView(navigation: navigation, state: state)
        case .checkIn:
            CheckInView(navigation: navigation, state: state)
        case .capture:
            CaptureChoiceView(navigation: navigation)
        case .journalVoice:
            VoiceJournalView(navigation: navigation)
        case .journalWrite:
            TextJournalView(navigation: navigation)
        case .journalPhoto:
            PhotoJournalView(navigation: navigation)
        case .journalDetail:
            JournalDetailView(navigation: navigation, state: state)
        case .journalSuggestions:
            JournalSuggestionsView(navigation: navigation, state: state)
        case .goals:
            GoalsView(navigation: navigation, state: state)
        case .bringUp:
            BringUpView(navigation: navigation, state: state)
        case .appointments:
            AppointmentsView(navigation: navigation)
        case .recordAppointment:
            RecordAppointmentView(navigation: navigation, state: state)
        case .activeAppointment:
            ActiveAppointmentView(navigation: navigation, state: state)
        case .therapySession:
            TherapySessionView(navigation: navigation, state: state)
        case .tmsPre:
            TMSPreSessionView(navigation: navigation, state: state)
        case .tmsPost:
            TMSPostSessionView(navigation: navigation)
        case .prepareTherapy:
            PrepareTherapyView(navigation: navigation)
        case .prepareTMS:
            PrepareTMSView(navigation: navigation, state: state)
        case .history:
            HistoryView(navigation: navigation, state: state)
        case .search:
            SearchMemoryView(navigation: navigation, state: state)
        case .settingsPrivacy:
            SettingsPrivacyView(navigation: navigation, state: state)
        case .settingsAI:
            SettingsPrivacyView(navigation: navigation, state: state)
        case .settingsData:
            SettingsPrivacyView(navigation: navigation, state: state)
        }
    }
}

import SwiftUI

struct PrepareTMSView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ScreenLayout(
            title: "Prepare for TMS",
            subtitle: "Saved observations for the next Riverbend TMS visit.",
            backAction: { navigation.navigate(to: .today) },
            backLabel: "Back to Today"
        ) {
            currentMood
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(DesignTokens.hairline)
                TMSBriefLine(
                    title: "Before and after notes",
                    copy: "Before the visit, you noted low energy and worry about the day. Afterward, you noted a quieter morning and a mild headache. These observations do not show that TMS caused a mood change.",
                    provenance: Provenance(voice: .user, label: "You recorded these observations", detail: "TMS, Sep 5 before and after the visit", occurredAt: nil, sourceRoute: .tmsPost)
                )
                TMSBriefLine(
                    title: "A question for the team",
                    copy: "Should I keep tracking the headache if it is still mild later today?",
                    provenance: Provenance(voice: .user, label: "You saved this question", detail: "TMS pre-session, Sep 5 at 9:18 AM", occurredAt: nil, sourceRoute: .tmsPre)
                )
                TMSBriefLine(
                    title: "Provider-approved focus",
                    copy: "Notice when moving-forward guilt appears. Do not change your treatment plan based on this app.",
                    provenance: Provenance(voice: .provider, label: "Dr. Elena Park asked you to notice this", detail: "Therapy, Sep 2 at 38:44", occurredAt: nil, sourceRoute: .therapySession)
                )
            }
            StatusNotice(
                title: "Your treatment stays with your care team",
                detail: "Candy Corn organizes saved items. It does not create treatment provocations or tell you how to change treatment."
            )
            VStack(spacing: DesignTokens.Spacing.small) {
                Button("Open pre-session capture") { navigation.navigate(to: .tmsPre) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Open post-session capture") { navigation.navigate(to: .tmsPost) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var currentMood: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("How you are doing now")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            if state.mood == nil {
                Text("No check-in yet")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            MoodBands(values: moodValues, compact: true)
            Text(moodSummary)
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }

    private var moodValues: MoodValues {
        MoodValues(mood: state.mood?.mood, anxiety: state.mood?.anxiety, energy: state.mood?.energy)
    }

    private var moodSummary: String {
        guard let mood = state.mood else {
            return "Mood not logged. Anxiety not logged. Distress was not recorded."
        }
        return "Mood \(value(mood.mood)). Anxiety \(value(mood.anxiety)). Distress was not recorded."
    }

    private func value(_ value: Int?) -> String {
        value.map { "\($0) of 10" } ?? "not logged"
    }
}

private struct TMSBriefLine: View {
    let title: String
    let copy: String
    let provenance: Provenance

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Text(copy)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceLine(provenance: provenance, compact: true)
                .padding(.top, DesignTokens.Spacing.xSmall)
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }
}

import SwiftUI

struct AppointmentsView: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        ScreenLayout(
            title: "Appointments",
            subtitle: "Upcoming care and the source record from completed visits.",
            backAction: navigation.backAction(for: .appointments)
        ) {
            Button {
                navigation.navigate(to: .recordAppointment)
            } label: {
                Label("Record an appointment", systemImage: AppIcon.microphone.rawValue)
            }
            .buttonStyle(PrimaryButtonStyle())

            VStack(spacing: 0) {
                Divider().overlay(DesignTokens.hairline)
                appointmentRow(
                    month: "Sep",
                    day: "9",
                    kind: "Therapy",
                    provider: SeededData.therapyProviderName,
                    detail: "2:00 PM · Upcoming",
                    actions: [
                        AppointmentAction(title: "Prepare", route: .prepareTherapy),
                        AppointmentAction(title: "Record appointment", route: .recordAppointment),
                    ]
                )
                appointmentRow(
                    month: "Sep",
                    day: "5",
                    kind: "TMS",
                    provider: SeededData.tmsProviderName,
                    detail: "22 min · Completed",
                    actions: [AppointmentAction(title: "Review check-in", route: .tmsPost)]
                )
                appointmentRow(
                    month: "Sep",
                    day: "2",
                    kind: "Therapy",
                    provider: SeededData.therapyProviderName,
                    detail: "50 min · Completed",
                    actions: [AppointmentAction(title: "Open session", route: .therapySession)]
                )
            }
        }
    }

    private func appointmentRow(
        month: String,
        day: String,
        kind: String,
        provider: String,
        detail: String,
        actions: [AppointmentAction]
    ) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.base) {
            dateBlock(month: month, day: day)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        appointmentTitle(kind)
                        Spacer(minLength: DesignTokens.Spacing.small)
                        providerLabel(provider)
                    }
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                        appointmentTitle(kind)
                        providerLabel(provider)
                    }
                }
                Text(detail)
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .monospacedDigit()
                FlowActions(actions: actions, navigation: navigation)
                    .padding(.top, DesignTokens.Spacing.xSmall)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .contain)
    }

    private func dateBlock(month: String, day: String) -> some View {
        VStack(spacing: 1) {
            Text(month).font(TypeScale.provenance)
            Text(day).font(TypeScale.sectionCompact).monospacedDigit()
        }
        .foregroundStyle(DesignTokens.cocoa)
        .frame(width: 48, height: 56)
        .background(DesignTokens.surfaceWarm)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DesignTokens.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func appointmentTitle(_ title: String) -> some View {
        Text(title).font(TypeScale.bodyMedium).foregroundStyle(DesignTokens.cocoa)
    }

    private func providerLabel(_ provider: String) -> some View {
        Text(provider)
            .font(TypeScale.provenance)
            .foregroundStyle(DesignTokens.cocoaSoft)
            .multilineTextAlignment(.trailing)
    }
}

private struct AppointmentAction: Identifiable {
    let title: String
    let route: Route
    var id: Route { route }
}

private struct FlowActions: View {
    let actions: [AppointmentAction]
    @Bindable var navigation: NavigationModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.base) { buttons }
            VStack(alignment: .leading, spacing: 0) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(actions) { action in
            Button(action.title) { navigation.navigate(to: action.route) }
                .font(TypeScale.label)
                .fontWeight(.semibold)
                .foregroundStyle(DesignTokens.cocoa)
                .underline()
                .frame(minHeight: DesignTokens.controlMinimum)
        }
    }
}

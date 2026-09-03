import SwiftUI

extension Appointment.Kind {
    var displayName: String {
        switch self {
        case .therapy: "Therapy"
        case .tms: "TMS"
        case .psychiatry: "Psychiatry"
        case .other: "Other"
        }
    }
}

struct RecordAppointmentView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ScreenLayout(
            title: "Record an appointment",
            subtitle: "Choose the visit type before confirming permission.",
            backAction: { navigation.dismissPresentedFlow() },
            backLabel: "Back to appointments",
            bottomInset: DesignTokens.Spacing.section
        ) {
            UnderlinePicker(
                options: Appointment.Kind.allCases,
                selection: appointmentKind,
                title: { $0.displayName }
            )
            consentCard
            Text("The original audio stays on this device before any processing.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .interactiveDismissDisabled(state.consentAcknowledged)
        .onAppear(perform: resetSavedRecording)
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: .user, height: 20, decorative: true)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("Recording requires permission")
                        .font(TypeScale.section)
                    Text(consentReason)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            consentToggle
            startButton
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }

    private var consentToggle: some View {
        Button {
            state.consentAcknowledged.toggle()
        } label: {
            HStack(spacing: DesignTokens.Spacing.compact) {
                Image(systemName: state.consentAcknowledged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(state.consentAcknowledged ? DesignTokens.orangePressed : DesignTokens.cocoaSoft)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                Text("I have permission to record this appointment")
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.compact)
            .background(DesignTokens.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I have permission to record this appointment")
        .accessibilityValue(state.consentAcknowledged ? "Checked" : "Not checked")
        .accessibilityHint(consentReason)
    }

    private var startButton: some View {
        Button("Start recording", action: start)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!state.consentAcknowledged || state.appointmentRecording != .idle)
            .opacity(state.consentAcknowledged ? 1 : 0.48)
            .accessibilityHint(state.consentAcknowledged ? "Starts recording" : consentReason)
    }

    private var appointmentKind: Binding<Appointment.Kind> {
        Binding(
            get: { state.selectedAppointmentKind },
            set: { state.selectAppointmentKind($0) }
        )
    }

    private var consentReason: String {
        "Ask everyone in the room before recording. Start stays unavailable until you confirm."
    }

    private func start() {
        guard state.startAppointmentRecording() else { return }
        navigation.navigate(to: .activeAppointment)
    }

    private func resetSavedRecording() {
        guard case .saved = state.appointmentRecording else { return }
        let selected = state.selectedAppointmentKind
        state.selectAppointmentKind(selected == .therapy ? .other : .therapy)
        state.selectAppointmentKind(selected)
    }
}

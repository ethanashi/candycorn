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
    @State private var isStarting = false
    @State private var startFailed = false

    var body: some View {
        ScreenLayout(
            title: "Record an appointment",
            subtitle: "Choose the visit type before confirming permission.",
            backAction: navigation.backAction(for: .recordAppointment),
            bottomInset: DesignTokens.Spacing.section
        ) {
            UnderlinePicker(options: Appointment.Kind.allCases, selection: appointmentKind, title: { $0.displayName })
            consentCard
            if startFailed {
                StatusNotice(title: "Recording could not start", detail: state.operationError ?? "Try again. Your existing records are unchanged.", kind: .warning)
            }
            Text("The original audio stays on this device before any processing.")
                .font(TypeScale.provenance)
                .tracking(0)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(isStarting)
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: .user, height: 20, decorative: true)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("Recording requires permission").font(TypeScale.section).tracking(-0.2)
                    Text("Ask everyone in the room before recording. Recording must be permitted where you are.")
                        .font(TypeScale.body).tracking(0).foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
            Button { state.consentAcknowledged.toggle() } label: {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Image(systemName: state.consentAcknowledged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24)).foregroundStyle(state.consentAcknowledged ? DesignTokens.orangePressed : DesignTokens.cocoa)
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                    Text("I have permission to record this appointment").font(TypeScale.bodyMedium).tracking(0)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityValue(state.consentAcknowledged ? "Checked" : "Not checked")
            Button(isStarting ? "Starting" : "Start recording", action: start)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!state.consentAcknowledged || isStarting)
        }
        .padding(DesignTokens.Spacing.medium)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius).stroke(DesignTokens.hairline))
    }

    private var appointmentKind: Binding<Appointment.Kind> {
        Binding(get: { state.selectedAppointmentKind }, set: { state.selectAppointmentKind($0) })
    }

    private func start() {
        guard state.consentAcknowledged, !isStarting else { return }
        isStarting = true
        startFailed = false
        Task {
            guard let appointment = await appointmentForRecording() else {
                startFailed = true
                isStarting = false
                return
            }
            if await state.startRecording(kind: .appointment(id: appointment.id)) {
                _ = state.startAppointmentRecording()
                navigation.goBack(from: .recordAppointment)
                navigation.navigate(to: .activeAppointment)
            } else {
                startFailed = true
            }
            isStarting = false
        }
    }

    private func appointmentForRecording() async -> Appointment? {
        if let existing = state.appointments.first(where: { $0.kind == state.selectedAppointmentKind && $0.status == .planned }) {
            return existing
        }
        let now = state.dependencies.now()
        let appointment = Appointment(
            id: UUID(), kind: state.selectedAppointmentKind, scheduledAt: now, startedAt: now,
            endedAt: nil, providerID: nil, providerName: "Care appointment",
            recordingAttachmentID: nil, transcriptID: nil, summaryID: nil, status: .recording
        )
        return await state.saveAppointment(appointment) ? appointment : nil
    }
}

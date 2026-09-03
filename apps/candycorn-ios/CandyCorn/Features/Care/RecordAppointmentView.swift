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
        V2Screen(
            title: "Record an appointment",
            subtitle: "Choose the visit type, then confirm permission.",
            backAction: navigation.backAction(for: .recordAppointment),
            backLabel: "Close",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.section
        ) {
            V2GroupCard(title: "Visit type") {
                ForEach(Appointment.Kind.allCases, id: \.self) { kind in
                    V2ChoiceRow(
                        title: kind.displayName,
                        detail: detail(for: kind),
                        selected: state.selectedAppointmentKind == kind,
                        disabled: isStarting
                    ) { state.selectAppointmentKind(kind) }
                }
            }
            consentCard
            if startFailed {
                StatusNotice(title: "Recording could not start", detail: state.operationError ?? "Try again. Your existing records are unchanged.", kind: .warning)
            }
            ProvenanceInline(voice: .user, text: "The original audio stays on this device before any processing.")
                .padding(.horizontal, DesignTokens.Spacing.xSmall)
        }
        .interactiveDismissDisabled(isStarting)
    }

    private func detail(for kind: Appointment.Kind) -> String {
        switch kind {
        case .therapy: "Talk therapy or counseling."
        case .tms: "A TMS treatment visit."
        case .psychiatry: "Medication or psychiatry visit."
        case .other: "Any other care visit."
        }
    }

    private var consentCard: some View {
        let checked = state.consentAcknowledged
        return V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: .shield, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording needs permission")
                            .font(TypeScale.cardTitle)
                            .foregroundStyle(DesignTokens.cocoa)
                        Text("Ask everyone in the room first. Recording must be allowed where you are.")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { state.consentAcknowledged.toggle() } label: {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(checked ? DesignTokens.orange : DesignTokens.surface)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(checked ? DesignTokens.orange : Color(hex: "#D9D0C7"), lineWidth: 2)
                            if checked {
                                AppIcon.check.image.font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text("I have permission to record this appointment")
                            .font(TypeScale.rowTitleCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(checked ? "Checked" : "Not checked")
                .accessibilityAddTraits(checked ? .isSelected : [])
                Button(isStarting ? "Starting" : "Start recording", action: start)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!checked || isStarting)
                    .opacity(checked ? 1 : 0.45)
            }
        }
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

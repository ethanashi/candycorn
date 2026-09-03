import SwiftUI

struct AppointmentsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ScreenLayout(
            title: "Appointments",
            subtitle: "Upcoming care and source recordings from completed visits.",
            backAction: navigation.backAction(for: .appointments)
        ) {
            Button {
                navigation.navigate(to: .recordAppointment)
            } label: {
                Label("Record an appointment", systemImage: AppIcon.microphone.rawValue)
            }
            .buttonStyle(PrimaryButtonStyle())

            if state.appointments.isEmpty {
                StatusNotice(title: "No appointments yet", detail: "You can record a care appointment when one begins.", kind: .information)
            } else {
                VStack(spacing: 0) {
                    ForEach(state.appointments.sorted(by: appointmentOrder)) { appointment in
                        Button { open(appointment) } label: {
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                                VStack(spacing: 0) {
                                    Text(appointmentDate(appointment).formatted(.dateTime.month(.abbreviated)))
                                        .tracking(0)
                                    Text(appointmentDate(appointment).formatted(.dateTime.day()))
                                        .font(TypeScale.section)
                                        .tracking(0)
                                }
                                .font(TypeScale.provenance).monospacedDigit()
                                .frame(width: 48)
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                                    Text(appointment.kind.displayName).font(TypeScale.bodyMedium).tracking(0)
                                    Text(appointment.providerName).font(TypeScale.label).tracking(0).foregroundStyle(DesignTokens.cocoaSoft)
                                    Text(statusText(appointment)).font(TypeScale.provenance).tracking(0).foregroundStyle(DesignTokens.cocoaSoft)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(DesignTokens.cocoaSoft)
                            }
                            .foregroundStyle(DesignTokens.cocoa)
                            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
                    }
                }
            }
        }
    }

    private func appointmentOrder(_ lhs: Appointment, _ rhs: Appointment) -> Bool {
        appointmentDate(lhs) > appointmentDate(rhs)
    }

    private func appointmentDate(_ appointment: Appointment) -> Date {
        appointment.scheduledAt ?? appointment.startedAt ?? .distantPast
    }

    private func statusText(_ appointment: Appointment) -> String {
        if let record = state.sessionProcessingRecord(for: appointment.id) {
            if record.failure?.code == .summaryPermissionRequired { return "Ready to make the debrief" }
            if record.failure != nil { return "Processing paused, tap to review" }
            switch record.stage {
            case .recordingSaved: return "Recording saved"
            case .transcribing: return "Transcribing on this device"
            case .separatingSpeakers: return "Separating speakers on this device"
            case .summarizing: return "Creating your debrief"
            case .ready: return "Transcript and debrief ready"
            }
        }
        return switch appointment.status {
        case .planned: "Upcoming"
        case .recording: "Recording"
        case .processing: "Recording saved"
        case .completed: appointment.recordingAttachmentID == nil ? "Notes saved" : "Recording saved"
        }
    }

    private func open(_ appointment: Appointment) {
        if appointment.recordingAttachmentID != nil,
           appointment.status == .processing || appointment.status == .completed {
            state.selectAppointment(id: appointment.id)
            navigation.navigate(to: appointment.kind == .tms ? .tmsPost : .therapySession)
        }
    }
}

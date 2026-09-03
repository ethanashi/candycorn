import SwiftUI

struct AppointmentsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        V2Screen(
            title: "Appointments",
            subtitle: "Upcoming care and recordings from completed visits.",
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
                V2GroupCard {
                    ForEach(Array(state.appointments.sorted(by: appointmentOrder).enumerated()), id: \.element.id) { index, appointment in
                        row(appointment, divider: index > 0)
                    }
                }
            }
        }
    }

    private func row(_ appointment: Appointment, divider: Bool) -> some View {
        let date = appointmentDate(appointment)
        let openable = isOpenable(appointment)
        return Button { open(appointment) } label: {
            HStack(spacing: DesignTokens.Spacing.compact) {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(TypeScale.tabLabel)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    Text(date.formatted(.dateTime.day()))
                        .font(TypeScale.numeral)
                        .foregroundStyle(DesignTokens.cocoa)
                }
                .frame(width: 44, height: 44)
                .background(DesignTokens.surfaceWarm)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appointment.kind.displayName) · \(appointment.providerName)")
                        .font(TypeScale.rowTitleCompact)
                        .foregroundStyle(DesignTokens.cocoa)
                        .lineLimit(1)
                    Text(statusText(appointment))
                        .font(TypeScale.meta)
                        .foregroundStyle(statusIsReady(appointment) ? DesignTokens.sage : DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignTokens.Spacing.small)
                if openable {
                    AppIcon.chevronRight.image
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.base)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .overlay(alignment: .top) {
                if divider {
                    Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!openable)
        .accessibilityLabel("\(appointment.kind.displayName) with \(appointment.providerName), \(date.formatted(.dateTime.month(.abbreviated).day())), \(statusText(appointment))")
    }

    private func appointmentOrder(_ lhs: Appointment, _ rhs: Appointment) -> Bool {
        appointmentDate(lhs) > appointmentDate(rhs)
    }

    private func appointmentDate(_ appointment: Appointment) -> Date {
        appointment.scheduledAt ?? appointment.startedAt ?? .distantPast
    }

    private func statusIsReady(_ appointment: Appointment) -> Bool {
        state.sessionProcessingRecord(for: appointment.id)?.stage == .ready
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

    private func isOpenable(_ appointment: Appointment) -> Bool {
        appointment.recordingAttachmentID != nil
            && (appointment.status == .processing || appointment.status == .completed)
    }

    private func open(_ appointment: Appointment) {
        guard isOpenable(appointment) else { return }
        state.selectAppointment(id: appointment.id)
        navigation.navigate(to: appointment.kind == .tms ? .tmsPost : .therapySession)
    }
}

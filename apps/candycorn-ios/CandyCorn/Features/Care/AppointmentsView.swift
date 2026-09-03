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
                                    Text(appointmentDate(appointment).formatted(.dateTime.day()))
                                        .font(TypeScale.section)
                                }
                                .font(TypeScale.provenance).monospacedDigit()
                                .frame(width: 48)
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                                    Text(appointment.kind.displayName).font(TypeScale.bodyMedium)
                                    Text(appointment.providerName).font(TypeScale.label).foregroundStyle(DesignTokens.cocoaSoft)
                                    Text(statusText(appointment)).font(TypeScale.provenance).foregroundStyle(DesignTokens.cocoaSoft)
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
        switch appointment.status {
        case .planned: "Upcoming"
        case .recording: "Recording"
        case .processing: "Saving"
        case .completed: appointment.recordingAttachmentID == nil ? "Notes saved" : "Recording saved"
        }
    }

    private func open(_ appointment: Appointment) {
        if appointment.status == .completed {
            state.selectAppointment(id: appointment.id)
            navigation.navigate(to: appointment.kind == .tms ? .tmsPost : .therapySession)
        }
    }
}

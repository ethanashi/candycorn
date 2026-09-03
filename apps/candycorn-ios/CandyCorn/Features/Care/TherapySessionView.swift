import SwiftUI

enum TherapySessionTab: String, CaseIterable, Sendable {
    case summary = "Summary"
    case transcript = "Transcript"
    case homework = "Homework"
    case talkingPoints = "Talking points"
    case notes = "Notes"
}

struct TherapySessionView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var selection = TherapySessionTab.transcript
    @State private var notes = ""
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var isPreparingSummary = false
    @State private var actionError: String?

    @ViewBuilder
    var body: some View {
        if sessionAppointment == nil {
            ScreenLayout(
                title: "Therapy session",
                subtitle: "Saved sessions appear here.",
                backAction: navigation.backAction(for: .therapySession)
            ) {
                StatusNotice(title: "No saved therapy session", detail: "Record an appointment or add manual notes first.", kind: .information)
            }
        } else {
            sessionContent
        }
    }

    private var sessionContent: some View {
        ScreenLayout(
            title: "Therapy with \(sessionAppointment?.providerName ?? "your provider")",
            subtitle: sessionMetadata,
            backAction: navigation.backAction(for: .therapySession),
            bottomInset: 260
        ) {
            UnderlinePicker(options: TherapySessionTab.allCases, selection: $selection) { $0.rawValue }
            panel
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sessionAppointment?.recordingAttachmentID != nil {
                PlaybackScrubber(onPlay: playRecording)
                    .padding(.horizontal, DesignTokens.screenInset)
                    .padding(.bottom, 82)
            }
        }
        .onAppear { notes = sessionAppointment?.manualNotes ?? "" }
        .sheet(item: $pendingSend, onDismiss: cancelSend) { pending in
            WhatLeavesDeviceSheet(
                pending: pending,
                processingState: state.aiProcessingState(for: pending.action),
                onSend: { send(pending) },
                onCancel: cancelSend
            )
        }
        .onDisappear(perform: cancelSend)
    }

    @ViewBuilder private var panel: some View {
        switch selection {
        case .summary: summaryPanel
        case .transcript: transcriptPanel
        case .homework: homeworkPanel
        case .talkingPoints: talkingPointsPanel
        case .notes: notesPanel
        }
    }

    private var summaryPanel: some View {
        VStack(spacing: 0) {
            if let summary = sessionSummary {
                ForEach(summary.result.sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.title)
                            .font(TypeScale.sectionCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                            .padding(.top, DesignTokens.Spacing.medium)
                        ForEach(section.statements) { statement in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                Text(statement.text)
                                    .font(TypeScale.body)
                                    .foregroundStyle(DesignTokens.cocoa)
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                                ProvenanceLine(
                                    provenance: Provenance(
                                        voice: .candyCorn,
                                        label: "Candy Corn suggested this summary",
                                        detail: "\(summary.artifact.provider), \(summary.artifact.model)",
                                        occurredAt: summary.artifact.createdAt,
                                        sourceRoute: nil
                                    ),
                                    compact: true
                                )
                                ForEach(Array(statement.evidence.enumerated()), id: \.offset) { _, evidence in
                                    Button {
                                        selection = .notes
                                    } label: {
                                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                                            Text("From your manual notes")
                                                .font(TypeScale.provenance)
                                                .underline()
                                            Text("“\(evidence.quote)”")
                                                .font(TypeScale.provenance)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .foregroundStyle(DesignTokens.cocoaSoft)
                                        .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, DesignTokens.Spacing.base)
                            .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
                        }
                    }
                }
            } else if hasCorruptSessionSummary {
                StatusNotice(
                    title: "Summary unavailable",
                    detail: "Candy Corn could not read the saved summary. Your manual notes and recording are unchanged.",
                    kind: .warning
                )
            } else {
                StatusNotice(
                    title: "No organized summary yet",
                    detail: "Use Summarize notes from the Notes tab. Audio and transcript text are never included.",
                    kind: .information
                )
            }
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Voice transcription: Not yet available")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            if sessionTranscript.isEmpty {
                StatusNotice(title: "No transcript", detail: "The original recording and your manual notes remain available.", kind: .information)
            } else {
                LazyVStack(spacing: 0) {
            ForEach(sessionTranscript) { segment in
                TranscriptRow(
                    segment: segment,
                    speaker: state.speakerCorrections[segment.id] ?? segment.speaker,
                    correct: { speaker in _ = state.correctSpeaker(segmentID: segment.id, to: speaker) }
                )
                .id(segment.id)
            }
                }
            }
        }
        .accessibilityLabel("Source-preserving transcript")
    }

    private var homeworkPanel: some View {
        CareLedger(items: state.goals.filter { $0.sourceEntityID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.title, provenance: $0.provenance)
        })
    }

    private var talkingPointsPanel: some View {
        CareLedger(items: state.talkingPoints.filter { $0.sourceID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.text, provenance: $0.provenance)
        })
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            Text("Manual notes").font(TypeScale.sectionCompact)
            TextEditor(text: $notes)
                .font(TypeScale.body)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
            Button("Save notes") {
                Task { _ = await saveNotes() }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(isPreparingSummary ? "Preparing" : "Summarize notes") {
                prepareSummary()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(trimmedNotes.isEmpty || !organizerAvailable || isPreparingSummary || pendingSend != nil)
            if !organizerAvailable {
                Text(state.aiMode == .off
                    ? "Organizer is off. Your notes remain editable and on this device."
                    : "Add a Router key in Settings to organize these notes.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.aiMode == .reflection {
                Text("Reflection uses Organizer for this summary. It does not start a conversation.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.yellowText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionError {
                StatusNotice(title: "Could not organize notes", detail: actionError, kind: .warning)
            }
            Button("Add to next appointment") {
                Task { _ = await state.createTalkingPoint(text: notes, source: .session, sourceID: sessionAppointment?.id) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sessionAppointment: Appointment? {
        if let id = state.selectedAppointmentID,
           let selected = state.appointments.first(where: { $0.id == id && $0.kind == .therapy && $0.status == .completed }) {
            return selected
        }
        return state.appointments.filter { $0.kind == .therapy && $0.status == .completed }.max {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
    }

    private var sessionTranscript: [TranscriptSegment] {
        guard let id = sessionAppointment?.id else { return [] }
        return state.transcript.filter { $0.appointmentID == id }
    }

    private var sessionSummary: (artifact: AIArtifact, result: SessionSummaryResult)? {
        guard let id = sessionAppointment?.id,
              let artifact = state.latestArtifact(kind: .sessionSummary, sourceID: id),
              let result = try? JSONDecoder().decode(SessionSummaryResult.self, from: artifact.structuredPayload),
              Self.isUsableSessionSummary(result) else { return nil }
        return (artifact, result)
    }

    private var hasCorruptSessionSummary: Bool {
        guard let id = sessionAppointment?.id,
              state.latestArtifact(kind: .sessionSummary, sourceID: id) != nil else { return false }
        return sessionSummary == nil
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var organizerAvailable: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private static func isUsableSessionSummary(_ result: SessionSummaryResult) -> Bool {
        guard !result.sections.isEmpty, result.sections.count <= 24 else { return false }
        return result.sections.allSatisfy { section in
            !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !section.statements.isEmpty
                && section.statements.allSatisfy {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.evidence.isEmpty
                }
        }
    }

    private var sessionMetadata: String {
        guard let appointment = sessionAppointment else { return "Saved on this device" }
        let date = (appointment.startedAt ?? appointment.scheduledAt)?.formatted(.dateTime.month(.abbreviated).day()) ?? "Date not recorded"
        let duration: String
        if let start = appointment.startedAt, let end = appointment.endedAt {
            duration = "\(max(0, Int(end.timeIntervalSince(start) / 60))) min"
        } else {
            duration = "Duration not recorded"
        }
        return "\(date) · \(duration) · Saved on this device"
    }

    private func playRecording() {
        guard let id = sessionAppointment?.recordingAttachmentID,
              let attachment = state.attachments.first(where: { $0.id == id }) else { return }
        Task { try? await state.dependencies.playback.play(attachment: attachment) }
    }

    @discardableResult
    private func saveNotes() async -> Bool {
        guard var appointment = sessionAppointment else { return false }
        appointment.manualNotes = String(notes.prefix(4_000))
        let saved = await state.saveAppointment(appointment)
        if !saved { actionError = state.operationError ?? "Your notes could not be saved." }
        return saved
    }

    private func prepareSummary() {
        guard !trimmedNotes.isEmpty, !isPreparingSummary, pendingSend == nil else { return }
        actionError = nil
        isPreparingSummary = true
        Task {
            defer { isPreparingSummary = false }
            guard organizerAvailable, await saveNotes(), let id = sessionAppointment?.id else { return }
            do {
                pendingSend = try state.prepareAISend(.summarizeSession(id))
            } catch let error as UserFacingError {
                actionError = error.message
            } catch {
                actionError = "These notes are not ready to send."
            }
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            prepareSummary()
            return
        }
        sendTask = Task {
            let succeeded = await state.performAISend(pending)
            guard !Task.isCancelled, pendingSend?.id == pending.id else {
                sendTask = nil
                return
            }
            sendTask = nil
            if succeeded {
                pendingSend = nil
                selection = .summary
            } else if case let .failed(message) = state.aiProcessingState(for: pending.action) {
                actionError = message
            }
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        pendingSend = nil
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment
    let speaker: TranscriptSegment.Speaker
    let correct: (TranscriptSegment.Speaker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(spacing: DesignTokens.Spacing.small) {
                speakerGlyph
                Text(speakerName)
                    .font(TypeScale.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(speakerColor)
                Spacer()
                Text(AppointmentRecordingClock.format(milliseconds: segment.startMilliseconds))
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .monospacedDigit()
            }
            Text(segment.text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            if speaker == .unknown { correctionButtons }
        }
        .padding(.vertical, DesignTokens.Spacing.base)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var speakerGlyph: some View {
        if speaker == .unknown {
            Text("?")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(width: 16, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.cocoaSoft))
                .accessibilityHidden(true)
        } else {
            KernelGlyph(voice: speaker == .provider ? .provider : .user, height: 18, decorative: true)
        }
    }

    private var correctionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.small) { correctionButtonContent }
            VStack(spacing: DesignTokens.Spacing.small) { correctionButtonContent }
        }
        .padding(.top, DesignTokens.Spacing.xSmall)
    }

    @ViewBuilder private var correctionButtonContent: some View {
        Button("Mark as me") { correct(.patient) }.buttonStyle(SecondaryButtonStyle())
        Button("Mark as provider") { correct(.provider) }.buttonStyle(SecondaryButtonStyle())
    }

    private var speakerName: String {
        switch speaker {
        case .patient: "Jamie"
        case .provider: "Dr. Elena Park"
        case .unknown: "Unknown speaker"
        }
    }

    private var speakerColor: Color {
        switch speaker {
        case .patient: DesignTokens.cocoa
        case .provider: DesignTokens.cocoa
        case .unknown: DesignTokens.cocoaSoft
        }
    }
}

private struct CareLedgerItem: Identifiable {
    let text: String
    let provenance: Provenance
    var id: String { text }
}

private struct CareLedger: View {
    let items: [CareLedgerItem]

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("Nothing saved here yet.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    Text(item.text).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                    ProvenanceLine(provenance: item.provenance)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.base)
                .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
            }
        }
    }
}

private struct PlaybackScrubber: View {
    let onPlay: () -> Void
    @State private var position = 768.0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack {
                Text("12:48")
                Spacer()
                Text("52:06")
            }
            .font(TypeScale.provenance)
            .foregroundStyle(DesignTokens.cocoaSoft)
            .monospacedDigit()
            Slider(value: $position, in: 0...3126)
                .tint(DesignTokens.orange)
                .frame(minHeight: DesignTokens.controlMinimum)
                .accessibilityLabel("Playback position")
            Text("Saved session audio")
                .font(TypeScale.bodyMedium)
            Button("Play recording", action: onPlay)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript playback")
    }
}

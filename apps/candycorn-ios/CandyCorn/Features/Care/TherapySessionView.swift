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
    @State private var openedScreenshotSheet = false
    @State private var relabelingSegmentIDs: Set<UUID> = []
    @State private var showsCorrections = false

    @ViewBuilder
    var body: some View {
        if sessionAppointment == nil {
            V2Screen(
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
        V2Screen(
            title: "Therapy with \(sessionAppointment?.providerName ?? "your provider")",
            subtitle: sessionMetadata,
            backAction: navigation.backAction(for: .therapySession),
            trailing: AnyView(correctionAction),
            bottomInset: sessionAppointment?.recordingAttachmentID != nil ? 200 : DesignTokens.tabBarClearance
        ) {
            SessionProcessingStatusView(
                record: sessionAppointment.flatMap { state.sessionProcessingRecord(for: $0.id) },
                onReviewSummary: prepareProcessedSummary,
                onRetry: retryProcessing,
                onOpenDebrief: openDebrief
            )
            UnderlinePicker(options: visibleTabs, selection: $selection) { $0.rawValue }
            panel
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sessionAppointment?.recordingAttachmentID != nil {
                PlaybackScrubber(onPlay: playRecording)
                    .padding(.horizontal, DesignTokens.screenInset)
                    .padding(.bottom, DesignTokens.tabBarReserved + DesignTokens.Spacing.xSmall)
            }
        }
        .onAppear { notes = sessionAppointment?.manualNotes ?? "" }
        .task { openScreenshotDisclosureIfNeeded() }
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
        VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
            if let summary = structuredSummary {
                V2Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(summary.result.debriefTopics.enumerated()), id: \.element.id) { index, topic in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                Text(topic.text)
                                    .font(TypeScale.body)
                                    .foregroundStyle(DesignTokens.cocoa)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: DesignTokens.Spacing.small) {
                                    ProvenanceInline(voice: topic.provenance.provenanceVoice, text: "From the processed transcript")
                                    Spacer(minLength: DesignTokens.Spacing.small)
                                    if let timestamp = topic.evidence.first?.timestampMilliseconds {
                                        Button {
                                            playRecording(fromMilliseconds: timestamp)
                                        } label: {
                                            HStack(spacing: 4) {
                                                AppIcon.play.image.font(.system(size: 10, weight: .bold))
                                                Text(AppointmentRecordingClock.format(milliseconds: timestamp))
                                                    .font(TypeScale.metaStrong)
                                                    .monospacedDigit()
                                            }
                                            .foregroundStyle(DesignTokens.orangePressed)
                                            .frame(minHeight: DesignTokens.controlMinimum)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Play from \(AppointmentRecordingClock.format(milliseconds: timestamp))")
                                    }
                                }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.base)
                            .padding(.vertical, DesignTokens.Spacing.compact)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base)
                                }
                            }
                        }
                    }
                }
            } else if let summary = legacySessionSummary {
                ForEach(summary.result.sections) { section in
                    V2Card {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                            HStack(spacing: DesignTokens.Spacing.compact) {
                                IconTile(icon: .sparkles, size: 34)
                                Text(section.title)
                                    .font(TypeScale.cardTitle)
                                    .foregroundStyle(DesignTokens.cocoa)
                            }
                            ForEach(section.statements) { statement in
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                                    Text(statement.text)
                                        .font(TypeScale.body)
                                        .foregroundStyle(DesignTokens.cocoa)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                    ProvenanceStack(provenance: Provenance(
                                        voice: .candyCorn,
                                        label: "Candy Corn suggested this summary",
                                        detail: "\(summary.artifact.provider), \(summary.artifact.model)",
                                        occurredAt: summary.artifact.createdAt,
                                        sourceRoute: nil
                                    ))
                                    ForEach(Array(statement.evidence.enumerated()), id: \.offset) { _, evidence in
                                        Button {
                                            selection = .notes
                                        } label: {
                                            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                                                KernelGlyph(voice: .user, height: 14, decorative: true)
                                                    .padding(.top, 2)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("From your manual notes")
                                                        .font(TypeScale.metaStrong)
                                                        .foregroundStyle(DesignTokens.cocoa)
                                                    Text("“\(evidence.quote)”")
                                                        .font(TypeScale.meta)
                                                        .foregroundStyle(DesignTokens.cocoaSoft)
                                                        .multilineTextAlignment(.leading)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                            .padding(DesignTokens.Spacing.compact)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(DesignTokens.surfaceWarm)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
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
            Text(sessionTranscript.isEmpty ? "Transcript is created on this device." : "Speaker labels can be corrected for the full transcript cluster.")
                .font(TypeScale.meta)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DesignTokens.Spacing.xSmall)
            SessionTranscriptView(
                segments: sessionTranscript,
                patientName: state.dependencies.screenshotMode ? "Jamie" : "You",
                providerName: sessionAppointment?.providerName ?? "Provider",
                providerRole: "Therapist",
                sessionDate: sessionDateLabel,
                showsCorrections: showsCorrections,
                isRelabeling: { relabelingSegmentIDs.contains($0.id) },
                onLabel: persistLabel,
                onTimestamp: { playRecording(fromMilliseconds: $0.startMilliseconds) }
            )
        }
        .accessibilityLabel("Source-preserving transcript")
    }

    private var homeworkPanel: some View {
        CareLedger(icon: .flag, emptyText: "No homework from this session yet.", items: state.goals.filter { $0.sourceEntityID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.title, provenance: $0.provenance)
        })
    }

    private var talkingPointsPanel: some View {
        CareLedger(icon: .listPlus, emptyText: "No talking points from this session yet.", items: state.talkingPoints.filter { $0.sourceID == sessionAppointment?.id }.map {
            CareLedgerItem(text: $0.text, provenance: $0.provenance)
        })
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
            V2Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    SectionLine(title: "Manual notes", trailing: trimmedNotes.isEmpty ? "Empty" : "\(trimmedNotes.count) characters")
                    TextEditor(text: $notes)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoa)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Manual notes")
                    HStack(spacing: DesignTokens.Spacing.small) {
                        Button("Save notes") {
                            Task { _ = await saveNotes() }
                        }
                        .buttonStyle(CompactDarkButtonStyle())
                        Button(isPreparingSummary ? "Preparing" : "Summarize notes") {
                            prepareSummary()
                        }
                        .buttonStyle(CompactGhostButtonStyle())
                        .disabled(trimmedNotes.isEmpty || !organizerAvailable || isPreparingSummary || pendingSend != nil)
                    }
                    if !organizerAvailable {
                        Text(state.aiMode == .off
                            ? "Organizer is off. Your notes remain editable and on this device."
                            : "Add a Router key in Settings to organize these notes.")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if state.aiMode == .reflection {
                        Text("Reflection uses Organizer for this summary. It does not start a conversation.")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.yellowText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let actionError {
                StatusNotice(title: "Could not organize notes", detail: actionError, kind: .warning)
            }
            V2GroupCard {
                V2ListRow(
                    icon: .listPlus,
                    title: "Add to next appointment",
                    detail: "Pin these notes as a talking point.",
                    divider: false,
                    disabled: trimmedNotes.isEmpty
                ) {
                    Task { _ = await state.createTalkingPoint(text: notes, source: .session, sourceID: sessionAppointment?.id) }
                }
            }
        }
    }

    private var sessionAppointment: Appointment? {
        if let id = state.selectedAppointmentID,
           let selected = state.appointments.first(where: {
               $0.id == id && $0.kind != .tms && $0.recordingAttachmentID != nil
                   && ($0.status == .processing || $0.status == .completed)
           }) {
            return selected
        }
        return state.appointments.filter {
            $0.kind != .tms && $0.recordingAttachmentID != nil
                && ($0.status == .processing || $0.status == .completed)
        }.max {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
    }

    private var sessionTranscript: [TranscriptSegment] {
        guard let id = sessionAppointment?.id else { return [] }
        let segments = state.transcript.filter { $0.appointmentID == id }
        return state.dependencies.screenshotMode ? Array(segments.prefix(2)) : segments
    }

    private var visibleTabs: [TherapySessionTab] {
        state.dependencies.screenshotMode
            ? [.summary, .transcript, .homework, .talkingPoints]
            : TherapySessionTab.allCases
    }

    private var correctionAction: some View {
        Button(showsCorrections ? "Done" : "Correct speakers") { showsCorrections.toggle() }
            .buttonStyle(CompactGhostButtonStyle())
            .accessibilityHint("Shows controls for correcting speaker labels")
    }

    private var sessionDateLabel: String? {
        (sessionAppointment?.startedAt ?? sessionAppointment?.scheduledAt)?
            .formatted(.dateTime.month(.abbreviated).day())
    }

    private var structuredSummary: (artifact: AIArtifact, result: StructuredSessionSummaryResult)? {
        guard let id = sessionAppointment?.id else { return nil }
        return state.structuredSessionSummary(for: id)
    }

    private var legacySessionSummary: (artifact: AIArtifact, result: SessionSummaryResult)? {
        guard let id = sessionAppointment?.id,
              let artifact = state.latestArtifact(kind: .sessionSummary, sourceID: id),
              let result = try? JSONDecoder().decode(SessionSummaryResult.self, from: artifact.structuredPayload),
              Self.isUsableSessionSummary(result) else { return nil }
        return (artifact, result)
    }

    private var hasCorruptSessionSummary: Bool {
        guard let id = sessionAppointment?.id,
              state.latestArtifact(kind: .sessionSummary, sourceID: id) != nil else { return false }
        return structuredSummary == nil && legacySessionSummary == nil
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

    private func playRecording(fromMilliseconds: Int) {
        guard let id = sessionAppointment?.id else { return }
        Task { _ = await state.playSessionRecording(appointmentID: id, fromMilliseconds: fromMilliseconds) }
    }

    private func persistLabel(_ segment: TranscriptSegment, _ speaker: TranscriptSegment.Speaker) {
        guard !relabelingSegmentIDs.contains(segment.id) else { return }
        relabelingSegmentIDs.insert(segment.id)
        Task {
            _ = await state.persistSpeakerCluster(segmentID: segment.id, as: speaker)
            relabelingSegmentIDs.remove(segment.id)
        }
    }

    private func prepareProcessedSummary() {
        guard pendingSend == nil, let id = sessionAppointment?.id else { return }
        do {
            pendingSend = try state.prepareProcessedSessionSummary(appointmentID: id)
        } catch let error as UserFacingError {
            actionError = error.message
        } catch {
            actionError = "This transcript is not ready to send."
        }
    }

    private func retryProcessing() {
        guard let id = sessionAppointment?.id else { return }
        Task { await state.retrySessionProcessing(appointmentID: id) }
    }

    private func openDebrief() {
        guard let route = Route(rawValue: "/sessions/therapy-sep-2/debrief") else { return }
        navigation.navigate(to: route)
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
            if case .summarizeProcessedSession = pending.action {
                prepareProcessedSummary()
            } else {
                prepareSummary()
            }
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

    private func openScreenshotDisclosureIfNeeded() {
        guard !openedScreenshotSheet,
              state.dependencies.screenshotScenario == .sessionSend,
              let appointment = state.appointments.first(where: { $0.id == SeededData.therapySessionID }),
              !appointment.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        openedScreenshotSheet = true
        state.selectAppointment(id: appointment.id)
        notes = appointment.manualNotes
        selection = .notes
        state.setAIMode(.organizer)
        state.setAIProvider(.router)
        prepareSummary()
    }
}

private struct CareLedgerItem: Identifiable {
    let text: String
    let provenance: Provenance
    var id: String { text }
}

private struct CareLedger: View {
    let icon: AppIcon
    let emptyText: String
    let items: [CareLedgerItem]

    var body: some View {
        V2GroupCard {
            if items.isEmpty {
                V2ListRow(icon: icon, title: emptyText, trailing: .none, divider: false, disabled: true)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    V2ListRow(
                        icon: icon,
                        title: item.text,
                        detail: item.provenance.detail.isEmpty ? item.provenance.label : "\(item.provenance.label) · \(item.provenance.detail)",
                        trailing: .none,
                        divider: index > 0
                    )
                }
            }
        }
    }
}

private extension SessionSummaryItemProvenance {
    var provenanceVoice: ProvenanceVoice {
        switch self {
        case .patient: .user
        case .provider: .provider
        case .candyCorn: .candyCorn
        }
    }
}

private struct PlaybackScrubber: View {
    let onPlay: () -> Void
    @State private var position = 768.0

    var body: some View {
        V2Card(padding: DesignTokens.Spacing.compact) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Button(action: onPlay) {
                        IconTile(icon: .play, size: 40, dark: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play recording")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved session audio")
                            .font(TypeScale.rowTitleCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                        Text("12:48 of 52:06")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                Slider(value: $position, in: 0...3126)
                    .tint(DesignTokens.orange)
                    .accessibilityLabel("Playback position")
            }
        }
        .shadow(color: DesignTokens.cocoa.opacity(0.08), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript playback")
    }
}

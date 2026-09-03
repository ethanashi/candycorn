import Foundation
import SwiftUI

struct TherapyBrief: Equatable, Sendable {
    var whereLeftOff: String
    var whatChanged: String
    var pinnedQuestion: String
    var carryingForward: String
    var possibleOpening: String

    static let seeded = TherapyBrief(
        whereLeftOff: "Last time, you stopped the football story at the end of junior year. Dr. Park asked you to finish the senior-year timeline and notice guilt when moving forward feels possible.",
        whatChanged: "You finished the senior-year narrative. Exercise helped for several hours, then guilt followed. Your notes do not show that exercise caused the change.",
        pinnedQuestion: "Is needing proof that I could have played the part that keeps me stuck?",
        carryingForward: "Keep noticing moving-forward guilt, write down one example when it appears, and use exercise when thoughts feel stuck.",
        possibleOpening: "Last time we stopped at junior year. I finished that part, and I realized I may need proof that I could have played more than I need to play again."
    )

    static let empty = TherapyBrief(
        whereLeftOff: "",
        whatChanged: "",
        pinnedQuestion: "",
        carryingForward: "",
        possibleOpening: ""
    )

    init(packet: ContextPacket) {
        whereLeftOff = Self.join(packet, kinds: [.sessionSummary, .transcriptEvidence])
        whatChanged = Self.join(packet, kinds: [.journal, .moodTrend, .moodLog])
        pinnedQuestion = Self.join(packet, kinds: [.talkingPoint])
        carryingForward = Self.join(packet, kinds: [.homework, .activeGoal, .goalProgress])
        possibleOpening = String(
            (packet.items.first { $0.provenance == .user }?.text ?? "").prefix(700)
        )
    }

    init(
        whereLeftOff: String,
        whatChanged: String,
        pinnedQuestion: String,
        carryingForward: String,
        possibleOpening: String
    ) {
        self.whereLeftOff = whereLeftOff
        self.whatChanged = whatChanged
        self.pinnedQuestion = pinnedQuestion
        self.carryingForward = carryingForward
        self.possibleOpening = possibleOpening
    }

    private static func join(_ packet: ContextPacket, kinds: Set<ContextPacketItem.Kind>) -> String {
        String(packet.items.filter { kinds.contains($0.kind) }.map(\.text).joined(separator: "\n\n").prefix(700))
    }

    func text(for section: TherapyBriefSection) -> String {
        switch section {
        case .whereLeftOff: whereLeftOff
        case .whatChanged: whatChanged
        case .pinnedQuestion: pinnedQuestion
        case .carryingForward: carryingForward
        case .possibleOpening: possibleOpening
        }
    }

    mutating func setText(_ text: String, for section: TherapyBriefSection) {
        let bounded = String(text.prefix(700))
        switch section {
        case .whereLeftOff: whereLeftOff = bounded
        case .whatChanged: whatChanged = bounded
        case .pinnedQuestion: pinnedQuestion = bounded
        case .carryingForward: carryingForward = bounded
        case .possibleOpening: possibleOpening = bounded
        }
    }
}

enum TherapyBriefSection: String, CaseIterable, Identifiable, Sendable {
    case whereLeftOff
    case whatChanged
    case pinnedQuestion
    case carryingForward
    case possibleOpening

    var id: Self { self }

    var title: String {
        switch self {
        case .whereLeftOff: "Where you left off"
        case .whatChanged: "What changed"
        case .pinnedQuestion: "A question you pinned"
        case .carryingForward: "What you are carrying forward"
        case .possibleOpening: "A possible opening"
        }
    }

    var icon: AppIcon {
        switch self {
        case .whereLeftOff: .history
        case .whatChanged: .journal
        case .pinnedQuestion: .questionmark
        case .carryingForward: .flag
        case .possibleOpening: .sparkles
        }
    }

    var provenance: Provenance {
        switch self {
        case .whereLeftOff:
            Provenance(voice: .provider, label: "Therapist assigned this", detail: "Therapy, Sep 2 at 42:18", occurredAt: nil, sourceRoute: .therapySession)
        case .whatChanged:
            Provenance(voice: .user, label: "You wrote this", detail: "Journals, Sep 3 and Sep 5", occurredAt: nil, sourceRoute: .journalDetail)
        case .pinnedQuestion:
            Provenance(voice: .user, label: "You pinned this", detail: "Journal, Sep 5 at 3:18 PM", occurredAt: nil, sourceRoute: .bringUp)
        case .carryingForward:
            Provenance(voice: .user, label: "From your current goals", detail: "Reviewed Sep 5", occurredAt: nil, sourceRoute: .goals)
        case .possibleOpening:
            Provenance(voice: .candyCorn, label: "Candy Corn suggested this wording", detail: "Built from your saved brief, Sep 5", occurredAt: nil, sourceRoute: nil)
        }
    }
}

struct TherapyBriefEditor: Equatable, Sendable {
    static let blankMessage = "Keep a short note in every section or cancel your edits."

    private(set) var saved: TherapyBrief
    private(set) var draft: TherapyBrief
    private(set) var isEditing = false
    private(set) var error: String?

    init(brief: TherapyBrief = .seeded) {
        saved = brief
        draft = brief
    }

    mutating func begin() {
        draft = saved
        error = nil
        isEditing = true
    }

    mutating func update(_ section: TherapyBriefSection, text: String) {
        guard isEditing else { return }
        draft.setText(text, for: section)
        error = nil
    }

    @discardableResult
    mutating func save() -> Bool {
        guard isEditing else { return false }
        let hasBlank = TherapyBriefSection.allCases.contains {
            draft.text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hasBlank else {
            error = Self.blankMessage
            return false
        }
        saved = draft
        error = nil
        isEditing = false
        return true
    }

    mutating func cancel() {
        draft = saved
        error = nil
        isEditing = false
    }
}

struct PrepareTherapyView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var manualEditor = TherapyBriefEditor(brief: .empty)
    @State private var generatedEditor: AppointmentBriefEditor?
    @State private var preferredArtifactID: UUID?
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var preparationTask: Task<Void, Never>?
    @State private var manualRefreshTask: Task<Void, Never>?
    @State private var actionError: String?
    @State private var isSavingGenerated = false
    @State private var openedScreenshotSheet = false

    var body: some View {
        V2Screen(
            title: isEditing ? "Edit your brief" : "Walk in knowing what matters",
            subtitle: isEditing
                ? "Change the wording without changing your journals or session."
                : "Before therapy with Dr. Elena Park on Sep 9.",
            backAction: isEditing ? cancelEditing : navigation.backAction(for: .prepareTherapy),
            backLabel: isEditing ? "Cancel editing" : "Back",
            backIcon: isEditing ? .close : .back,
            bottomInset: 220
        ) {
            if generatedEditor?.isEditing == true {
                generatedBriefEditor
            } else if manualEditor.isEditing {
                manualBriefEditor
            } else if let generatedEditor, let artifact = generatedArtifact {
                AppointmentBriefReadingView(
                    result: generatedEditor.saved,
                    artifact: artifact,
                    provenanceForSource: provenance(for:)
                )
            } else {
                manualBriefReading
            }
            if generatedEditor == nil, hasUnreadableArtifact {
                StatusNotice(
                    title: "Saved brief unavailable",
                    detail: "Candy Corn could not read the generated brief. Your manual brief and source records are unchanged.",
                    kind: .warning
                )
            }
            if let actionError {
                StatusNotice(title: "Brief not changed", detail: actionError, kind: .warning)
            }
            if state.aiMode == .reflection {
                Text("Reflection uses Organizer for this brief. It does not start a conversation.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.yellowText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .background(DesignTokens.canvas)
        .onAppear {
            refreshManualBrief()
            refreshGeneratedBrief()
        }
        .onChange(of: state.loadState) { _, _ in
            refreshManualBrief()
            refreshGeneratedBrief()
        }
        .onChange(of: state.artifacts) { _, _ in refreshGeneratedBrief() }
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

    private var manualBriefReading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
            ForEach(TherapyBriefSection.allCases) { section in
                BriefSectionCard(
                    title: section.title,
                    text: highlighted(manualEditor.saved.text(for: section), quoted: section == .possibleOpening),
                    provenance: section.provenance,
                    icon: section.icon
                )
            }
        }
    }

    private var manualBriefEditor: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            ForEach(TherapyBriefSection.allCases) { section in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(section.title)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoa)
                    TextEditor(text: draftBinding(for: section))
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoa)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.compact)
                        .frame(minHeight: section == .pinnedQuestion ? 96 : 128)
                        .background(DesignTokens.surface)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                        .accessibilityLabel(section.title)
                }
            }
            if let error = manualEditor.error {
                Text(error)
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error. \(error)")
            }
        }
    }

    private var generatedBriefEditor: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            if let editor = generatedEditor {
                ForEach(editor.draft.sections) { section in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(section.title)
                            .font(TypeScale.sectionCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                        ForEach(section.statements) { statement in
                            TextEditor(text: generatedBinding(sectionID: section.id, statementID: statement.id))
                                .font(TypeScale.body)
                                .scrollContentBackground(.hidden)
                                .padding(DesignTokens.Spacing.compact)
                                .frame(minHeight: 128)
                                .background(DesignTokens.surface)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                                .accessibilityLabel(section.title)
                        }
                    }
                }
                if let error = editor.error {
                    Text(error)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            if generatedEditor?.isEditing == true {
                Button(isSavingGenerated ? "Saving" : "Save brief", action: saveGeneratedBrief)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSavingGenerated)
                Button("Cancel editing", action: cancelEditing)
                    .buttonStyle(SecondaryButtonStyle())
            } else if manualEditor.isEditing {
                Button("Save brief") { _ = manualEditor.save() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Cancel editing", action: cancelEditing)
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Button(action: beginEditing) {
                    Label("Edit brief", systemImage: AppIcon.pencil.rawValue)
                }
                .buttonStyle(PrimaryButtonStyle())
                if organizerAvailable {
                    Button("Generate brief", action: prepareGeneration)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(pendingSend != nil)
                } else {
                    Text(state.aiMode == .off
                        ? "Organizer is off. This manual brief stays usable."
                        : "Add a Router key in Settings to generate a brief.")
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.small)
        .padding(.bottom, 76)
        .background(DesignTokens.canvas)
    }

    private func draftBinding(for section: TherapyBriefSection) -> Binding<String> {
        Binding(
            get: { manualEditor.draft.text(for: section) },
            set: { manualEditor.update(section, text: $0) }
        )
    }

    private func generatedBinding(sectionID: UUID, statementID: UUID) -> Binding<String> {
        Binding(
            get: {
                generatedEditor?.draft.sections
                    .first(where: { $0.id == sectionID })?.statements
                    .first(where: { $0.id == statementID })?.text ?? ""
            },
            set: { generatedEditor?.update(sectionID: sectionID, statementID: statementID, text: $0) }
        )
    }

    private func highlighted(_ value: String, quoted: Bool) -> AttributedString {
        let displayed = quoted ? "“\(value)”" : value
        var result = AttributedString(displayed)
        let phrase = "proof that I could have played"
        if let range = result.range(of: phrase, options: [.caseInsensitive]) {
            result[range].backgroundColor = DesignTokens.surfaceWarm
        }
        return result
    }

    private func refreshManualBrief() {
        guard !manualEditor.isEditing, generatedEditor?.isEditing != true else { return }
        manualRefreshTask?.cancel()
        manualRefreshTask = Task {
            defer { manualRefreshTask = nil }
            let now = state.dependencies.now()
            let window = DateInterval(start: now.addingTimeInterval(-90 * 24 * 60 * 60), end: now)
            guard let packet = try? await state.appointmentContextPacket(kind: .therapy, window: window),
                  !Task.isCancelled, !manualEditor.isEditing, generatedEditor?.isEditing != true else { return }
            manualEditor = TherapyBriefEditor(brief: TherapyBrief(packet: packet))
        }
    }

    private var isEditing: Bool {
        manualEditor.isEditing || generatedEditor?.isEditing == true
    }

    private var organizerAvailable: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private var generatedArtifact: AIArtifact? {
        AppointmentBriefArtifactReader.latest(
            kind: .therapy,
            preferredID: preferredArtifactID,
            artifacts: state.artifacts,
            appointments: state.appointments,
            goals: state.goals,
            talkingPoints: state.talkingPoints
        )
    }

    private var hasUnreadableArtifact: Bool {
        AppointmentBriefArtifactReader.hasUnreadableArtifact(
            kind: .therapy,
            preferredID: preferredArtifactID,
            artifacts: state.artifacts,
            appointments: state.appointments,
            goals: state.goals,
            talkingPoints: state.talkingPoints
        )
    }

    private func refreshGeneratedBrief() {
        guard generatedEditor?.isEditing != true else { return }
        guard let artifact = generatedArtifact else {
            generatedEditor = nil
            return
        }
        generatedEditor = AppointmentBriefEditor(artifact: artifact)
    }

    private func beginEditing() {
        actionError = nil
        if generatedEditor != nil {
            generatedEditor?.begin()
        } else {
            manualEditor.begin()
        }
    }

    private func cancelEditing() {
        generatedEditor?.cancel()
        manualEditor.cancel()
        actionError = nil
    }

    private func prepareGeneration() {
        guard organizerAvailable, pendingSend == nil, preparationTask == nil else { return }
        actionError = nil
        preparationTask = Task {
            defer { preparationTask = nil }
            do {
                let prepared = try await state.prepareAppointmentBriefSend(kind: .therapy)
                guard !Task.isCancelled else { return }
                pendingSend = prepared
            } catch is CancellationError {
                return
            } catch let error as UserFacingError {
                actionError = error.message
            } catch {
                actionError = "Your saved sources are not ready to send."
            }
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            prepareGeneration()
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
                preferredArtifactID = state.artifacts.filter { $0.kind == .appointmentBrief }.max { $0.createdAt < $1.createdAt }?.id
                refreshGeneratedBrief()
                pendingSend = nil
            } else if case let .failed(message) = state.aiProcessingState(for: pending.action) {
                actionError = message
            }
        }
    }

    private func cancelSend() {
        preparationTask?.cancel()
        preparationTask = nil
        manualRefreshTask?.cancel()
        manualRefreshTask = nil
        sendTask?.cancel()
        sendTask = nil
        pendingSend = nil
    }

    private func openScreenshotDisclosureIfNeeded() {
        guard !openedScreenshotSheet,
              state.dependencies.screenshotScenario == .prepareSend else {
            return
        }
        openedScreenshotSheet = true
        state.setAIMode(.organizer)
        state.setAIProvider(.router)
        prepareGeneration()
    }

    private func saveGeneratedBrief() {
        guard !isSavingGenerated, let currentEditor = generatedEditor else { return }
        var editor = currentEditor
        guard let result = editor.preparedSave(at: state.dependencies.now()) else {
            generatedEditor = editor
            return
        }
        isSavingGenerated = true
        Task {
            let saved = await state.saveEditedAppointmentBrief(editor.artifactID, result: result)
            isSavingGenerated = false
            if saved {
                editor.commit(result)
                generatedEditor = editor
            } else {
                editor.failSave()
                generatedEditor = editor
            }
        }
    }

    private func provenance(for sourceID: UUID) -> Provenance {
        if let journal = state.journals.first(where: { $0.id == sourceID }) { return journal.provenance }
        if let goal = state.goals.first(where: { $0.id == sourceID }) { return goal.provenance }
        if let point = state.talkingPoints.first(where: { $0.id == sourceID }) { return point.provenance }
        if state.appointments.contains(where: { $0.id == sourceID }) {
            return Provenance(voice: .user, label: "From your manual session notes", detail: "Saved on this device", occurredAt: nil, sourceRoute: .therapySession)
        }
        if state.moods.contains(where: { $0.id == sourceID }) {
            return Provenance(voice: .user, label: "From your mood check-ins", detail: "Saved on this device", occurredAt: nil, sourceRoute: .checkIn)
        }
        return Provenance(voice: .user, label: "From your saved source", detail: "Saved on this device", occurredAt: nil, sourceRoute: nil)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

import SwiftUI

enum TMSBriefSection: String, CaseIterable, Identifiable, Sendable {
    case observations
    case question
    case providerFocus

    var id: Self { self }

    var title: String {
        switch self {
        case .observations: "Before and after notes"
        case .question: "A question for the team"
        case .providerFocus: "Provider-approved focus"
        }
    }

    var provenance: Provenance {
        switch self {
        case .observations:
            Provenance(voice: .user, label: "You recorded these observations", detail: "TMS, Sep 5 before and after the visit", occurredAt: nil, sourceRoute: .tmsPost)
        case .question:
            Provenance(voice: .user, label: "You saved this question", detail: "TMS pre-session, Sep 5 at 9:18 AM", occurredAt: nil, sourceRoute: .tmsPre)
        case .providerFocus:
            Provenance(voice: .provider, label: "Dr. Elena Park asked you to notice this", detail: "Therapy, Sep 2 at 38:44", occurredAt: nil, sourceRoute: .therapySession)
        }
    }
}

struct TMSBrief: Equatable, Sendable {
    var observations = "Before the visit, you noted low energy and worry about the day. Afterward, you noted a quieter morning and a mild headache. These observations do not show that TMS caused a mood change."
    var question = "Should I keep tracking the headache if it is still mild later today?"
    var providerFocus = "Notice when moving-forward guilt appears. Do not change your treatment plan based on this app."

    func text(for section: TMSBriefSection) -> String {
        switch section {
        case .observations: observations
        case .question: question
        case .providerFocus: providerFocus
        }
    }

    mutating func setText(_ text: String, for section: TMSBriefSection) {
        let bounded = String(text.prefix(1_400))
        switch section {
        case .observations: observations = bounded
        case .question: question = bounded
        case .providerFocus: providerFocus = bounded
        }
    }
}

struct TMSBriefEditor: Equatable, Sendable {
    static let blankMessage = "Keep text in every TMS brief section or cancel your edits."
    private(set) var saved = TMSBrief()
    private(set) var draft = TMSBrief()
    private(set) var isEditing = false
    private(set) var error: String?

    mutating func begin() {
        draft = saved
        error = nil
        isEditing = true
    }

    mutating func update(_ section: TMSBriefSection, text: String) {
        guard isEditing else { return }
        draft.setText(text, for: section)
        error = nil
    }

    mutating func save() -> Bool {
        guard isEditing else { return false }
        guard TMSBriefSection.allCases.allSatisfy({
            !draft.text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
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

struct PrepareTMSView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var manualEditor = TMSBriefEditor()
    @State private var generatedEditor: AppointmentBriefEditor?
    @State private var preferredArtifactID: UUID?
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var actionError: String?
    @State private var isSavingGenerated = false

    var body: some View {
        ScreenLayout(
            title: isEditing ? "Edit your TMS brief" : "Prepare for TMS",
            subtitle: isEditing ? "Edit this brief without changing any source." : "Saved observations for the next Riverbend TMS visit.",
            backAction: isEditing ? cancelEditing : navigation.backAction(for: .prepareTMS),
            backLabel: isEditing ? "Cancel editing" : "Back",
            bottomInset: 240
        ) {
            currentMood
            briefContent
            if generatedEditor == nil, hasUnreadableArtifact {
                StatusNotice(
                    title: "Saved brief unavailable",
                    detail: "Candy Corn rejected or could not read the generated brief. Your manual TMS brief is unchanged.",
                    kind: .warning
                )
            }
            if let actionError {
                StatusNotice(title: "Brief not changed", detail: actionError, kind: .warning)
            }
            StatusNotice(
                title: "Your treatment stays with your care team",
                detail: "Candy Corn organizes saved items. It does not create treatment provocations or tell you how to change treatment."
            )
            if state.aiMode == .reflection {
                Text("Reflection uses Organizer for this brief. It does not start a conversation.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.yellowText)
            }
            captureActions
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { briefActions }
        .sheet(item: $pendingSend, onDismiss: cancelSend) { pending in
            WhatLeavesDeviceSheet(
                pending: pending,
                processingState: state.aiProcessingState(for: pending.action),
                onSend: { send(pending) },
                onCancel: cancelSend
            )
        }
        .onAppear(perform: refreshGeneratedBrief)
        .onChange(of: state.artifacts) { _, _ in refreshGeneratedBrief() }
        .onDisappear(perform: cancelSend)
    }

    @ViewBuilder private var briefContent: some View {
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
    }

    private var manualBriefReading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(DesignTokens.hairline)
            ForEach(TMSBriefSection.allCases) { section in
                TMSBriefLine(
                    title: section.title,
                    copy: manualEditor.saved.text(for: section),
                    provenance: section.provenance
                )
            }
        }
    }

    private var manualBriefEditor: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            ForEach(TMSBriefSection.allCases) { section in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(section.title).font(TypeScale.sectionCompact)
                    TextEditor(text: manualBinding(for: section))
                        .font(TypeScale.body)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.compact)
                        .frame(minHeight: 128)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                        .accessibilityLabel(section.title)
                }
            }
            if let error = manualEditor.error {
                Text(error).font(TypeScale.label).foregroundStyle(DesignTokens.rose)
            }
        }
    }

    private var generatedBriefEditor: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            if let editor = generatedEditor {
                ForEach(editor.draft.sections) { section in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(section.title).font(TypeScale.sectionCompact)
                        ForEach(section.statements) { statement in
                            TextEditor(text: generatedBinding(sectionID: section.id, statementID: statement.id))
                                .font(TypeScale.body)
                                .scrollContentBackground(.hidden)
                                .padding(DesignTokens.Spacing.compact)
                                .frame(minHeight: 128)
                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                                .accessibilityLabel(section.title)
                        }
                    }
                }
                if let error = editor.error {
                    Text(error).font(TypeScale.label).foregroundStyle(DesignTokens.rose)
                }
            }
        }
    }

    private var briefActions: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            if generatedEditor?.isEditing == true {
                Button(isSavingGenerated ? "Saving" : "Save brief", action: saveGeneratedBrief)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSavingGenerated)
                Button("Cancel editing", action: cancelEditing).buttonStyle(SecondaryButtonStyle())
            } else if manualEditor.isEditing {
                Button("Save brief") { _ = manualEditor.save() }.buttonStyle(PrimaryButtonStyle())
                Button("Cancel editing", action: cancelEditing).buttonStyle(SecondaryButtonStyle())
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
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.small)
        .padding(.bottom, 76)
        .background(DesignTokens.surface)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
    }

    private var captureActions: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            Button("Open pre-session capture") { navigation.navigate(to: .tmsPre) }
                .buttonStyle(SecondaryButtonStyle())
            Button("Open post-session capture") { navigation.navigate(to: .tmsPost) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var currentMood: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("How you are doing now").font(TypeScale.sectionCompact).foregroundStyle(DesignTokens.cocoa)
            if state.mood == nil {
                Text("No check-in yet").font(TypeScale.label).foregroundStyle(DesignTokens.cocoaSoft)
            }
            MoodBands(values: moodValues, compact: true)
            Text(moodSummary)
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }

    private var moodValues: MoodValues {
        MoodValues(mood: state.mood?.mood, anxiety: state.mood?.anxiety, energy: state.mood?.energy)
    }

    private var moodSummary: String {
        guard let mood = state.mood else { return "Mood not logged. Anxiety not logged. Distress was not recorded." }
        return "Mood \(value(mood.mood)). Anxiety \(value(mood.anxiety)). Distress was not recorded."
    }

    private var isEditing: Bool { manualEditor.isEditing || generatedEditor?.isEditing == true }

    private var organizerAvailable: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private var generatedArtifact: AIArtifact? {
        AppointmentBriefArtifactReader.latest(
            kind: .tms,
            preferredID: preferredArtifactID,
            artifacts: state.artifacts,
            appointments: state.appointments,
            goals: state.goals,
            talkingPoints: state.talkingPoints
        )
    }

    private var hasUnreadableArtifact: Bool {
        AppointmentBriefArtifactReader.hasUnreadableArtifact(
            kind: .tms,
            preferredID: preferredArtifactID,
            artifacts: state.artifacts,
            appointments: state.appointments,
            goals: state.goals,
            talkingPoints: state.talkingPoints
        )
    }

    private func manualBinding(for section: TMSBriefSection) -> Binding<String> {
        Binding(
            get: { manualEditor.draft.text(for: section) },
            set: { manualEditor.update(section, text: $0) }
        )
    }

    private func generatedBinding(sectionID: UUID, statementID: UUID) -> Binding<String> {
        Binding(
            get: {
                generatedEditor?.draft.sections.first(where: { $0.id == sectionID })?.statements
                    .first(where: { $0.id == statementID })?.text ?? ""
            },
            set: { generatedEditor?.update(sectionID: sectionID, statementID: statementID, text: $0) }
        )
    }

    private func beginEditing() {
        actionError = nil
        if generatedEditor != nil { generatedEditor?.begin() } else { manualEditor.begin() }
    }

    private func cancelEditing() {
        generatedEditor?.cancel()
        manualEditor.cancel()
        actionError = nil
    }

    private func prepareGeneration() {
        guard organizerAvailable, pendingSend == nil else { return }
        actionError = nil
        do {
            pendingSend = try state.prepareAISend(.generateAppointmentBrief(.tms))
        } catch let error as UserFacingError {
            actionError = error.message
        } catch {
            actionError = "Your saved sources are not ready to send."
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
                if generatedEditor == nil {
                    actionError = "Candy Corn rejected treatment or causality language. Your manual brief is unchanged."
                }
                pendingSend = nil
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

    private func refreshGeneratedBrief() {
        guard generatedEditor?.isEditing != true else { return }
        guard let artifact = generatedArtifact else {
            generatedEditor = nil
            return
        }
        generatedEditor = AppointmentBriefEditor(artifact: artifact)
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
            } else {
                editor.failSave()
            }
            generatedEditor = editor
        }
    }

    private func provenance(for sourceID: UUID) -> Provenance {
        if let journal = state.journals.first(where: { $0.id == sourceID }) { return journal.provenance }
        if let goal = state.goals.first(where: { $0.id == sourceID }) { return goal.provenance }
        if let point = state.talkingPoints.first(where: { $0.id == sourceID }) { return point.provenance }
        if state.appointments.contains(where: { $0.id == sourceID }) {
            return Provenance(voice: .user, label: "From your manual session notes", detail: "Saved on this device", occurredAt: nil, sourceRoute: .tmsPost)
        }
        if state.moods.contains(where: { $0.id == sourceID }) {
            return Provenance(voice: .user, label: "From your mood check-ins", detail: "Saved on this device", occurredAt: nil, sourceRoute: .checkIn)
        }
        return Provenance(voice: .user, label: "From your saved source", detail: "Saved on this device", occurredAt: nil, sourceRoute: nil)
    }

    private func value(_ value: Int?) -> String {
        value.map { "\($0) of 10" } ?? "not logged"
    }
}

private struct TMSBriefLine: View {
    let title: String
    let copy: String
    let provenance: Provenance

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title).font(TypeScale.sectionCompact).foregroundStyle(DesignTokens.cocoa)
            Text(copy)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceLine(provenance: provenance, compact: true)
                .padding(.top, DesignTokens.Spacing.xSmall)
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }
}

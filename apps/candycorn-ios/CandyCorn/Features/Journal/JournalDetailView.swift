import SwiftUI
import UIKit

enum JournalDetailTab: String, CaseIterable, Sendable {
    case original = "Original"
    case extracted = "Extracted"
    case cleaned = "Cleaned"
    case summary = "Summary"
}

struct JournalDetailView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var selection = JournalDetailTab.original
    @State private var isEditing = false
    @State private var editText = ""
    @State private var confirmingDelete = false
    @State private var sourceImage: UIImage?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var isAddingPoint = false
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var actionError: String?
    @State private var openedScreenshotSheet = false

    private var entry: JournalEntry? {
        if let id = state.selectedJournalID,
           let selected = state.journals.first(where: { $0.id == id }) {
            return selected
        }
        return state.journals.max { $0.updatedAt < $1.updatedAt }
    }

    private var extracted: (artifact: AIArtifact, result: VisionReadResult)? {
        guard let entry else { return nil }
        return JournalArtifactReader.decode(
            VisionReadResult.self,
            kind: .photoText,
            journal: entry,
            artifacts: state.artifacts
        )
    }

    private var rewrite: (artifact: AIArtifact, result: RewriteJournalResult)? {
        guard let entry else { return nil }
        return JournalArtifactReader.decode(
            RewriteJournalResult.self,
            kind: .journalRewrite,
            journal: entry,
            artifacts: state.artifacts
        )
    }

    private var summary: (artifact: AIArtifact, result: JournalSummaryResult)? {
        guard let entry else { return nil }
        return JournalArtifactReader.decode(
            JournalSummaryResult.self,
            kind: .journalSummary,
            journal: entry,
            artifacts: state.artifacts
        )
    }

    var body: some View {
        ScreenLayout(
            title: entry?.title ?? "Journal entry",
            backAction: navigation.backAction(for: .journalDetail),
            trailing: entry == nil || entry?.inputType == .photo ? nil : AnyView(editButton)
        ) {
            if let entry {
                sourceAttachment(for: entry)
                if isEditing {
                    editor(for: entry)
                } else {
                    detail(for: entry)
                }
            } else {
                StatusNotice(
                    title: "No journal entries yet",
                    detail: "Talk, write, or take a photo when you want to remember something.",
                    kind: .information
                )
            }
        }
        .task(id: entry?.originalAttachmentID) { await loadSourceImage() }
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

    private var editButton: some View {
        Button(isEditing ? "Cancel" : "Edit") {
            guard let entry else { return }
            editText = entry.rawText
            isEditing.toggle()
            confirmingDelete = false
        }
        .font(TypeScale.bodyMedium)
        .foregroundStyle(DesignTokens.cocoa)
        .frame(minWidth: DesignTokens.controlMinimum, minHeight: DesignTokens.controlMinimum)
    }

    @ViewBuilder
    private func sourceAttachment(for entry: JournalEntry) -> some View {
        if let attachment = attachment(for: entry) {
            if attachment.kind == .image {
                if let sourceImage {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
                        .accessibilityLabel("Original journal photo")
                } else {
                    StatusNotice(
                        title: "Original photo unavailable",
                        detail: "The journal entry is still here. Text extraction is unavailable without the photo.",
                        kind: .warning
                    )
                }
            } else if attachment.kind == .audio {
                Button {
                    Task { try? await state.dependencies.playback.play(attachment: attachment) }
                } label: {
                    Label("Play original audio", systemImage: AppIcon.play.rawValue)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else if entry.inputType == .photo {
            StatusNotice(
                title: "Original photo unavailable",
                detail: "The journal record remains, but this photo cannot be sent for text extraction.",
                kind: .warning
            )
        }
    }

    private func detail(for entry: JournalEntry) -> some View {
        Group {
            UnderlinePicker(options: availableTabs(for: entry), selection: $selection) { $0.rawValue }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                tabContent(entry)
                ProvenanceLine(provenance: provenance(for: entry))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            organizerActions(for: entry)
            Button {
                addJournalTalkingPoint(entry)
            } label: {
                Label(isAddingPoint ? "Adding" : "Add to next appointment", systemImage: AppIcon.listPlus.rawValue)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isAddingPoint)
        }
    }

    @ViewBuilder
    private func tabContent(_ entry: JournalEntry) -> some View {
        switch selection {
        case .original:
            originalText(entry)
        case .extracted:
            extractedText
        case .cleaned:
            cleanedText(entry)
        case .summary:
            summaryText(entry)
        }
    }

    @ViewBuilder
    private func originalText(_ entry: JournalEntry) -> some View {
        if entry.rawText.isEmpty && entry.inputType != .text {
            Text(entry.inputType == .voice ? "Voice journal" : "The photo above is the unchanged original.")
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
        } else {
            Text(entry.rawText)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var extractedText: some View {
        if let extracted, !extracted.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                Text(extracted.result.text)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                if !extracted.result.uncertainSpans.isEmpty {
                    Text("Check uncertain text: \(extracted.result.uncertainSpans.prefix(8).joined(separator: ", "))")
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.yellowText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("No extracted text is available.")
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
    }

    @ViewBuilder
    private func cleanedText(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            if let rewrite, !rewrite.result.segments.isEmpty {
                ForEach(rewrite.result.segments) { segment in
                    Text(segment.text)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(entry.cleanedText ?? "No cleaned version is available.")
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Your original remains unchanged.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
    }

    @ViewBuilder
    private func summaryText(_ entry: JournalEntry) -> some View {
        let statements = summary?.result.statements.map(\.text) ?? entry.summaryItems
        if statements.isEmpty {
            Text("No summary is available.")
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoaSoft)
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                ForEach(Array(statements.enumerated()), id: \.offset) { _, statement in
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                        KernelGlyph(voice: .candyCorn, height: 16)
                            .padding(.top, DesignTokens.Spacing.xSmall)
                        Text(statement)
                            .font(TypeScale.body)
                            .foregroundStyle(DesignTokens.cocoa)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func organizerActions(for entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Organize this journal")
                .font(TypeScale.section)
                .foregroundStyle(DesignTokens.cocoa)
            if canUseOrganizer {
                if entry.inputType == .photo && extracted == nil {
                    if let attachmentID = entry.originalAttachmentID {
                        actionButton(
                            "Extract text",
                            action: .readPhoto(journalID: entry.id, attachmentID: attachmentID)
                        )
                    }
                } else if hasLanguageSource(entry) {
                    actionButton("Make this easier to read", action: .rewriteJournal(entry.id))
                    actionButton("Summarize", action: .summarizeJournal(entry.id))
                    actionButton("Find possible next steps", action: .extractJournalSignals(entry.id))
                }
            } else {
                StatusNotice(
                    title: state.aiMode == .off ? "Organizing is off" : "Router key needed",
                    detail: "Your original stays available. You can keep editing and adding items manually.",
                    kind: .information
                )
                Button("Open AI settings") { navigation.navigate(to: .settingsAI) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if let actionError {
                StatusNotice(
                    title: "Could not organize this journal",
                    detail: "\(actionError) The original is unchanged.",
                    kind: .warning
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ title: String, action: AISendAction) -> some View {
        Button {
            prepare(action)
        } label: {
            HStack(spacing: DesignTokens.Spacing.small) {
                KernelGlyph(voice: .candyCorn, height: 18)
                Text(state.aiProcessingState(for: action) == .processing ? "Working" : title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(state.aiProcessingState(for: action) == .processing)
    }

    private func editor(for entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            TextEditor(text: $editText)
                .font(TypeScale.body)
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
            Button(isSaving ? "Saving" : "Save changes") { saveEdit(entry) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            deleteControls(entry)
        }
    }

    @ViewBuilder
    private func deleteControls(_ entry: JournalEntry) -> some View {
        if confirmingDelete {
            Text("Delete this journal entry? The original attachment is kept until the vault removes it.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
            Button(isDeleting ? "Deleting" : "Delete journal", role: .destructive) {
                delete(entry)
            }
            .buttonStyle(DangerButtonStyle())
            .disabled(isDeleting)
        } else {
            Button("Delete journal") { confirmingDelete = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func prepare(_ action: AISendAction) {
        guard pendingSend == nil else { return }
        actionError = nil
        do {
            pendingSend = try state.prepareAISend(action)
        } catch let error as UserFacingError {
            actionError = error.message
        } catch {
            actionError = "This source is not ready to send."
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            prepare(pending.action)
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
                reveal(pending.action)
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

    private func reveal(_ action: AISendAction) {
        switch action {
        case .rewriteJournal: selection = .cleaned
        case .summarizeJournal: selection = .summary
        case .extractJournalSignals: navigation.navigate(to: .journalSuggestions)
        case .readPhoto: selection = .extracted
        case .summarizeSession, .generateAppointmentBrief: break
        }
    }

    private func addJournalTalkingPoint(_ entry: JournalEntry) {
        guard !isAddingPoint else { return }
        isAddingPoint = true
        Task {
            _ = await state.createTalkingPoint(text: entry.title, source: .journal, sourceID: entry.id)
            isAddingPoint = false
        }
    }

    private func saveEdit(_ entry: JournalEntry) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if await state.editJournal(id: entry.id, rawText: editText) { isEditing = false }
            isSaving = false
        }
    }

    private func delete(_ entry: JournalEntry) {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            if await state.deleteJournal(id: entry.id) { navigation.goBack(from: .journalDetail) }
            isDeleting = false
        }
    }

    private func availableTabs(for entry: JournalEntry) -> [JournalDetailTab] {
        var tabs: [JournalDetailTab] = [.original]
        if extracted != nil { tabs.append(.extracted) }
        if rewrite != nil || entry.cleanedText != nil { tabs.append(.cleaned) }
        if summary != nil || !entry.summaryItems.isEmpty { tabs.append(.summary) }
        return tabs
    }

    private func provenance(for entry: JournalEntry) -> Provenance {
        let artifact: AIArtifact?
        switch selection {
        case .original: return entry.provenance
        case .extracted: artifact = extracted?.artifact
        case .cleaned: artifact = rewrite?.artifact
        case .summary: artifact = summary?.artifact
        }
        return Provenance(
            voice: .candyCorn,
            label: selection == .extracted ? "Candy Corn extracted this" : "Candy Corn organized this",
            detail: artifact.map { "\($0.provider), \($0.model)" } ?? "Derived from your unchanged original",
            occurredAt: artifact?.createdAt ?? entry.updatedAt,
            sourceRoute: .journalDetail
        )
    }

    private var canUseOrganizer: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private func hasLanguageSource(_ entry: JournalEntry) -> Bool {
        if entry.inputType == .photo {
            return extracted?.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attachment(for entry: JournalEntry) -> Attachment? {
        let id = entry.originalAttachmentID ?? entry.audioAttachmentID
        return state.attachments.first { $0.id == id }
    }

    private func loadSourceImage() async {
        guard let entry, let attachment = attachment(for: entry), attachment.kind == .image else {
            sourceImage = nil
            return
        }
        do {
            let url = try await state.dependencies.attachments.url(for: attachment)
            sourceImage = UIImage(contentsOfFile: url.path)
        } catch {
            sourceImage = nil
        }
    }

    private func openScreenshotDisclosureIfNeeded() {
        guard !openedScreenshotSheet,
              let action = state.dependencies.screenshotScenario?.sendAction,
              actionMatchesJournal(action) else { return }
        openedScreenshotSheet = true
        state.setAIMode(.organizer)
        state.setAIProvider(.router)
        if case let .readPhoto(journalID, _) = action { state.selectJournal(id: journalID) }
        prepare(action)
    }

    private func actionMatchesJournal(_ action: AISendAction) -> Bool {
        switch action {
        case .rewriteJournal, .summarizeJournal, .extractJournalSignals, .readPhoto: true
        case .summarizeSession, .generateAppointmentBrief: false
        }
    }
}

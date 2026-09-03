import SwiftUI
import UIKit

enum JournalDetailTab: String, CaseIterable, Sendable {
    case original = "Original"
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

    private var entry: JournalEntry? {
        if let id = state.selectedJournalID,
           let selected = state.journals.first(where: { $0.id == id }) {
            return selected
        }
        return state.journals.max { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ScreenLayout(
            title: entry?.title ?? "Journal entry",
            backAction: navigation.backAction(for: .journalDetail),
            trailing: entry == nil ? nil : AnyView(editButton)
        ) {
            if let entry {
                sourceAttachment(for: entry)
                if isEditing {
                    editor(for: entry)
                } else {
                    detail(for: entry)
                }
            } else {
                StatusNotice(title: "No journal entries yet", detail: "Talk, write, or take a photo when you want to remember something.", kind: .information)
            }
        }
        .task(id: entry?.originalAttachmentID) { await loadSourceImage() }
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
                    StatusNotice(title: "Original photo unavailable", detail: "The journal entry is still here.", kind: .warning)
                }
            } else if attachment.kind == .audio {
                Button {
                    Task { try? await state.dependencies.playback.play(attachment: attachment) }
                } label: {
                    Label("Play original audio", systemImage: AppIcon.play.rawValue)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
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
            Button {
                guard !isAddingPoint else { return }
                isAddingPoint = true
                Task {
                    _ = await state.createTalkingPoint(text: entry.title, source: .journal, sourceID: entry.id)
                    isAddingPoint = false
                }
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
            if entry.rawText.isEmpty && entry.inputType != .text {
                Text(entry.inputType == .voice ? "Voice journal" : "Photo journal")
                    .font(TypeScale.body)
            } else {
                Text(entry.rawText).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
            }
        case .cleaned:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                Text(entry.cleanedText ?? "No cleaned version is available.").font(TypeScale.body)
                Text("Your original remains unchanged.").font(TypeScale.provenance).foregroundStyle(DesignTokens.cocoaSoft)
            }
        case .summary:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                ForEach(Array(entry.summaryItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                        KernelGlyph(voice: .candyCorn, height: 16)
                        Text(item).font(TypeScale.body)
                    }
                }
            }
        }
    }

    private func editor(for entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            TextEditor(text: $editText)
                .font(TypeScale.body)
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
            Button(isSaving ? "Saving" : "Save changes") {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    if await state.editJournal(id: entry.id, rawText: editText) { isEditing = false }
                    isSaving = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving || editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if confirmingDelete {
                Text("Delete this journal entry? The original attachment is kept until the vault removes it.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                Button(isDeleting ? "Deleting" : "Delete journal", role: .destructive) {
                    guard !isDeleting else { return }
                    isDeleting = true
                    Task {
                        if await state.deleteJournal(id: entry.id) { navigation.goBack(from: .journalDetail) }
                        isDeleting = false
                    }
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(isDeleting)
            } else {
                Button("Delete journal") { confirmingDelete = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func availableTabs(for entry: JournalEntry) -> [JournalDetailTab] {
        var tabs: [JournalDetailTab] = [.original]
        if entry.cleanedText != nil { tabs.append(.cleaned) }
        if !entry.summaryItems.isEmpty { tabs.append(.summary) }
        return tabs
    }

    private func provenance(for entry: JournalEntry) -> Provenance {
        if selection == .summary {
            return Provenance(voice: .candyCorn, label: "Candy Corn organized this", detail: "Derived from your original", occurredAt: entry.updatedAt, sourceRoute: .journalDetail)
        }
        return entry.provenance
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
}

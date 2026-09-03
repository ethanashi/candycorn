import SwiftUI

enum JournalWritingResult: Equatable, Sendable {
    case none
    case rewrite
    case summary
}

struct JournalDraftState: Equatable, Sendable {
    var text: String
    private(set) var savedOriginal: String?
    private(set) var result: JournalWritingResult = .none

    var canSave: Bool {
        savedOriginal == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    mutating func saveOriginal() -> Bool {
        guard canSave else { return false }
        savedOriginal = text
        result = .none
        return true
    }

    mutating func show(_ nextResult: JournalWritingResult) {
        guard savedOriginal != nil else { return }
        result = nextResult
    }
}

struct TextJournalView: View {
    @Bindable var navigation: NavigationModel
    @State private var draft = JournalDraftState(text: Self.seedText)
    @FocusState private var editorFocused: Bool

    private static var seedText: String {
        SeededData.journalEntries.first(where: { $0.id == SeededData.footballJournalID })?.rawText
            ?? "This journal entry is unavailable."
    }

    var body: some View {
        if let original = draft.savedOriginal {
            savedView(original: original)
        } else {
            editorView
        }
    }

    private var editorView: some View {
        ScreenLayout(
            title: "Write it down",
            subtitle: "Messy is welcome. Your original stays unchanged.",
            backAction: dismiss,
            bottomInset: DesignTokens.Spacing.section
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Your journal")
                    .font(TypeScale.label)
                TextEditor(text: $draft.text)
                    .font(Font.custom("AvenirNext-Regular", size: 18, relativeTo: .body))
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 330)
                    .focused($editorFocused)
                    .accessibilityLabel("Your journal")
                Divider()
                    .overlay(DesignTokens.hairline)
            }

            if !draft.canSave {
                Text("Write something before saving. Nothing has been lost.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Save original") {
                editorFocused = false
                _ = draft.saveOriginal()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!draft.canSave)
            .opacity(draft.canSave ? 1 : 0.45)
        }
        .onAppear { editorFocused = true }
    }

    private func savedView(original: String) -> some View {
        ScreenLayout(
            title: "Your words are saved",
            subtitle: "The original stays exactly as you wrote it.",
            backAction: dismiss,
            bottomInset: DesignTokens.Spacing.section
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                ProvenanceLine(provenance: Self.userProvenance)
                Text(original)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, DesignTokens.Spacing.large)
            .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text("What would help?")
                    .font(TypeScale.sectionCompact)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.small) {
                    choice("Rewrite clearly") { draft.show(.rewrite) }
                    choice("Summarize") { draft.show(.summary) }
                    choice("Find talking points") { open(.journalSuggestions) }
                    choice("Leave it alone") { open(.journalDetail) }
                }
            }

            if draft.result == .rewrite {
                resultCard(
                    title: "Clearer version",
                    text: Self.entry?.cleanedText ?? "No clearer version is available."
                )
            } else if draft.result == .summary {
                resultCard(
                    title: "Short summary",
                    text: Self.entry?.summaryItems.joined(separator: " ") ?? "No summary is available."
                )
            }
        }
    }

    private func choice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(TypeScale.label)
            .foregroundStyle(DesignTokens.cocoa)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum)
            .padding(.horizontal, DesignTokens.Spacing.small)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DesignTokens.cocoa, lineWidth: 1))
            .buttonStyle(.plain)
    }

    private func resultCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(TypeScale.bodyMedium)
            Text(text)
                .font(TypeScale.body)
            Text("Your original above has not changed.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .padding(DesignTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
    }

    private static var entry: JournalEntry? {
        SeededData.journalEntries.first { $0.id == SeededData.footballJournalID }
    }

    private static let userProvenance = Provenance(
        voice: .user,
        label: "You wrote this",
        detail: "Journal, Sep 5 at 3:18 PM",
        occurredAt: nil,
        sourceRoute: .journalDetail
    )

    private func dismiss() {
        navigation.dismissPresentedFlow()
    }

    private func open(_ route: Route) {
        navigation.dismissPresentedFlow()
        navigation.navigate(to: route)
    }
}

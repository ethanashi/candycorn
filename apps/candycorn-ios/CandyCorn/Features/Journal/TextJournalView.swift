import SwiftUI

struct JournalDraftState: Equatable, Sendable {
    var text = ""
    private(set) var saveStarted = false

    var canSave: Bool {
        !saveStarted && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func beginSave() -> String? {
        guard canSave else { return nil }
        saveStarted = true
        return text
    }

    mutating func retry() { saveStarted = false }
}

struct TextJournalView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var draft = JournalDraftState()
    @State private var savedEntry: JournalEntry?
    @State private var saveFailed = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        if let savedEntry {
            savedView(savedEntry)
        } else {
            editorView
        }
    }

    private var editorView: some View {
        V2Screen(
            title: "Write it down",
            subtitle: "Messy is welcome. Your original stays unchanged.",
            backAction: navigation.backAction(for: .journalWrite),
            backLabel: "Close",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.section
        ) {
            V2Card {
                TextEditor(text: $draft.text)
                    .font(Font.custom("AvenirNext-Regular", size: 18, relativeTo: .body))
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 300)
                    .focused($editorFocused)
                    .accessibilityLabel("Your journal")
            }

            if saveFailed {
                StatusNotice(title: "Your journal could not be saved", detail: "Your words are still here. Try again.", kind: .warning)
            }

            Button(draft.saveStarted ? "Saving" : "Save original", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!draft.canSave)
                .opacity(draft.canSave ? 1 : 0.45)
        }
        .onAppear { editorFocused = true }
    }

    private func savedView(_ entry: JournalEntry) -> some View {
        V2Screen(
            title: "Your words are saved",
            subtitle: "The original stays exactly as you wrote it.",
            backAction: navigation.backAction(for: .journalWrite),
            backLabel: "Close",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.section
        ) {
            V2Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    ProvenanceInline(voice: entry.provenance.voice, text: entry.provenance.inlineText)
                    Text(entry.rawText)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            StatusNotice(title: "Saved on this device", detail: "AI is off. No cleaned text or summary was created.", kind: .saved)
            Button("View in history") { open(.history) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func save() {
        guard let original = draft.beginSave() else { return }
        editorFocused = false
        saveFailed = false
        Task {
            if let entry = await state.createJournal(rawText: original) {
                savedEntry = entry
            } else {
                draft.retry()
                saveFailed = true
            }
        }
    }

    private func open(_ route: Route) {
        navigation.goBack(from: .journalWrite)
        navigation.navigate(to: route)
    }
}

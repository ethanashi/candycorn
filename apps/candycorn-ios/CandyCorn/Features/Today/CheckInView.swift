import Foundation
import SwiftUI

struct CheckInDraft: Equatable, Sendable {
    private static let newMoodID = UUID(uuidString: "20000000-0000-0000-0000-000000000099")!

    private let id: UUID
    private let createdAt: Date
    private let customValues: [String: Int]
    var values: MoodValues
    private(set) var note: String
    private(set) var saveStarted = false

    init(mood: MoodLog?, now: Date) {
        id = mood?.id ?? Self.newMoodID
        createdAt = mood?.createdAt ?? now
        customValues = mood?.customValues ?? [:]
        values = MoodValues(mood: mood?.mood, anxiety: mood?.anxiety, energy: mood?.energy)
        note = String((mood?.note ?? "").prefix(180))
    }

    mutating func set(_ dimension: MoodDimension, to value: Int?) {
        let next = value.map { min(max($0, 1), 10) }
        switch dimension {
        case .anxiety: values.anxiety = next
        case .mood: values.mood = next
        case .energy: values.energy = next
        }
    }

    mutating func updateNote(_ value: String) {
        note = String(value.prefix(180))
    }

    mutating func beginSave() -> MoodLog? {
        guard !saveStarted else { return nil }
        saveStarted = true
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return MoodLog(
            id: id,
            createdAt: createdAt,
            mood: values.mood,
            anxiety: values.anxiety,
            energy: values.energy,
            customValues: customValues,
            note: cleanedNote.isEmpty ? nil : cleanedNote
        )
    }

    mutating func retrySave() { saveStarted = false }
}

struct CheckInView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var draft: CheckInDraft

    init(navigation: NavigationModel, state: DemoState) {
        self.navigation = navigation
        self.state = state
        _draft = State(initialValue: CheckInDraft(mood: state.mood, now: state.dependencies.now()))
    }

    var body: some View {
        V2Screen(
            title: "How are you doing?",
            subtitle: "Tap or drag each band, 1 to 10.",
            backAction: cancel,
            backLabel: "Cancel check-in",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.large
        ) {
            if allValuesEmpty {
                Text("No check-in yet")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            moodEditor
            legend
            noteEditor
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal, DesignTokens.screenInset)
                .padding(.vertical, DesignTokens.Spacing.small)
                .background(DesignTokens.canvas)
        }
        .interactiveDismissDisabled()
    }

    private var moodEditor: some View {
        MoodBands(values: draft.values) { (dimension: MoodDimension, value: Int?) in
            draft.set(dimension, to: value)
        }
    }

    private var legend: some View {
        HStack(spacing: DesignTokens.blockGap) {
            legendItem("Anxiety", color: DesignTokens.yellow)
            legendItem("Mood", color: DesignTokens.orange)
            legendItem("Energy", color: DesignTokens.energyBand)
            Spacer(minLength: 0)
            Text("Minus and plus also work")
                .font(TypeScale.meta)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(TypeScale.meta).foregroundStyle(DesignTokens.cocoaSoft)
        }
    }

    private var noteEditor: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                SectionLine(title: "Add a note", trailing: "Optional")
                TextEditor(text: noteBinding)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .accessibilityLabel("Optional note")
                    .accessibilityHint("Up to 180 characters")
            }
        }
    }

    private var saveButton: some View {
        Button(draft.saveStarted ? "Saving" : "Save check-in", action: save)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(draft.saveStarted)
            .accessibilityHint("Saves this check-in and returns to Today")
    }

    private var noteBinding: Binding<String> {
        Binding(get: { draft.note }, set: { draft.updateNote($0) })
    }

    private var allValuesEmpty: Bool {
        draft.values.mood == nil && draft.values.anxiety == nil && draft.values.energy == nil
    }

    private func cancel() {
        navigation.dismissPresentedFlow()
    }

    private func save() {
        guard let mood = draft.beginSave() else { return }
        Task {
            if await state.persistMood(mood) {
                navigation.goBack(from: .checkIn)
            } else {
                draft.retrySave()
            }
        }
    }
}

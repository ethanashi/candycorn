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
    @State private var editor = TherapyBriefEditor()

    var body: some View {
        ScreenLayout(
            title: editor.isEditing ? "Edit your therapy brief" : "Walk in knowing what matters",
            subtitle: editor.isEditing
                ? "Change the wording without changing your original journals or session."
                : "A brief for Jamie Rivera to read before therapy with Dr. Elena Park on Sep 9.",
            backAction: { navigation.navigate(to: .today) },
            backLabel: "Back to Today",
            bottomInset: 180
        ) {
            if editor.isEditing {
                briefEditor
            } else {
                briefReading
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .background(DesignTokens.canvas)
    }

    private var briefReading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(DesignTokens.hairline)
            ForEach(TherapyBriefSection.allCases) { section in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(section.title)
                        .font(TypeScale.sectionCompact)
                    Text(highlighted(editor.saved.text(for: section), quoted: section == .possibleOpening))
                        .font(TypeScale.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    ProvenanceLine(provenance: section.provenance, compact: true)
                        .padding(.top, DesignTokens.Spacing.xSmall)
                }
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.vertical, DesignTokens.Spacing.medium)
                Divider().overlay(DesignTokens.hairline)
            }
        }
    }

    private var briefEditor: some View {
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
            if let error = editor.error {
                Text(error)
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error. \(error)")
            }
        }
    }

    private var actions: some View {
        Group {
            if editor.isEditing {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Button("Cancel") { editor.cancel() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Save brief") { _ = editor.save() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                Button(action: { editor.begin() }) {
                    Label("Edit brief", systemImage: AppIcon.pencil.rawValue)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.small)
        .padding(.bottom, 76)
        .background(DesignTokens.surface)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
    }

    private func draftBinding(for section: TherapyBriefSection) -> Binding<String> {
        Binding(
            get: { editor.draft.text(for: section) },
            set: { editor.update(section, text: $0) }
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
}

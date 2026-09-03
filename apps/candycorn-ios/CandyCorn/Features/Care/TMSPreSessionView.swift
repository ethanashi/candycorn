import SwiftUI

enum TMSMeasure: Sendable {
    case mood
    case anxiety
    case energy
    case distress
}

struct TMSCheckInSnapshot: Equatable, Sendable {
    private(set) var mood: Int
    private(set) var anxiety: Int
    private(set) var energy: Int
    private(set) var distress: Int

    init(mood: Int, anxiety: Int, energy: Int, distress: Int) {
        self.mood = Self.clamp(mood)
        self.anxiety = Self.clamp(anxiety)
        self.energy = Self.clamp(energy)
        self.distress = Self.clamp(distress)
    }

    @discardableResult
    mutating func update(_ measure: TMSMeasure, value: Int) -> Bool {
        guard Self.contains(value) else { return false }
        switch measure {
        case .mood: mood = value
        case .anxiety: anxiety = value
        case .energy: energy = value
        case .distress: distress = value
        }
        return true
    }

    static func contains(_ value: Int) -> Bool {
        (1...10).contains(value)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 1), 10)
    }
}

struct TMSPreSessionView: View {
    private static let talkingPointID = UUID(uuidString: "50000000-0000-0000-0000-000000000099")!

    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var snapshot = TMSCheckInSnapshot(mood: 6, anxiety: 7, energy: 4, distress: 6)
    @State private var bothering = "The guilt that shows up after I start feeling better."
    @State private var providerFocus = "Mention any sleep changes before today’s session."
    @State private var isAdding = false

    var body: some View {
        V2Screen(
            title: "Before TMS",
            subtitle: "A short check-in before your visit.",
            backAction: navigation.backAction(for: .tmsPre),
            bottomInset: DesignTokens.Spacing.section
        ) {
            TMSMeasuresEditor(snapshot: $snapshot)
            noteField(title: "What has been bothering you most today?", text: $bothering)
            V2GroupCard {
                V2ListRow(
                    icon: .listPlus,
                    title: isAdded ? "Added for the provider" : "Tell the provider about this",
                    detail: "Adds this note to your TMS talking points.",
                    trailing: isAdded ? .check : .chevron,
                    divider: false,
                    disabled: trimmedBothering.isEmpty || isAdded || isAdding
                ) { addForProvider() }
                .accessibilityHint(trimmedBothering.isEmpty ? "Enter a note before adding it" : "Adds this note once")
            }
            noteField(title: "Provider-supplied focus item", text: $providerFocus, provenance: providerProvenance)
            StatusNotice(
                title: "You set the focus",
                detail: "Candy Corn does not create treatment provocations. It only organizes what you and your provider supply."
            )
            Button("Save pre-session check-in") { navigation.navigate(to: .prepareTMS) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var isAdded: Bool {
        state.talkingPoints.contains { $0.id == Self.talkingPointID }
    }

    private var trimmedBothering: String {
        bothering.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var providerProvenance: Provenance {
        Provenance(
            voice: .provider,
            label: "TMS team supplied this",
            detail: "Visit instructions, Sep 5 at 9:12 AM",
            occurredAt: nil,
            sourceRoute: .tmsPre
        )
    }

    private func noteField(title: String, text: Binding<String>, provenance: Provenance? = nil) -> some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                SectionLine(title: title)
                TextEditor(text: text)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .accessibilityLabel(title)
                if let provenance {
                    ProvenanceStack(provenance: provenance)
                }
            }
        }
    }

    private func addForProvider() {
        guard !trimmedBothering.isEmpty else { return }
        let point = TalkingPoint(
            id: Self.talkingPointID,
            text: String(trimmedBothering.prefix(500)),
            source: .manual,
            sourceID: nil,
            targetAppointmentKind: .tms,
            isImportant: false,
            status: .open,
            createdAt: state.dependencies.now(),
            provenance: Provenance(voice: .user, label: "You chose to tell the provider", detail: "TMS pre-session check-in", occurredAt: nil, sourceRoute: .tmsPre)
        )
        isAdding = true
        Task {
            _ = await state.saveTalkingPoint(point)
            isAdding = false
        }
    }
}

struct TMSMeasuresEditor: View {
    @Binding var snapshot: TMSCheckInSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
            V2Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    SectionLine(title: "Mood, anxiety, and energy", trailing: "1 to 10")
                    MoodBands(values: moodValues, onChange: updateMood)
                }
            }
            V2Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    SectionLine(title: "Distress", trailing: "\(snapshot.distress) of 10")
                    Slider(value: distress, in: 1...10, step: 1)
                        .tint(DesignTokens.yellowDeep)
                        .frame(minHeight: DesignTokens.controlMinimum)
                        .accessibilityLabel("Distress")
                }
            }
        }
    }

    private var moodValues: MoodValues {
        MoodValues(mood: snapshot.mood, anxiety: snapshot.anxiety, energy: snapshot.energy)
    }

    private var distress: Binding<Double> {
        Binding(
            get: { Double(snapshot.distress) },
            set: { _ = snapshot.update(.distress, value: Int($0.rounded())) }
        )
    }

    private func updateMood(_ dimension: MoodDimension, _ value: Int) {
        switch dimension {
        case .mood: _ = snapshot.update(.mood, value: value)
        case .anxiety: _ = snapshot.update(.anxiety, value: value)
        case .energy: _ = snapshot.update(.energy, value: value)
        }
    }
}

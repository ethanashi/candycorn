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

    var body: some View {
        ScreenLayout(
            title: "Before TMS",
            subtitle: "A short check-in for Jamie’s next visit.",
            backAction: { navigation.navigate(to: .appointments) },
            backLabel: "Back to appointments",
            bottomInset: DesignTokens.Spacing.section
        ) {
            TMSMeasuresEditor(snapshot: $snapshot)
            noteField(title: "What has been bothering you most today?", text: $bothering)
            Button(isAdded ? "Added for the provider" : "Add this to tell the provider", action: addForProvider)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(trimmedBothering.isEmpty || isAdded)
                .accessibilityHint(trimmedBothering.isEmpty ? "Enter a note before adding it" : "Adds this note once")
            noteField(title: "Provider-supplied focus item", text: $providerFocus)
            ProvenanceLine(provenance: providerProvenance)
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

    private func noteField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title).font(TypeScale.sectionCompact)
            TextEditor(text: text)
                .font(TypeScale.body)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.compact)
                .frame(minHeight: 104)
                .background(DesignTokens.surface)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                .accessibilityLabel(title)
        }
        .foregroundStyle(DesignTokens.cocoa)
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
            createdAt: Date(timeIntervalSince1970: 1_788_654_600),
            provenance: Provenance(voice: .user, label: "You chose to tell the provider", detail: "TMS pre-session check-in", occurredAt: nil, sourceRoute: .tmsPre)
        )
        _ = state.addTalkingPoint(point)
    }
}

struct TMSMeasuresEditor: View {
    @Binding var snapshot: TMSCheckInSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Mood, anxiety, and distress")
                .font(TypeScale.section)
                .foregroundStyle(DesignTokens.cocoa)
            MoodBands(values: moodValues, onChange: updateMood)
            VStack(spacing: DesignTokens.Spacing.xSmall) {
                HStack {
                    Text("Distress")
                    Spacer()
                    Text("\(snapshot.distress)/10").monospacedDigit()
                }
                .font(TypeScale.label)
                .fontWeight(.semibold)
                Slider(value: distress, in: 1...10, step: 1)
                    .tint(DesignTokens.yellowDeep)
                    .frame(minHeight: DesignTokens.controlMinimum)
                    .accessibilityLabel("Distress")
            }
            .padding(DesignTokens.Spacing.base)
            .background(DesignTokens.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
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

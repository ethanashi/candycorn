import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case privacy = "Privacy"
    case ai = "AI"
    case data = "Data"

    var id: Self { self }

    var route: Route {
        switch self {
        case .privacy: .settingsPrivacy
        case .ai: .settingsAI
        case .data: .settingsData
        }
    }
}

struct SettingsSectionPicker: View {
    let current: SettingsSection
    @Bindable var navigation: NavigationModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    navigation.navigate(to: section.route)
                } label: {
                    VStack(spacing: DesignTokens.Spacing.small) {
                        Text(section.rawValue)
                            .font(section == current ? TypeScale.bodyMedium : TypeScale.label)
                            .foregroundStyle(section == current ? DesignTokens.cocoa : DesignTokens.cocoaSoft)
                        Rectangle()
                            .fill(section == current ? DesignTokens.orange : Color.clear)
                            .frame(width: 86, height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.rawValue) settings")
                .accessibilityAddTraits(section == current ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

struct SettingsStatusRow: View {
    let status: String
    let detail: String
    var voice: ProvenanceVoice = .candyCorn

    var body: some View {
        ProvenanceLine(
            provenance: Provenance(
                voice: voice,
                label: status,
                detail: detail,
                occurredAt: nil,
                sourceRoute: nil
            ),
            compact: false
        )
        .padding(.vertical, DesignTokens.Spacing.small)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }
}

struct SettingsChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                ZStack {
                    Circle()
                        .stroke(disabled ? DesignTokens.hairline : DesignTokens.cocoaSoft, lineWidth: 1)
                    if selected {
                        Circle()
                            .fill(DesignTokens.orange)
                            .padding(5)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    Text(title)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(disabled ? DesignTokens.cocoaSoft : DesignTokens.cocoa)
                    Text(detail)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DesignTokens.Spacing.small)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

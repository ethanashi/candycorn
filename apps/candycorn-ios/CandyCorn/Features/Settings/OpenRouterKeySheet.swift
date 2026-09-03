import SwiftUI

struct OpenRouterKeySheet: View {
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        V2Screen(
            title: "Paste OpenRouter key",
            subtitle: "Your own key powers cloud organizing and photo-to-text.",
            backAction: { dismiss() },
            backLabel: "Cancel",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.large
        ) {
            keyField
            privacyExplanation
            if let errorMessage {
                StatusNotice(title: "Key not saved", detail: errorMessage, kind: .warning)
            }
            Button(isSaving ? "Saving" : "Save", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var keyField: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                SectionLine(title: "OpenRouter key", trailing: "Never shown once saved")
                SecureField("Paste key", text: boundedKeyBinding)
                    .font(TypeScale.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .padding(.horizontal, DesignTokens.Spacing.compact)
                    .frame(minHeight: DesignTokens.controlMinimum + 4)
                    .background(DesignTokens.surfaceWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("OpenRouter key")
                    .accessibilityHint("Secure text field. A saved key is never shown here.")
                Text("The field is always empty when opened. Candy Corn never reveals a saved key.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyExplanation: some View {
        V2GroupCard {
            V2ListRow(icon: .key, title: "Stored in this iPhone's Keychain", detail: "Not included in exports.", trailing: .check, divider: false)
            V2ListRow(icon: .cloudUpload, title: "Used only after you tap Send", detail: "You review what leaves this device first.", trailing: .check)
        }
    }

    private var boundedKeyBinding: Binding<String> {
        Binding(
            get: { key },
            set: {
                key = String($0.prefix(OpenRouterAPIKeyStore.maximumCharacterCount + 1))
                errorMessage = nil
            }
        )
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let normalized = try AISettingsLogic.normalizedKey(key)
            guard onSave(normalized) else {
                errorMessage = "That key could not be saved. Check it and try again."
                isSaving = false
                return
            }
            dismiss()
        } catch let error as AISettingsValidationError {
            errorMessage = error.message
            isSaving = false
        } catch {
            errorMessage = "That key could not be saved. Check it and try again."
            isSaving = false
        }
    }
}

import SwiftUI

struct OpenRouterKeySheet: View {
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScreenLayout(
            title: "Paste OpenRouter key",
            subtitle: "Add your own key for cloud organizer and photo-to-text requests.",
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
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSaving)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("OpenRouter key")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            SecureField("Paste key", text: boundedKeyBinding)
                .font(TypeScale.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.password)
                .padding(DesignTokens.Spacing.compact)
                .frame(minHeight: DesignTokens.primaryButtonHeight)
                .background(DesignTokens.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                )
                .accessibilityLabel("OpenRouter key")
                .accessibilityHint("Secure text field. A saved key is never shown here.")
            Text("The field is always empty when opened. Candy Corn never reveals a saved key.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyExplanation: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .user, height: 18, decorative: true)
                .padding(.top, 2)
            Text(
                "The key is stored only in this iPhone's Keychain and is not included in exports. "
                    + "It is used only after you review what will leave this device and tap Send."
            )
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
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

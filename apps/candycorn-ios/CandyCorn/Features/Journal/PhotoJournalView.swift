import SwiftUI

struct PhotoJournalState: Equatable, Sendable {
    static let originalPageText = "I keep thinking about senior year. I wanted the chance to prove I could have played. That part still feels unfinished."
    static let defaultExtraction = "I keep thinking about senior year. I wanted the chance to prove I could have played. Exercise helped me get unstuck today, but then feeling better brought up guilt."

    private(set) var captured = false
    var extractedText = Self.defaultExtraction

    mutating func capture() {
        guard !captured else { return }
        captured = true
    }

    mutating func retake() {
        guard captured else { return }
        captured = false
        extractedText = Self.defaultExtraction
    }
}

struct PhotoJournalView: View {
    @Bindable var navigation: NavigationModel
    @State private var photo = PhotoJournalState()
    @FocusState private var extractionFocused: Bool

    var body: some View {
        if photo.captured {
            comparisonView
        } else {
            cameraView
        }
    }

    private var cameraView: some View {
        ScreenLayout(
            title: "Photograph a page",
            subtitle: "Frame the full page. This screen does not use your camera.",
            backAction: dismiss,
            bottomInset: DesignTokens.Spacing.section
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .fill(DesignTokens.cocoa)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 2)
                    .padding(DesignTokens.Spacing.base)
                VStack(spacing: DesignTokens.Spacing.large) {
                    JournalPageFixture()
                        .frame(width: 190, height: 270)
                        .rotationEffect(.degrees(-1.5))
                    Text("Line up the whole page")
                        .font(TypeScale.label)
                        .foregroundStyle(.white)
                }
            }
            .frame(minHeight: 474)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Journal page positioned inside the camera frame")

            Button {
                photo.capture()
            } label: {
                Label("Use photo", systemImage: AppIcon.camera.rawValue)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var comparisonView: some View {
        ScreenLayout(
            title: "Keep the original",
            subtitle: "Edit the extracted words if needed. The page image stays unchanged.",
            backAction: dismiss,
            bottomInset: DesignTokens.Spacing.section
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                JournalPageFixture()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .padding(DesignTokens.Spacing.base)
                    .background(DesignTokens.cocoa)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Immutable original journal page")
                Text("Original page")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Extracted text")
                    .font(TypeScale.label)
                TextEditor(text: $photo.extractedText)
                    .font(TypeScale.body)
                    .scrollContentBackground(.hidden)
                    .padding(DesignTokens.Spacing.compact)
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
                    .focused($extractionFocused)
            }

            HStack(spacing: DesignTokens.Spacing.compact) {
                Button("Retake") {
                    extractionFocused = false
                    photo.retake()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Keep this page") { openDetail() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(photo.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func dismiss() {
        navigation.dismissPresentedFlow()
    }

    private func openDetail() {
        navigation.dismissPresentedFlow()
        navigation.navigate(to: .journalDetail)
    }
}

private struct JournalPageFixture: View {
    private let lines = [
        "September 5",
        "I keep thinking about senior year.",
        "I wanted the chance to prove I could",
        "have played. That part still feels",
        "unfinished.",
        "The gym helped me get unstuck today.",
        "Then I felt guilty because I had felt",
        "better for a while.",
        "Why does moving forward feel like",
        "I am dismissing what happened?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(Font.custom("AvenirNext-Regular", size: index == 0 ? 8 : 9, relativeTo: .caption2))
                    .italic(index > 0)
                    .foregroundStyle(DesignTokens.cocoa)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .padding(.leading, 28)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DesignTokens.hairline).frame(height: 1)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.Spacing.compact)
        .background(Color.white)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.rose.opacity(0.55))
                .frame(width: 1)
                .padding(.leading, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

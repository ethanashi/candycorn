import SwiftUI

enum AISendDisclosureText {
    static let sendActionName = "Send"
    static let cancelActionName = "Cancel"

    static func characterCount(_ count: Int) -> String {
        let safeCount = max(0, count)
        return "\(safeCount) \(safeCount == 1 ? "character" : "characters")"
    }

    static func imageCount(_ count: Int) -> String {
        let safeCount = max(0, count)
        return "\(safeCount) \(safeCount == 1 ? "image" : "images")"
    }

    static func sourceCounts(_ source: OutgoingSourceDescriptor) -> String {
        var parts = [characterCount(source.characterCount)]
        if source.imageCount > 0 {
            parts.append(imageCount(source.imageCount))
        }
        return parts.joined(separator: " · ")
    }

    static func sourceAccessibilityLabel(_ source: OutgoingSourceDescriptor) -> String {
        "\(source.title). \(sourceCounts(source))"
    }

    static func omittedSources(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "newer journal was" : "newer journals were") not included."
    }
}

struct WhatLeavesDeviceSheet: View {
    let pendingSend: PendingAISend
    let processingState: AIProcessingState
    let onSend: () -> Void
    let onCancel: () -> Void

    init(
        pendingSend: PendingAISend,
        processingState: AIProcessingState,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pendingSend = pendingSend
        self.processingState = processingState
        self.onSend = onSend
        self.onCancel = onCancel
    }

    init(
        pending: PendingAISend,
        processingState: AIProcessingState,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            pendingSend: pending,
            processingState: processingState,
            onSend: onSend,
            onCancel: onCancel
        )
    }

    private var hasSources: Bool { !pendingSend.disclosure.sources.isEmpty }
    private var isProcessing: Bool { processingState == .processing }

    var body: some View {
        VStack(spacing: 0) {
            header
            sourceLedger
            footer
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(isProcessing)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What leaves this device")
                        .font(TypeScale.screenTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pendingSend.disclosure.purpose)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignTokens.Spacing.small)
                RoundActionButton(icon: .close, label: AISendDisclosureText.cancelActionName, action: onCancel)
                    .disabled(isProcessing)
            }
            ProvenanceInline(voice: .candyCorn, text: "Candy Corn suggestion · review every source before sending")
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.medium)
        .padding(.bottom, DesignTokens.blockGap)
    }

    private var sourceLedger: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                if hasSources {
                    V2Card(padding: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(pendingSend.disclosure.sources.enumerated()), id: \.element.id) { index, source in
                                V2ListRow(
                                    icon: source.imageCount > 0 ? .camera : .journal,
                                    title: source.title,
                                    detail: AISendDisclosureText.sourceCounts(source),
                                    trailing: .none,
                                    divider: index > 0
                                )
                                .accessibilityLabel(AISendDisclosureText.sourceAccessibilityLabel(source))
                            }
                        }
                    }
                } else {
                    emptySources
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.bottom, DesignTokens.blockGap)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sources leaving this device")
    }

    private var emptySources: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Nothing is ready to send")
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Add source material, then review this list again.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            disclosureTotals
            processingMessage
            actionButtons
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.base)
        .padding(.bottom, DesignTokens.Spacing.small)
        .background(DesignTokens.surfaceWarm)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DesignTokens.heroRadius, topTrailingRadius: DesignTokens.heroRadius, style: .continuous))
    }

    private var disclosureTotals: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .top, spacing: DesignTokens.blockGap) {
                ledgerLine(title: "Destination", value: pendingSend.disclosure.destination, monospaced: false)
                ledgerLine(title: "Total", value: totalCounts, monospaced: true)
            }
            if let omitted = AISendDisclosureText.omittedSources(pendingSend.disclosure.omittedSourceCount) {
                Text(omitted)
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProvenanceInline(voice: .user, text: "Cloud upload starts only when you tap Send.")
        }
    }

    private var totalCounts: String {
        let summary = pendingSend.disclosure
        var parts = [AISendDisclosureText.characterCount(summary.totalCharacterCount)]
        if summary.totalImageCount > 0 {
            parts.append(AISendDisclosureText.imageCount(summary.totalImageCount))
        }
        return parts.joined(separator: " · ")
    }

    private func ledgerLine(title: String, value: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeScale.metaStrong)
                .foregroundStyle(DesignTokens.cocoaSoft)
            Text(value)
                .font(monospaced ? TypeScale.rowTitleCompact.monospacedDigit() : TypeScale.rowTitleCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var processingMessage: some View {
        AIProcessingStateView(state: processingState)
    }

    @ViewBuilder private var actionButtons: some View {
        switch processingState {
        case .succeeded:
            Button("Close", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Close")
        case .failed:
            Button("Retry send", action: onSend)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasSources)
                .accessibilityLabel("Retry send")
            Button(AISendDisclosureText.cancelActionName, action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(AISendDisclosureText.cancelActionName)
        case .idle, .processing:
            Button(AISendDisclosureText.sendActionName, action: onSend)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasSources || isProcessing)
                .accessibilityLabel(AISendDisclosureText.sendActionName)
            Button(AISendDisclosureText.cancelActionName, action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(AISendDisclosureText.cancelActionName)
        }
    }
}

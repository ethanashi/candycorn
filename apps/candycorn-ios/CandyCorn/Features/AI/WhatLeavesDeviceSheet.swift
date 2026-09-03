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
            Divider().overlay(DesignTokens.hairline)
            sourceLedger
            Divider().overlay(DesignTokens.hairline)
            footer
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(isProcessing)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: .candyCorn, height: 20)
                    .padding(.top, DesignTokens.Spacing.xSmall)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("What leaves this device")
                        .font(TypeScale.pageTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text(pendingSend.disclosure.purpose)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ProvenanceLine(
                provenance: Provenance(
                    voice: .candyCorn,
                    label: "Candy Corn suggestion",
                    detail: "Review every source before sending.",
                    occurredAt: nil,
                    sourceRoute: nil
                ),
                compact: true
            )
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.vertical, DesignTokens.Spacing.large)
    }

    private var sourceLedger: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if hasSources {
                    ForEach(pendingSend.disclosure.sources) { source in
                        sourceRow(source)
                        Divider().overlay(DesignTokens.hairline)
                    }
                } else {
                    emptySources
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sources leaving this device")
    }

    private func sourceRow(_ source: OutgoingSourceDescriptor) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(source.title)
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text(AISendDisclosureText.sourceCounts(source))
                .font(TypeScale.provenance.monospacedDigit())
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .frame(maxWidth: .infinity, minHeight: DesignTokens.hero, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AISendDisclosureText.sourceAccessibilityLabel(source))
    }

    private var emptySources: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Nothing is ready to send")
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Add source material, then review this list again.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            disclosureTotals
            processingMessage
            actionButtons
        }
        .padding(DesignTokens.screenInset)
        .background(DesignTokens.surfaceWarm)
    }

    private var disclosureTotals: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            ledgerLine(title: "Destination", value: pendingSend.disclosure.destination, monospaced: false)
            ledgerLine(
                title: "Total",
                value: totalCounts,
                monospaced: true
            )
            if let omitted = AISendDisclosureText.omittedSources(pendingSend.disclosure.omittedSourceCount) {
                Text(omitted)
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Cloud upload starts only when you tap Send.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            Text(title)
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
            Text(value)
                .font(monospaced ? TypeScale.bodyMedium.monospacedDigit() : TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
        }
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

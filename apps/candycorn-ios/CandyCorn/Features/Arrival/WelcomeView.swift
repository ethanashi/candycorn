import SwiftUI

struct WelcomePage: Equatable, Sendable {
    let title: String
    let copy: String
    let detail: String
    let voice: ProvenanceVoice
}

struct WelcomeFlowState: Equatable, Sendable {
    static let pageCount = 4
    private(set) var pageIndex = 0

    var isFinalPage: Bool { pageIndex == Self.pageCount - 1 }

    mutating func advance() -> Bool {
        guard !isFinalPage else { return true }
        pageIndex = min(pageIndex + 1, Self.pageCount - 1)
        return false
    }

    mutating func goBack() {
        pageIndex = max(pageIndex - 1, 0)
    }
}

struct WelcomeView: View {
    static let pages = [
        WelcomePage(
            title: "Your care, remembered",
            copy: "Keep the threads between journals, goals, and appointments in one private place.",
            detail: "Candy Corn helps you carry what mattered into the next conversation.",
            voice: .user
        ),
        WelcomePage(
            title: "Private by design",
            copy: "Your vault is designed to keep originals and recordings on your device.",
            detail: "No account, no upload, no analytics.",
            voice: .provider
        ),
        WelcomePage(
            title: "AI stays your choice",
            copy: "Turn organization off, or choose when a journal entry is sent to the cloud router.",
            detail: "Your original stays readable even when AI is off.",
            voice: .candyCorn
        ),
        WelcomePage(
            title: "Support, with boundaries",
            copy: "Candy Corn can help you remember and prepare. It is not a therapist or a crisis service.",
            detail: "If you are in immediate danger, contact local emergency services or a crisis line.",
            voice: .provider
        ),
    ]

    @Bindable var navigation: NavigationModel
    @State private var flow = WelcomeFlowState()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let page = Self.pages[flow.pageIndex]
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.large) {
                    progress
                    Spacer(minLength: DesignTokens.Spacing.large)
                    WelcomeMark(voice: page.voice)
                    welcomeCopy(page)
                    Spacer(minLength: DesignTokens.Spacing.large)
                    actions
                }
                .frame(minHeight: max(geometry.size.height - 48, 0))
                .padding(.horizontal, DesignTokens.screenInset)
                .padding(.top, DesignTokens.Spacing.large)
                .padding(.bottom, DesignTokens.Spacing.large)
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: flow.pageIndex)
    }

    private var progress: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= flow.pageIndex ? DesignTokens.orange : DesignTokens.hairline)
                    .frame(height: 4)
            }
        }
        .padding(.top, DesignTokens.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(flow.pageIndex + 1) of \(Self.pages.count)")
    }

    private func welcomeCopy(_ page: WelcomePage) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            Text(page.title)
                .font(TypeScale.display)
                .foregroundStyle(DesignTokens.cocoa)
            Text(page.copy)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
            Divider().overlay(DesignTokens.hairline)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: page.voice, height: 18)
                    .padding(.top, 2)
                Text(page.detail)
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: DesignTokens.Spacing.compact) { actionButtons }
        } else {
            HStack(spacing: DesignTokens.Spacing.compact) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        if flow.pageIndex > 0 {
            Button("Back") { flow.goBack() }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 112)
        } else if !dynamicTypeSize.isAccessibilitySize {
            Color.clear.frame(width: 112, height: DesignTokens.primaryButtonHeight)
                .accessibilityHidden(true)
        }
        Button(flow.isFinalPage ? "Create my vault" : "Continue") {
            if flow.advance() { navigation.completeOnboarding() }
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityHint(flow.isFinalPage ? "Finishes setup and opens Today" : "Shows the next privacy page")
    }
}

private struct WelcomeMark: View {
    let voice: ProvenanceVoice

    var body: some View {
        WelcomeMarkShape()
            .fill(DesignTokens.surfaceWarm)
            .overlay(WelcomeMarkShape().stroke(DesignTokens.hairline, lineWidth: 1))
            .overlay(KernelGlyph(voice: voice, height: 34))
            .frame(width: 88, height: 108)
            .accessibilityHidden(true)
    }
}

private struct WelcomeMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.82))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY * 0.82), control: CGPoint(x: rect.midX, y: rect.maxY * 1.12))
        path.closeSubpath()
        return path
    }
}

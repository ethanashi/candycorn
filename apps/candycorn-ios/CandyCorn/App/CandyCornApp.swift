import SwiftUI

@main
struct CandyCornApp: App {
    @State private var navigation = NavigationModel()
    @State private var bootstrap = RuntimeBootstrap()

    var body: some Scene {
        WindowGroup {
            RuntimeBootstrapView(navigation: navigation, bootstrap: bootstrap)
        }
    }
}

private struct RuntimeBootstrapView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var bootstrap: RuntimeBootstrap
    @State private var isRetrying = false

    var body: some View {
        Group {
            switch bootstrap.state {
            case .idle, .loading:
                loadingView
            case let .failed(message):
                failureView(message: message)
            case let .ready(graph):
                AppRootView(navigation: navigation, state: graph.model)
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .task {
            guard case .idle = bootstrap.state else { return }
            _ = try? await bootstrap.start()
        }
    }

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.base) {
            ProgressView()
            Text("Opening your care vault")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(message: String) -> some View {
        ScreenLayout(title: "Care vault unavailable", subtitle: message) {
            Button(isRetrying ? "Opening" : "Try again") {
                guard !isRetrying else { return }
                isRetrying = true
                Task {
                    _ = try? await bootstrap.start()
                    isRetrying = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isRetrying)
        }
    }
}

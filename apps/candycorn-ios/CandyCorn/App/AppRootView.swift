import SwiftUI

struct AppRootView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var isRetryingLoad = false

    var body: some View {
        Group {
            if navigation.onboardingComplete {
                loadedApplication
            } else {
                WelcomeView(navigation: navigation)
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .task { await state.load() }
        .fullScreenCover(item: presentedFlow) { route in
            RouteDestinationView(route: route, navigation: navigation, state: state)
        }
    }

    @ViewBuilder private var loadedApplication: some View {
        switch state.loadState {
        case .loading:
            VStack(spacing: DesignTokens.Spacing.base) {
                ProgressView()
                Text("Opening your care vault")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ScreenLayout(title: "Care vault unavailable", subtitle: message) {
                Button(isRetryingLoad ? "Opening" : "Try again") {
                    guard !isRetryingLoad else { return }
                    isRetryingLoad = true
                    Task {
                        await state.load()
                        isRetryingLoad = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRetryingLoad)
            }
        case .loaded, .empty:
            applicationShell
        }
    }

    private var applicationShell: some View {
        ZStack {
            tabStack(.goals, path: $navigation.goalsPath)
            tabStack(.journal, path: $navigation.journalPath)
            tabStack(.today, path: $navigation.todayPath)
            tabStack(.history, path: $navigation.historyPath)
            tabStack(.settings, path: $navigation.settingsPath)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if visibleRoute.showsFloatingTabBar {
                FloatingTabBar(selectedTab: tabSelection)
                    .padding(.top, DesignTokens.Spacing.xSmall)
                    .padding(.bottom, DesignTokens.Spacing.xSmall)
                    .background(DesignTokens.canvas)
            }
        }
    }

    private func tabStack(_ tab: AppTab, path: Binding<[Route]>) -> some View {
        NavigationStack(path: path) {
            RouteDestinationView(route: rootRoute(for: tab), navigation: navigation, state: state)
                .navigationDestination(for: Route.self) { route in
                    RouteDestinationView(route: route, navigation: navigation, state: state)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .opacity(navigation.selectedTab == tab ? 1 : 0)
        .allowsHitTesting(navigation.selectedTab == tab)
        .accessibilityHidden(navigation.selectedTab != tab)
    }

    private var visibleRoute: Route {
        let path = navigation.path(for: navigation.selectedTab)
        return path.last ?? rootRoute(for: navigation.selectedTab)
    }

    private func rootRoute(for tab: AppTab) -> Route {
        guard let launchRoute = navigation.launchRoute, launchRoute.tab == tab, !launchRoute.isPresentedFlow else {
            return tab.rootRoute
        }
        return launchRoute
    }

    private var presentedFlow: Binding<Route?> {
        Binding(
            get: { navigation.presentedFlow },
            set: { route in
                if route == nil {
                    navigation.dismissPresentedFlow()
                }
            }
        )
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { navigation.selectedTab },
            set: { tab in
                if navigation.selectedTab == tab {
                    navigation.navigate(to: tab.rootRoute)
                } else {
                    navigation.select(tab)
                }
            }
        )
    }
}

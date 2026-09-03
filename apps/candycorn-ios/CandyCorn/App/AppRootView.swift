import SwiftUI

struct AppRootView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        Group {
            if navigation.onboardingComplete {
                applicationShell
            } else {
                WelcomeView(navigation: navigation)
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .fullScreenCover(item: presentedFlow) { route in
            RouteDestinationView(route: route, navigation: navigation, state: state)
        }
    }

    private var applicationShell: some View {
        ZStack {
            tabStack(.today, path: $navigation.todayPath)
            tabStack(.journal, path: $navigation.journalPath)
            tabStack(.prepare, path: $navigation.preparePath)
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
            RouteDestinationView(route: tab.rootRoute, navigation: navigation, state: state)
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
        let path = path(for: navigation.selectedTab)
        return path.last ?? navigation.selectedTab.rootRoute
    }

    private func path(for tab: AppTab) -> [Route] {
        switch tab {
        case .today: navigation.todayPath
        case .journal: navigation.journalPath
        case .prepare: navigation.preparePath
        case .history: navigation.historyPath
        case .settings: navigation.settingsPath
        }
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
                if tab == .journal,
                   navigation.selectedTab != .journal,
                   navigation.journalPath.isEmpty {
                    navigation.navigate(to: .capture)
                } else {
                    navigation.select(tab)
                }
            }
        )
    }
}

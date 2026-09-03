import SwiftUI

@main
struct CandyCornApp: App {
    @State private var navigation = NavigationModel()
    @State private var state = DemoState()

    var body: some Scene {
        WindowGroup {
            AppRootView(navigation: navigation, state: state)
        }
    }
}

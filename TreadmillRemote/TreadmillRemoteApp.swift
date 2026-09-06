import SwiftUI

@main
struct TreadmillRemoteApp: App {
    @State private var manager = TreadmillManager()

    var body: some Scene {
        WindowGroup {
            DashboardView(manager: manager)
        }
    }
}


import SwiftUI

@main
struct TreadmillRemoteApp: App {
    @State private var manager = TreadmillManager()
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingSplash {
                    SplashView()
                } else {
                    DashboardView(manager: manager)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    isShowingSplash = false
                }
            }
        }
    }
}

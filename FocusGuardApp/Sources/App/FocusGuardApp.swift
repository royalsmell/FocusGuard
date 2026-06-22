import SwiftUI

@main
struct FocusGuardApp: App {
    @State private var model = AppModel()
    @State private var router = AppRouter()
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingCompleted {
                    RootView()
                } else {
                    OnboardingView {
                        onboardingCompleted = true
                    }
                }
            }
            .environment(model)
            .environment(router)
            .task {
                await model.bootstrap()
            }
        }
    }
}


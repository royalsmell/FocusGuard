import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        @Bindable var model = model

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("专注", systemImage: "scope") }
            .tag(AppTab.focus)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(.indigo)
        .sheet(item: $router.presentedSheet) { destination in
            NavigationStack {
                switch destination {
                case .broadcastAuthorization:
                    BroadcastAuthorizationSheet()
                case .durationPresetEditor(let index):
                    DurationPresetEditorView(
                        index: index,
                        initialMinutes: model.durationPreferences.quickMinutes[index]
                    )
                case .providerEditor:
                    ProviderEditorView()
                }
            }
            .presentationDetents(destination == .broadcastAuthorization ? [.medium, .large] : [.large])
        }
        .alert("出现了一点问题", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? String(localized: "未知错误"))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await model.refreshActiveSession()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(AppRouter())
}

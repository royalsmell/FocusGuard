import Observation

enum AppTab: Hashable {
    case focus
    case history
    case settings
}

enum SheetDestination: Identifiable, Hashable {
    case broadcastAuthorization
    case durationPresetEditor(index: Int)
    case providerEditor

    var id: String {
        switch self {
        case .broadcastAuthorization: "broadcast-authorization"
        case .durationPresetEditor(let index): "duration-preset-\(index)"
        case .providerEditor: "provider-editor"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .focus
    var presentedSheet: SheetDestination?
}

import Observation

enum AppTab: Hashable {
    case focus
    case history
    case settings
}

enum SheetDestination: Identifiable, Hashable {
    case broadcastAuthorization
    case durationPresetEditor(index: Int)

    var id: String {
        switch self {
        case .broadcastAuthorization: "broadcast-authorization"
        case .durationPresetEditor(let index): "duration-preset-\(index)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .focus
    var presentedSheet: SheetDestination?
}

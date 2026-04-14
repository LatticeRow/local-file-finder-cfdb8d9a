import Foundation
import Observation

enum RootTab: Hashable {
    case search
    case library
    case settings
}

@Observable
final class AppState {
    var selectedTab: RootTab = .search
    var indexingSummary = "No indexing activity yet."
    var isIndexing = false
    var indexingDetail: String?
}

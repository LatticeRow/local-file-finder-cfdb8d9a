import Foundation
import Observation

@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultItem] = []
    var statusSummary = "The dependency container is wired."

    private let searchRepository: SearchRepository

    init(searchRepository: SearchRepository) {
        self.searchRepository = searchRepository
    }

    func performSearch() {
        results = searchRepository.placeholderResults(matching: query)
    }
}

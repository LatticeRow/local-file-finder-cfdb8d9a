import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResultItem] = []

    private let searchRepository: SearchRepository

    init(searchRepository: SearchRepository) {
        self.searchRepository = searchRepository
    }

    func performSearch() {
        results = searchRepository.search(matching: query)
    }
}

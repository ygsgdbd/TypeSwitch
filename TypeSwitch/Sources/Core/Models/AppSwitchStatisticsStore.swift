import Foundation

struct AppSwitchStatisticsStore: Codable, Hashable, Sendable {
    var counts: [String: Int]

    init(counts: [String: Int] = [:]) {
        self.counts = counts
    }
}

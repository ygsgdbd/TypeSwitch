import Foundation

struct SearchResult<T> {
    let item: T
    let score: Double
    
    static func search<Item>(_ items: [Item], query: String, by keyPath: KeyPath<Item, String>) -> [Item] {
        if query.isEmpty {
            return items
        }
        
        return items
            .map { item in
                let score = FuzzySearch.score(query, in: item[keyPath: keyPath])
                return (item, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
} 
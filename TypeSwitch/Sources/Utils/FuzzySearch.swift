import Foundation

enum FuzzySearch {
    /// 使用 NSPredicate 进行模糊搜索
    static func search(_ query: String, in text: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        
        // 构建搜索条件：
        // 1. CONTAINS[cd] - 包含匹配，不区分大小写和变音符号
        // 2. BEGINSWITH[cd] - 前缀匹配，不区分大小写和变音符号
        let format = "self CONTAINS[cd] %@ OR self BEGINSWITH[cd] %@"
        let predicate = NSPredicate(format: format, query, query)
        return predicate.evaluate(with: text)
    }
    
    /// 计算匹配分数
    static func score(_ query: String, in text: String) -> Double {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return 0 }
        
        // 构建不同的匹配条件并赋予不同的权重
        let conditions: [(predicate: NSPredicate, score: Double)] = [
            // 完全匹配（忽略大小写）
            (NSPredicate(format: "self MATCHES[c] %@", "^" + NSRegularExpression.escapedPattern(for: query) + "$"), 1.0),
            
            // 前缀匹配
            (NSPredicate(format: "self BEGINSWITH[cd] %@", query), 0.9),
            
            // 单词匹配（比如查询"word"可以匹配"someWord"）
            (NSPredicate(format: "self MATCHES[c] %@", ".*\\b" + NSRegularExpression.escapedPattern(for: query) + ".*"), 0.8),
            
            // 包含匹配
            (NSPredicate(format: "self CONTAINS[cd] %@", query), 0.7),
            
            // 首字母匹配（比如"wc"可以匹配"WeChat"）
            (NSPredicate(format: "self MATCHES[c] %@", 
                        query.reduce("^") { $0 + "\\w*" + NSRegularExpression.escapedPattern(for: String($1)) }), 0.6)
        ]
        
        // 返回最高的匹配分数
        for (predicate, score) in conditions {
            if predicate.evaluate(with: text) {
                return score
            }
        }
        
        return 0
    }
} 
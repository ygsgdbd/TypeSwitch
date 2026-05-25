import Foundation

/// 输入法数据模型
struct InputMethod: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
}

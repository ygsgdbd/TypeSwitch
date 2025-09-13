import Defaults
import Foundation

/// Defaults 扩展，统一管理所有应用设置 Keys
extension Defaults.Keys {
    /// 应用输入法设置存储 Key
    /// 存储格式：`[String: String?]`，其中 String 是应用的 bundleId，String? 是输入法 ID（nil 表示不配置）
    static let appInputMethodSettings = Key<[String: String?]>("appInputMethodSettings", default: [:])
    
}

import Foundation
import Logging

/// 日志工具类,提供全局统一的日志记录功能
enum LoggerUtils {
    /// 应用主日志记录器
    private static let mainLogger = Logger(label: "top.ygsgdbd.TypeSwitch")
    
    /// 功能模块日志记录器
    static let autoLaunch = mainLogger.with(category: "AutoLaunch")
    static let inputMethod = mainLogger.with(category: "InputMethod") 
    static let appManagement = mainLogger.with(category: "AppManagement")
    static let settings = mainLogger.with(category: "Settings")
    static let quickSwitch = mainLogger.with(category: "QuickSwitch")
    static let security = mainLogger.with(category: "Security")
    
    /// 创建自定义类别的日志记录器
    /// - Parameter category: 日志类别名称
    /// - Returns: 对应类别的日志记录器
    static func custom(category: String) -> Logger {
        mainLogger.with(category: category)
    }
}

private extension Logger {
    /// 创建带有特定类别的日志记录器
    /// - Parameter category: 日志类别名称
    /// - Returns: 新的日志记录器实例
    func with(category: String) -> Logger {
        var logger = self
        logger[metadataKey: "category"] = .string(category)
        return logger
    }
} 
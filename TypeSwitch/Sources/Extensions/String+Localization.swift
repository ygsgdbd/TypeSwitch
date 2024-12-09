import Foundation

extension String {
    /// 获取本地化字符串
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// 获取带参数的本地化字符串
    /// - Parameter arguments: 格式化参数
    /// - Returns: 格式化后的本地化字符串
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
} 
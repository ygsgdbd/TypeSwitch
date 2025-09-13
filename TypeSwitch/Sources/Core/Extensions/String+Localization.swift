import Foundation

extension String {
    /// 获取本地化字符串
    /// 注意：建议使用 TypeSwitchStrings 枚举替代此方法
    @available(*, deprecated, message: "请使用 TypeSwitchStrings 枚举替代")
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// 获取带参数的本地化字符串
    /// 注意：建议使用 TypeSwitchStrings 枚举替代此方法
    /// - Parameter arguments: 格式化参数
    /// - Returns: 格式化后的本地化字符串
    @available(*, deprecated, message: "请使用 TypeSwitchStrings 枚举替代")
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
} 
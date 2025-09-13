import Foundation
import ServiceManagement

/// 开机启动管理工具
enum LaunchAtLoginManager {
    /// 获取当前开机启动状态
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    /// 设置开机启动状态
    /// - Parameter enabled: 是否启用开机启动
    /// - Returns: 设置是否成功
    @discardableResult
    static func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            print("设置开机启动失败: \(error)")
            return false
        }
    }
}

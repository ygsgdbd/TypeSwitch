import Foundation
import ServiceManagement

/// 开机启动服务类
enum LaunchAtLoginService {
    /// 获取当前开机启动状态
    static var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    /// 设置开机启动状态
    /// - Parameter enabled: 是否启用开机启动
    /// - Returns: 设置后的系统状态
    static func setLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginStatus {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("❌ 设置自动启动失败: \(error.localizedDescription)")
        }
        return status
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

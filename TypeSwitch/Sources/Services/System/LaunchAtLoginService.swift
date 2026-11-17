import Foundation
import ServiceManagement

struct LaunchAtLoginServiceEnvironment {
    var serviceManagementStatus: () -> SMAppService.Status
    var registerMainApp: () throws -> Void
    var unregisterMainApp: () throws -> Void
    var plistURL: URL
    var executableURL: () -> URL?
    var fileManager: FileManager
    var reportError: (String, URL, Error) -> Void
}

/// 开机启动服务类
enum LaunchAtLoginService {
    private static let launchAgentIdentifier = "top.ygsgdbd.TypeSwitch"
    private static let launchAgentPlistName = "\(launchAgentIdentifier).plist"

    private static var liveEnvironment: LaunchAtLoginServiceEnvironment {
        LaunchAtLoginServiceEnvironment(
            serviceManagementStatus: { SMAppService.mainApp.status },
            registerMainApp: { try SMAppService.mainApp.register() },
            unregisterMainApp: { try SMAppService.mainApp.unregister() },
            plistURL: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
                .appendingPathComponent(launchAgentPlistName),
            executableURL: { Bundle.main.executableURL },
            fileManager: .default,
            reportError: { operation, url, error in
                print("❌ \(operation) [\(url.path)]: \(error as NSError)")
            }
        )
    }

    /// 获取当前开机启动状态
    static var status: LaunchAtLoginStatus {
        status(environment: liveEnvironment)
    }

    static func status(environment: LaunchAtLoginServiceEnvironment) -> LaunchAtLoginStatus {
        let fallbackEnabled = fallbackLaunchAgentIsEnabled(environment: environment)

        switch environment.serviceManagementStatus() {
        case .enabled:
            if fallbackEnabled {
                removeFallbackLaunchAgent(environment: environment)
            }
            return .enabled
        case .notRegistered:
            return fallbackEnabled ? .enabled : .disabled
        case .requiresApproval:
            return fallbackEnabled ? .enabled : .requiresApproval
        case .notFound:
            return fallbackEnabled ? .enabled : .unavailable
        @unknown default:
            return fallbackEnabled ? .enabled : .unavailable
        }
    }

    /// 设置开机启动状态
    /// - Parameter enabled: 是否启用开机启动
    /// - Returns: 设置后的系统状态
    static func setLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginStatus {
        setLaunchAtLogin(enabled, environment: liveEnvironment)
    }

    static func setLaunchAtLogin(
        _ enabled: Bool,
        environment: LaunchAtLoginServiceEnvironment
    ) -> LaunchAtLoginStatus {
        if enabled {
            enableLaunchAtLogin(environment: environment)
        } else {
            disableLaunchAtLogin(environment: environment)
        }

        return status(environment: environment)
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private extension LaunchAtLoginService {
    static func enableLaunchAtLogin(environment: LaunchAtLoginServiceEnvironment) {
        if environment.serviceManagementStatus() == .enabled {
            removeFallbackLaunchAgent(environment: environment)
            return
        }

        do {
            try environment.registerMainApp()
            if environment.serviceManagementStatus() == .enabled {
                removeFallbackLaunchAgent(environment: environment)
                return
            }
        } catch {
            print("❌ 设置自动启动失败: \(error.localizedDescription)")
            if environment.serviceManagementStatus() == .enabled {
                removeFallbackLaunchAgent(environment: environment)
                return
            }
        }

        do {
            try installFallbackLaunchAgent(environment: environment)
        } catch {
            environment.reportError("写入 LaunchAgent 配置失败", environment.plistURL, error)
        }
    }

    static func disableLaunchAtLogin(environment: LaunchAtLoginServiceEnvironment) {
        do {
            try environment.unregisterMainApp()
        } catch {
            print("❌ 关闭自动启动失败: \(error.localizedDescription)")
        }

        removeFallbackLaunchAgent(environment: environment)
    }

    static func fallbackLaunchAgentIsEnabled(environment: LaunchAtLoginServiceEnvironment) -> Bool {
        guard
            let executableURL = environment.executableURL(),
            let arguments = fallbackProgramArguments(environment: environment),
            let executablePath = arguments.first
        else {
            return false
        }

        return normalizedPath(executablePath) == normalizedPath(executableURL.path)
    }

    static func fallbackProgramArguments(environment: LaunchAtLoginServiceEnvironment) -> [String]? {
        do {
            let data = try Data(contentsOf: environment.plistURL)
            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
                let arguments = plist["ProgramArguments"] as? [String],
                !arguments.isEmpty
            else {
                throw CocoaError(.propertyListReadCorrupt)
            }

            return arguments
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            environment.reportError("读取 LaunchAgent 配置失败", environment.plistURL, error)
            return nil
        }
    }

    static func installFallbackLaunchAgent(environment: LaunchAtLoginServiceEnvironment) throws {
        guard let executableURL = environment.executableURL() else {
            throw NSError(
                domain: "TypeSwitch.LaunchAtLogin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot resolve TypeSwitch executable path"]
            )
        }

        try environment.fileManager.createDirectory(
            at: environment.plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": launchAgentIdentifier,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        // launchd 会在下次登录时加载配置；当前应用无需重新启动或卸载。
        try data.write(to: environment.plistURL, options: .atomic)
    }

    static func removeFallbackLaunchAgent(environment: LaunchAtLoginServiceEnvironment) {
        do {
            try environment.fileManager.removeItem(at: environment.plistURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            environment.reportError("删除 LaunchAgent 配置失败", environment.plistURL, error)
        }
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

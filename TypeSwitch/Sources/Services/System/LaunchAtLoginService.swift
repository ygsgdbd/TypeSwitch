import Foundation
import ServiceManagement

struct LaunchAtLoginServiceEnvironment {
    var serviceManagementStatus: () -> SMAppService.Status
    var registerMainApp: () throws -> Void
    var unregisterMainApp: () throws -> Void
    var plistURL: URL
    var executableURL: () -> URL?
    var runLaunchctl: ([String]) throws -> Void
    var userID: () -> uid_t
    var fileManager: FileManager
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
            runLaunchctl: runLaunchctl,
            userID: { getuid() },
            fileManager: .default
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
            print("❌ 设置 LaunchAgent 自动启动失败: \(error.localizedDescription)")
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
            let arguments = fallbackProgramArguments(
                plistURL: environment.plistURL,
                fileManager: environment.fileManager
            ),
            let executablePath = arguments.first
        else {
            return false
        }

        return normalizedPath(executablePath) == normalizedPath(executableURL.path)
    }

    static func fallbackProgramArguments(
        plistURL: URL,
        fileManager: FileManager
    ) -> [String]? {
        guard
            fileManager.fileExists(atPath: plistURL.path),
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        return plist["ProgramArguments"] as? [String]
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

        try data.write(to: environment.plistURL, options: .atomic)

        let domain = "gui/\(environment.userID())"
        try? environment.runLaunchctl(["bootout", domain, environment.plistURL.path])
        try environment.runLaunchctl(["bootstrap", domain, environment.plistURL.path])
    }

    static func removeFallbackLaunchAgent(environment: LaunchAtLoginServiceEnvironment) {
        let domain = "gui/\(environment.userID())"
        try? environment.runLaunchctl(["bootout", domain, environment.plistURL.path])
        try? environment.fileManager.removeItem(at: environment.plistURL)
    }

    static func runLaunchctl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "TypeSwitch.LaunchAtLogin",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "launchctl \(arguments.joined(separator: " ")) failed"]
            )
        }
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

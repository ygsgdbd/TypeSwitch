import AppKit
import Foundation

/// 应用列表服务类
/// 负责获取运行中的应用信息
enum AppListService {
    @MainActor
    static func fetchRunningApps() -> [AppInfo] {
        let runningApps = NSWorkspace.shared.runningApplications

        var uniqueApps: [String: AppInfo] = [:]
        for runningApp in runningApps {
            guard let appInfo = trackedRunningApplicationInfo(for: runningApp) else {
                continue
            }
            uniqueApps[appInfo.bundleId] = appInfo
        }

        return uniqueApps.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @MainActor
    static func frontmostApplication() -> AppInfo? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return trackedRunningApplicationInfo(for: frontmostApplication)
    }

    @MainActor
    static func trackedRunningApplicationInfo(for runningApplication: NSRunningApplication) -> AppInfo? {
        guard shouldTrackRunningApplication(
            activationPolicy: runningApplication.activationPolicy,
            bundleIdentifier: runningApplication.bundleIdentifier,
            bundleURL: runningApplication.bundleURL
        ) else {
            return nil
        }
        return AppInfo(runningApplication: runningApplication)
    }

    static func shouldTrackRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> Bool {
        guard activationPolicy == .regular,
              let bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              let bundleURL
        else {
            return false
        }

        return bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}

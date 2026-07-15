import AppKit
import Foundation
import SwifterSwift

/// 应用列表服务类
/// 负责获取运行中的应用信息，以及首次迁移时的定向扫描
enum AppListService {
    /// 应用搜索目录列表
    /// 按优先级排序：用户应用目录 > 系统应用目录
    static let applicationDirs = [
        "/Applications", // 用户安装的应用
        "~/Applications", // 用户主目录下的应用
        "/System/Applications", // 系统应用
    ].map { NSString(string: $0).expandingTildeInPath }

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

    /// 从指定 bundleId 集合中查找已安装应用，仅用于旧配置迁移
    static func fetchApps(matching bundleIds: Set<String>) async -> [String: AppInfo] {
        guard !bundleIds.isEmpty else { return [:] }

        return await withTaskGroup(of: [String: AppInfo].self) { group in
            for dir in applicationDirs {
                group.addTask {
                    scanAppsInDirectory(dir, matching: bundleIds)
                }
            }

            var matchedApps: [String: AppInfo] = [:]
            for await dirApps in group {
                for (bundleId, appInfo) in dirApps where matchedApps[bundleId] == nil {
                    matchedApps[bundleId] = appInfo
                }
            }

            return matchedApps
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

    /// 从指定目录获取匹配的应用信息
    private static func scanAppsInDirectory(_ dir: String, matching bundleIds: Set<String>) -> [String: AppInfo] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: dir),
              fileManager.isReadableFile(atPath: dir)
        else {
            print("⚠️ 无法访问目录: \(dir)")
            return [:]
        }

        let dirURL = URL(fileURLWithPath: dir)
        guard let enumerator = fileManager.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("⚠️ 无法创建目录枚举器: \(dir)")
            return [:]
        }

        var matchedApps: [String: AppInfo] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileManager.isReadableFile(atPath: fileURL.path) else { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isApplicationKey])
                guard resourceValues.isApplication == true else { continue }

                if let app = AppInfo(bundleURL: fileURL),
                   bundleIds.contains(app.bundleId),
                   app.bundleId != Bundle.main.bundleIdentifier
                {
                    matchedApps[app.bundleId] = app
                    if matchedApps.count == bundleIds.count {
                        break
                    }
                }
            } catch {
                print("⚠️ 处理应用时出错: \(fileURL.path) - \(error.localizedDescription)")
                continue
            }
        }

        return matchedApps
    }
}

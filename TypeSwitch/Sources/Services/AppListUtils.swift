import Foundation
import SwiftUI
import SwifterSwift

enum AppListUtils {
    static let applicationDirs = [
        "/Applications",
        "~/Applications",
        "/System/Applications"
    ].map { NSString(string: $0).expandingTildeInPath }
    
    /// 获取当前运行中的应用（仅返回在已安装应用列表中的应用）
    static func fetchRunningApps() async -> [AppInfo] {
        // 先获取已安装应用列表
        let installedApps = await fetchInstalledApps()
        let installedBundleIds = Set(installedApps.map { $0.bundleId })
        
        // 获取运行中的应用
        let runningApps = NSWorkspace.shared.runningApplications
        
        return runningApps.compactMap { runningApp in
            guard let bundleId = runningApp.bundleIdentifier,
                  let bundleURL = runningApp.bundleURL,
                  let bundle = Bundle(url: bundleURL),
                  let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                            bundle.infoDictionary?["CFBundleName"] as? String else {
                return nil
            }
            
            // 只保留在已安装应用列表中的应用
            guard installedBundleIds.contains(bundleId) else {
                return nil
            }
            
            return AppInfo(bundleId: bundleId, name: name, iconPath: bundleURL.path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    static func fetchInstalledApps() async -> [AppInfo] {
        await withTaskGroup(of: [AppInfo].self) { group in
            for dir in applicationDirs {
                group.addTask {
                    await fetchAppsInDirectory(dir)
                }
            }
            
            var apps: [AppInfo] = []
            for await dirApps in group {
                apps.append(contentsOf: dirApps)
            }
            
            var uniqueApps: Set<AppInfo> = []
            return apps.filter { uniqueApps.insert($0).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    
    private static func fetchAppsInDirectory(_ dir: String) async -> [AppInfo] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: dir),
              fileManager.isReadableFile(atPath: dir) else {
            return []
        }
        
        let dirURL = URL(fileURLWithPath: dir)
        guard let enumerator = fileManager.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        var dirApps: [AppInfo] = []
        
        // 将枚举器转换为数组以避免异步上下文问题
        let urls = Array(enumerator.compactMap { $0 as? URL })
        
        for fileURL in urls {
            guard fileManager.isReadableFile(atPath: fileURL.path) else { continue }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isApplicationKey])
                guard resourceValues.isApplication == true else { continue }
                
                guard let bundle = Bundle(url: fileURL),
                      let bundleId = bundle.bundleIdentifier,
                      let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                                bundle.infoDictionary?["CFBundleName"] as? String else {
                    continue
                }
                
                let app = AppInfo(bundleId: bundleId, name: name, iconPath: fileURL.path)
                dirApps.append(app)
            } catch {
                continue
            }
        }
        
        return dirApps
    }
}

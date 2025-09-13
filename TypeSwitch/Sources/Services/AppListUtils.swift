import Foundation
import SwiftUI
import SwifterSwift

/// 应用列表工具类
/// 负责获取系统中已安装和正在运行的应用信息
enum AppListUtils {
    /// 应用搜索目录列表
    /// 按优先级排序：用户应用目录 > 系统应用目录
    static let applicationDirs = [
        "/Applications",        // 用户安装的应用
        "~/Applications",       // 用户主目录下的应用
        "/System/Applications"  // 系统应用
    ].map { NSString(string: $0).expandingTildeInPath }
    
    /// 获取当前运行中的应用（仅返回在已安装应用列表中的应用）
    static func fetchRunningApps() async -> [AppInfo] {
        // 先获取已安装应用列表（已经过滤掉了自己）
        let installedApps = await fetchInstalledApps()
        let installedBundleIds = Set(installedApps.map { $0.bundleId })
        
        // 获取运行中的应用
        let runningApps = NSWorkspace.shared.runningApplications
        
        return runningApps.compactMap { runningApp in
            guard let bundleURL = runningApp.bundleURL else { return nil }
            
            // 只保留在已安装应用列表中的应用（已安装应用列表已经过滤掉了自己）
            guard let bundleId = runningApp.bundleIdentifier,
                  installedBundleIds.contains(bundleId) else {
                return nil
            }
            
            return createAppInfo(from: bundleURL)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    /// 获取系统中已安装的应用列表
    /// - Returns: 已安装的应用信息数组，按名称排序，已过滤掉TypeSwitch应用本身
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
                .filter { $0.bundleId != Bundle.main.bundleIdentifier } // 过滤掉自己（TypeSwitch应用）
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    
    /// 从指定目录获取应用信息（使用流式处理优化内存使用）
    private static func fetchAppsInDirectory(_ dir: String) async -> [AppInfo] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: dir),
              fileManager.isReadableFile(atPath: dir) else {
            print("⚠️ 无法访问目录: \(dir)")
            return []
        }
        
        let dirURL = URL(fileURLWithPath: dir)
        guard let enumerator = fileManager.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { 
            print("⚠️ 无法创建目录枚举器: \(dir)")
            return [] 
        }
        
        var dirApps: [AppInfo] = []
        
        // 流式处理，避免一次性加载所有URL到内存
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileManager.isReadableFile(atPath: fileURL.path) else { continue }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isApplicationKey])
                guard resourceValues.isApplication == true else { continue }
                
                if let app = createAppInfo(from: fileURL) {
                    dirApps.append(app)
                }
            } catch {
                print("⚠️ 处理应用时出错: \(fileURL.path) - \(error.localizedDescription)")
                continue
            }
        }
        
        return dirApps
    }
    
    /// 从Bundle URL创建AppInfo对象
    /// - Parameter fileURL: 应用的Bundle URL
    /// - Returns: 创建成功的AppInfo对象，失败时返回nil
    private static func createAppInfo(from fileURL: URL) -> AppInfo? {
        guard let bundle = Bundle(url: fileURL),
              let bundleId = bundle.bundleIdentifier,
              let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                        bundle.infoDictionary?["CFBundleName"] as? String else {
            return nil
        }
        
        return AppInfo(bundleId: bundleId, name: name, iconPath: fileURL.path)
    }
}

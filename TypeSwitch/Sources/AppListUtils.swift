import Foundation
import SwiftUI

enum AppListUtils {
    static let applicationDirs = [
        "/Applications",
        "~/Applications",
        "/System/Applications"
    ].map { NSString(string: $0).expandingTildeInPath }
    
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
            
            let uniqueApps = Dictionary(grouping: apps, by: \.bundleId)
                .values
                .compactMap { $0.first }
            
            return uniqueApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    
    private static func fetchAppsInDirectory(_ dir: String) async -> [AppInfo] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: dir),
              fileManager.isReadableFile(atPath: dir) else {
            return []
        }
        
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        var dirApps: [AppInfo] = []
        for case let fileURL as URL in enumerator {
            guard fileManager.isReadableFile(atPath: fileURL.path) else { continue }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isApplicationKey])
                guard resourceValues.isApplication == true,
                      let bundle = Bundle(url: fileURL),
                      let bundleId = bundle.bundleIdentifier,
                      let name = bundle.infoDictionary?["CFBundleName"] as? String
                else { continue }
                
                dirApps.append(AppInfo(bundleId: bundleId, name: name, iconPath: fileURL.path))
            } catch {
                continue
            }
        }
        return dirApps
    }
} 
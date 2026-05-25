import AppKit
import Foundation
import SwiftUI

/// 应用信息数据模型
struct AppInfo: Identifiable, Sendable, Hashable {
    let bundleId: String
    let name: String
    let path: String?
    
    var id: String { bundleId }
    
    @MainActor
    var icon: Image {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return Image(systemName: "app.dashed")
        }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
    }
    
    init(bundleId: String, name: String, path: String?) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
    }

    init?(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL),
              let bundleId = bundle.bundleIdentifier,
              let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                bundle.infoDictionary?["CFBundleName"] as? String else {
            return nil
        }

        self.init(bundleId: bundleId, name: name, path: bundleURL.path)
    }

    @MainActor
    init?(runningApplication: NSRunningApplication) {
        guard let bundleId = runningApplication.bundleIdentifier else {
            return nil
        }

        let path = runningApplication.bundleURL?.path
        let bundleName = runningApplication.bundleURL.flatMap {
            Bundle(url: $0)?.infoDictionary?["CFBundleDisplayName"] as? String ??
                Bundle(url: $0)?.infoDictionary?["CFBundleName"] as? String
        }
        let name = bundleName ?? runningApplication.localizedName ?? bundleId

        self.init(bundleId: bundleId, name: name, path: path)
    }
}

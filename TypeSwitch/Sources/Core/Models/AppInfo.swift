import Foundation
import SwiftUI

/// 应用信息数据模型
struct AppInfo: Identifiable, Sendable, Hashable {
    let bundleId: String
    let name: String
    private let iconPath: String
    
    var id: String { bundleId }
    
    @MainActor
    var icon: Image {
        Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
    }
    
    init(bundleId: String, name: String, iconPath: String) {
        self.bundleId = bundleId
        self.name = name
        self.iconPath = iconPath
    }
}

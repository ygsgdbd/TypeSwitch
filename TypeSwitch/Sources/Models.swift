import Foundation
import SwiftUI

struct InputMethod: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct InputSourceProperties {
    let sourceID: String
    let sourceType: String
    let localizedName: String
    let isSelectable: Bool
    let isEnabled: Bool
}

enum AppSection: String, CaseIterable {
    case running = "正在运行"
    case others = "其他应用"
}

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
    
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
    }
} 
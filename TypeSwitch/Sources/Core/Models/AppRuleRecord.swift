import Foundation

struct AppRuleRecord: Identifiable, Codable, Hashable, Sendable {
    let bundleId: String
    var lastKnownPath: String?
    var lastKnownName: String
    var strategy: InputMethodStrategy
    var createdAt: Date
    var updatedAt: Date

    var id: String { bundleId }

    var isAvailable: Bool {
        guard let lastKnownPath else { return false }
        return FileManager.default.fileExists(atPath: lastKnownPath)
    }

    var appInfo: AppInfo {
        AppInfo(
            bundleId: bundleId,
            name: lastKnownName,
            path: isAvailable ? lastKnownPath : nil
        )
    }
}

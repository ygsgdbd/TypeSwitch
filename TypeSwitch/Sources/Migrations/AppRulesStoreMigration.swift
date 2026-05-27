import ComposableArchitecture
import Foundation

// Migration: v0 -> v1
// Added: 2026-05-25
enum AppRulesStoreMigration {
    enum PrepareResult: Equatable, Sendable {
        case currentStorePresent
        case noStoreFound
    }

    static func prepareStore(
        currentStoreURL: URL = .appRulesStoreURL,
        fileManager: FileManager = .default
    ) throws -> PrepareResult {
        try fileManager.createDirectory(
            at: currentStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if fileManager.fileExists(atPath: currentStoreURL.path) {
            return .currentStorePresent
        }

        return .noStoreFound
    }
}

struct AppRulesStoreMigrationClient {
    var prepareStore: @Sendable () async -> AppRulesStoreMigration.PrepareResult
}

extension AppRulesStoreMigrationClient: DependencyKey {
    static let liveValue = Self(
        prepareStore: {
            do {
                return try AppRulesStoreMigration.prepareStore()
            } catch {
                print("⚠️ 规则存储迁移失败: \(error.localizedDescription)")
                return .noStoreFound
            }
        }
    )

    static let testValue = Self(
        prepareStore: { .noStoreFound }
    )
}

extension DependencyValues {
    var appRulesStoreMigrationClient: AppRulesStoreMigrationClient {
        get { self[AppRulesStoreMigrationClient.self] }
        set { self[AppRulesStoreMigrationClient.self] = newValue }
    }
}

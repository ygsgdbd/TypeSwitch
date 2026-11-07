import ComposableArchitecture
import Foundation
import Sharing
@testable import TypeSwitch
import XCTest

@MainActor
final class AppAvailabilityTests: XCTestCase {
    func testMenuSnapshotRefreshesOnlyOnNewPresentation() async {
        let rule = makeRule("editor", path: "/apps/Editor.app")
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: [rule.bundleId: rule]))
        )) {
            AppFeature()
        }
        store.dependencies.appAvailabilityClient.pathExists = { $0 == "/apps/Editor.app" }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [rule.lastKnownPath!])
        }
        store.dependencies.appAvailabilityClient.pathExists = { _ in
            XCTFail("Reading or presenting an already open menu must not probe again")
            return false
        }
        XCTAssertEqual(store.state.configuredApps.map(\.bundleId), [rule.bundleId])
        XCTAssertEqual(store.state.configuredApps.first?.path, rule.lastKnownPath)
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
        await store.send(.menuPresented)
        await store.send(.menuDismissed) {
            $0.isMenuPresented = false
            $0.menuStrategiesAtPresentation = [:]
        }
        store.dependencies.appAvailabilityClient.pathExists = { _ in false }
        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot()
        }
        XCTAssertTrue(store.state.configuredApps.isEmpty)
        XCTAssertEqual(store.state.unavailableApps.map(\.bundleId), [rule.bundleId])
        XCTAssertNil(store.state.unavailableApps.first?.path)
    }

    func testNewRunningAppRemainsAvailableWhileMenuIsOpen() async {
        let timestamp = Date(timeIntervalSince1970: 10)
        let path = "/apps/Editor.app"
        let app = AppInfo(bundleId: "editor", name: "Editor", path: path)
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore())
        )) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.appAvailabilityClient.pathExists = { $0 == path }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
        }
        await store.send(.response(.runningApps([app]))) {
            $0.runningApps = [app]
            $0.$appRulesStore.withLock {
                $0.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: path,
                    lastKnownName: app.name,
                    strategy: .none,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            }
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [path])
        }
        XCTAssertEqual(store.state.runningUnconfiguredMenuItems.map(\.bundleId), [app.bundleId])
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
    }

    func testChangedRunningAppPathRemainsAvailableWhileMenuIsOpen() async {
        let rule = makeRule("editor", path: "/apps/Editor.app")
        let newPath = "/moved/Editor.app"
        let app = AppInfo(bundleId: rule.bundleId, name: rule.lastKnownName, path: newPath)
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: [rule.bundleId: rule]))
        )) {
            AppFeature()
        }
        store.dependencies.date = .constant(rule.updatedAt)
        store.dependencies.appAvailabilityClient.pathExists = { _ in true }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [rule.lastKnownPath!])
        }
        await store.send(.response(.runningApps([app]))) {
            $0.runningApps = [app]
            $0.$appRulesStore.withLock { $0.rules[rule.bundleId]?.lastKnownPath = newPath }
            $0.appAvailability.availablePaths.insert(newPath)
        }
        XCTAssertEqual(store.state.configuredApps.map(\.bundleId), [rule.bundleId])
        XCTAssertEqual(store.state.configuredApps.first?.path, newPath)
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
    }

    func testActivationRefreshesAvailabilityForChangedPath() async {
        let rule = makeRule("editor", path: "/apps/Editor.app", strategy: .none)
        let newPath = "/moved/Editor.app"
        let app = AppInfo(bundleId: rule.bundleId, name: rule.lastKnownName, path: newPath)
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: [rule.bundleId: rule]))
        )) {
            AppFeature()
        }
        store.dependencies.date = .constant(rule.updatedAt)
        store.dependencies.appAvailabilityClient.pathExists = { _ in true }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [rule.lastKnownPath!])
        }
        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = rule.bundleId
            $0.$appRulesStore.withLock { $0.rules[rule.bundleId]?.lastKnownPath = newPath }
            $0.appAvailability.availablePaths.insert(newPath)
        }
        XCTAssertEqual(store.state.currentAppMenuItem?.path, newPath)
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
    }

    func testNameAndStrategyChangesDoNotProbeUnchangedPaths() async {
        let rule = makeRule("editor", path: "/apps/Editor.app")
        let app = AppInfo(bundleId: rule.bundleId, name: "Renamed Editor", path: rule.lastKnownPath)
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: [rule.bundleId: rule]))
        )) {
            AppFeature()
        }
        store.dependencies.date = .constant(rule.updatedAt)
        store.dependencies.appAvailabilityClient.pathExists = { _ in true }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [rule.lastKnownPath!])
        }
        store.dependencies.appAvailabilityClient.pathExists = { _ in
            XCTFail("Unchanged paths must not be probed again")
            return false
        }
        await store.send(.response(.runningApps([app]))) {
            $0.runningApps = [app]
            $0.$appRulesStore.withLock { $0.rules[rule.bundleId]?.lastKnownName = app.name }
        }
        await store.send(.view(.setStrategy(bundleId: rule.bundleId, strategy: .none))) {
            $0.$appRulesStore.withLock { $0.rules[rule.bundleId]?.strategy = .none }
        }
        XCTAssertEqual(store.state.configuredApps.first?.strategy, rule.strategy)
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
    }

    func testChangedPathRechecksPreviouslyAvailablePath() async {
        let rule = makeRule("editor", path: "/apps/Editor.app")
        let otherRule = makeRule("other", path: "/moved/Editor.app")
        let newPath = otherRule.lastKnownPath!
        let app = AppInfo(bundleId: rule.bundleId, name: rule.lastKnownName, path: newPath)
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: [rule.bundleId: rule, otherRule.bundleId: otherRule]))
        )) {
            AppFeature()
        }
        store.dependencies.date = .constant(rule.updatedAt)
        store.dependencies.appAvailabilityClient.pathExists = { _ in true }

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [rule.bundleId: rule.strategy, otherRule.bundleId: otherRule.strategy]
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [rule.lastKnownPath!, newPath])
        }
        store.dependencies.appAvailabilityClient.pathExists = { path in
            XCTAssertEqual(path, newPath)
            return false
        }
        await store.send(.response(.runningApps([app]))) {
            $0.runningApps = [app]
            $0.$appRulesStore.withLock { $0.rules[rule.bundleId]?.lastKnownPath = newPath }
            $0.appAvailability.availablePaths.remove(newPath)
        }
        XCTAssertTrue(store.state.configuredApps.isEmpty)
        XCTAssertEqual(Set(store.state.unavailableApps.map(\.bundleId)), [rule.bundleId, otherRule.bundleId])
    }

    func testCleanupRechecksRestoredAndRemovedAppsAndPreservesIgnoredRules() async {
        let restored = makeRule("restored", path: "/apps/Restored.app")
        let removed = makeRule("removed", path: "/apps/Removed.app")
        let ignored = makeRule("ignored", path: "/apps/Ignored.app", strategy: .ignored)
        let noPath = makeRule("no-path", path: nil)
        let rules = [restored, removed, ignored, noPath]
        let store = TestStore(initialState: AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore(rules: Dictionary(uniqueKeysWithValues: rules.map { ($0.bundleId, $0) })))
        )) {
            AppFeature()
        }
        store.dependencies.appAvailabilityClient.pathExists = { $0 == "/apps/Removed.app" }
        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = Dictionary(uniqueKeysWithValues: rules.map { ($0.bundleId, $0.strategy) })
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [removed.lastKnownPath!])
        }
        XCTAssertEqual(Set(store.state.unavailableApps.map(\.bundleId)), [restored.bundleId, noPath.bundleId])

        store.dependencies.appAvailabilityClient.pathExists = { $0 == "/apps/Restored.app" }
        await store.send(.view(.removeUnavailableRulesTapped)) {
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: [restored.lastKnownPath!])
            $0.$appRulesStore.withLock {
                $0.rules = [restored.bundleId: restored, ignored.bundleId: ignored]
            }
        }
        XCTAssertEqual(store.state.configuredApps.map(\.bundleId), [restored.bundleId])
        XCTAssertTrue(store.state.unavailableApps.isEmpty)
    }

    func testSnapshotDoesNotReuseAvailabilityForChangedPath() {
        var rule = makeRule("editor", path: "/apps/Editor.app")
        let snapshot = AppAvailabilityClient(pathExists: { _ in true }).snapshot(for: [rule])
        XCTAssertEqual(snapshot.appInfo(for: rule).path, rule.lastKnownPath)
        rule.lastKnownPath = "/moved/Editor.app"
        XCTAssertFalse(snapshot.isAvailable(rule))
        XCTAssertNil(snapshot.appInfo(for: rule).path)
        XCTAssertEqual(snapshot.appInfo(for: rule).name, rule.lastKnownName)
        rule.lastKnownPath = nil
        XCTAssertFalse(snapshot.isAvailable(rule))
    }

    func testLiveAdapterObservesDirectoryCreationAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rule = makeRule("editor", path: directory.path)
        let client = AppAvailabilityClient.liveValue
        XCTAssertFalse(client.snapshot(for: [rule]).isAvailable(rule))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(client.snapshot(for: [rule]).isAvailable(rule))
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(client.snapshot(for: [rule]).isAvailable(rule))
    }

    private func makeRule(
        _ bundleId: String,
        path: String?,
        strategy: InputMethodStrategy = .fixed(inputMethodId: "ime.en")
    ) -> AppRuleRecord {
        AppRuleRecord(
            bundleId: bundleId,
            lastKnownPath: path,
            lastKnownName: bundleId,
            strategy: strategy,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}

import AppKit
import ComposableArchitecture
import Foundation
@testable import TypeSwitch
import XCTest

@MainActor
final class AppFeatureTests: XCTestCase {
    func testStartupLoadsConfiguredFrontmostAppWithoutSwitching() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethods = [InputMethod(id: "ime.en", name: "English")]
        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = makeRule(app: app, strategy: .fixed(inputMethodId: "ime.en"))
        }
        let store = TestStore(initialState: initialState) { AppFeature() }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.workspaceClient.frontmostApplication = { app }
        store.dependencies.workspaceClient.runningApplications = { [app] }
        store.dependencies.workspaceClient.events = { AsyncStream { $0.finish() } }
        store.dependencies.inputMethodClient.fetchInputMethods = { inputMethods }
        store.dependencies.inputMethodClient.availabilityChanges = { AsyncStream { $0.finish() } }
        store.dependencies.inputMethodClient.selectionChanges = { AsyncStream { $0.finish() } }
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Startup records the frontmost app without attempting a switch")
            return "ime.other"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("Startup must not reapply the configured rule")
        }

        await store.send(.task) {
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await store.receive(.response(.launchAtLoginLoaded(.disabled)))
        await store.receive(.switching(.response(.frontmostApplicationLoaded(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(refreshID: 0, result: .success(inputMethods))))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = inputMethods
        }
        await store.receive(.response(.runningApps([app]))) {
            $0.runningApps = [app]
        }
        await store.finish()
        XCTAssertEqual(store.state.currentFrontmostBundleId, app.bundleId)
        XCTAssertEqual(store.state.inputMethods, inputMethods)
        XCTAssertNil(store.state.lastSwitchAttempt)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 0)
    }

    func testRuleEditsAndSwitchResultsShareStorageAcrossModules() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let timestamp = Date(timeIntervalSince1970: 10)
        let recorder = SwitchRecorder()
        var initialState = AppFeature.State(
            inputMethodCatalogStatus: .ready,
            inputMethods: [InputMethod(id: "ime.en", name: "English")]
        )
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = makeRule(app: app, strategy: .none, timestamp: timestamp)
        }
        let store = TestStore(initialState: initialState) { AppFeature() }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { await recorder.record($0) }

        await store.send(.view(.setStrategy(bundleId: app.bundleId, strategy: .fixed(inputMethodId: "ime.en")))) {
            $0.$appRulesStore.withLock { $0.rules[app.bundleId]?.strategy = .fixed(inputMethodId: "ime.en") }
        }
        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                attemptID: 0,
                bundleId: app.bundleId,
                inputMethodId: "ime.en",
                inputMethodName: "English"
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(attemptID: 0, outcome: .switched)))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: "ime.en",
                inputMethodName: "English",
                outcome: .switched,
                ruleSource: .app,
                timestamp: timestamp
            )
            $0.$appSwitchStatisticsStore.withLock { $0.counts[app.bundleId] = 1 }
        }
        let switchedIds = await recorder.values
        XCTAssertEqual(switchedIds, ["ime.en"])
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 1)
        XCTAssertEqual(store.state.currentAppMenuItem?.strategy, .fixed(inputMethodId: "ime.en"))

        await store.send(.view(.clearSwitchStatisticsTapped)) {
            $0.$appSwitchStatisticsStore.withLock { $0.counts = [:] }
        }
        XCTAssertTrue(store.state.switching.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testFrontmostAndRunningAppsCreateDefaultRule() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let app = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)

        await store.send(.switching(.response(.frontmostApplicationLoaded(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.$appRulesStore.withLock {
                $0.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: app.path,
                    lastKnownName: app.name,
                    strategy: .none,
                    createdAt: now,
                    updatedAt: now
                )
            }
        }

        await store.send(.response(.launchAtLoginLoaded(.enabled))) {
            $0.launchAtLoginStatus = .enabled
        }

        await store.send(.response(.runningApps([app]))) {
            $0.runningApps = [app]
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
    }

    func testLaunchAtLoginLoadedRequiresApprovalKeepsToggleOn() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.response(.launchAtLoginLoaded(.requiresApproval))) {
            $0.launchAtLoginStatus = .requiresApproval
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
        XCTAssertTrue(store.state.launchAtLoginRequiresApproval)
    }

    func testSetLaunchAtLoginRefreshesRequiresApprovalStatus() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.launchAtLoginClient.setEnabled = { enabled in
            XCTAssertTrue(enabled)
            return .requiresApproval
        }

        await store.send(.view(.setLaunchAtLogin(true))) {
            $0.launchAtLoginStatus = .enabled
        }
        await store.receive(.response(.launchAtLoginLoaded(.requiresApproval))) {
            $0.launchAtLoginStatus = .requiresApproval
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
        XCTAssertTrue(store.state.launchAtLoginRequiresApproval)
    }

    func testSetStrategyUpdatesUpdatedAtButKeepsCreatedAt() async {
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let newUpdatedAt = Date(timeIntervalSince1970: 300)
        let bundleId = "com.test.editor"

        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Editor.app",
                lastKnownName: "Editor",
                strategy: .none,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(newUpdatedAt)

        await store.send(.view(.setStrategy(bundleId: bundleId, strategy: .fixed(inputMethodId: "ime.en")))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[bundleId] else { return }
                rule.strategy = .fixed(inputMethodId: "ime.en")
                rule.updatedAt = newUpdatedAt
                $0.rules[bundleId] = rule
            }
        }

        let rule = store.state.appRules[bundleId]
        XCTAssertEqual(rule?.createdAt, createdAt)
        XCTAssertEqual(rule?.updatedAt, newUpdatedAt)
    }

    func testSetFallbackStrategyDoesNotModifyAppRules() async {
        let bundleId = "com.test.editor"
        let appRule = AppRuleRecord(
            bundleId: bundleId,
            lastKnownPath: "/Applications/Editor.app",
            lastKnownName: "Editor",
            strategy: .fixed(inputMethodId: "ime.en"),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = appRule
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.view(.setFallbackStrategy(.fixed(inputMethodId: "ime.abc")))) {
            $0.$fallbackRuleStore.withLock {
                $0.strategy = .fixed(inputMethodId: "ime.abc")
            }
        }

        XCTAssertEqual(store.state.appRules, [bundleId: appRule])
    }

    func testSetFallbackStrategyCoercesFollowLastToNone() async {
        var initialState = AppFeature.State()
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: "ime.en")
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.view(.setFallbackStrategy(.followLast(lastInputMethodId: "ime.jp")))) {
            $0.$fallbackRuleStore.withLock {
                $0.strategy = .none
            }
        }

        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testSetFallbackStrategyCoercesIgnoredToNone() async {
        var initialState = AppFeature.State()
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: "ime.en")
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.view(.setFallbackStrategy(.ignored))) {
            $0.$fallbackRuleStore.withLock {
                $0.strategy = .none
            }
        }

        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testActivatedAppSwitchesFixedInputMethodWhenNeeded() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English",
                outcome: .switched,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [targetInputMethod])
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 1)
    }

    func testActivatedAppSkipsStatisticsWhenInputMethodAlreadySelected() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { targetInputMethod }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            XCTFail("Already selected input method should not switch again")
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .alreadySelected
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English",
                outcome: .alreadySelected,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 0)
    }

    func testActivatedAppSkipsStatisticsWhenSwitchFails() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            throw TestError.failed
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .failed(.diagnostic(from: TestError.failed))
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English",
                outcome: .failed(.diagnostic(from: TestError.failed)),
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 0)
    }

    func testInputMethodRefreshFailurePreservesLastSuccessfulList() async {
        let inputMethods = [InputMethod(id: "ime.en", name: "English")]
        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = inputMethods
        initialState.$appRulesStore.withLock {
            $0.rules["com.test.editor"] = AppRuleRecord(
                bundleId: "com.test.editor",
                lastKnownPath: "/Applications/Editor.app",
                lastKnownName: "Editor",
                strategy: .fixed(inputMethodId: "ime.deleted"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }
        XCTAssertTrue(initialState.hasMissingInputMethodRules)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.inputMethodClient.fetchInputMethods = {
            throw InputMethodService.InputMethodError.failedToFetchInputMethods
        }

        await store.send(.switching(.system(.inputMethodAvailabilityChanged))) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .failure(.failedToFetchInputMethods)
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .failed(.failedToFetchInputMethods)
        }

        XCTAssertEqual(store.state.switching.inputMethods, inputMethods)
        XCTAssertEqual(store.state.inputMethodDiagnostic?.kind, .catalogFailed)
        XCTAssertFalse(store.state.hasMissingInputMethodRules)

        await store.send(.view(.removeMissingInputMethodRulesTapped))
        XCTAssertEqual(
            store.state.appRules["com.test.editor"]?.strategy,
            .fixed(inputMethodId: "ime.deleted")
        )
    }

    func testReloadInputMethodsRecoversFromFailure() async {
        let inputMethods = [InputMethod(id: "ime.en", name: "English")]
        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .failed(.failedToFetchInputMethods)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.inputMethodClient.fetchInputMethods = { inputMethods }

        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success(inputMethods)
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = inputMethods
        }

        XCTAssertNil(store.state.inputMethodDiagnostic)
    }

    func testStaleInputMethodRefreshDoesNotOverrideLatestResult() async {
        let latestInputMethods = [InputMethod(id: "ime.en", name: "English")]
        let refreshGate = InputMethodRefreshGate(latestInputMethods: latestInputMethods)
        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .failed(.failedToFetchInputMethods)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.inputMethodClient.fetchInputMethods = {
            try await refreshGate.value()
        }

        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await refreshGate.waitUntilFirstStarted()

        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.nextInputMethodRefreshID = 2
            $0.switching.pendingInputMethodRefreshID = 1
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 1,
            result: .success(latestInputMethods)
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = latestInputMethods
        }

        await refreshGate.resumeFirst(with: .failure(.failedToFetchInputMethods))
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .failure(.failedToFetchInputMethods)
        ))))

        XCTAssertEqual(store.state.switching.inputMethodCatalogStatus, .ready)
        XCTAssertEqual(store.state.switching.inputMethods, latestInputMethods)
    }

    func testFailedInputMethodRefreshPreservesCatalogRetryAfterReactivationUntilReloadSucceeds() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = AppFeature.State()
        initialState.switching.nextInputMethodRefreshID = 1
        initialState.switching.pendingInputMethodRefreshID = 0
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: inputMethod.id)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.inputMethodClient.fetchInputMethods = { [inputMethod] }
        store.dependencies.workspaceClient.frontmostApplication = { app }
        store.dependencies.inputMethodClient.currentInputMethodId = { inputMethod.id }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = true
            $0.$appRulesStore.withLock {
                $0.rules[app.bundleId] = self.makeRule(app: app, strategy: .none)
            }
        }
        await store.send(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .failure(.failedToFetchInputMethods)
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .failed(.failedToFetchInputMethods)
        }
        await store.send(.system(.workspaceEvent(.activated(app))))
        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 2
            $0.switching.pendingInputMethodRefreshID = 1
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 1,
            result: .success([inputMethod])
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = [inputMethod]
            $0.switching.nextFrontmostRetryID = 1
            $0.switching.pendingFrontmostRetryID = 0
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.receive(.switching(.response(.frontmostApplicationRetried(retryID: 0, appInfo: app)))) {
            $0.switching.pendingFrontmostRetryID = nil
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name,
                ruleSource: .fallback
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .alreadySelected
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name,
                outcome: .alreadySelected,
                ruleSource: .fallback,
                timestamp: timestamp
            )
        }
    }

    func testFailedCatalogRetriesOnlyFinalFrontmostConfiguredAppAfterReloadSucceeds() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let firstInputMethod = InputMethod(id: "ime.first", name: "First Input Method")
        let secondInputMethod = InputMethod(id: "ime.second", name: "Second Input Method")
        let timestamp = Date(timeIntervalSince1970: 10)
        let recorder = SwitchRecorder()
        let switchGate = InputMethodSwitchGate()

        var initialState = AppFeature.State(
            inputMethodCatalogStatus: .failed(.failedToFetchInputMethods)
        )
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = makeRule(
                app: firstApp,
                strategy: .fixed(inputMethodId: firstInputMethod.id)
            )
            $0.rules[secondApp.bundleId] = makeRule(
                app: secondApp,
                strategy: .followLast(lastInputMethodId: secondInputMethod.id)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.inputMethodClient.fetchInputMethods = {
            [firstInputMethod, secondInputMethod]
        }
        store.dependencies.workspaceClient.frontmostApplication = { secondApp }
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            await switchGate.wait()
        }

        await store.send(.system(.workspaceEvent(.activated(firstApp)))) {
            $0.switching.currentFrontmostBundleId = firstApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.system(.workspaceEvent(.activated(secondApp)))) {
            $0.switching.currentFrontmostBundleId = secondApp.bundleId
        }
        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([firstInputMethod, secondInputMethod])
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = [firstInputMethod, secondInputMethod]
            $0.switching.nextFrontmostRetryID = 1
            $0.switching.pendingFrontmostRetryID = 0
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.receive(.switching(.response(.frontmostApplicationRetried(retryID: 0, appInfo: secondApp)))) {
            $0.switching.pendingFrontmostRetryID = nil
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: secondApp.name,
                bundleId: secondApp.bundleId,
                inputMethodId: secondInputMethod.id,
                inputMethodName: secondInputMethod.name
            )
        }
        await switchGate.waitUntilStarted()
        await switchGate.resume()
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: secondApp.name,
                bundleId: secondApp.bundleId,
                inputMethodId: secondInputMethod.id,
                inputMethodName: secondInputMethod.name,
                outcome: .switched,
                ruleSource: .app,
                timestamp: timestamp
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[secondApp.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [secondInputMethod.id])
    }

    func testFailedCatalogClearsRetryForAppsWithoutExplicitTarget() async {
        let configuredApp = AppInfo(
            bundleId: "com.test.configured",
            name: "Configured",
            path: "/Applications/Configured.app"
        )
        let unconfiguredApp = AppInfo(
            bundleId: "com.test.unconfigured",
            name: "Unconfigured",
            path: "/Applications/Unconfigured.app"
        )
        let ignoredApp = AppInfo(
            bundleId: "com.test.ignored",
            name: "Ignored",
            path: "/Applications/Ignored.app"
        )
        let followLastApp = AppInfo(
            bundleId: "com.test.follow-last",
            name: "Follow Last",
            path: "/Applications/Follow Last.app"
        )
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = AppFeature.State(
            inputMethodCatalogStatus: .failed(.failedToFetchInputMethods)
        )
        initialState.$appRulesStore.withLock {
            $0.rules[configuredApp.bundleId] = makeRule(
                app: configuredApp,
                strategy: .fixed(inputMethodId: inputMethod.id)
            )
            $0.rules[ignoredApp.bundleId] = makeRule(app: ignoredApp, strategy: .ignored)
            $0.rules[followLastApp.bundleId] = makeRule(
                app: followLastApp,
                strategy: .followLast(lastInputMethodId: nil)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.inputMethodClient.fetchInputMethods = { [inputMethod] }
        store.dependencies.workspaceClient.frontmostApplication = {
            XCTFail("A cleared catalog retry must not query the frontmost application")
            return followLastApp
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("An app without an explicit target must not trigger a compensated switch")
        }

        await store.send(.system(.workspaceEvent(.activated(configuredApp)))) {
            $0.switching.currentFrontmostBundleId = configuredApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.system(.workspaceEvent(.activated(unconfiguredApp)))) {
            $0.switching.currentFrontmostBundleId = unconfiguredApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = false
            $0.$appRulesStore.withLock {
                $0.rules[unconfiguredApp.bundleId] = self.makeRule(app: unconfiguredApp, strategy: .none)
            }
        }
        await store.send(.system(.workspaceEvent(.activated(configuredApp)))) {
            $0.switching.currentFrontmostBundleId = configuredApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.system(.workspaceEvent(.activated(ignoredApp)))) {
            $0.switching.currentFrontmostBundleId = ignoredApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.send(.system(.workspaceEvent(.activated(configuredApp)))) {
            $0.switching.currentFrontmostBundleId = configuredApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.system(.workspaceEvent(.activated(followLastApp)))) {
            $0.switching.currentFrontmostBundleId = followLastApp.bundleId
            $0.switching.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.send(.view(.reloadInputMethodsTapped)) {
            $0.switching.inputMethodCatalogStatus = .loading
            $0.switching.nextInputMethodRefreshID = 1
            $0.switching.pendingInputMethodRefreshID = 0
        }
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
            $0.switching.inputMethods = [inputMethod]
        }
    }

    func testRetryCurrentAppUsesFreshFrontmostApplication() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)
        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [inputMethod]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: inputMethod.id),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = { app }
        store.dependencies.inputMethodClient.currentInputMethodId = { inputMethod.id }

        await store.send(.view(.retryCurrentAppTapped)) {
            $0.switching.nextFrontmostRetryID = 1
            $0.switching.pendingFrontmostRetryID = 0
        }
        await store.receive(.switching(.response(.frontmostApplicationRetried(retryID: 0, appInfo: app)))) {
            $0.switching.pendingFrontmostRetryID = nil
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .alreadySelected
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name,
                outcome: .alreadySelected,
                ruleSource: .app,
                timestamp: timestamp
            )
        }
    }

    func testRetryCurrentAppIgnoresSnapshotAfterNewActivation() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let frontmostGate = FrontmostApplicationGate(appInfo: firstApp)
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = firstApp.bundleId
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = AppRuleRecord(
                bundleId: firstApp.bundleId,
                lastKnownPath: firstApp.path,
                lastKnownName: firstApp.name,
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: timestamp,
                updatedAt: timestamp
            )
            $0.rules[secondApp.bundleId] = AppRuleRecord(
                bundleId: secondApp.bundleId,
                lastKnownPath: secondApp.path,
                lastKnownName: secondApp.name,
                strategy: .none,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = {
            await frontmostGate.value()
        }

        await store.send(.view(.retryCurrentAppTapped)) {
            $0.switching.nextFrontmostRetryID = 1
            $0.switching.pendingFrontmostRetryID = 0
        }
        await frontmostGate.waitUntilStarted()

        await store.send(.system(.workspaceEvent(.activated(secondApp)))) {
            $0.switching.currentFrontmostBundleId = secondApp.bundleId
            $0.switching.pendingFrontmostRetryID = nil
        }

        await frontmostGate.resume()
        await store.receive(.switching(.response(.frontmostApplicationRetried(retryID: 0, appInfo: firstApp))))

        XCTAssertEqual(store.state.switching.currentFrontmostBundleId, secondApp.bundleId)
    }

    func testRetryCurrentAppContinuesAfterUnrelatedAppTerminates() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let unrelatedApp = AppInfo(bundleId: "com.test.other", name: "Other", path: "/Applications/Other.app")
        let frontmostGate = FrontmostApplicationGate(appInfo: secondApp)
        let runningApps = [firstApp, secondApp, unrelatedApp]
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = firstApp.bundleId
        initialState.runningApps = runningApps
        initialState.$appRulesStore.withLock { store in
            for app in runningApps {
                store.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: app.path,
                    lastKnownName: app.name,
                    strategy: .none,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            }
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = {
            await frontmostGate.value()
        }
        store.dependencies.workspaceClient.runningApplications = { [firstApp, secondApp] }

        await store.send(.view(.retryCurrentAppTapped)) {
            $0.switching.nextFrontmostRetryID = 1
            $0.switching.pendingFrontmostRetryID = 0
        }
        await frontmostGate.waitUntilStarted()

        await store.send(.system(.workspaceEvent(.terminated(bundleId: unrelatedApp.bundleId))))
        await store.receive(.response(.runningApps([firstApp, secondApp]))) {
            $0.runningApps = [firstApp, secondApp]
        }

        await frontmostGate.resume()
        await store.receive(.switching(.response(.frontmostApplicationRetried(retryID: 0, appInfo: secondApp)))) {
            $0.switching.currentFrontmostBundleId = secondApp.bundleId
            $0.switching.pendingFrontmostRetryID = nil
        }

        XCTAssertEqual(store.state.switching.currentFrontmostBundleId, secondApp.bundleId)
    }

    func testSelectionNotificationPreventsFailureFromOverwritingConfirmedSuccess() async {
        let timestamp = Date(timeIntervalSince1970: 10)
        let bundleId = "com.test.editor"
        let inputMethodId = "ime.en"
        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.switching.pendingProgrammaticSwitch = .init(
            appName: "Editor",
            bundleId: bundleId,
            inputMethodId: inputMethodId,
            inputMethodName: "English"
        )
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Editor.app",
                lastKnownName: "Editor",
                strategy: .fixed(inputMethodId: inputMethodId),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)

        await store.send(.switching(.system(.inputMethodSelectedChanged(inputMethodId)))) {
            $0.switching.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }
        await store.send(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .failed(.failedToVerifyInputMethod(inputMethodId))
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: "Editor",
                bundleId: bundleId,
                inputMethodId: inputMethodId,
                inputMethodName: "English",
                outcome: .alreadySelected,
                ruleSource: .app,
                timestamp: timestamp
            )
        }

        XCTAssertNil(store.state.inputMethodDiagnostic)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testVerificationFailureProducesSwitchDiagnostic() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            throw InputMethodService.InputMethodError.failedToVerifyInputMethod(targetInputMethod)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await store.receive(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .failed(.failedToVerifyInputMethod(targetInputMethod))
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English",
                outcome: .failed(.failedToVerifyInputMethod(targetInputMethod)),
                ruleSource: .app,
                timestamp: timestamp
            )
        }

        XCTAssertEqual(store.state.inputMethodDiagnostic?.kind, .switchFailed)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testSwitchDiagnosticDisappearsWhenRuleNoLongerTargetsFailedInputMethod() {
        let bundleId = "com.test.browser"
        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = bundleId
        state.switching.lastSwitchAttempt = .init(
            appName: "Browser",
            bundleId: bundleId,
            inputMethodId: "ime.en",
            inputMethodName: "English",
            outcome: .failed(.failedToSwitchInputMethod("ime.en")),
            ruleSource: .app,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        state.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Browser.app",
                lastKnownName: "Browser",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.inputMethodDiagnostic?.kind, .switchFailed)

        state.$appRulesStore.withLock {
            $0.rules[bundleId]?.strategy = .none
        }
        XCTAssertNil(state.inputMethodDiagnostic)

        state.$appRulesStore.withLock {
            $0.rules[bundleId]?.strategy = .fixed(inputMethodId: "ime.zh")
        }
        XCTAssertNil(state.inputMethodDiagnostic)

        state.$appRulesStore.withLock {
            $0.rules[bundleId]?.strategy = .ignored
        }
        XCTAssertNil(state.inputMethodDiagnostic)
    }

    func testIgnoringCurrentAppCancelsPendingProgrammaticSwitch() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let updateDate = Date(timeIntervalSince1970: 20)
        let lookupGate = InputMethodLookupGate(firstValue: "ime.other")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(updateDate)
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await lookupGate.waitForFirstCall()

        await store.send(.view(.ignoreAppTapped(app))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[app.bundleId] else { return }
                rule.strategyBeforeIgnoring = .fixed(inputMethodId: targetInputMethod)
                rule.strategy = .ignored
                rule.updatedAt = updateDate
                $0.rules[app.bundleId] = rule
            }
        }

        await lookupGate.resumeFirst()
        await store.finish()

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testTerminatingCurrentAppCancelsSwitchAfterSelectionNotification() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let switchGate = InputMethodSwitchGate()
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.runningApps = [app]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            await switchGate.wait()
        }
        store.dependencies.workspaceClient.runningApplications = { [] }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.nextSwitchAttemptID = 1
            $0.switching.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await switchGate.waitUntilStarted()

        await store.send(.switching(.system(.inputMethodSelectedChanged(targetInputMethod)))) {
            $0.switching.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }
        await store.send(.system(.workspaceEvent(.terminated(bundleId: app.bundleId)))) {
            $0.switching.currentFrontmostBundleId = nil
            $0.switching.pendingProgrammaticSwitch = nil
        }
        await store.receive(.response(.runningApps([]))) {
            $0.runningApps = []
        }

        await switchGate.resume()
        await store.finish()

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [targetInputMethod])
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testActivatedAppSkipsSwitchWhenFallbackRuleIsLegacyFollowLast() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethods = [InputMethod(id: "ime.jp", name: "Japanese")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: "ime.jp")
        }
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Legacy fallback follow-last should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testActivatedAppSkipsMissingFallbackInputMethod() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [InputMethod(id: "ime.en", name: "English")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: "ime.deleted")
        }
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Missing fallback input methods should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: "ime.deleted",
                inputMethodName: nil,
                outcome: .failed(.inputMethodNotFound("ime.deleted")),
                ruleSource: .fallback,
                timestamp: Date(timeIntervalSince1970: 10)
            )
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(store.state.fallbackStrategy, .fixed(inputMethodId: "ime.deleted"))
    }

    func testUnavailableAppIsExcludedFromConfiguredApps() async {
        let missingPath = "/tmp/\(UUID().uuidString)"

        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [InputMethod(id: "ime.en", name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules["com.test.missing"] = AppRuleRecord(
                bundleId: "com.test.missing",
                lastKnownPath: missingPath,
                lastKnownName: "Missing",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertTrue(initialState.configuredApps.isEmpty)
        XCTAssertEqual(initialState.unavailableApps.map(\.bundleId), ["com.test.missing"])
    }

    func testFollowLastAvailableInputMethodShowsCurrentInputMethodInMenuOption() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.inputMethods = [InputMethod(id: "ime.zh", name: "Pinyin")]
        state.runningApps = [app]
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .followLast(lastInputMethodId: "ime.zh"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(
            state.runningConfiguredMenuItems.first?.followLastOptionLabel,
            TypeSwitchStrings.InputMethod.followLastWithInputMethod("Pinyin")
        )
    }

    func testFallbackNoneShowsNoAutomaticSwitchLabel() {
        let state = AppFeature.State()

        XCTAssertEqual(
            state.fallbackSelectedLabel,
            TypeSwitchStrings.InputMethod.fallbackDefaultOption
        )
    }

    func testAppDefaultOptionShowsNoAutomaticSwitchFallbackRule() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.runningApps = [app]

        XCTAssertEqual(
            state.runningUnconfiguredMenuItems.first?.defaultOptionLabel,
            TypeSwitchStrings.InputMethod.appDefaultFallbackNoneOption
        )
    }

    func testAppDefaultOptionShowsFixedFallbackRule() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.inputMethods = [InputMethod(id: "ime.zh", name: "Pinyin")]
        state.runningApps = [app]
        state.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: "ime.zh")
        }

        XCTAssertEqual(
            state.runningUnconfiguredMenuItems.first?.defaultOptionLabel,
            TypeSwitchStrings.InputMethod.appDefaultWithInputMethod("Pinyin")
        )
    }

    func testRunningAppsSplitConfiguredAndUnconfiguredMenuItems() {
        let browser = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let chat = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")
        let notes = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")
        let terminal = AppInfo(bundleId: "com.test.terminal", name: "Terminal", path: "/Applications/Terminal.app")

        var state = AppFeature.State()
        state.runningApps = [browser, chat, notes, terminal]
        state.$appRulesStore.withLock {
            $0.rules[browser.bundleId] = AppRuleRecord(
                bundleId: browser.bundleId,
                lastKnownPath: browser.path,
                lastKnownName: browser.name,
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules[chat.bundleId] = AppRuleRecord(
                bundleId: chat.bundleId,
                lastKnownPath: chat.path,
                lastKnownName: chat.name,
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules[terminal.bundleId] = AppRuleRecord(
                bundleId: terminal.bundleId,
                lastKnownPath: terminal.path,
                lastKnownName: terminal.name,
                strategy: .followLast(lastInputMethodId: nil),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.runningConfiguredMenuItems.map(\.bundleId), [
            browser.bundleId,
            terminal.bundleId,
        ])
        XCTAssertEqual(state.runningUnconfiguredMenuItems.map(\.bundleId), [
            chat.bundleId,
            notes.bundleId,
        ])
    }

    func testIgnoredAppOnlyAppearsInIgnoredMenu() {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = app.bundleId
        state.runningApps = [app]
        state.$appSwitchStatisticsStore.withLock {
            $0.counts[app.bundleId] = 4
        }
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: nil,
                lastKnownName: app.name,
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertNil(state.currentAppMenuItem)
        XCTAssertTrue(state.runningConfiguredMenuItems.isEmpty)
        XCTAssertTrue(state.runningUnconfiguredMenuItems.isEmpty)
        XCTAssertTrue(state.configuredApps.isEmpty)
        XCTAssertTrue(state.unavailableApps.isEmpty)
        XCTAssertTrue(state.switchStatisticsItems.isEmpty)
        XCTAssertEqual(state.totalSuccessfulSwitchCount, 0)
        XCTAssertEqual(state.ignoredAppsForMenu.map(\.bundleId), [app.bundleId])
        XCTAssertEqual(state.appSwitchStatisticsStore.counts[app.bundleId], 4)
    }

    func testIgnoreAndRestoreAppPreservesPreviousStrategy() async {
        let strategies: [InputMethodStrategy] = [
            .none,
            .fixed(inputMethodId: "ime.en"),
            .followLast(lastInputMethodId: "ime.zh"),
        ]

        for (index, strategy) in strategies.enumerated() {
            let app = AppInfo(
                bundleId: "com.test.app.\(index)",
                name: "App \(index)",
                path: "/Applications/App\(index).app"
            )
            var initialState = AppFeature.State()
            initialState.$appRulesStore.withLock {
                $0.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: app.path,
                    lastKnownName: app.name,
                    strategy: strategy,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            }

            let store = TestStore(initialState: initialState) {
                AppFeature()
            }
            store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

            await store.send(.view(.ignoreAppTapped(app))) {
                $0.$appRulesStore.withLock {
                    guard var rule = $0.rules[app.bundleId] else { return }
                    rule.strategy = .ignored
                    rule.strategyBeforeIgnoring = strategy
                    rule.updatedAt = Date(timeIntervalSince1970: 20)
                    $0.rules[app.bundleId] = rule
                }
            }

            await store.send(.view(.ignoreAppTapped(app)))

            await store.send(.view(.restoreIgnoredAppTapped(bundleId: app.bundleId))) {
                $0.$appRulesStore.withLock {
                    guard var rule = $0.rules[app.bundleId] else { return }
                    rule.strategy = strategy
                    rule.strategyBeforeIgnoring = nil
                    rule.updatedAt = Date(timeIntervalSince1970: 20)
                    $0.rules[app.bundleId] = rule
                }
            }

            await store.send(.view(.restoreIgnoredAppTapped(bundleId: app.bundleId)))
        }
    }

    func testIgnoringUnavailableAppPreservesLastKnownPath() async {
        let bundleId = "com.test.missing"
        let lastKnownPath = "/Applications/Missing.app"

        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: lastKnownPath,
                lastKnownName: "Missing",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

        await store.send(.view(.ignoreAppTapped(
            AppInfo(bundleId: bundleId, name: "Missing", path: nil)
        ))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[bundleId] else { return }
                rule.strategyBeforeIgnoring = .fixed(inputMethodId: "ime.en")
                rule.strategy = .ignored
                rule.updatedAt = Date(timeIntervalSince1970: 20)
                $0.rules[bundleId] = rule
            }
        }

        XCTAssertEqual(store.state.appRules[bundleId]?.lastKnownPath, lastKnownPath)
    }

    func testRestoreAllIgnoredAppsUsesSavedStrategyAndLegacyFallback() async {
        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules["com.test.fixed"] = AppRuleRecord(
                bundleId: "com.test.fixed",
                lastKnownPath: nil,
                lastKnownName: "Fixed",
                strategy: .ignored,
                strategyBeforeIgnoring: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules["com.test.follow-last"] = AppRuleRecord(
                bundleId: "com.test.follow-last",
                lastKnownPath: nil,
                lastKnownName: "Follow Last",
                strategy: .ignored,
                strategyBeforeIgnoring: .followLast(lastInputMethodId: "ime.zh"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules["com.test.legacy"] = AppRuleRecord(
                bundleId: "com.test.legacy",
                lastKnownPath: nil,
                lastKnownName: "Legacy",
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

        await store.send(.view(.restoreAllIgnoredAppsTapped)) {
            $0.$appRulesStore.withLock {
                let restoredStrategies: [String: InputMethodStrategy] = [
                    "com.test.fixed": .fixed(inputMethodId: "ime.en"),
                    "com.test.follow-last": .followLast(lastInputMethodId: "ime.zh"),
                    "com.test.legacy": .none,
                ]
                for (bundleId, strategy) in restoredStrategies {
                    guard var rule = $0.rules[bundleId] else { continue }
                    rule.strategy = strategy
                    rule.strategyBeforeIgnoring = nil
                    rule.updatedAt = Date(timeIntervalSince1970: 20)
                    $0.rules[bundleId] = rule
                }
            }
        }
    }

    func testMenuPresentationFreezesIgnoredVisibilityUntilDismissed() async {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var initialState = AppFeature.State()
        initialState.runningApps = [app]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [:]
        }
        await store.send(.view(.ignoreAppTapped(app))) {
            $0.$appRulesStore.withLock {
                $0.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: app.path,
                    lastKnownName: app.name,
                    strategy: .ignored,
                    strategyBeforeIgnoring: .some(.none),
                    createdAt: Date(timeIntervalSince1970: 20),
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            }
        }

        XCTAssertEqual(store.state.runningUnconfiguredMenuItems.map(\.bundleId), [app.bundleId])
        XCTAssertTrue(store.state.ignoredAppsForMenu.isEmpty)

        await store.send(.menuDismissed) {
            $0.isMenuPresented = false
            $0.menuStrategiesAtPresentation = [:]
        }

        XCTAssertTrue(store.state.runningUnconfiguredMenuItems.isEmpty)
        XCTAssertEqual(store.state.ignoredAppsForMenu.map(\.bundleId), [app.bundleId])

        await store.send(.menuPresented) {
            $0.isMenuPresented = true
            $0.menuStrategiesAtPresentation = [app.bundleId: .ignored]
        }
        await store.send(.view(.restoreIgnoredAppTapped(bundleId: app.bundleId))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[app.bundleId] else { return }
                rule.strategy = .none
                rule.strategyBeforeIgnoring = nil
                rule.updatedAt = Date(timeIntervalSince1970: 20)
                $0.rules[app.bundleId] = rule
            }
        }

        XCTAssertEqual(store.state.ignoredAppsForMenu.map(\.bundleId), [app.bundleId])
        XCTAssertTrue(store.state.runningUnconfiguredMenuItems.isEmpty)

        await store.send(.menuDismissed) {
            $0.isMenuPresented = false
            $0.menuStrategiesAtPresentation = [:]
        }

        XCTAssertTrue(store.state.ignoredAppsForMenu.isEmpty)
        XCTAssertEqual(store.state.runningUnconfiguredMenuItems.map(\.bundleId), [app.bundleId])
    }

    func testRemoveUnavailableRulesPreservesIgnoredApps() async {
        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules["ignored"] = AppRuleRecord(
                bundleId: "ignored",
                lastKnownPath: nil,
                lastKnownName: "Ignored",
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules["missing"] = AppRuleRecord(
                bundleId: "missing",
                lastKnownPath: nil,
                lastKnownName: "Missing",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.view(.removeUnavailableRulesTapped)) {
            $0.$appRulesStore.withLock {
                $0.rules = ["ignored": $0.rules["ignored"]!]
            }
        }
    }

    func testMenuTrackingNotificationOnlyAcceptsRootMenu() {
        let rootMenu = NSMenu()
        let submenu = NSMenu()
        let submenuItem = NSMenuItem(title: "Submenu", action: nil, keyEquivalent: "")
        rootMenu.addItem(submenuItem)
        rootMenu.setSubmenu(submenu, for: submenuItem)

        XCTAssertTrue(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didBeginTrackingNotification, object: rootMenu)
            )
        )
        XCTAssertFalse(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didEndTrackingNotification, object: submenu)
            )
        )
        XCTAssertFalse(
            MenuBarView.isRootMenuTrackingNotification(
                Notification(name: NSMenu.didEndTrackingNotification, object: NSObject())
            )
        )
    }

    func testCurrentAppMenuItemIsSeparatedFromRunningApps() {
        let chat = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")
        let notes = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = chat.bundleId
        state.runningApps = [chat, notes]

        XCTAssertEqual(state.currentAppMenuItem?.bundleId, chat.bundleId)
        XCTAssertTrue(state.runningConfiguredMenuItems.isEmpty)
        XCTAssertEqual(state.runningUnconfiguredMenuItems.map(\.bundleId), [notes.bundleId])
    }

    func testMenuBarIconUsesKeyboardWithoutFrontmostApp() {
        let state = AppFeature.State()

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard")
        XCTAssertEqual(state.menuBarAccessibilityLabel, "TypeSwitch")
    }

    func testMenuBarIconUsesUnconfiguredIconForFrontmostAppWithoutRule() {
        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = "com.test.chat"

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard.badge.ellipsis")
        XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityUnconfigured)
    }

    func testMenuBarIconUsesUnconfiguredIconForFrontmostAppWithNoneStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = app.bundleId
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard.badge.ellipsis")
        XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityUnconfigured)
    }

    func testMenuBarIconUsesKeyboardForFrontmostAppWithFixedStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = app.bundleId
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: "ime.zh"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard")
        XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityConfigured)
    }

    func testMenuBarIconUsesKeyboardForFrontmostAppWithFollowLastStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = app.bundleId
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .followLast(lastInputMethodId: nil),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard")
        XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityConfigured)
    }

    func testMenuBarAccessibilityLabelDescribesIgnoredFrontmostApp() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.switching.currentFrontmostBundleId = app.bundleId
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard")
        XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityIgnored)
    }

    func testMenuBarAccessibilityLabelUsesWarningWithoutFrontmostApp() {
        var catalogEmptyState = AppFeature.State()
        catalogEmptyState.switching.inputMethodCatalogStatus = .ready

        var catalogFailedState = AppFeature.State()
        catalogFailedState.switching.inputMethodCatalogStatus = .failed(.failedToFetchInputMethods)

        for state in [catalogEmptyState, catalogFailedState] {
            XCTAssertNotNil(state.inputMethodDiagnostic)
            XCTAssertEqual(state.menuBarAccessibilityLabel, TypeSwitchStrings.Menu.accessibilityWarning)
        }
    }

    func testMenuBarAccessibilityLabelCombinesWarningWithFrontmostAppStatus() {
        let bundleId = "com.test.chat"
        var state = AppFeature.State(
            currentFrontmostBundleId: bundleId,
            inputMethodCatalogStatus: .failed(.failedToFetchInputMethods)
        )
        state.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Chat.app",
                lastKnownName: "Chat",
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(
            state.menuBarAccessibilityLabel,
            TypeSwitchStrings.Menu.accessibilityWarningUnconfigured
        )

        state.$appRulesStore.withLock {
            $0.rules[bundleId]?.strategy = .fixed(inputMethodId: "ime.zh")
        }
        XCTAssertEqual(
            state.menuBarAccessibilityLabel,
            TypeSwitchStrings.Menu.accessibilityWarningConfigured
        )

        state.$appRulesStore.withLock {
            $0.rules[bundleId]?.strategy = .ignored
        }
        XCTAssertEqual(
            state.menuBarAccessibilityLabel,
            TypeSwitchStrings.Menu.accessibilityWarningIgnored
        )
    }

    func testFollowLastWithoutRecordShowsEmptyMenuOption() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.runningApps = [app]
        state.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .followLast(lastInputMethodId: nil),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        XCTAssertEqual(
            state.runningConfiguredMenuItems.first?.followLastOptionLabel,
            TypeSwitchStrings.InputMethod.followLastEmptyOption
        )

        let unrecordedApp = AppInfo(
            bundleId: "com.test.unrecorded-chat",
            name: "Chat",
            path: "/Applications/Chat.app"
        )

        var defaultState = AppFeature.State()
        defaultState.runningApps = [unrecordedApp]
        XCTAssertEqual(
            defaultState.runningUnconfiguredMenuItems.first?.followLastOptionLabel,
            TypeSwitchStrings.InputMethod.followLastEmptyOption
        )
    }

    func testFollowLastMissingInputMethodShowsMissingLabelAndSkipsSwitch() async throws {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")
        let missingInputMethod = "ime.deleted"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [InputMethod(id: "ime.en", name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .followLast(lastInputMethodId: missingInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        initialState.appAvailability = AppAvailabilitySnapshot(availablePaths: [app.path!])

        XCTAssertEqual(
            initialState.configuredApps.first?.selectedLabel,
            TypeSwitchStrings.InputMethod.followLastMissingOption
        )
        XCTAssertEqual(
            initialState.configuredApps.first?.followLastOptionLabel,
            TypeSwitchStrings.InputMethod.followLastMissingOption
        )
        XCTAssertEqual(initialState.configuredApps.first?.hasMissingInputMethod, true)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Missing follow-last input methods should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.switching.currentFrontmostBundleId = app.bundleId
            $0.switching.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: missingInputMethod,
                inputMethodName: nil,
                outcome: .failed(.inputMethodNotFound(missingInputMethod)),
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(
            store.state.appRules[app.bundleId]?.strategy,
            .followLast(lastInputMethodId: missingInputMethod)
        )
    }

    func testManualSelectionOfFailedTargetClearsDiagnosticWithoutIncrementingStatistics() async {
        let bundleId = "com.test.chat"
        let targetInputMethod = "ime.zh"

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [InputMethod(id: targetInputMethod, name: "Pinyin")]
        initialState.switching.lastSwitchAttempt = .init(
            appName: "Chat",
            bundleId: bundleId,
            inputMethodId: targetInputMethod,
            inputMethodName: "Pinyin",
            outcome: .failed(.failedToSwitchInputMethod(targetInputMethod)),
            ruleSource: .app,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Chat.app",
                lastKnownName: "Chat",
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts[bundleId] = 2
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        XCTAssertEqual(store.state.inputMethodDiagnostic?.kind, .switchFailed)

        await store.send(.switching(.system(.inputMethodSelectedChanged(targetInputMethod)))) {
            $0.switching.lastSwitchAttempt = nil
        }

        XCTAssertNil(store.state.inputMethodDiagnostic)
        XCTAssertEqual(store.state.appSwitchStatisticsStore.counts[bundleId], 2)
    }

    func testManualSelectionOfStaleFailedFollowLastTargetClearsDiagnosticWithoutIncrementingStatistics() async {
        let bundleId = "com.test.chat"
        let failedInputMethod = "ime.zh"
        let otherInputMethod = "ime.jp"
        let updateDate = Date(timeIntervalSince1970: 888)

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [
            InputMethod(id: failedInputMethod, name: "Pinyin"),
            InputMethod(id: otherInputMethod, name: "Japanese"),
        ]
        initialState.switching.lastSwitchAttempt = .init(
            appName: "Chat",
            bundleId: bundleId,
            inputMethodId: failedInputMethod,
            inputMethodName: "Pinyin",
            outcome: .failed(.failedToSwitchInputMethod(failedInputMethod)),
            ruleSource: .app,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Chat.app",
                lastKnownName: "Chat",
                strategy: .followLast(lastInputMethodId: failedInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts[bundleId] = 2
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(updateDate)

        XCTAssertEqual(store.state.inputMethodDiagnostic?.kind, .switchFailed)

        await store.send(.switching(.system(.inputMethodSelectedChanged(otherInputMethod)))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[bundleId] else { return }
                rule.strategy = .followLast(lastInputMethodId: otherInputMethod)
                rule.updatedAt = updateDate
                $0.rules[bundleId] = rule
            }
        }

        XCTAssertNil(store.state.inputMethodDiagnostic)
        XCTAssertNotNil(store.state.switching.lastSwitchAttempt)

        await store.send(.switching(.system(.inputMethodSelectedChanged(failedInputMethod)))) {
            $0.switching.lastSwitchAttempt = nil
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[bundleId] else { return }
                rule.strategy = .followLast(lastInputMethodId: failedInputMethod)
                rule.updatedAt = updateDate
                $0.rules[bundleId] = rule
            }
        }

        XCTAssertNil(store.state.inputMethodDiagnostic)
        XCTAssertEqual(
            store.state.appRules[bundleId]?.strategy,
            .followLast(lastInputMethodId: failedInputMethod)
        )
        XCTAssertEqual(store.state.appSwitchStatisticsStore.counts[bundleId], 2)
    }

    func testManualSelectionDoesNotUpdateFallbackFollowLastWhenAppRuleIsNone() async {
        let bundleId = "com.test.chat"

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: nil)
        }
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Chat.app",
                lastKnownName: "Chat",
                strategy: .none,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.switching(.system(.inputMethodSelectedChanged("ime.jp"))))

        XCTAssertEqual(store.state.appRules[bundleId]?.strategy, InputMethodStrategy.none)
        XCTAssertEqual(
            store.state.fallbackRuleStore.strategy,
            .followLast(lastInputMethodId: nil)
        )
        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testManualSelectionDoesNotUpdateFallbackFollowLastWhenAppRuleIsMissing() async {
        let bundleId = "com.test.chat"

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: nil)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.switching(.system(.inputMethodSelectedChanged("ime.jp"))))

        XCTAssertTrue(store.state.appRules.isEmpty)
        XCTAssertEqual(
            store.state.fallbackRuleStore.strategy,
            .followLast(lastInputMethodId: nil)
        )
        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testProgrammaticSelectionDoesNotOverwriteFallbackFollowLastStrategy() async {
        let bundleId = "com.test.terminal"
        let targetInputMethod = "ime.en"

        var initialState = AppFeature.State()
        initialState.switching.currentFrontmostBundleId = bundleId
        initialState.switching.pendingProgrammaticSwitch = .init(bundleId: bundleId, inputMethodId: targetInputMethod)
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: nil)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.switching(.system(.inputMethodSelectedChanged(targetInputMethod)))) {
            $0.switching.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }

        XCTAssertEqual(
            store.state.fallbackRuleStore.strategy,
            .followLast(lastInputMethodId: nil)
        )
        XCTAssertEqual(store.state.fallbackStrategy, .none)
        XCTAssertTrue(store.state.appRules.isEmpty)
    }

    func testRemoveMissingInputMethodRulesTappedClearsOnlyMissingStrategies() async {
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let newUpdatedAt = Date(timeIntervalSince1970: 300)

        var initialState = AppFeature.State()
        initialState.switching.inputMethodCatalogStatus = .ready
        initialState.switching.inputMethods = [InputMethod(id: "ime.en", name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules["missing-fixed"] = AppRuleRecord(
                bundleId: "missing-fixed",
                lastKnownPath: "/Applications/MissingFixed.app",
                lastKnownName: "Missing Fixed",
                strategy: .fixed(inputMethodId: "ime.deleted"),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            $0.rules["missing-follow-last"] = AppRuleRecord(
                bundleId: "missing-follow-last",
                lastKnownPath: "/Applications/MissingFollowLast.app",
                lastKnownName: "Missing Follow Last",
                strategy: .followLast(lastInputMethodId: "ime.deleted"),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            $0.rules["valid"] = AppRuleRecord(
                bundleId: "valid",
                lastKnownPath: "/Applications/Valid.app",
                lastKnownName: "Valid",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(newUpdatedAt)

        await store.send(.view(.removeMissingInputMethodRulesTapped)) {
            $0.$appRulesStore.withLock {
                guard var missingFixed = $0.rules["missing-fixed"],
                      var missingFollowLast = $0.rules["missing-follow-last"]
                else { return }

                missingFixed.strategy = .none
                missingFixed.updatedAt = newUpdatedAt
                $0.rules["missing-fixed"] = missingFixed

                missingFollowLast.strategy = .none
                missingFollowLast.updatedAt = newUpdatedAt
                $0.rules["missing-follow-last"] = missingFollowLast
            }
        }

        XCTAssertEqual(store.state.appRules["missing-fixed"]?.lastKnownName, "Missing Fixed")
        XCTAssertEqual(store.state.appRules["missing-fixed"]?.createdAt, createdAt)
        XCTAssertEqual(store.state.appRules["missing-fixed"]?.strategy, InputMethodStrategy.none)
        XCTAssertEqual(store.state.appRules["missing-follow-last"]?.strategy, InputMethodStrategy.none)
        XCTAssertEqual(store.state.appRules["valid"]?.strategy, .fixed(inputMethodId: "ime.en"))
        XCTAssertEqual(store.state.appRules["valid"]?.updatedAt, updatedAt)
    }

    func testRemoveUnavailableRulesTappedRemovesOnlyUnavailableRules() async throws {
        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules["available"] = AppRuleRecord(
                bundleId: "available",
                lastKnownPath: "/Applications/Available.app",
                lastKnownName: "Available",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules["missing"] = AppRuleRecord(
                bundleId: "missing",
                lastKnownPath: "/tmp/\(UUID().uuidString)",
                lastKnownName: "Missing",
                strategy: .fixed(inputMethodId: "ime.zh"),
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        store.dependencies.appAvailabilityClient.pathExists = { $0 == "/Applications/Available.app" }

        await store.send(.view(.removeUnavailableRulesTapped)) {
            $0.appAvailability = AppAvailabilitySnapshot(availablePaths: ["/Applications/Available.app"])
            $0.$appRulesStore.withLock {
                _ = $0.rules.removeValue(forKey: "missing")
            }
        }

        XCTAssertNotNil(store.state.appRules["available"])
        XCTAssertNil(store.state.appRules["missing"])
    }

    func testSuccessfulSwitchStatisticsAccumulateForSameApp() async {
        let bundleId = "com.test.browser"

        var initialState = AppFeature.State()
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts[bundleId] = 1
        }
        initialState.switching.pendingProgrammaticSwitch = .init(
            appName: "Browser",
            bundleId: bundleId,
            inputMethodId: "ime.en"
        )

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))

        await store.send(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: "Browser",
                bundleId: bundleId,
                inputMethodId: "ime.en",
                inputMethodName: nil,
                outcome: .switched,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[bundleId] = 2
            }
        }

        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 2)
    }

    func testSuccessfulSwitchStatisticsTrackDifferentAppsSeparately() async {
        var initialState = AppFeature.State()
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts["com.test.browser"] = 2
        }
        initialState.switching.pendingProgrammaticSwitch = .init(
            appName: "Editor",
            bundleId: "com.test.editor",
            inputMethodId: "ime.en"
        )

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))

        await store.send(.switching(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        )))) {
            $0.switching.pendingProgrammaticSwitch = nil
            $0.switching.lastSwitchAttempt = .init(
                appName: "Editor",
                bundleId: "com.test.editor",
                inputMethodId: "ime.en",
                inputMethodName: nil,
                outcome: .switched,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts["com.test.editor"] = 1
            }
        }

        XCTAssertEqual(store.state.appSwitchStatisticsStore.counts["com.test.browser"], 2)
        XCTAssertEqual(store.state.appSwitchStatisticsStore.counts["com.test.editor"], 1)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 3)
    }

    func testClearSwitchStatisticsDoesNotModifyRules() async {
        let bundleId = "com.test.browser"
        let appRule = AppRuleRecord(
            bundleId: bundleId,
            lastKnownPath: "/Applications/Browser.app",
            lastKnownName: "Browser",
            strategy: .fixed(inputMethodId: "ime.en"),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = appRule
        }
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts[bundleId] = 4
            $0.counts["com.test.editor"] = 2
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.view(.clearSwitchStatisticsTapped)) {
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts.removeAll()
            }
        }

        XCTAssertEqual(store.state.appRules[bundleId], appRule)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 0)
    }

    func testSwitchStatisticsItemsSortByCountThenName() {
        var state = AppFeature.State()
        state.runningApps = [
            AppInfo(bundleId: "com.test.runner", name: "Runner", path: "/Applications/Runner.app"),
        ]
        state.$appRulesStore.withLock {
            $0.rules["com.test.alpha"] = AppRuleRecord(
                bundleId: "com.test.alpha",
                lastKnownPath: "/Applications/Alpha.app",
                lastKnownName: "Alpha",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules["com.test.browser"] = AppRuleRecord(
                bundleId: "com.test.browser",
                lastKnownPath: "/Applications/Browser.app",
                lastKnownName: "Browser",
                strategy: .fixed(inputMethodId: "ime.en"),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }
        state.$appSwitchStatisticsStore.withLock {
            $0.counts["com.test.alpha"] = 3
            $0.counts["com.test.browser"] = 3
            $0.counts["com.test.runner"] = 4
            $0.counts["com.test.unknown"] = 2
            $0.counts["com.test.zero"] = 0
        }

        XCTAssertEqual(
            state.switchStatisticsItems.map(\.bundleId),
            [
                "com.test.runner",
                "com.test.alpha",
                "com.test.browser",
                "com.test.unknown",
            ]
        )
        XCTAssertEqual(state.switchStatisticsItems.map(\.count), [4, 3, 3, 2])
        XCTAssertEqual(state.totalSuccessfulSwitchCount, 12)
    }

    private func makeRule(
        app: AppInfo,
        strategy: InputMethodStrategy,
        timestamp: Date = Date(timeIntervalSince1970: 10)
    ) -> AppRuleRecord {
        AppRuleRecord(
            bundleId: app.bundleId,
            lastKnownPath: app.path,
            lastKnownName: app.name,
            strategy: strategy,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func receiveStartupResponses(from store: TestStoreOf<AppFeature>) async {
        await store.receive(.response(.launchAtLoginLoaded(.disabled)))
        await store.receive(.switching(.response(.frontmostApplicationLoaded(nil))))
        let refreshID = store.state.switching.pendingInputMethodRefreshID
        await store.receive(.switching(.response(.inputMethodsLoaded(
            refreshID: refreshID ?? -1,
            result: .success([])
        )))) {
            $0.switching.pendingInputMethodRefreshID = nil
            $0.switching.inputMethodCatalogStatus = .ready
        }
        await store.receive(.response(.runningApps([])))
    }

    private func finishedStream<Element>() -> AsyncStream<Element> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

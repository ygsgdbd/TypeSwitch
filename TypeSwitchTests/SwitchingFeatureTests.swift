import ComposableArchitecture
import Sharing
@testable import TypeSwitch
import XCTest

@MainActor
final class SwitchingFeatureTests: XCTestCase {
    func testActivatedAppStillSwitchesWhenCurrentInputMethodLookupFails() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
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
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { throw TestError.failed }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
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
    }

    func testInputMethodRefreshRetriesActivationSkippedWhileCatalogIsLoading() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)
        let recorder = SwitchRecorder()
        let switchGate = InputMethodSwitchGate()

        var initialState = makeState()
        initialState.nextInputMethodRefreshID = 1
        initialState.pendingInputMethodRefreshID = 0
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = makeRule(app: app, strategy: .fixed(inputMethodId: inputMethod.id))
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = { app }
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            await switchGate.wait()
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [inputMethod]
            $0.nextFrontmostRetryID = 1
            $0.pendingFrontmostRetryID = 0
            $0.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.receive(.response(.frontmostApplicationRetried(retryID: 0, appInfo: app))) {
            $0.pendingFrontmostRetryID = nil
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name
            )
        }
        await switchGate.waitUntilStarted()
        await switchGate.resume()
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name,
                outcome: .switched,
                ruleSource: .app,
                timestamp: timestamp
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [inputMethod.id])
    }

    func testInputMethodRefreshRetriesOnlyLatestActivationSkippedWhileCatalogIsLoading() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let firstInputMethod = InputMethod(id: "ime.first", name: "First Input Method")
        let secondInputMethod = InputMethod(id: "ime.second", name: "Second Input Method")
        let timestamp = Date(timeIntervalSince1970: 10)
        let recorder = SwitchRecorder()
        let switchGate = InputMethodSwitchGate()

        var initialState = makeState()
        initialState.nextInputMethodRefreshID = 1
        initialState.pendingInputMethodRefreshID = 0
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = makeRule(
                app: firstApp,
                strategy: .fixed(inputMethodId: firstInputMethod.id)
            )
            $0.rules[secondApp.bundleId] = makeRule(
                app: secondApp,
                strategy: .fixed(inputMethodId: secondInputMethod.id)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = { secondApp }
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            await switchGate.wait()
        }

        await store.send(.applicationActivated(firstApp)) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.applicationActivated(secondApp)) {
            $0.currentFrontmostBundleId = secondApp.bundleId
        }
        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([firstInputMethod, secondInputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [firstInputMethod, secondInputMethod]
            $0.nextFrontmostRetryID = 1
            $0.pendingFrontmostRetryID = 0
            $0.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.receive(.response(.frontmostApplicationRetried(retryID: 0, appInfo: secondApp))) {
            $0.pendingFrontmostRetryID = nil
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: secondApp.name,
                bundleId: secondApp.bundleId,
                inputMethodId: secondInputMethod.id,
                inputMethodName: secondInputMethod.name
            )
        }
        await switchGate.waitUntilStarted()
        await switchGate.resume()
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
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

    func testActivationWithoutSwitchTargetClearsPendingCatalogRetry() async {
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
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = makeState()
        initialState.nextInputMethodRefreshID = 1
        initialState.pendingInputMethodRefreshID = 0
        initialState.$appRulesStore.withLock {
            $0.rules[configuredApp.bundleId] = makeRule(
                app: configuredApp,
                strategy: .fixed(inputMethodId: inputMethod.id)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = {
            XCTFail("A cleared catalog retry must not query the frontmost application")
            return unconfiguredApp
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("An unconfigured app must not trigger a compensated switch")
        }

        await store.send(.applicationActivated(configuredApp)) {
            $0.currentFrontmostBundleId = configuredApp.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.applicationActivated(unconfiguredApp)) {
            $0.currentFrontmostBundleId = unconfiguredApp.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = false
            $0.$appRulesStore.withLock {
                $0.rules[unconfiguredApp.bundleId] = self.makeRule(app: unconfiguredApp, strategy: .none)
            }
        }
        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [inputMethod]
        }
    }

    func testStaleInputMethodRefreshDoesNotConsumePendingCatalogRetry() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let timestamp = Date(timeIntervalSince1970: 10)

        var initialState = makeState()
        initialState.nextInputMethodRefreshID = 2
        initialState.pendingInputMethodRefreshID = 1
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = makeRule(app: app, strategy: .fixed(inputMethodId: inputMethod.id))
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)
        store.dependencies.workspaceClient.frontmostApplication = { app }
        store.dependencies.inputMethodClient.currentInputMethodId = { inputMethod.id }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        )))
        XCTAssertTrue(store.state.shouldRetryFrontmostAfterInputMethodRefresh)

        await store.send(.response(.inputMethodsLoaded(
            refreshID: 1,
            result: .success([inputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [inputMethod]
            $0.nextFrontmostRetryID = 1
            $0.pendingFrontmostRetryID = 0
            $0.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await store.receive(.response(.frontmostApplicationRetried(retryID: 0, appInfo: app))) {
            $0.pendingFrontmostRetryID = nil
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name
            )
        }
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .alreadySelected
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
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

    func testCatalogRetryIgnoresFrontmostSnapshotAfterNewActivation() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")
        let frontmostGate = FrontmostApplicationGate(appInfo: firstApp)

        var initialState = makeState()
        initialState.nextInputMethodRefreshID = 1
        initialState.pendingInputMethodRefreshID = 0
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = makeRule(
                app: firstApp,
                strategy: .fixed(inputMethodId: inputMethod.id)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.workspaceClient.frontmostApplication = {
            await frontmostGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("A stale frontmost snapshot must not switch input methods")
        }

        await store.send(.applicationActivated(firstApp)) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.shouldRetryFrontmostAfterInputMethodRefresh = true
        }
        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [inputMethod]
            $0.nextFrontmostRetryID = 1
            $0.pendingFrontmostRetryID = 0
            $0.shouldRetryFrontmostAfterInputMethodRefresh = false
        }
        await frontmostGate.waitUntilStarted()

        await store.send(.applicationActivated(secondApp)) {
            $0.currentFrontmostBundleId = secondApp.bundleId
            $0.pendingFrontmostRetryID = nil
            $0.$appRulesStore.withLock {
                $0.rules[secondApp.bundleId] = self.makeRule(app: secondApp, strategy: .none)
            }
        }

        await frontmostGate.resume()
        await store.receive(.response(.frontmostApplicationRetried(retryID: 0, appInfo: firstApp)))

        XCTAssertEqual(store.state.currentFrontmostBundleId, secondApp.bundleId)
    }

    func testSuccessfulInputMethodRefreshWithoutPendingCatalogRetryDoesNotReapplyCurrentRule() async {
        let app = AppInfo(bundleId: "com.test.editor", name: "Editor", path: "/Applications/Editor.app")
        let inputMethod = InputMethod(id: "ime.en", name: "English")

        var initialState = makeState()
        initialState.currentFrontmostBundleId = app.bundleId
        initialState.nextInputMethodRefreshID = 1
        initialState.pendingInputMethodRefreshID = 0
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = makeRule(app: app, strategy: .fixed(inputMethodId: inputMethod.id))
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.workspaceClient.frontmostApplication = {
            XCTFail("A normal catalog refresh must not query the frontmost application")
            return app
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("A normal catalog refresh must not reapply the current rule")
        }

        await store.send(.response(.inputMethodsLoaded(
            refreshID: 0,
            result: .success([inputMethod])
        ))) {
            $0.pendingInputMethodRefreshID = nil
            $0.inputMethodCatalogStatus = .ready
            $0.inputMethods = [inputMethod]
        }
    }

    func testStaleProgrammaticSwitchResultIsIgnored() async {
        var initialState = makeState()
        initialState.pendingProgrammaticSwitch = .init(
            appName: "Editor",
            attemptID: 1,
            bundleId: "com.test.editor",
            inputMethodId: "ime.en",
            inputMethodName: "English"
        )

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }

        await store.send(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        )))

        XCTAssertNotNil(store.state.pendingProgrammaticSwitch)
        XCTAssertNil(store.state.lastSwitchAttempt)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testSelectionNotificationDoesNotDiscardSuccessfulSwitchResult() async {
        let timestamp = Date(timeIntervalSince1970: 10)
        let bundleId = "com.test.editor"
        var initialState = makeState()
        initialState.pendingProgrammaticSwitch = .init(
            appName: "Editor",
            bundleId: bundleId,
            inputMethodId: "ime.en",
            inputMethodName: "English"
        )

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)

        await store.send(.system(.inputMethodSelectedChanged("ime.en"))) {
            $0.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }
        await store.send(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: "Editor",
                bundleId: bundleId,
                inputMethodId: "ime.en",
                inputMethodName: "English",
                outcome: .switched,
                ruleSource: .app,
                timestamp: timestamp
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[bundleId] = 1
            }
        }
    }

    func testNonTargetSelectionRevokesConfirmedProgrammaticSwitch() async {
        let timestamp = Date(timeIntervalSince1970: 10)
        let bundleId = "com.test.editor"
        let targetInputMethodId = "ime.en"
        var initialState = makeState()
        initialState.currentFrontmostBundleId = bundleId
        initialState.pendingProgrammaticSwitch = .init(
            appName: "Editor",
            bundleId: bundleId,
            inputMethodId: targetInputMethodId,
            inputMethodName: "English"
        )
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Editor.app",
                lastKnownName: "Editor",
                strategy: .fixed(inputMethodId: targetInputMethodId),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(timestamp)

        await store.send(.system(.inputMethodSelectedChanged(targetInputMethodId))) {
            $0.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }
        await store.send(.system(.inputMethodSelectedChanged("ime.jp"))) {
            $0.pendingProgrammaticSwitch?.didObserveTargetSelection = false
        }
        await store.send(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .failed(.failedToVerifyInputMethod(targetInputMethodId))
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: "Editor",
                bundleId: bundleId,
                inputMethodId: targetInputMethodId,
                inputMethodName: "English",
                outcome: .failed(.failedToVerifyInputMethod(targetInputMethodId)),
                ruleSource: .app,
                timestamp: timestamp
            )
        }

        XCTAssertEqual(
            store.state.lastSwitchAttempt?.outcome,
            .failed(.failedToVerifyInputMethod(targetInputMethodId))
        )
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testActivatedAppUsesAppRuleBeforeFallbackRule() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let appInputMethod = "ime.app"
        let fallbackInputMethod = "ime.fallback"
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [
            InputMethod(id: appInputMethod, name: "App"),
            InputMethod(id: fallbackInputMethod, name: "Fallback"),
        ]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: fallbackInputMethod)
        }
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: appInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: appInputMethod,
                inputMethodName: "App"
            )
        }
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: appInputMethod,
                inputMethodName: "App",
                outcome: .switched,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [appInputMethod])
    }

    func testActivatedAppUsesFallbackRuleWhenAppRuleIsNone() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let fallbackInputMethod = "ime.fallback"
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [InputMethod(id: fallbackInputMethod, name: "Fallback")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: fallbackInputMethod)
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
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: fallbackInputMethod,
                inputMethodName: "Fallback",
                ruleSource: .fallback
            )
        }
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: fallbackInputMethod,
                inputMethodName: "Fallback",
                outcome: .switched,
                ruleSource: .fallback,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [fallbackInputMethod])
    }

    func testActivatedIgnoredAppOverridesFixedFallback() async {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var initialState = makeState()
        initialState.inputMethods = [InputMethod(id: "ime.fallback", name: "Fallback")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: "ime.fallback")
        }
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Ignored apps must not query the current input method")
            return "ime.other"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("Ignored apps must not switch input methods")
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
        }

        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testActivatingIgnoredAppCancelsPreviousProgrammaticSwitch() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let ignoredApp = AppInfo(bundleId: "com.test.ignored", name: "Ignored", path: "/Applications/Ignored.app")
        let targetInputMethod = "ime.en"
        let lookupGate = InputMethodLookupGate(firstValue: "ime.other")
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = AppRuleRecord(
                bundleId: firstApp.bundleId,
                lastKnownPath: firstApp.path,
                lastKnownName: firstApp.name,
                strategy: .fixed(inputMethodId: targetInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules[ignoredApp.bundleId] = AppRuleRecord(
                bundleId: ignoredApp.bundleId,
                lastKnownPath: ignoredApp.path,
                lastKnownName: ignoredApp.name,
                strategy: .ignored,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(firstApp)) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: firstApp.name,
                bundleId: firstApp.bundleId,
                inputMethodId: targetInputMethod,
                inputMethodName: "English"
            )
        }
        await lookupGate.waitForFirstCall()

        await store.send(.applicationActivated(ignoredApp)) {
            $0.currentFrontmostBundleId = ignoredApp.bundleId
            $0.pendingProgrammaticSwitch = nil
        }

        await lookupGate.resumeFirst()
        await store.finish()

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testConsecutiveActivationsOnlyCompleteLatestProgrammaticSwitch() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let secondApp = AppInfo(bundleId: "com.test.second", name: "Second", path: "/Applications/Second.app")
        let firstInputMethod = "ime.first"
        let secondInputMethod = "ime.second"
        let lookupGate = InputMethodLookupGate(
            firstValue: "ime.other",
            subsequentValue: "ime.other"
        )
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [
            InputMethod(id: firstInputMethod, name: "First"),
            InputMethod(id: secondInputMethod, name: "Second"),
        ]
        initialState.$appRulesStore.withLock {
            $0.rules[firstApp.bundleId] = AppRuleRecord(
                bundleId: firstApp.bundleId,
                lastKnownPath: firstApp.path,
                lastKnownName: firstApp.name,
                strategy: .fixed(inputMethodId: firstInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            $0.rules[secondApp.bundleId] = AppRuleRecord(
                bundleId: secondApp.bundleId,
                lastKnownPath: secondApp.path,
                lastKnownName: secondApp.name,
                strategy: .fixed(inputMethodId: secondInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(firstApp)) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: firstApp.name,
                bundleId: firstApp.bundleId,
                inputMethodId: firstInputMethod,
                inputMethodName: "First"
            )
        }
        await lookupGate.waitForFirstCall()

        await store.send(.applicationActivated(secondApp)) {
            $0.currentFrontmostBundleId = secondApp.bundleId
            $0.nextSwitchAttemptID = 2
            $0.pendingProgrammaticSwitch = .init(
                appName: secondApp.name,
                attemptID: 1,
                bundleId: secondApp.bundleId,
                inputMethodId: secondInputMethod,
                inputMethodName: "Second"
            )
        }
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 1,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: secondApp.name,
                bundleId: secondApp.bundleId,
                inputMethodId: secondInputMethod,
                inputMethodName: "Second",
                outcome: .switched,
                ruleSource: .app,
                timestamp: Date(timeIntervalSince1970: 10)
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[secondApp.bundleId] = 1
            }
        }

        await lookupGate.resumeFirst()
        await store.finish()

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [secondInputMethod])
        XCTAssertNil(store.state.appSwitchStatisticsStore.counts[firstApp.bundleId])
        XCTAssertEqual(store.state.appSwitchStatisticsStore.counts[secondApp.bundleId], 1)
    }

    func testActivatedAppUsesFallbackRuleWhenAppRuleIsMissing() async {
        let now = Date(timeIntervalSince1970: 10)
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let fallbackInputMethod = "ime.fallback"
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethods = [InputMethod(id: fallbackInputMethod, name: "Fallback")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: fallbackInputMethod)
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.nextSwitchAttemptID = 1
            $0.pendingProgrammaticSwitch = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: fallbackInputMethod,
                inputMethodName: "Fallback",
                ruleSource: .fallback
            )
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
        await store.receive(.response(.programmaticSwitchFinished(
            attemptID: 0,
            outcome: .switched
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.lastSwitchAttempt = .init(
                appName: app.name,
                bundleId: app.bundleId,
                inputMethodId: fallbackInputMethod,
                inputMethodName: "Fallback",
                outcome: .switched,
                ruleSource: .fallback,
                timestamp: now
            )
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [fallbackInputMethod])
    }

    func testActivatedAppSkipsSwitchWhenFallbackRuleIsNone() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .none
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
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Fallback .none should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
    }

    func testActivatedAppSkipsMissingFixedInputMethod() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let missingInputMethod = "ime.deleted"
        let recorder = SwitchRecorder()

        var initialState = makeState()
        initialState.inputMethodCatalogStatus = .ready
        initialState.inputMethods = [InputMethod(id: "ime.en", name: "English")]
        initialState.$appRulesStore.withLock {
            $0.rules[app.bundleId] = AppRuleRecord(
                bundleId: app.bundleId,
                lastKnownPath: app.path,
                lastKnownName: app.name,
                strategy: .fixed(inputMethodId: missingInputMethod),
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Missing input methods should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.applicationActivated(app)) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.lastSwitchAttempt = .init(
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
            store.state.appRulesStore.rules[app.bundleId]?.strategy,
            .fixed(inputMethodId: missingInputMethod)
        )
    }

    func testManualSelectionUpdatesFollowLastStrategy() async {
        let bundleId = "com.test.chat"
        let updateDate = Date(timeIntervalSince1970: 888)

        var initialState = makeState()
        initialState.currentFrontmostBundleId = bundleId
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Chat.app",
                lastKnownName: "Chat",
                strategy: .followLast(lastInputMethodId: nil),
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }
        store.dependencies.date = .constant(updateDate)

        await store.send(.system(.inputMethodSelectedChanged("ime.jp"))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[bundleId] else { return }
                rule.strategy = .followLast(lastInputMethodId: "ime.jp")
                rule.updatedAt = updateDate
                $0.rules[bundleId] = rule
            }
        }
    }

    func testProgrammaticSelectionDoesNotOverwriteFollowLastStrategy() async {
        let bundleId = "com.test.terminal"
        let targetInputMethod = "ime.en"

        var initialState = makeState()
        initialState.currentFrontmostBundleId = bundleId
        initialState.pendingProgrammaticSwitch = .init(bundleId: bundleId, inputMethodId: targetInputMethod)
        initialState.$appRulesStore.withLock {
            $0.rules[bundleId] = AppRuleRecord(
                bundleId: bundleId,
                lastKnownPath: "/Applications/Terminal.app",
                lastKnownName: "Terminal",
                strategy: .followLast(lastInputMethodId: nil),
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        }

        let store = TestStore(initialState: initialState) {
            SwitchingFeature()
        }

        await store.send(.system(.inputMethodSelectedChanged(targetInputMethod))) {
            $0.pendingProgrammaticSwitch?.didObserveTargetSelection = true
        }

        XCTAssertEqual(
            store.state.appRulesStore.rules[bundleId]?.strategy,
            .followLast(lastInputMethodId: nil)
        )
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

    private func makeState() -> SwitchingFeature.State {
        SwitchingFeature.State(
            appRulesStore: Shared(value: AppRulesStore()),
            appSwitchStatisticsStore: Shared(value: AppSwitchStatisticsStore()),
            fallbackRuleStore: Shared(value: FallbackRuleStore())
        )
    }
}

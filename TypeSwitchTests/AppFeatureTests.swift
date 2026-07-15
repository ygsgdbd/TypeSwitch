import ComposableArchitecture
import Foundation
@testable import TypeSwitch
import XCTest

@MainActor
final class AppFeatureTests: XCTestCase {
    func testFrontmostAndRunningAppsCreateDefaultRule() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let app = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)

        await store.send(.response(.frontmostApplicationLoaded(app))) {
            $0.currentFrontmostBundleId = app.bundleId
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

    func testActivatedAppSwitchesFixedInputMethodWhenNeeded() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: targetInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: app.bundleId,
            inputMethodId: targetInputMethod,
            didSwitch: true
        ))) {
            $0.pendingProgrammaticSwitch = nil
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { targetInputMethod }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
            XCTFail("Already selected input method should not switch again")
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: targetInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: app.bundleId,
            inputMethodId: targetInputMethod,
            didSwitch: false
        ))) {
            $0.pendingProgrammaticSwitch = nil
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.zh" }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            throw TestError.failed
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: targetInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: app.bundleId,
            inputMethodId: targetInputMethod,
            didSwitch: false
        ))) {
            $0.pendingProgrammaticSwitch = nil
        }

        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 0)
    }

    func testActivatedAppUsesAppRuleBeforeFallbackRule() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let appInputMethod = "ime.app"
        let fallbackInputMethod = "ime.fallback"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: appInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: app.bundleId,
            inputMethodId: appInputMethod,
            didSwitch: true
        ))) {
            $0.pendingProgrammaticSwitch = nil
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

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: fallbackInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: app.bundleId,
            inputMethodId: fallbackInputMethod,
            didSwitch: true
        ))) {
            $0.pendingProgrammaticSwitch = nil
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[app.bundleId] = 1
            }
        }

        let switchedInputMethods = await recorder.values
        XCTAssertEqual(switchedInputMethods, [fallbackInputMethod])
    }

    func testActivatedAppUsesFallbackRuleWhenAppRuleIsMissing() async {
        let now = Date(timeIntervalSince1970: 10)
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let fallbackInputMethod = "ime.fallback"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: fallbackInputMethod, name: "Fallback")]
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .fixed(inputMethodId: fallbackInputMethod)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(now)
        store.dependencies.inputMethodClient.currentInputMethodId = { "ime.other" }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: fallbackInputMethod)
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
            bundleId: app.bundleId,
            inputMethodId: fallbackInputMethod,
            didSwitch: true
        ))) {
            $0.pendingProgrammaticSwitch = nil
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

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Fallback .none should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
    }

    func testActivatedAppSkipsSwitchWhenFallbackRuleIsLegacyFollowLast() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: "ime.jp", name: "Japanese")]
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
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testActivatedAppSkipsMissingFallbackInputMethod() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: "ime.en", name: "English")]
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
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(store.state.fallbackStrategy, .fixed(inputMethodId: "ime.deleted"))
    }

    func testUnavailableAppIsExcludedFromConfiguredApps() async {
        let missingPath = "/tmp/\(UUID().uuidString)"

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: "ime.en", name: "English")]
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

    func testActivatedAppSkipsMissingFixedInputMethod() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let missingInputMethod = "ime.deleted"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Missing input methods should not trigger current input method lookup")
            return "ime.en"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(
            store.state.appRules[app.bundleId]?.strategy,
            .fixed(inputMethodId: missingInputMethod)
        )
    }

    func testFollowLastAvailableInputMethodShowsCurrentInputMethodInMenuOption() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.inputMethods = [InputMethod(id: "ime.zh", name: "Pinyin")]
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
        state.inputMethods = [InputMethod(id: "ime.zh", name: "Pinyin")]
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

    func testCurrentAppMenuItemIsSeparatedFromRunningApps() {
        let chat = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")
        let notes = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")

        var state = AppFeature.State()
        state.currentFrontmostBundleId = chat.bundleId
        state.runningApps = [chat, notes]

        XCTAssertEqual(state.currentAppMenuItem?.bundleId, chat.bundleId)
        XCTAssertTrue(state.runningConfiguredMenuItems.isEmpty)
        XCTAssertEqual(state.runningUnconfiguredMenuItems.map(\.bundleId), [notes.bundleId])
    }

    func testMenuBarIconUsesKeyboardWithoutFrontmostApp() {
        let state = AppFeature.State()

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard")
    }

    func testMenuBarIconUsesUnconfiguredIconForFrontmostAppWithoutRule() {
        var state = AppFeature.State()
        state.currentFrontmostBundleId = "com.test.chat"

        XCTAssertEqual(state.menuBarIconSystemName, "keyboard.badge.ellipsis")
    }

    func testMenuBarIconUsesUnconfiguredIconForFrontmostAppWithNoneStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.currentFrontmostBundleId = app.bundleId
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
    }

    func testMenuBarIconUsesKeyboardForFrontmostAppWithFixedStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.currentFrontmostBundleId = app.bundleId
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
    }

    func testMenuBarIconUsesKeyboardForFrontmostAppWithFollowLastStrategy() {
        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: "/Applications/Chat.app")

        var state = AppFeature.State()
        state.currentFrontmostBundleId = app.bundleId
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
        let appURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: appURL) }

        let app = AppInfo(bundleId: "com.test.chat", name: "Chat", path: appURL.path)
        let missingInputMethod = "ime.deleted"
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: "ime.en", name: "English")]
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
            $0.currentFrontmostBundleId = app.bundleId
        }

        let switchedInputMethods = await recorder.values
        XCTAssertTrue(switchedInputMethods.isEmpty)
        XCTAssertEqual(
            store.state.appRules[app.bundleId]?.strategy,
            .followLast(lastInputMethodId: missingInputMethod)
        )
    }

    func testManualSelectionUpdatesFollowLastStrategy() async {
        let bundleId = "com.test.chat"
        let updateDate = Date(timeIntervalSince1970: 888)

        var initialState = AppFeature.State()
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
            AppFeature()
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

    func testManualSelectionDoesNotUpdateFallbackFollowLastWhenAppRuleIsNone() async {
        let bundleId = "com.test.chat"

        var initialState = AppFeature.State()
        initialState.currentFrontmostBundleId = bundleId
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

        await store.send(.system(.inputMethodSelectedChanged("ime.jp")))

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
        initialState.currentFrontmostBundleId = bundleId
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: nil)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.system(.inputMethodSelectedChanged("ime.jp")))

        XCTAssertTrue(store.state.appRules.isEmpty)
        XCTAssertEqual(
            store.state.fallbackRuleStore.strategy,
            .followLast(lastInputMethodId: nil)
        )
        XCTAssertEqual(store.state.fallbackStrategy, .none)
    }

    func testProgrammaticSelectionDoesNotOverwriteFollowLastStrategy() async {
        let bundleId = "com.test.terminal"
        let targetInputMethod = "ime.en"

        var initialState = AppFeature.State()
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
            AppFeature()
        }

        await store.send(.system(.inputMethodSelectedChanged(targetInputMethod))) {
            $0.pendingProgrammaticSwitch = nil
        }

        XCTAssertEqual(
            store.state.appRules[bundleId]?.strategy,
            .followLast(lastInputMethodId: nil)
        )
    }

    func testProgrammaticSelectionDoesNotOverwriteFallbackFollowLastStrategy() async {
        let bundleId = "com.test.terminal"
        let targetInputMethod = "ime.en"

        var initialState = AppFeature.State()
        initialState.currentFrontmostBundleId = bundleId
        initialState.pendingProgrammaticSwitch = .init(bundleId: bundleId, inputMethodId: targetInputMethod)
        initialState.$fallbackRuleStore.withLock {
            $0.strategy = .followLast(lastInputMethodId: nil)
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.system(.inputMethodSelectedChanged(targetInputMethod))) {
            $0.pendingProgrammaticSwitch = nil
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
        initialState.inputMethods = [InputMethod(id: "ime.en", name: "English")]
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
        let availableURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: availableURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: availableURL) }

        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            $0.rules["available"] = AppRuleRecord(
                bundleId: "available",
                lastKnownPath: availableURL.path,
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

        await store.send(.view(.removeUnavailableRulesTapped)) {
            $0.$appRulesStore.withLock {
                _ = $0.rules.removeValue(forKey: "missing")
            }
        }

        XCTAssertNotNil(store.state.appRules["available"])
        XCTAssertNil(store.state.appRules["missing"])
    }

    func testSuccessfulSwitchStatisticsAccumulateForSameApp() async {
        let bundleId = "com.test.browser"

        let initialState = AppFeature.State()
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts[bundleId] = 1
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.response(.programmaticSwitchFinished(
            bundleId: bundleId,
            inputMethodId: "ime.en",
            didSwitch: true
        ))) {
            $0.$appSwitchStatisticsStore.withLock {
                $0.counts[bundleId] = 2
            }
        }

        XCTAssertEqual(store.state.totalSuccessfulSwitchCount, 2)
    }

    func testSuccessfulSwitchStatisticsTrackDifferentAppsSeparately() async {
        let initialState = AppFeature.State()
        initialState.$appSwitchStatisticsStore.withLock {
            $0.counts["com.test.browser"] = 2
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }

        await store.send(.response(.programmaticSwitchFinished(
            bundleId: "com.test.editor",
            inputMethodId: "ime.en",
            didSwitch: true
        ))) {
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

    func testLegacyMigrationMigratesOnlyMatchedRules() async {
        let migrationDate = Date(timeIntervalSince1970: 777)
        let migrationTracker = MigrationTracker()
        let matchedApp = AppInfo(bundleId: "com.test.notes", name: "Notes", path: "/Applications/Notes.app")

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.dependencies.date = .constant(migrationDate)
        store.dependencies.legacyDefaultsMigrationClient.didCompleteMigration = { false }
        store.dependencies.legacyDefaultsMigrationClient.migrateRules = { receivedDate in
            XCTAssertEqual(receivedDate, migrationDate)
            await migrationTracker.markMigrated()
            return [
                "com.test.notes": AppRuleRecord(
                    bundleId: "com.test.notes",
                    lastKnownPath: matchedApp.path,
                    lastKnownName: matchedApp.name,
                    strategy: .fixed(inputMethodId: "ime.zh"),
                    createdAt: migrationDate,
                    updatedAt: migrationDate
                ),
            ]
        }

        await store.send(.response(.appRulesStorePrepared(.noStoreFound)))
        await store.receive(.response(.legacyRulesMigrated([
            "com.test.notes": AppRuleRecord(
                bundleId: "com.test.notes",
                lastKnownPath: matchedApp.path,
                lastKnownName: matchedApp.name,
                strategy: .fixed(inputMethodId: "ime.zh"),
                createdAt: migrationDate,
                updatedAt: migrationDate
            ),
        ]))) {
            $0.$appRulesStore.withLock {
                $0.rules["com.test.notes"] = AppRuleRecord(
                    bundleId: "com.test.notes",
                    lastKnownPath: matchedApp.path,
                    lastKnownName: matchedApp.name,
                    strategy: .fixed(inputMethodId: "ime.zh"),
                    createdAt: migrationDate,
                    updatedAt: migrationDate
                )
            }
        }

        let didMigrate = await migrationTracker.didMigrate
        XCTAssertTrue(didMigrate)
        XCTAssertNil(store.state.appRules["com.test.missing"])
        XCTAssertEqual(store.state.appRulesStore.v, MigrationVersion.current)
    }
}

private actor SwitchRecorder {
    private(set) var values: [String] = []

    func record(_ inputMethodId: String) {
        values.append(inputMethodId)
    }
}

private enum TestError: Error {
    case failed
}

private actor MigrationTracker {
    private(set) var didMigrate = false

    func markMigrated() {
        didMigrate = true
    }
}

import AppKit
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

    func testActivatedIgnoredAppOverridesFixedFallback() async {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            XCTFail("Ignored apps must not query the current input method")
            return "ime.other"
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { _ in
            XCTFail("Ignored apps must not switch input methods")
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
        }

        XCTAssertTrue(store.state.appSwitchStatisticsStore.counts.isEmpty)
    }

    func testIgnoringCurrentAppCancelsPendingProgrammaticSwitch() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let updateDate = Date(timeIntervalSince1970: 20)
        let lookupGate = InputMethodLookupGate(firstValue: "ime.other")
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
        store.dependencies.date = .constant(updateDate)
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(app)))) {
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: targetInputMethod)
        }
        await lookupGate.waitForFirstCall()

        await store.send(.view(.ignoreAppTapped(app))) {
            $0.pendingProgrammaticSwitch = nil
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[app.bundleId] else { return }
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

    func testActivatingIgnoredAppCancelsPreviousProgrammaticSwitch() async {
        let firstApp = AppInfo(bundleId: "com.test.first", name: "First", path: "/Applications/First.app")
        let ignoredApp = AppInfo(bundleId: "com.test.ignored", name: "Ignored", path: "/Applications/Ignored.app")
        let targetInputMethod = "ime.en"
        let lookupGate = InputMethodLookupGate(firstValue: "ime.other")
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(firstApp)))) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: firstApp.bundleId, inputMethodId: targetInputMethod)
        }
        await lookupGate.waitForFirstCall()

        await store.send(.system(.workspaceEvent(.activated(ignoredApp)))) {
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

        var initialState = AppFeature.State()
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
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 10))
        store.dependencies.inputMethodClient.currentInputMethodId = {
            await lookupGate.value()
        }
        store.dependencies.inputMethodClient.switchToInputMethod = { inputMethodId in
            await recorder.record(inputMethodId)
        }

        await store.send(.system(.workspaceEvent(.activated(firstApp)))) {
            $0.currentFrontmostBundleId = firstApp.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: firstApp.bundleId, inputMethodId: firstInputMethod)
        }
        await lookupGate.waitForFirstCall()

        await store.send(.system(.workspaceEvent(.activated(secondApp)))) {
            $0.currentFrontmostBundleId = secondApp.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: secondApp.bundleId, inputMethodId: secondInputMethod)
        }
        await store.receive(.response(.programmaticSwitchFinished(
            bundleId: secondApp.bundleId,
            inputMethodId: secondInputMethod,
            didSwitch: true
        ))) {
            $0.pendingProgrammaticSwitch = nil
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

    func testTerminatingCurrentAppCancelsSwitchAfterSelectionNotificationClearsPending() async {
        let app = AppInfo(bundleId: "com.test.browser", name: "Browser", path: "/Applications/Browser.app")
        let targetInputMethod = "ime.en"
        let switchGate = InputMethodSwitchGate()
        let recorder = SwitchRecorder()

        var initialState = AppFeature.State()
        initialState.inputMethods = [InputMethod(id: targetInputMethod, name: "English")]
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
            $0.currentFrontmostBundleId = app.bundleId
            $0.pendingProgrammaticSwitch = .init(bundleId: app.bundleId, inputMethodId: targetInputMethod)
        }
        await switchGate.waitUntilStarted()

        await store.send(.system(.inputMethodSelectedChanged(targetInputMethod))) {
            $0.pendingProgrammaticSwitch = nil
        }
        await store.send(.system(.workspaceEvent(.terminated(bundleId: app.bundleId)))) {
            $0.currentFrontmostBundleId = nil
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

    func testIgnoredAppOnlyAppearsInIgnoredMenu() {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var state = AppFeature.State()
        state.currentFrontmostBundleId = app.bundleId
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

    func testIgnoreAndRestoreAppUseIgnoredAndDefaultStrategies() async {
        let app = AppInfo(bundleId: "com.test.passwords", name: "Passwords", path: "/Applications/Passwords.app")

        var initialState = AppFeature.State()
        initialState.runningApps = [app]

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

        await store.send(.view(.ignoreAppTapped(app))) {
            $0.$appRulesStore.withLock {
                $0.rules[app.bundleId] = AppRuleRecord(
                    bundleId: app.bundleId,
                    lastKnownPath: app.path,
                    lastKnownName: app.name,
                    strategy: .ignored,
                    createdAt: Date(timeIntervalSince1970: 20),
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            }
        }

        await store.send(.view(.restoreIgnoredAppTapped(bundleId: app.bundleId))) {
            $0.$appRulesStore.withLock {
                guard var rule = $0.rules[app.bundleId] else { return }
                rule.strategy = .none
                rule.updatedAt = Date(timeIntervalSince1970: 20)
                $0.rules[app.bundleId] = rule
            }
        }

        XCTAssertEqual(store.state.runningUnconfiguredMenuItems.map(\.bundleId), [app.bundleId])
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
                rule.strategy = .ignored
                rule.updatedAt = Date(timeIntervalSince1970: 20)
                $0.rules[bundleId] = rule
            }
        }

        XCTAssertEqual(store.state.appRules[bundleId]?.lastKnownPath, lastKnownPath)
    }

    func testRestoreAllIgnoredAppsUsesDefaultStrategy() async {
        var initialState = AppFeature.State()
        initialState.$appRulesStore.withLock {
            for bundleId in ["com.test.alpha", "com.test.beta"] {
                $0.rules[bundleId] = AppRuleRecord(
                    bundleId: bundleId,
                    lastKnownPath: nil,
                    lastKnownName: bundleId,
                    strategy: .ignored,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            }
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(Date(timeIntervalSince1970: 20))

        await store.send(.view(.restoreAllIgnoredAppsTapped)) {
            $0.$appRulesStore.withLock {
                for bundleId in ["com.test.alpha", "com.test.beta"] {
                    guard var rule = $0.rules[bundleId] else { continue }
                    rule.strategy = .none
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

    func testLegacyRulesLoadedSavesBeforeMarkingMigrationCompleted() async {
        let currentDate = Date(timeIntervalSince1970: 100)
        let migrationDate = Date(timeIntervalSince1970: 777)
        let migrationTracker = MigrationTracker()
        let currentRule = AppRuleRecord(
            bundleId: "com.test.notes",
            lastKnownPath: "/Applications/Notes.app",
            lastKnownName: "Notes",
            strategy: .none,
            createdAt: currentDate,
            updatedAt: currentDate
        )
        let legacyRule = AppRuleRecord(
            bundleId: currentRule.bundleId,
            lastKnownPath: nil,
            lastKnownName: currentRule.bundleId,
            strategy: .fixed(inputMethodId: "ime.zh"),
            createdAt: migrationDate,
            updatedAt: migrationDate
        )
        let expectedRule = AppRuleRecord(
            bundleId: currentRule.bundleId,
            lastKnownPath: currentRule.lastKnownPath,
            lastKnownName: currentRule.lastKnownName,
            strategy: legacyRule.strategy,
            createdAt: currentDate,
            updatedAt: migrationDate
        )
        var initialState = makeMigrationTestState()
        initialState.$appRulesStore.withLock {
            $0.rules[currentRule.bundleId] = currentRule
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.appRulesStoreMigrationClient.save = { _ in
            await migrationTracker.record(.save)
        }
        store.dependencies.legacyDefaultsMigrationClient.markCompleted = { version in
            await migrationTracker.record(.markCompleted(version))
        }

        await store.send(.response(.legacyRulesLoaded(
            [legacyRule.bundleId: legacyRule],
            didCompleteLegacyMigration: false
        ))) {
            $0.$appRulesStore.withLock {
                $0.rules[legacyRule.bundleId] = expectedRule
            }
        }
        await store.finish()

        let events = await migrationTracker.events
        XCTAssertEqual(events, [.save, .markCompleted(2)])
    }

    func testLegacyRulesLoadedDoesNotMarkMigrationCompletedWhenSaveFails() async {
        let migrationTracker = MigrationTracker()
        let legacyRule = AppRuleRecord(
            bundleId: "com.test.notes",
            lastKnownPath: "/Applications/Notes.app",
            lastKnownName: "Notes",
            strategy: .fixed(inputMethodId: "ime.zh"),
            createdAt: Date(timeIntervalSince1970: 777),
            updatedAt: Date(timeIntervalSince1970: 777)
        )

        let store = TestStore(initialState: makeMigrationTestState()) {
            AppFeature()
        }
        store.dependencies.appRulesStoreMigrationClient.save = { _ in
            await migrationTracker.record(.save)
            throw TestError.failed
        }
        store.dependencies.legacyDefaultsMigrationClient.markCompleted = { version in
            await migrationTracker.record(.markCompleted(version))
        }

        await store.send(.response(.legacyRulesLoaded(
            [legacyRule.bundleId: legacyRule],
            didCompleteLegacyMigration: false
        ))) {
            $0.$appRulesStore.withLock {
                $0.rules[legacyRule.bundleId] = legacyRule
            }
        }
        await store.finish()

        let events = await migrationTracker.events
        XCTAssertEqual(events, [.save])
    }

    func testLegacyRulesLoadedWithoutLegacyMappingsKeepsCurrentRulesAndMarksCompleted() async {
        let migrationTracker = MigrationTracker()
        let currentRule = AppRuleRecord(
            bundleId: "com.test.notes",
            lastKnownPath: "/Applications/Notes.app",
            lastKnownName: "Notes",
            strategy: .ignored,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        var initialState = makeMigrationTestState()
        initialState.$appRulesStore.withLock {
            $0.rules[currentRule.bundleId] = currentRule
        }

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.appRulesStoreMigrationClient.save = { _ in
            await migrationTracker.record(.save)
        }
        store.dependencies.legacyDefaultsMigrationClient.markCompleted = { version in
            await migrationTracker.record(.markCompleted(version))
        }

        await store.send(.response(.legacyRulesLoaded(
            [:],
            didCompleteLegacyMigration: true
        )))
        await store.finish()

        let events = await migrationTracker.events
        XCTAssertEqual(events, [.markCompleted(2)])
        XCTAssertEqual(store.state.appRules[currentRule.bundleId], currentRule)
    }

    func testTaskMigratesWithExistingEmptyStoreBeforeScanningRunningAppsAndDoesNotRepeatV2Migration() async throws {
        let migrationDate = Date(timeIntervalSince1970: 777)
        let migrationTracker = MigrationTracker()
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = rootDirectory.appending(path: AppStorageConfiguration.appRulesFilename)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(AppRulesStore()).write(to: storeURL)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let legacyRule = AppRuleRecord(
            bundleId: "com.test.notes",
            lastKnownPath: "/Applications/Notes.app",
            lastKnownName: "Notes",
            strategy: .fixed(inputMethodId: "ime.zh"),
            createdAt: migrationDate,
            updatedAt: migrationDate
        )

        let initialState = AppFeature.State(
            appRulesStore: Shared(
                wrappedValue: AppRulesStore(),
                .fileStorage(storeURL)
            ),
            appSwitchStatisticsStore: Shared(value: AppSwitchStatisticsStore()),
            fallbackRuleStore: Shared(value: FallbackRuleStore())
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.dependencies.date = .constant(migrationDate)
        store.dependencies.legacyDefaultsMigrationClient.completedVersion = {
            await migrationTracker.completedVersion
        }
        store.dependencies.legacyDefaultsMigrationClient.didCompleteLegacyMigration = { true }
        store.dependencies.legacyDefaultsMigrationClient.loadRules = { receivedDate in
            await migrationTracker.record(.loadRules(receivedDate))
            return [legacyRule.bundleId: legacyRule]
        }
        store.dependencies.legacyDefaultsMigrationClient.markCompleted = { version in
            await migrationTracker.markCompleted(version)
        }
        store.dependencies.appRulesStoreMigrationClient.save = { _ in
            await migrationTracker.record(.save)
        }
        store.dependencies.workspaceClient.runningApplications = {
            await migrationTracker.record(.runningApplications)
            return []
        }
        store.dependencies.workspaceClient.events = finishedStream
        store.dependencies.inputMethodClient.availabilityChanges = finishedStream
        store.dependencies.inputMethodClient.selectionChanges = finishedStream

        await store.send(.task)
        await store.receive(.response(.legacyRulesLoaded(
            [legacyRule.bundleId: legacyRule],
            didCompleteLegacyMigration: true
        ))) {
            $0.$appRulesStore.withLock {
                $0.rules[legacyRule.bundleId] = legacyRule
            }
        }
        await receiveStartupResponses(from: store)
        await store.finish()

        let migratedRule = store.state.appRules[legacyRule.bundleId]
        let firstRunEvents = await migrationTracker.events
        XCTAssertLessThan(
            try XCTUnwrap(firstRunEvents.firstIndex(of: .loadRules(migrationDate))),
            try XCTUnwrap(firstRunEvents.firstIndex(of: .runningApplications))
        )
        XCTAssertEqual(firstRunEvents.filter { $0 == .save }.count, 1)
        XCTAssertEqual(firstRunEvents.filter { $0 == .markCompleted(2) }.count, 1)

        await store.send(.task)
        await receiveStartupResponses(from: store)
        await store.finish()

        let secondRunEvents = await migrationTracker.events
        XCTAssertEqual(secondRunEvents.filter {
            if case .loadRules = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(secondRunEvents.filter { $0 == .save }.count, 1)
        XCTAssertEqual(secondRunEvents.filter { $0 == .markCompleted(2) }.count, 1)
        XCTAssertEqual(store.state.appRules[legacyRule.bundleId], migratedRule)
    }

    private func makeMigrationTestState() -> AppFeature.State {
        AppFeature.State(
            appRulesStore: Shared(value: AppRulesStore()),
            appSwitchStatisticsStore: Shared(value: AppSwitchStatisticsStore()),
            fallbackRuleStore: Shared(value: FallbackRuleStore())
        )
    }

    private func receiveStartupResponses(from store: TestStoreOf<AppFeature>) async {
        await store.receive(.response(.launchAtLoginLoaded(.disabled)))
        await store.receive(.response(.frontmostApplicationLoaded(nil)))
        await store.receive(.response(.inputMethods([])))
        await store.receive(.response(.runningApps([])))
    }

    private func finishedStream<Element>() -> AsyncStream<Element> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private actor SwitchRecorder {
    private(set) var values: [String] = []

    func record(_ inputMethodId: String) {
        values.append(inputMethodId)
    }
}

private actor InputMethodLookupGate {
    private let firstValue: String
    private let subsequentValue: String
    private var callCount = 0
    private var firstContinuation: CheckedContinuation<String, Never>?
    private var firstStartedContinuation: CheckedContinuation<Void, Never>?
    private var hasStartedFirstCall = false

    init(firstValue: String, subsequentValue: String = "") {
        self.firstValue = firstValue
        self.subsequentValue = subsequentValue
    }

    func value() async -> String {
        callCount += 1
        guard callCount == 1 else { return subsequentValue }

        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
            hasStartedFirstCall = true
            firstStartedContinuation?.resume()
            firstStartedContinuation = nil
        }
    }

    func waitForFirstCall() async {
        guard !hasStartedFirstCall else { return }
        await withCheckedContinuation { continuation in
            firstStartedContinuation = continuation
        }
    }

    func resumeFirst() {
        firstContinuation?.resume(returning: firstValue)
        firstContinuation = nil
    }
}

private actor InputMethodSwitchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum TestError: Error {
    case failed
}

private actor MigrationTracker {
    enum Event: Equatable {
        case loadRules(Date)
        case markCompleted(Int)
        case runningApplications
        case save
    }

    private(set) var completedVersion = 0
    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }

    func markCompleted(_ version: Int) {
        completedVersion = version
        events.append(.markCompleted(version))
    }
}

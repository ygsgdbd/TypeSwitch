import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct AppFeature {
    @Dependency(\.appRulesStoreMigrationClient) var appRulesStoreMigrationClient
    @Dependency(\.date.now) var now
    @Dependency(\.inputMethodClient) var inputMethodClient
    @Dependency(\.legacyDefaultsMigrationClient) var legacyDefaultsMigrationClient
    @Dependency(\.launchAtLoginClient) var launchAtLoginClient
    @Dependency(\.workspaceClient) var workspaceClient

    @ObservableState
    struct State: Equatable {
        enum InputMethodCatalogStatus: Equatable, Sendable {
            case loading
            case ready
            case failed(InputMethodService.InputMethodError)
        }

        enum RuleSource: Equatable, Sendable {
            case app
            case fallback
        }

        enum ProgrammaticSwitchOutcome: Equatable, Sendable {
            case alreadySelected
            case switched
            case failed(InputMethodService.InputMethodError)
        }

        struct LastSwitchAttempt: Equatable, Sendable {
            let appName: String
            let bundleId: String
            let inputMethodId: String
            let inputMethodName: String?
            let outcome: ProgrammaticSwitchOutcome
            let ruleSource: RuleSource
            let timestamp: Date
        }

        struct AppMenuItem: Equatable, Identifiable {
            let bundleId: String
            let name: String
            let path: String?
            let strategy: InputMethodStrategy
            let defaultOptionLabel: String
            let selectedLabel: String?
            let followLastOptionLabel: String
            let hasMissingInputMethod: Bool

            var id: String { bundleId }

            var appInfo: AppInfo {
                AppInfo(bundleId: bundleId, name: name, path: path)
            }
        }

        struct PendingProgrammaticSwitch: Equatable {
            let appName: String
            let attemptID: Int
            let bundleId: String
            let inputMethodId: String
            let inputMethodName: String?
            let ruleSource: RuleSource

            init(
                appName: String = "",
                attemptID: Int = 0,
                bundleId: String,
                inputMethodId: String,
                inputMethodName: String? = nil,
                ruleSource: RuleSource = .app
            ) {
                self.appName = appName
                self.attemptID = attemptID
                self.bundleId = bundleId
                self.inputMethodId = inputMethodId
                self.inputMethodName = inputMethodName
                self.ruleSource = ruleSource
            }
        }

        struct SwitchStatisticsItem: Equatable, Identifiable {
            let bundleId: String
            let name: String
            let path: String?
            let count: Int

            var id: String { bundleId }
        }

        @Shared var appRulesStore: AppRulesStore
        @Shared var appSwitchStatisticsStore: AppSwitchStatisticsStore
        @Shared var fallbackRuleStore: FallbackRuleStore
        var currentFrontmostBundleId: String?
        var inputMethodCatalogStatus: InputMethodCatalogStatus = .loading
        var inputMethods: [InputMethod] = []
        var isMenuPresented = false
        var isReadmeDemo = false
        var lastSwitchAttempt: LastSwitchAttempt?
        var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
        var menuStrategiesAtPresentation: [String: InputMethodStrategy] = [:]
        var nextFrontmostRetryID = 0
        var nextInputMethodRefreshID = 0
        var nextSwitchAttemptID = 0
        var pendingFrontmostRetryID: Int?
        var pendingInputMethodRefreshID: Int?
        var pendingProgrammaticSwitch: PendingProgrammaticSwitch?
        var runningApps: [AppInfo] = []
        var shouldRetryFrontmostAfterInputMethodRefresh = false

        init(
            appRulesStore: Shared<AppRulesStore> = Shared(
                wrappedValue: AppRulesStore(),
                .fileStorage(.appRulesStoreURL)
            ),
            appSwitchStatisticsStore: Shared<AppSwitchStatisticsStore> = Shared(
                wrappedValue: AppSwitchStatisticsStore(),
                .fileStorage(.appSwitchStatisticsStoreURL)
            ),
            fallbackRuleStore: Shared<FallbackRuleStore> = Shared(
                wrappedValue: FallbackRuleStore(),
                .fileStorage(.fallbackRuleStoreURL)
            ),
            currentFrontmostBundleId: String? = nil,
            inputMethodCatalogStatus: InputMethodCatalogStatus = .loading,
            inputMethods: [InputMethod] = [],
            isMenuPresented: Bool = false,
            isReadmeDemo: Bool = false,
            lastSwitchAttempt: LastSwitchAttempt? = nil,
            launchAtLoginStatus: LaunchAtLoginStatus = .disabled,
            menuStrategiesAtPresentation: [String: InputMethodStrategy] = [:],
            nextFrontmostRetryID: Int = 0,
            nextInputMethodRefreshID: Int = 0,
            nextSwitchAttemptID: Int = 0,
            pendingFrontmostRetryID: Int? = nil,
            pendingInputMethodRefreshID: Int? = nil,
            pendingProgrammaticSwitch: PendingProgrammaticSwitch? = nil,
            runningApps: [AppInfo] = [],
            shouldRetryFrontmostAfterInputMethodRefresh: Bool = false
        ) {
            self._appRulesStore = appRulesStore
            self._appSwitchStatisticsStore = appSwitchStatisticsStore
            self._fallbackRuleStore = fallbackRuleStore
            self.currentFrontmostBundleId = currentFrontmostBundleId
            self.inputMethodCatalogStatus = inputMethodCatalogStatus
            self.inputMethods = inputMethods
            self.isMenuPresented = isMenuPresented
            self.isReadmeDemo = isReadmeDemo
            self.lastSwitchAttempt = lastSwitchAttempt
            self.launchAtLoginStatus = launchAtLoginStatus
            self.menuStrategiesAtPresentation = menuStrategiesAtPresentation
            self.nextFrontmostRetryID = nextFrontmostRetryID
            self.nextInputMethodRefreshID = nextInputMethodRefreshID
            self.nextSwitchAttemptID = nextSwitchAttemptID
            self.pendingFrontmostRetryID = pendingFrontmostRetryID
            self.pendingInputMethodRefreshID = pendingInputMethodRefreshID
            self.pendingProgrammaticSwitch = pendingProgrammaticSwitch
            self.runningApps = runningApps
            self.shouldRetryFrontmostAfterInputMethodRefresh = shouldRetryFrontmostAfterInputMethodRefresh
        }
    }

    enum ViewAction: Equatable, Sendable {
        case clearSwitchStatisticsTapped
        case ignoreAppTapped(AppInfo)
        case reloadInputMethodsTapped
        case removeMissingInputMethodRulesTapped
        case removeUnavailableRulesTapped
        case restoreAllIgnoredAppsTapped
        case restoreIgnoredAppTapped(bundleId: String)
        case retryCurrentAppTapped
        case setFallbackStrategy(InputMethodStrategy)
        case setLaunchAtLogin(Bool)
        case setStrategy(bundleId: String, strategy: InputMethodStrategy)
    }

    enum ResponseAction: Equatable, Sendable {
        case frontmostApplicationLoaded(AppInfo?)
        case frontmostApplicationRetried(retryID: Int, appInfo: AppInfo?)
        case inputMethodsLoaded(
            refreshID: Int,
            result: Result<[InputMethod], InputMethodService.InputMethodError>
        )
        case launchAtLoginLoaded(LaunchAtLoginStatus)
        case legacyRulesLoaded(
            [String: AppRuleRecord],
            didCompleteLegacyMigration: Bool
        )
        case programmaticSwitchFinished(attemptID: Int, outcome: State.ProgrammaticSwitchOutcome)
        case runningApps([AppInfo])
    }

    enum SystemAction: Equatable, Sendable {
        case inputMethodAvailabilityChanged
        case inputMethodSelectedChanged(String)
        case workspaceEvent(WorkspaceClient.Event)
    }

    enum Action: Equatable, Sendable {
        case menuDismissed
        case menuPresented
        case task
        case view(ViewAction)
        case response(ResponseAction)
        case system(SystemAction)
    }

    private enum CancelID {
        case inputMethodAvailability
        case inputMethodSelection
        case programmaticSwitch
        case workspaceEvents
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .menuPresented:
                guard !state.isMenuPresented else { return .none }
                state.isMenuPresented = true
                state.menuStrategiesAtPresentation = state.appRules.mapValues(\.strategy)
                return .none

            case .menuDismissed:
                state.isMenuPresented = false
                state.menuStrategiesAtPresentation = [:]
                return .none

            case .task:
                guard !state.isReadmeDemo else { return .none }
                normalizeFallbackRule(in: &state)
                let inputMethodRefreshEffect = beginInputMethodRefresh(in: &state)
                return .merge(
                    .concatenate(
                        migrateLegacyRulesEffect(),
                        .run { send in
                            await send(.response(.launchAtLoginLoaded(await launchAtLoginClient.status())))
                        },
                        .run { send in
                            await send(.response(.frontmostApplicationLoaded(await workspaceClient.frontmostApplication())))
                        },
                        inputMethodRefreshEffect,
                        refreshRunningAppsEffect()
                    ),
                    .run { send in
                        let events = await workspaceClient.events()
                        for await event in events {
                            await send(.system(.workspaceEvent(event)))
                        }
                    }
                    .cancellable(id: CancelID.workspaceEvents, cancelInFlight: true),
                    .run { send in
                        let changes = await inputMethodClient.availabilityChanges()
                        for await _ in changes {
                            await send(.system(.inputMethodAvailabilityChanged))
                        }
                    }
                    .cancellable(id: CancelID.inputMethodAvailability, cancelInFlight: true),
                    .run { send in
                        let changes = await inputMethodClient.selectionChanges()
                        for await inputMethodId in changes {
                            await send(.system(.inputMethodSelectedChanged(inputMethodId)))
                        }
                    }
                    .cancellable(id: CancelID.inputMethodSelection, cancelInFlight: true)
                )

            case .view where state.isReadmeDemo:
                return .none

            case .response(.frontmostApplicationLoaded(let appInfo)):
                state.currentFrontmostBundleId = appInfo?.bundleId
                if let appInfo {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none

            case let .response(.frontmostApplicationRetried(retryID, appInfo)):
                guard state.pendingFrontmostRetryID == retryID else {
                    return .none
                }
                state.pendingFrontmostRetryID = nil
                guard let appInfo else { return .none }
                return handleActivatedApplication(appInfo, state: &state)

            case .system(.inputMethodAvailabilityChanged):
                return beginInputMethodRefresh(in: &state)

            case .system(.inputMethodSelectedChanged(let inputMethodId)):
                if state.pendingProgrammaticSwitch?.inputMethodId == inputMethodId {
                    return .none
                }

                guard let bundleId = state.currentFrontmostBundleId else {
                    return .none
                }

                if case .followLast(let previousInputMethodId) = state.appRules[bundleId]?.strategy {
                    guard previousInputMethodId != inputMethodId else {
                        return .none
                    }

                    let updateDate = now
                    state.$appRulesStore.withLock { store in
                        guard var rule = store.rules[bundleId] else { return }
                        rule.strategy = .followLast(lastInputMethodId: inputMethodId)
                        rule.updatedAt = updateDate
                        store.rules[bundleId] = rule
                    }
                    return .none
                }

                return .none

            case let .response(.inputMethodsLoaded(refreshID, .success(inputMethods))):
                guard state.pendingInputMethodRefreshID == refreshID else {
                    return .none
                }
                state.pendingInputMethodRefreshID = nil
                state.inputMethodCatalogStatus = .ready
                state.inputMethods = inputMethods
                guard state.shouldRetryFrontmostAfterInputMethodRefresh else {
                    return .none
                }
                state.shouldRetryFrontmostAfterInputMethodRefresh = false
                return retryFrontmostApplicationEffect(in: &state)

            case let .response(.inputMethodsLoaded(refreshID, .failure(error))):
                guard state.pendingInputMethodRefreshID == refreshID else {
                    return .none
                }
                state.pendingInputMethodRefreshID = nil
                state.inputMethodCatalogStatus = .failed(error)
                return .none

            case .response(.launchAtLoginLoaded(let status)):
                state.launchAtLoginStatus = status
                return .none

            case let .response(.legacyRulesLoaded(legacyRules, didCompleteLegacyMigration)):
                let mergedRules = AppRulesStoreMigration.merge(
                    currentRules: state.appRules,
                    legacyRules: legacyRules,
                    didCompleteLegacyMigration: didCompleteLegacyMigration
                )
                guard mergedRules != state.appRules else {
                    return markLegacyMigrationCompletedEffect()
                }

                state.$appRulesStore.withLock { store in
                    store.rules = mergedRules
                }
                return saveLegacyMigrationEffect(store: state.$appRulesStore)

            case let .response(.programmaticSwitchFinished(attemptID, outcome)):
                guard let pendingSwitch = state.pendingProgrammaticSwitch,
                      pendingSwitch.attemptID == attemptID
                else {
                    return .none
                }
                state.pendingProgrammaticSwitch = nil
                state.lastSwitchAttempt = .init(
                    appName: pendingSwitch.appName,
                    bundleId: pendingSwitch.bundleId,
                    inputMethodId: pendingSwitch.inputMethodId,
                    inputMethodName: pendingSwitch.inputMethodName,
                    outcome: outcome,
                    ruleSource: pendingSwitch.ruleSource,
                    timestamp: now
                )
                if outcome == .switched {
                    state.$appSwitchStatisticsStore.withLock { store in
                        store.counts[pendingSwitch.bundleId, default: 0] += 1
                    }
                }
                return .none

            case .view(.clearSwitchStatisticsTapped):
                state.$appSwitchStatisticsStore.withLock { store in
                    store.counts.removeAll()
                }
                return .none

            case .view(.ignoreAppTapped(let appInfo)):
                let shouldCancelProgrammaticSwitch = state.currentFrontmostBundleId == appInfo.bundleId
                    || state.pendingProgrammaticSwitch?.bundleId == appInfo.bundleId
                let updateDate = now
                state.$appRulesStore.withLock { store in
                    let currentRule = store.rules[appInfo.bundleId] ?? AppRuleRecord(
                        bundleId: appInfo.bundleId,
                        lastKnownPath: appInfo.path,
                        lastKnownName: appInfo.name,
                        strategy: .none,
                        createdAt: updateDate,
                        updatedAt: updateDate
                    )
                    guard currentRule.strategy != .ignored else { return }

                    var updatedRule = currentRule
                    updatedRule.lastKnownPath = appInfo.path ?? currentRule.lastKnownPath
                    updatedRule.lastKnownName = appInfo.name
                    updatedRule.strategyBeforeIgnoring = currentRule.strategy
                    updatedRule.strategy = .ignored
                    updatedRule.updatedAt = updateDate
                    store.rules[appInfo.bundleId] = updatedRule
                }
                guard shouldCancelProgrammaticSwitch else { return .none }
                state.pendingProgrammaticSwitch = nil
                return .cancel(id: CancelID.programmaticSwitch)

            case .view(.reloadInputMethodsTapped):
                return beginInputMethodRefresh(in: &state)

            case .view(.removeMissingInputMethodRulesTapped):
                guard state.inputMethodCatalogStatus == .ready else {
                    return .none
                }
                let updateDate = now
                let missingBundleIds = state.appRules.values
                    .filter { state.hasMissingInputMethod(in: $0.strategy) }
                    .map(\.bundleId)

                state.$appRulesStore.withLock { store in
                    for bundleId in missingBundleIds {
                        guard var rule = store.rules[bundleId] else { continue }
                        rule.strategy = .none
                        rule.updatedAt = updateDate
                        store.rules[bundleId] = rule
                    }
                }
                return .none

            case .view(.removeUnavailableRulesTapped):
                state.$appRulesStore.withLock { store in
                    store.rules = store.rules.filter {
                        $0.value.isAvailable || $0.value.strategy == .ignored
                    }
                }
                return .none

            case .view(.restoreAllIgnoredAppsTapped):
                let updateDate = now
                state.$appRulesStore.withLock { store in
                    for bundleId in Array(store.rules.keys) {
                        guard var rule = store.rules[bundleId], rule.strategy == .ignored else {
                            continue
                        }
                        rule.strategy = rule.strategyBeforeIgnoring ?? .none
                        rule.strategyBeforeIgnoring = nil
                        rule.updatedAt = updateDate
                        store.rules[bundleId] = rule
                    }
                }
                return .none

            case .view(.restoreIgnoredAppTapped(let bundleId)):
                let updateDate = now
                state.$appRulesStore.withLock { store in
                    guard var rule = store.rules[bundleId], rule.strategy == .ignored else {
                        return
                    }
                    rule.strategy = rule.strategyBeforeIgnoring ?? .none
                    rule.strategyBeforeIgnoring = nil
                    rule.updatedAt = updateDate
                    store.rules[bundleId] = rule
                }
                return .none

            case .view(.retryCurrentAppTapped):
                return retryFrontmostApplicationEffect(in: &state)

            case .response(.runningApps(let runningApps)):
                state.runningApps = runningApps
                for appInfo in runningApps {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none

            case .view(.setFallbackStrategy(let strategy)):
                state.$fallbackRuleStore.withLock { store in
                    let supportedStrategy = fallbackSupportedStrategy(strategy)
                    guard store.strategy != supportedStrategy else {
                        return
                    }

                    store.strategy = supportedStrategy
                }
                return .none

            case .view(.setLaunchAtLogin(let isEnabled)):
                state.launchAtLoginStatus = isEnabled ? .enabled : .disabled
                return .run { send in
                    await send(.response(.launchAtLoginLoaded(await launchAtLoginClient.setEnabled(isEnabled))))
                }

            case let .view(.setStrategy(bundleId, strategy)):
                let updateDate = now
                let fallbackAppInfo = state.runningApps.first(where: { $0.bundleId == bundleId })
                state.$appRulesStore.withLock { store in
                    let currentRule = store.rules[bundleId] ?? AppRuleRecord(
                        bundleId: bundleId,
                        lastKnownPath: fallbackAppInfo?.path,
                        lastKnownName: fallbackAppInfo?.name ?? bundleId,
                        strategy: .none,
                        createdAt: updateDate,
                        updatedAt: updateDate
                    )

                    guard currentRule.strategy != strategy || store.rules[bundleId] == nil else {
                        return
                    }

                    var updatedRule = currentRule
                    updatedRule.strategy = strategy
                    updatedRule.strategyBeforeIgnoring = nil
                    updatedRule.updatedAt = updateDate
                    store.rules[bundleId] = updatedRule
                }
                return .none

            case .system(.workspaceEvent(.launched)):
                return refreshRunningAppsEffect()

            case .system(.workspaceEvent(.terminated(let bundleId))):
                let wasCurrentApp = state.currentFrontmostBundleId == bundleId
                if wasCurrentApp {
                    state.currentFrontmostBundleId = nil
                    state.pendingFrontmostRetryID = nil
                    state.shouldRetryFrontmostAfterInputMethodRefresh = false
                }
                let shouldCancelProgrammaticSwitch = wasCurrentApp
                    || state.pendingProgrammaticSwitch?.bundleId == bundleId
                guard shouldCancelProgrammaticSwitch else {
                    return refreshRunningAppsEffect()
                }
                state.pendingProgrammaticSwitch = nil
                return .merge(
                    .cancel(id: CancelID.programmaticSwitch),
                    refreshRunningAppsEffect()
                )

            case .system(.workspaceEvent(.activated(let appInfo))):
                state.pendingFrontmostRetryID = nil
                return handleActivatedApplication(appInfo, state: &state)
            }
        }
    }

    private func handleActivatedApplication(_ appInfo: AppInfo, state: inout State) -> Effect<Action> {
        state.currentFrontmostBundleId = appInfo.bundleId
        upsertRecord(for: appInfo, in: &state)

        switch resolveSwitchTarget(for: appInfo.bundleId, state: state) {
        case .none:
            state.pendingProgrammaticSwitch = nil
            state.shouldRetryFrontmostAfterInputMethodRefresh = false
            return .cancel(id: CancelID.programmaticSwitch)
        case .waitingForCatalog:
            state.pendingProgrammaticSwitch = nil
            state.shouldRetryFrontmostAfterInputMethodRefresh = true
            return .cancel(id: CancelID.programmaticSwitch)
        case let .unavailable(inputMethodId, ruleSource):
            state.pendingProgrammaticSwitch = nil
            state.shouldRetryFrontmostAfterInputMethodRefresh = false
            state.lastSwitchAttempt = .init(
                appName: appInfo.name,
                bundleId: appInfo.bundleId,
                inputMethodId: inputMethodId,
                inputMethodName: nil,
                outcome: .failed(.inputMethodNotFound(inputMethodId)),
                ruleSource: ruleSource,
                timestamp: now
            )
            return .cancel(id: CancelID.programmaticSwitch)
        case let .target(inputMethod, ruleSource):
            state.shouldRetryFrontmostAfterInputMethodRefresh = false
            let attemptID = state.nextSwitchAttemptID
            state.nextSwitchAttemptID += 1
            state.pendingProgrammaticSwitch = .init(
                appName: appInfo.name,
                attemptID: attemptID,
                bundleId: appInfo.bundleId,
                inputMethodId: inputMethod.id,
                inputMethodName: inputMethod.name,
                ruleSource: ruleSource
            )

            return .run { send in
                let outcome: State.ProgrammaticSwitchOutcome
                do {
                    if (try? await inputMethodClient.currentInputMethodId()) == inputMethod.id {
                        outcome = .alreadySelected
                    } else {
                        guard !Task.isCancelled else { return }
                        try await inputMethodClient.switchToInputMethod(inputMethod.id)
                        outcome = .switched
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    outcome = .failed(.diagnostic(from: error))
                }
                guard !Task.isCancelled else { return }
                await send(.response(.programmaticSwitchFinished(
                    attemptID: attemptID,
                    outcome: outcome
                )))
            }
            .cancellable(id: CancelID.programmaticSwitch, cancelInFlight: true)
        }
    }

    private func migrateLegacyRulesEffect() -> Effect<Action> {
        .run { send in
            guard await legacyDefaultsMigrationClient.completedVersion() < LegacyDefaultsMigration.currentVersion else {
                return
            }

            let legacyRules = await legacyDefaultsMigrationClient.loadRules(now)
            let didCompleteLegacyMigration = await legacyDefaultsMigrationClient.didCompleteLegacyMigration()
            await send(.response(.legacyRulesLoaded(
                legacyRules,
                didCompleteLegacyMigration: didCompleteLegacyMigration
            )))
        }
    }

    private func saveLegacyMigrationEffect(store: Shared<AppRulesStore>) -> Effect<Action> {
        .run { _ in
            do {
                try await appRulesStoreMigrationClient.save(store)
                await legacyDefaultsMigrationClient.markCompleted(LegacyDefaultsMigration.currentVersion)
            } catch {
                print("⚠️ 规则存储迁移保存失败: \(error.localizedDescription)")
            }
        }
    }

    private func markLegacyMigrationCompletedEffect() -> Effect<Action> {
        .run { _ in
            await legacyDefaultsMigrationClient.markCompleted(LegacyDefaultsMigration.currentVersion)
        }
    }

    private func beginInputMethodRefresh(in state: inout State) -> Effect<Action> {
        let refreshID = state.nextInputMethodRefreshID
        state.nextInputMethodRefreshID += 1
        state.pendingInputMethodRefreshID = refreshID
        state.inputMethodCatalogStatus = .loading
        return refreshInputMethodsEffect(refreshID: refreshID)
    }

    private func refreshInputMethodsEffect(refreshID: Int) -> Effect<Action> {
        .run { send in
            do {
                let inputMethods = try await inputMethodClient.fetchInputMethods()
                guard !Task.isCancelled else { return }
                await send(.response(.inputMethodsLoaded(
                    refreshID: refreshID,
                    result: .success(inputMethods)
                )))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.response(.inputMethodsLoaded(
                    refreshID: refreshID,
                    result: .failure(.diagnostic(from: error))
                )))
            }
        }
    }

    private func refreshRunningAppsEffect() -> Effect<Action> {
        .run { send in
            await send(.response(.runningApps(await workspaceClient.runningApplications())))
        }
    }

    private enum SwitchTargetResolution {
        case none
        case target(InputMethod, State.RuleSource)
        case unavailable(String, State.RuleSource)
        case waitingForCatalog
    }

    private func resolveSwitchTarget(for bundleId: String, state: State) -> SwitchTargetResolution {
        let appStrategy = state.strategy(for: bundleId)
        let strategy = appStrategy == .none ? state.fallbackStrategy : appStrategy
        let ruleSource: State.RuleSource = appStrategy == .none ? .fallback : .app
        let candidateId: String?

        switch strategy {
        case .ignored, .none:
            return .none
        case .fixed(let inputMethodId):
            candidateId = inputMethodId
        case .followLast(let lastInputMethodId):
            candidateId = lastInputMethodId
        }

        guard let candidateId else {
            return .none
        }
        if let inputMethod = state.inputMethods.first(where: { $0.id == candidateId }) {
            return .target(inputMethod, ruleSource)
        }
        switch state.inputMethodCatalogStatus {
        case .loading:
            return .waitingForCatalog
        case .ready:
            return .unavailable(candidateId, ruleSource)
        case .failed:
            return .waitingForCatalog
        }
    }

    private func retryFrontmostApplicationEffect(in state: inout State) -> Effect<Action> {
        let retryID = state.nextFrontmostRetryID
        state.nextFrontmostRetryID += 1
        state.pendingFrontmostRetryID = retryID
        return .run { send in
            await send(.response(.frontmostApplicationRetried(
                retryID: retryID,
                appInfo: await workspaceClient.frontmostApplication()
            )))
        }
    }

    private func fallbackSupportedStrategy(_ strategy: InputMethodStrategy) -> InputMethodStrategy {
        switch strategy {
        case .followLast, .ignored:
            return .none
        case .none, .fixed:
            return strategy
        }
    }

    private func normalizeFallbackRule(in state: inout State) {
        state.$fallbackRuleStore.withLock { store in
            let supportedStrategy = fallbackSupportedStrategy(store.strategy)
            guard store.strategy != supportedStrategy else {
                return
            }
            store.strategy = supportedStrategy
        }
    }

    private func upsertRecord(for appInfo: AppInfo, in state: inout State) {
        let updateDate = now
        state.$appRulesStore.withLock { store in
            guard var existingRule = store.rules[appInfo.bundleId] else {
                store.rules[appInfo.bundleId] = AppRuleRecord(
                    bundleId: appInfo.bundleId,
                    lastKnownPath: appInfo.path,
                    lastKnownName: appInfo.name,
                    strategy: .none,
                    createdAt: updateDate,
                    updatedAt: updateDate
                )
                return
            }

            guard existingRule.lastKnownPath != appInfo.path || existingRule.lastKnownName != appInfo.name else {
                return
            }

            existingRule.lastKnownPath = appInfo.path
            existingRule.lastKnownName = appInfo.name
            existingRule.updatedAt = updateDate
            store.rules[appInfo.bundleId] = existingRule
        }
    }
}

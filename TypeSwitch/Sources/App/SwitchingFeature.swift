import ComposableArchitecture
import Foundation
import Sharing

/// Owns switching, catalog recovery, and frontmost retries as one event sequence.
@Reducer
struct SwitchingFeature {
    @Dependency(\.date.now) var now
    @Dependency(\.inputMethodClient) var inputMethodClient
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

        struct PendingProgrammaticSwitch: Equatable {
            let appName: String
            let attemptID: Int
            let bundleId: String
            var didObserveTargetSelection: Bool
            let inputMethodId: String
            let inputMethodName: String?
            let ruleSource: RuleSource

            init(
                appName: String = "",
                attemptID: Int = 0,
                bundleId: String,
                didObserveTargetSelection: Bool = false,
                inputMethodId: String,
                inputMethodName: String? = nil,
                ruleSource: RuleSource = .app
            ) {
                self.appName = appName
                self.attemptID = attemptID
                self.bundleId = bundleId
                self.didObserveTargetSelection = didObserveTargetSelection
                self.inputMethodId = inputMethodId
                self.inputMethodName = inputMethodName
                self.ruleSource = ruleSource
            }
        }

        @Shared var appRulesStore: AppRulesStore
        @Shared var appSwitchStatisticsStore: AppSwitchStatisticsStore
        @Shared var fallbackRuleStore: FallbackRuleStore
        var currentFrontmostBundleId: String?
        var inputMethodCatalogStatus: InputMethodCatalogStatus = .loading
        var inputMethods: [InputMethod] = []
        var lastSwitchAttempt: LastSwitchAttempt?
        var nextFrontmostRetryID = 0
        var nextInputMethodRefreshID = 0
        var nextSwitchAttemptID = 0
        var pendingFrontmostRetryID: Int?
        var pendingInputMethodRefreshID: Int?
        var pendingProgrammaticSwitch: PendingProgrammaticSwitch?
        var shouldRetryFrontmostAfterInputMethodRefresh = false

        init(
            appRulesStore: Shared<AppRulesStore>,
            appSwitchStatisticsStore: Shared<AppSwitchStatisticsStore>,
            fallbackRuleStore: Shared<FallbackRuleStore>,
            currentFrontmostBundleId: String? = nil,
            inputMethodCatalogStatus: InputMethodCatalogStatus = .loading,
            inputMethods: [InputMethod] = [],
            lastSwitchAttempt: LastSwitchAttempt? = nil
        ) {
            self._appRulesStore = appRulesStore
            self._appSwitchStatisticsStore = appSwitchStatisticsStore
            self._fallbackRuleStore = fallbackRuleStore
            self.currentFrontmostBundleId = currentFrontmostBundleId
            self.inputMethodCatalogStatus = inputMethodCatalogStatus
            self.inputMethods = inputMethods
            self.lastSwitchAttempt = lastSwitchAttempt
        }

        func strategy(for bundleId: String) -> InputMethodStrategy {
            appRulesStore.rules[bundleId]?.strategy ?? .none
        }

        var fallbackStrategy: InputMethodStrategy {
            switch fallbackRuleStore.strategy {
            case .followLast, .ignored:
                return .none
            case .none, .fixed:
                return fallbackRuleStore.strategy
            }
        }

        func isCurrentTarget(_ attempt: LastSwitchAttempt) -> Bool {
            let appStrategy = strategy(for: attempt.bundleId)
            switch attempt.ruleSource {
            case .app:
                return inputMethodId(for: appStrategy) == attempt.inputMethodId
            case .fallback:
                return appStrategy == .none
                    && inputMethodId(for: fallbackStrategy) == attempt.inputMethodId
            }
        }

        private func inputMethodId(for strategy: InputMethodStrategy) -> String? {
            switch strategy {
            case .fixed(let inputMethodId):
                return inputMethodId
            case .followLast(let lastInputMethodId):
                return lastInputMethodId
            case .ignored, .none:
                return nil
            }
        }
    }

    enum ResponseAction: Equatable, Sendable {
        case frontmostApplicationLoaded(AppInfo?)
        case frontmostApplicationRetried(retryID: Int, appInfo: AppInfo?)
        case inputMethodsLoaded(
            refreshID: Int,
            result: Result<[InputMethod], InputMethodService.InputMethodError>
        )
        case programmaticSwitchFinished(attemptID: Int, outcome: State.ProgrammaticSwitchOutcome)
    }

    enum SystemAction: Equatable, Sendable {
        case inputMethodAvailabilityChanged
        case inputMethodSelectedChanged(String)
    }

    enum Action: Equatable, Sendable {
        case loadInitialState
        case observeInputMethods
        case reloadInputMethods
        case retryCurrentApp
        case applicationActivated(AppInfo)
        case applicationTerminated(bundleId: String)
        case applicationIgnored(bundleId: String)
        case response(ResponseAction)
        case system(SystemAction)
    }

    private enum CancelID {
        case inputMethodAvailability
        case inputMethodSelection
        case programmaticSwitch
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadInitialState:
                let refreshEffect = beginInputMethodRefresh(in: &state)
                return .concatenate(
                    .run { send in
                        await send(.response(.frontmostApplicationLoaded(await workspaceClient.frontmostApplication())))
                    },
                    refreshEffect
                )

            case .observeInputMethods:
                return .merge(
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

            case .response(.frontmostApplicationLoaded(let appInfo)):
                state.currentFrontmostBundleId = appInfo?.bundleId
                if let appInfo {
                    state.$appRulesStore.withLock { $0.upsertRecord(for: appInfo, at: now) }
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
                if var pendingSwitch = state.pendingProgrammaticSwitch {
                    if pendingSwitch.inputMethodId == inputMethodId {
                        pendingSwitch.didObserveTargetSelection = true
                        state.pendingProgrammaticSwitch = pendingSwitch
                        return .none
                    }
                    if pendingSwitch.didObserveTargetSelection {
                        pendingSwitch.didObserveTargetSelection = false
                        state.pendingProgrammaticSwitch = pendingSwitch
                    }
                }

                guard let bundleId = state.currentFrontmostBundleId else {
                    return .none
                }

                if let lastSwitchAttempt = state.lastSwitchAttempt,
                   lastSwitchAttempt.bundleId == bundleId,
                   lastSwitchAttempt.inputMethodId == inputMethodId,
                   case .failed = lastSwitchAttempt.outcome
                {
                    state.lastSwitchAttempt = nil
                }

                if case .followLast(let previousInputMethodId) = state.appRulesStore.rules[bundleId]?.strategy {
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

            case let .response(.programmaticSwitchFinished(attemptID, outcome)):
                guard let pendingSwitch = state.pendingProgrammaticSwitch,
                      pendingSwitch.attemptID == attemptID
                else {
                    return .none
                }
                state.pendingProgrammaticSwitch = nil
                let resolvedOutcome: State.ProgrammaticSwitchOutcome
                if pendingSwitch.didObserveTargetSelection,
                   case .failed = outcome
                {
                    resolvedOutcome = .alreadySelected
                } else {
                    resolvedOutcome = outcome
                }
                state.lastSwitchAttempt = .init(
                    appName: pendingSwitch.appName,
                    bundleId: pendingSwitch.bundleId,
                    inputMethodId: pendingSwitch.inputMethodId,
                    inputMethodName: pendingSwitch.inputMethodName,
                    outcome: resolvedOutcome,
                    ruleSource: pendingSwitch.ruleSource,
                    timestamp: now
                )
                if resolvedOutcome == .switched {
                    state.$appSwitchStatisticsStore.withLock { store in
                        store.counts[pendingSwitch.bundleId, default: 0] += 1
                    }
                }
                return .none

            case .reloadInputMethods:
                return beginInputMethodRefresh(in: &state)

            case .retryCurrentApp:
                return retryFrontmostApplicationEffect(in: &state)

            case .applicationIgnored(let bundleId):
                guard state.currentFrontmostBundleId == bundleId
                    || state.pendingProgrammaticSwitch?.bundleId == bundleId
                else { return .none }
                state.pendingProgrammaticSwitch = nil
                return .cancel(id: CancelID.programmaticSwitch)

            case .applicationTerminated(let bundleId):
                let wasCurrentApp = state.currentFrontmostBundleId == bundleId
                if wasCurrentApp {
                    state.currentFrontmostBundleId = nil
                    state.pendingFrontmostRetryID = nil
                    state.shouldRetryFrontmostAfterInputMethodRefresh = false
                }
                guard wasCurrentApp || state.pendingProgrammaticSwitch?.bundleId == bundleId else {
                    return .none
                }
                state.pendingProgrammaticSwitch = nil
                return .cancel(id: CancelID.programmaticSwitch)

            case .applicationActivated(let appInfo):
                state.pendingFrontmostRetryID = nil
                return handleActivatedApplication(appInfo, state: &state)
            }
        }
    }

    private func handleActivatedApplication(_ appInfo: AppInfo, state: inout State) -> Effect<Action> {
        state.currentFrontmostBundleId = appInfo.bundleId
        state.$appRulesStore.withLock { $0.upsertRecord(for: appInfo, at: now) }

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
}

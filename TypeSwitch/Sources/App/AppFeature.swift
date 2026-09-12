import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct AppFeature {
    @Dependency(\.appAvailabilityClient) var appAvailabilityClient
    @Dependency(\.date.now) var now
    @Dependency(\.launchAtLoginClient) var launchAtLoginClient
    @Dependency(\.workspaceClient) var workspaceClient

    @ObservableState
    struct State: Equatable {
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
        var switching: SwitchingFeature.State
        var appAvailability = AppAvailabilitySnapshot()
        var isMenuPresented = false
        var isReadmeDemo = false
        var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
        var menuStrategiesAtPresentation: [String: InputMethodStrategy] = [:]
        var runningApps: [AppInfo] = []

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
            appAvailability: AppAvailabilitySnapshot = AppAvailabilitySnapshot(),
            currentFrontmostBundleId: String? = nil,
            inputMethodCatalogStatus: SwitchingFeature.State.InputMethodCatalogStatus = .loading,
            inputMethods: [InputMethod] = [],
            isMenuPresented: Bool = false,
            isReadmeDemo: Bool = false,
            lastSwitchAttempt: SwitchingFeature.State.LastSwitchAttempt? = nil,
            launchAtLoginStatus: LaunchAtLoginStatus = .disabled,
            menuStrategiesAtPresentation: [String: InputMethodStrategy] = [:],
            runningApps: [AppInfo] = []
        ) {
            self._appRulesStore = appRulesStore
            self._appSwitchStatisticsStore = appSwitchStatisticsStore
            self._fallbackRuleStore = fallbackRuleStore
            self.switching = SwitchingFeature.State(
                appRulesStore: appRulesStore,
                appSwitchStatisticsStore: appSwitchStatisticsStore,
                fallbackRuleStore: fallbackRuleStore,
                currentFrontmostBundleId: currentFrontmostBundleId,
                inputMethodCatalogStatus: inputMethodCatalogStatus,
                inputMethods: inputMethods,
                lastSwitchAttempt: lastSwitchAttempt
            )
            self.appAvailability = appAvailability
            self.isMenuPresented = isMenuPresented
            self.isReadmeDemo = isReadmeDemo
            self.launchAtLoginStatus = launchAtLoginStatus
            self.menuStrategiesAtPresentation = menuStrategiesAtPresentation
            self.runningApps = runningApps
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
        case launchAtLoginLoaded(LaunchAtLoginStatus)
        case runningApps([AppInfo])
    }

    enum SystemAction: Equatable, Sendable {
        case workspaceEvent(WorkspaceClient.Event)
    }

    enum Action: Equatable, Sendable {
        case menuDismissed
        case menuPresented
        case task
        case view(ViewAction)
        case response(ResponseAction)
        case system(SystemAction)
        case switching(SwitchingFeature.Action)
    }

    private enum CancelID {
        case workspaceEvents
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .menuPresented:
                guard !state.isMenuPresented else { return .none }
                if !state.isReadmeDemo {
                    state.appAvailability = appAvailabilityClient.snapshot(for: state.appRules.values)
                }
                state.isMenuPresented = true
                state.menuStrategiesAtPresentation = state.appRules.mapValues(\.strategy)
                return .none

            case .menuDismissed:
                state.isMenuPresented = false
                state.menuStrategiesAtPresentation = [:]
                return .none

            case .task:
                guard !state.isReadmeDemo else { return .none }
                state.appAvailability = appAvailabilityClient.snapshot(for: state.appRules.values)
                normalizeFallbackRule(in: &state)
                let initialSwitchingEffect = reduceSwitching(.loadInitialState, state: &state)
                return .merge(
                    .concatenate(
                        .run { send in
                            await send(.response(.launchAtLoginLoaded(await launchAtLoginClient.status())))
                        },
                        initialSwitchingEffect,
                        refreshRunningAppsEffect()
                    ),
                    .run { send in
                        let events = await workspaceClient.events()
                        for await event in events {
                            await send(.system(.workspaceEvent(event)))
                        }
                    }
                    .cancellable(id: CancelID.workspaceEvents, cancelInFlight: true),
                    reduceSwitching(.observeInputMethods, state: &state)
                )

            case .view where state.isReadmeDemo:
                return .none

            case .response(.launchAtLoginLoaded(let status)):
                state.launchAtLoginStatus = status
                return .none

            case .view(.clearSwitchStatisticsTapped):
                state.$appSwitchStatisticsStore.withLock { store in
                    store.counts.removeAll()
                }
                return .none

            case .view(.ignoreAppTapped(let appInfo)):
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
                return reduceSwitching(.applicationIgnored(bundleId: appInfo.bundleId), state: &state)

            case .view(.reloadInputMethodsTapped):
                return reduceSwitching(.reloadInputMethods, state: &state)

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
                // Deletion must recheck paths rather than trust the menu snapshot.
                let availability = appAvailabilityClient.snapshot(for: state.appRules.values)
                state.appAvailability = availability
                state.$appRulesStore.withLock { store in
                    store.rules = store.rules.filter {
                        availability.isAvailable($0.value) || $0.value.strategy == .ignored
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
                return reduceSwitching(.retryCurrentApp, state: &state)

            case .response(.runningApps(let runningApps)):
                state.runningApps = runningApps
                for appInfo in runningApps {
                    state.$appRulesStore.withLock { $0.upsertRecord(for: appInfo, at: now) }
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
                return .merge(
                    reduceSwitching(.applicationTerminated(bundleId: bundleId), state: &state),
                    refreshRunningAppsEffect()
                )

            case .system(.workspaceEvent(.activated(let appInfo))):
                return reduceSwitching(.applicationActivated(appInfo), state: &state)

            case .switching(let action):
                return reduceSwitching(action, state: &state)
            }
        }
    }

    // Route synchronously so ignore/termination invalidate pending work in this turn.
    private func reduceSwitching(_ action: SwitchingFeature.Action, state: inout State) -> Effect<Action> {
        SwitchingFeature().reduce(into: &state.switching, action: action).map(Action.switching)
    }

    private func refreshRunningAppsEffect() -> Effect<Action> {
        .run { send in
            await send(.response(.runningApps(await workspaceClient.runningApplications())))
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
}

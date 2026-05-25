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
        struct AppMenuItem: Equatable, Identifiable {
            let bundleId: String
            let name: String
            let path: String?
            let strategy: InputMethodStrategy
            let selectedLabel: String?
            let followLastOptionLabel: String
            let hasMissingInputMethod: Bool
            
            var id: String { bundleId }
        }
        
        struct PendingProgrammaticSwitch: Equatable {
            let bundleId: String
            let inputMethodId: String
        }
        
        @Shared(.fileStorage(.appRulesStoreURL)) var appRulesStore = AppRulesStore()
        @Shared(.fileStorage(.fallbackRuleStoreURL)) var fallbackRuleStore = FallbackRuleStore()
        var currentFrontmostBundleId: String?
        var inputMethods: [InputMethod] = []
        var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
        var pendingProgrammaticSwitch: PendingProgrammaticSwitch?
        var runningApps: [AppInfo] = []
    }
    
    enum ViewAction: Equatable, Sendable {
        case removeMissingInputMethodRulesTapped
        case removeUnavailableRulesTapped
        case setFallbackStrategy(InputMethodStrategy)
        case setLaunchAtLogin(Bool)
        case setStrategy(bundleId: String, strategy: InputMethodStrategy)
    }

    enum ResponseAction: Equatable, Sendable {
        case appRulesStorePrepared(AppRulesStoreMigration.PrepareResult)
        case frontmostApplicationLoaded(AppInfo?)
        case inputMethods([InputMethod])
        case launchAtLoginLoaded(LaunchAtLoginStatus)
        case legacyRulesMigrated([String: AppRuleRecord])
        case programmaticSwitchFinished(bundleId: String, inputMethodId: String)
        case runningApps([AppInfo])
    }

    enum SystemAction: Equatable, Sendable {
        case inputMethodAvailabilityChanged
        case inputMethodSelectedChanged(String)
        case workspaceEvent(WorkspaceClient.Event)
    }

    enum Action: Equatable, Sendable {
        case task
        case view(ViewAction)
        case response(ResponseAction)
        case system(SystemAction)
    }
    
    private enum CancelID {
        case inputMethodAvailability
        case inputMethodSelection
        case workspaceEvents
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .concatenate(
                        prepareAppRulesStoreMigrationEffect(),
                        .run { send in
                            await send(.response(.launchAtLoginLoaded(await launchAtLoginClient.status())))
                        },
                        .run { send in
                            await send(.response(.frontmostApplicationLoaded(await workspaceClient.frontmostApplication())))
                        },
                        refreshInputMethodsEffect(),
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

            case .response(.appRulesStorePrepared(let result)):
                switch result {
                case .currentStorePresent:
                    return .none
                case .noStoreFound:
                    return migrateLegacyRulesEffect()
                }
                
            case .response(.frontmostApplicationLoaded(let appInfo)):
                state.currentFrontmostBundleId = appInfo?.bundleId
                if let appInfo {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none
                
            case .system(.inputMethodAvailabilityChanged):
                return refreshInputMethodsEffect()
                
            case .system(.inputMethodSelectedChanged(let inputMethodId)):
                if state.pendingProgrammaticSwitch?.inputMethodId == inputMethodId {
                    state.pendingProgrammaticSwitch = nil
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

                guard state.strategy(for: bundleId) == .none else {
                    return .none
                }

                state.$fallbackRuleStore.withLock { store in
                    guard case .followLast(let previousInputMethodId) = store.strategy else {
                        return
                    }
                    guard previousInputMethodId != inputMethodId else {
                        return
                    }

                    store.strategy = .followLast(lastInputMethodId: inputMethodId)
                }
                return .none
                
            case .response(.inputMethods(let inputMethods)):
                state.inputMethods = inputMethods
                return .none
                
            case .response(.launchAtLoginLoaded(let status)):
                state.launchAtLoginStatus = status
                return .none
                
            case .response(.legacyRulesMigrated(let migratedRules)):
                state.$appRulesStore.withLock { store in
                    store.rules.merge(migratedRules) { _, newValue in newValue }
                }
                return .none
                
            case let .response(.programmaticSwitchFinished(bundleId, inputMethodId)):
                if state.pendingProgrammaticSwitch == .init(bundleId: bundleId, inputMethodId: inputMethodId) {
                    state.pendingProgrammaticSwitch = nil
                }
                return .none
                
            case .view(.removeMissingInputMethodRulesTapped):
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
                    store.rules = store.rules.filter { $0.value.isAvailable }
                }
                return .none
                
            case .response(.runningApps(let runningApps)):
                state.runningApps = runningApps
                for appInfo in runningApps {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none

            case .view(.setFallbackStrategy(let strategy)):
                state.$fallbackRuleStore.withLock { store in
                    guard store.strategy != strategy else {
                        return
                    }

                    store.strategy = strategy
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
                    updatedRule.updatedAt = updateDate
                    store.rules[bundleId] = updatedRule
                }
                return .none

            case .system(.workspaceEvent(.launched(_))):
                return refreshRunningAppsEffect()
                
            case .system(.workspaceEvent(.terminated(let bundleId))):
                if state.currentFrontmostBundleId == bundleId {
                    state.currentFrontmostBundleId = nil
                }
                return refreshRunningAppsEffect()
                
            case .system(.workspaceEvent(.activated(let appInfo))):
                state.currentFrontmostBundleId = appInfo.bundleId
                upsertRecord(for: appInfo, in: &state)
                
                guard let inputMethodId = targetInputMethodId(for: appInfo.bundleId, state: state) else {
                    state.pendingProgrammaticSwitch = nil
                    return .none
                }
                
                state.pendingProgrammaticSwitch = .init(
                    bundleId: appInfo.bundleId,
                    inputMethodId: inputMethodId
                )
                
                return .run { send in
                    if (try? await inputMethodClient.currentInputMethodId()) != inputMethodId {
                        try? await inputMethodClient.switchToInputMethod(inputMethodId)
                    }
                    await send(.response(.programmaticSwitchFinished(bundleId: appInfo.bundleId, inputMethodId: inputMethodId)))
                }
            }
        }
    }

    private func prepareAppRulesStoreMigrationEffect() -> Effect<Action> {
        .run { send in
            await send(.response(.appRulesStorePrepared(await appRulesStoreMigrationClient.prepareStore())))
        }
    }

    private func migrateLegacyRulesEffect() -> Effect<Action> {
        .run { send in
            guard !(await legacyDefaultsMigrationClient.didCompleteMigration()) else {
                return
            }

            let migratedRules = await legacyDefaultsMigrationClient.migrateRules(now)
            await send(.response(.legacyRulesMigrated(migratedRules)))
        }
    }
    
    private func refreshInputMethodsEffect() -> Effect<Action> {
        .run { send in
            let inputMethods = (try? await inputMethodClient.fetchInputMethods()) ?? []
            await send(.response(.inputMethods(inputMethods)))
        }
    }

    private func refreshRunningAppsEffect() -> Effect<Action> {
        .run { send in
            await send(.response(.runningApps(await workspaceClient.runningApplications())))
        }
    }
    
    private func targetInputMethodId(for bundleId: String, state: State) -> String? {
        let appStrategy = state.strategy(for: bundleId)
        let strategy = appStrategy == .none ? state.fallbackStrategy : appStrategy
        let candidateId: String?
        
        switch strategy {
        case .none:
            return nil
        case .fixed(let inputMethodId):
            candidateId = inputMethodId
        case .followLast(let lastInputMethodId):
            candidateId = lastInputMethodId
        }
        
        guard let candidateId else {
            return nil
        }
        return state.inputMethods.contains(where: { $0.id == candidateId }) ? candidateId : nil
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

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

        var launchAtLoginEnabled: Bool {
            launchAtLoginStatus.isToggleOn
        }

        var launchAtLoginRequiresApproval: Bool {
            launchAtLoginStatus == .requiresApproval
        }

        var appRules: [String: AppRuleRecord] {
            appRulesStore.rules
        }

        var fallbackStrategy: InputMethodStrategy {
            fallbackRuleStore.strategy
        }

        var fallbackSelectedLabel: String? {
            selectedLabel(for: fallbackStrategy)
        }

        var fallbackFollowLastOptionLabel: String {
            followLastOptionLabel(for: fallbackStrategy)
        }

        var fallbackHasMissingInputMethod: Bool {
            hasMissingInputMethod(in: fallbackStrategy)
        }
        
        private var sortedRules: [AppRuleRecord] {
            appRules.values.sorted {
                $0.lastKnownName.localizedStandardCompare($1.lastKnownName) == .orderedAscending
            }
        }
        
        var configuredApps: [AppMenuItem] {
            sortedRules
                .filter { $0.strategy != .none && $0.isAvailable }
                .map(menuItem(from:))
        }
        
        var runningMenuItems: [AppMenuItem] {
            runningApps.map { app in
                menuItem(
                    bundleId: app.bundleId,
                    name: app.name,
                    path: app.path,
                    strategy: appRules[app.bundleId]?.strategy ?? .none
                )
            }
        }
        
        var unavailableApps: [AppMenuItem] {
            sortedRules
                .filter { !$0.isAvailable }
                .map {
                    menuItem(
                        bundleId: $0.bundleId,
                        name: $0.lastKnownName,
                        path: nil,
                        strategy: $0.strategy
                    )
                }
        }

        var hasMissingInputMethodRules: Bool {
            appRules.values.contains { hasMissingInputMethod(in: $0.strategy) }
        }
        
        func strategy(for bundleId: String) -> InputMethodStrategy {
            appRules[bundleId]?.strategy ?? .none
        }

        func hasMissingInputMethod(in strategy: InputMethodStrategy) -> Bool {
            switch strategy {
            case .none:
                return false
            case .fixed(let inputMethodId):
                return inputMethodName(for: inputMethodId) == nil
            case .followLast(let lastInputMethodId):
                guard let lastInputMethodId else { return false }
                return inputMethodName(for: lastInputMethodId) == nil
            }
        }
        
        private func menuItem(from rule: AppRuleRecord) -> AppMenuItem {
            menuItem(
                bundleId: rule.bundleId,
                name: rule.lastKnownName,
                path: rule.isAvailable ? rule.lastKnownPath : nil,
                strategy: rule.strategy
            )
        }
        
        private func menuItem(
            bundleId: String,
            name: String,
            path: String?,
            strategy: InputMethodStrategy
        ) -> AppMenuItem {
            AppMenuItem(
                bundleId: bundleId,
                name: name,
                path: path,
                strategy: strategy,
                selectedLabel: selectedLabel(for: strategy),
                followLastOptionLabel: followLastOptionLabel(for: strategy),
                hasMissingInputMethod: hasMissingInputMethod(in: strategy)
            )
        }
        
        private func selectedLabel(for strategy: InputMethodStrategy) -> String? {
            switch strategy {
            case .none:
                return nil
            case .fixed(let inputMethodId):
                return inputMethodName(for: inputMethodId) ?? TypeSwitchStrings.InputMethod.deletedOption
            case .followLast(let lastInputMethodId):
                if let lastInputMethodId, inputMethodName(for: lastInputMethodId) == nil {
                    return TypeSwitchStrings.InputMethod.followLastMissingOption
                }
                return TypeSwitchStrings.InputMethod.followLastOption
            }
        }

        private func followLastOptionLabel(for strategy: InputMethodStrategy) -> String {
            guard case .followLast(let lastInputMethodId) = strategy else {
                return TypeSwitchStrings.InputMethod.followLastEmptyOption
            }

            guard let lastInputMethodId else {
                return TypeSwitchStrings.InputMethod.followLastEmptyOption
            }

            guard let inputMethodName = inputMethodName(for: lastInputMethodId) else {
                return TypeSwitchStrings.InputMethod.followLastMissingOption
            }

            return inputMethodName
        }

        private func inputMethodName(for inputMethodId: String) -> String? {
            inputMethods.first(where: { $0.id == inputMethodId })?.name
        }
    }
    
    enum Action: Equatable {
        case appRulesStorePrepared(AppRulesStoreMigration.PrepareResult)
        case task
        case frontmostApplicationLoaded(AppInfo?)
        case inputMethodAvailabilityChanged
        case inputMethodSelectedChanged(String)
        case inputMethodsResponse([InputMethod])
        case launchAtLoginLoaded(LaunchAtLoginStatus)
        case migrateLegacyRules
        case legacyRulesMigrated([String: AppRuleRecord])
        case programmaticSwitchFinished(bundleId: String, inputMethodId: String)
        case refreshRunningApps
        case removeMissingInputMethodRulesTapped
        case removeUnavailableRulesTapped
        case runningAppsResponse([AppInfo])
        case setFallbackStrategy(InputMethodStrategy)
        case setLaunchAtLogin(Bool)
        case setStrategy(bundleId: String, strategy: InputMethodStrategy)
        case prepareAppRulesStoreMigration
        case workspaceEvent(WorkspaceClient.Event)
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
                        .send(.prepareAppRulesStoreMigration),
                        .run { send in
                            await send(.launchAtLoginLoaded(await launchAtLoginClient.status()))
                        },
                        .run { send in
                            await send(.frontmostApplicationLoaded(await workspaceClient.frontmostApplication()))
                        },
                        refreshInputMethodsEffect(),
                        .send(.refreshRunningApps)
                    ),
                    .run { send in
                        let events = await workspaceClient.events()
                        for await event in events {
                            await send(.workspaceEvent(event))
                        }
                    }
                    .cancellable(id: CancelID.workspaceEvents, cancelInFlight: true),
                    .run { send in
                        let changes = await inputMethodClient.availabilityChanges()
                        for await _ in changes {
                            await send(.inputMethodAvailabilityChanged)
                        }
                    }
                    .cancellable(id: CancelID.inputMethodAvailability, cancelInFlight: true),
                    .run { send in
                        let changes = await inputMethodClient.selectionChanges()
                        for await inputMethodId in changes {
                            await send(.inputMethodSelectedChanged(inputMethodId))
                        }
                    }
                    .cancellable(id: CancelID.inputMethodSelection, cancelInFlight: true)
                )

            case .appRulesStorePrepared(let result):
                switch result {
                case .currentStorePresent:
                    return .none
                case .noStoreFound:
                    return .send(.migrateLegacyRules)
                }
                
            case .frontmostApplicationLoaded(let appInfo):
                state.currentFrontmostBundleId = appInfo?.bundleId
                if let appInfo {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none
                
            case .inputMethodAvailabilityChanged:
                return refreshInputMethodsEffect()
                
            case .inputMethodSelectedChanged(let inputMethodId):
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
                
            case .inputMethodsResponse(let inputMethods):
                state.inputMethods = inputMethods
                return .none
                
            case .launchAtLoginLoaded(let status):
                state.launchAtLoginStatus = status
                return .none
                
            case .migrateLegacyRules:
                return .run { send in
                    guard !(await legacyDefaultsMigrationClient.didCompleteMigration()) else {
                        return
                    }

                    let migratedRules = await legacyDefaultsMigrationClient.migrateRules(now)
                    await send(.legacyRulesMigrated(migratedRules))
                }
                
            case .legacyRulesMigrated(let migratedRules):
                state.$appRulesStore.withLock { store in
                    store.rules.merge(migratedRules) { _, newValue in newValue }
                }
                return .none
                
            case let .programmaticSwitchFinished(bundleId, inputMethodId):
                if state.pendingProgrammaticSwitch == .init(bundleId: bundleId, inputMethodId: inputMethodId) {
                    state.pendingProgrammaticSwitch = nil
                }
                return .none
                
            case .refreshRunningApps:
                return .run { send in
                    await send(.runningAppsResponse(await workspaceClient.runningApplications()))
                }

            case .removeMissingInputMethodRulesTapped:
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
                
            case .removeUnavailableRulesTapped:
                state.$appRulesStore.withLock { store in
                    store.rules = store.rules.filter { $0.value.isAvailable }
                }
                return .none
                
            case .runningAppsResponse(let runningApps):
                state.runningApps = runningApps
                for appInfo in runningApps {
                    upsertRecord(for: appInfo, in: &state)
                }
                return .none

            case .setFallbackStrategy(let strategy):
                state.$fallbackRuleStore.withLock { store in
                    guard store.strategy != strategy else {
                        return
                    }

                    store.strategy = strategy
                }
                return .none
                
            case .setLaunchAtLogin(let isEnabled):
                state.launchAtLoginStatus = isEnabled ? .enabled : .disabled
                return .run { send in
                    await send(.launchAtLoginLoaded(await launchAtLoginClient.setEnabled(isEnabled)))
                }
                
            case let .setStrategy(bundleId, strategy):
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

            case .prepareAppRulesStoreMigration:
                return .run { send in
                    await send(.appRulesStorePrepared(await appRulesStoreMigrationClient.prepareStore()))
                }
                
            case .workspaceEvent(.launched(_)):
                return .send(.refreshRunningApps)
                
            case .workspaceEvent(.terminated(let bundleId)):
                if state.currentFrontmostBundleId == bundleId {
                    state.currentFrontmostBundleId = nil
                }
                return .send(.refreshRunningApps)
                
            case .workspaceEvent(.activated(let appInfo)):
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
                    await send(.programmaticSwitchFinished(bundleId: appInfo.bundleId, inputMethodId: inputMethodId))
                }
            }
        }
    }
    
    private func refreshInputMethodsEffect() -> Effect<Action> {
        .run { send in
            let inputMethods = (try? await inputMethodClient.fetchInputMethods()) ?? []
            await send(.inputMethodsResponse(inputMethods))
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

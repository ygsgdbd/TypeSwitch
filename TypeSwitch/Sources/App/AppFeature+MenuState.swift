import Foundation

extension AppFeature.State {
    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus.isToggleOn
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    var appRules: [String: AppRuleRecord] {
        appRulesStore.rules
    }

    var menuBarIconSystemName: String {
        guard let currentFrontmostBundleId else {
            return "keyboard"
        }

        return strategy(for: currentFrontmostBundleId) == .none
            ? "keyboard.badge.ellipsis"
            : "keyboard"
    }

    var fallbackStrategy: InputMethodStrategy {
        switch fallbackRuleStore.strategy {
        case .followLast, .ignored:
            return .none
        case .none, .fixed:
            return fallbackRuleStore.strategy
        }
    }

    var fallbackSelectedLabel: String? {
        if fallbackStrategy == .none {
            return TypeSwitchStrings.InputMethod.fallbackDefaultOption
        }
        return selectedLabel(for: fallbackStrategy)
    }

    var fallbackHasMissingInputMethod: Bool {
        hasMissingInputMethod(in: fallbackStrategy)
    }

    var totalSuccessfulSwitchCount: Int {
        appSwitchStatisticsStore.counts
            .filter { !ignoredAppBundleIdsForMenu.contains($0.key) && $0.value > 0 }
            .values
            .reduce(0, +)
    }

    var switchStatisticsItems: [SwitchStatisticsItem] {
        appSwitchStatisticsStore.counts.compactMap { bundleId, count in
            guard count > 0, !ignoredAppBundleIdsForMenu.contains(bundleId) else { return nil }
            let appInfo = appInfo(for: bundleId)
            return SwitchStatisticsItem(
                bundleId: bundleId,
                name: appInfo.name,
                path: appInfo.path,
                count: count
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }

            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.bundleId < rhs.bundleId
        }
    }

    var configuredApps: [AppMenuItem] {
        sortedRules
            .filter {
                let strategy = strategyForMenu(bundleId: $0.bundleId)
                return strategy != .none && strategy != .ignored && $0.isAvailable
            }
            .map { menuItem(from: $0, strategy: strategyForMenu(bundleId: $0.bundleId)) }
    }

    var currentAppMenuItem: AppMenuItem? {
        guard let currentFrontmostBundleId,
              strategyForMenu(bundleId: currentFrontmostBundleId) != .ignored,
              let appInfo = knownAppInfo(for: currentFrontmostBundleId)
        else {
            return nil
        }

        return menuItem(
            bundleId: appInfo.bundleId,
            name: appInfo.name,
            path: appInfo.path,
            strategy: strategyForMenu(bundleId: appInfo.bundleId)
        )
    }

    var runningConfiguredMenuItems: [AppMenuItem] {
        runningMenuItems { $0 != .none && $0 != .ignored }
    }

    var runningUnconfiguredMenuItems: [AppMenuItem] {
        runningMenuItems { $0 == .none }
    }

    var unavailableApps: [AppMenuItem] {
        sortedRules
            .filter {
                !$0.isAvailable && strategyForMenu(bundleId: $0.bundleId) != .ignored
            }
            .map {
                menuItem(
                    bundleId: $0.bundleId,
                    name: $0.lastKnownName,
                    path: nil,
                    strategy: strategyForMenu(bundleId: $0.bundleId)
                )
            }
    }

    var ignoredAppsForMenu: [AppInfo] {
        sortedRules.compactMap { rule in
            guard ignoredAppBundleIdsForMenu.contains(rule.bundleId) else { return nil }
            return appInfo(for: rule.bundleId)
        }
    }

    var hasMissingInputMethodRules: Bool {
        appRules.keys.contains {
            hasMissingInputMethod(in: strategyForMenu(bundleId: $0))
        }
    }

    func strategy(for bundleId: String) -> InputMethodStrategy {
        appRules[bundleId]?.strategy ?? .none
    }

    func hasMissingInputMethod(in strategy: InputMethodStrategy) -> Bool {
        switch strategy {
        case .ignored, .none:
            return false
        case .fixed(let inputMethodId):
            return inputMethodName(for: inputMethodId) == nil
        case .followLast(let lastInputMethodId):
            guard let lastInputMethodId else { return false }
            return inputMethodName(for: lastInputMethodId) == nil
        }
    }

    private var sortedRules: [AppRuleRecord] {
        appRules.values.sorted {
            $0.lastKnownName.localizedStandardCompare($1.lastKnownName) == .orderedAscending
        }
    }

    private func menuItem(
        from rule: AppRuleRecord,
        strategy: InputMethodStrategy
    ) -> AppMenuItem {
        menuItem(
            bundleId: rule.bundleId,
            name: rule.lastKnownName,
            path: rule.isAvailable ? rule.lastKnownPath : nil,
            strategy: strategy
        )
    }

    private func runningMenuItems(
        matching isIncluded: (InputMethodStrategy) -> Bool
    ) -> [AppMenuItem] {
        runningApps.compactMap { app in
            guard app.bundleId != currentFrontmostBundleId else {
                return nil
            }

            let strategy = strategyForMenu(bundleId: app.bundleId)
            guard isIncluded(strategy) else {
                return nil
            }

            return menuItem(
                bundleId: app.bundleId,
                name: app.name,
                path: app.path,
                strategy: strategy
            )
        }
    }

    private func appInfo(for bundleId: String) -> AppInfo {
        if let runningApp = runningApps.first(where: { $0.bundleId == bundleId }) {
            return runningApp
        }

        if let rule = appRules[bundleId] {
            return rule.appInfo
        }

        return AppInfo(bundleId: bundleId, name: bundleId, path: nil)
    }

    private func knownAppInfo(for bundleId: String) -> AppInfo? {
        if let runningApp = runningApps.first(where: { $0.bundleId == bundleId }) {
            return runningApp
        }

        return appRules[bundleId]?.appInfo
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
            defaultOptionLabel: appDefaultOptionLabel,
            selectedLabel: selectedLabel(for: strategy),
            followLastOptionLabel: followLastOptionLabel(for: strategy),
            hasMissingInputMethod: hasMissingInputMethod(in: strategy)
        )
    }

    private var appDefaultOptionLabel: String {
        switch fallbackStrategy {
        case .ignored, .none:
            return TypeSwitchStrings.InputMethod.appDefaultFallbackNoneOption
        case .fixed(let inputMethodId):
            guard let inputMethodName = inputMethodName(for: inputMethodId) else {
                return TypeSwitchStrings.InputMethod.appDefaultMissingOption
            }
            return TypeSwitchStrings.InputMethod.appDefaultWithInputMethod(inputMethodName)
        case .followLast:
            return TypeSwitchStrings.InputMethod.appDefaultFallbackNoneOption
        }
    }

    private func selectedLabel(for strategy: InputMethodStrategy) -> String? {
        switch strategy {
        case .none:
            return nil
        case .ignored:
            return nil
        case .fixed(let inputMethodId):
            return inputMethodName(for: inputMethodId) ?? TypeSwitchStrings.InputMethod.deletedOption
        case .followLast(let lastInputMethodId):
            guard let lastInputMethodId else {
                return TypeSwitchStrings.InputMethod.followLastEmptyOption
            }
            guard let inputMethodName = inputMethodName(for: lastInputMethodId) else {
                return TypeSwitchStrings.InputMethod.followLastMissingOption
            }
            return TypeSwitchStrings.InputMethod.followLastWithInputMethod(inputMethodName)
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

        return TypeSwitchStrings.InputMethod.followLastWithInputMethod(inputMethodName)
    }

    private func inputMethodName(for inputMethodId: String) -> String? {
        inputMethods.first(where: { $0.id == inputMethodId })?.name
    }

    private var ignoredAppBundleIdsForMenu: Set<String> {
        Set(appRules.keys.filter {
            strategyForMenu(bundleId: $0) == .ignored
        })
    }

    private func strategyForMenu(bundleId: String) -> InputMethodStrategy {
        if isMenuPresented {
            return menuStrategiesAtPresentation[bundleId] ?? .none
        }
        return strategy(for: bundleId)
    }
}

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

    var fallbackStrategy: InputMethodStrategy {
        if case .followLast = fallbackRuleStore.strategy {
            return .none
        }
        return fallbackRuleStore.strategy
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
        appSwitchStatisticsStore.counts.values
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    var switchStatisticsItems: [SwitchStatisticsItem] {
        appSwitchStatisticsStore.counts.compactMap { bundleId, count in
            guard count > 0 else { return nil }
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

    private var sortedRules: [AppRuleRecord] {
        appRules.values.sorted {
            $0.lastKnownName.localizedStandardCompare($1.lastKnownName) == .orderedAscending
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

    private func appInfo(for bundleId: String) -> AppInfo {
        if let runningApp = runningApps.first(where: { $0.bundleId == bundleId }) {
            return runningApp
        }

        if let rule = appRules[bundleId] {
            return rule.appInfo
        }

        return AppInfo(bundleId: bundleId, name: bundleId, path: nil)
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
        case .none:
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
}

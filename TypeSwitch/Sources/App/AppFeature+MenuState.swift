import Foundation

extension AppFeature.State {
    var currentFrontmostBundleId: String? { switching.currentFrontmostBundleId }
    var inputMethodCatalogStatus: SwitchingFeature.State.InputMethodCatalogStatus { switching.inputMethodCatalogStatus }
    var inputMethods: [InputMethod] { switching.inputMethods }
    var lastSwitchAttempt: SwitchingFeature.State.LastSwitchAttempt? { switching.lastSwitchAttempt }

    struct InputMethodDiagnostic: Equatable {
        enum Kind: Equatable {
            case catalogEmpty
            case catalogFailed
            case switchFailed
        }

        let appName: String?
        let errorDescription: String?
        let inputMethodName: String?
        let kind: Kind
    }

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
        if inputMethodDiagnostic != nil {
            return "exclamationmark.triangle"
        }

        guard let currentFrontmostBundleId else {
            return "keyboard"
        }

        return strategy(for: currentFrontmostBundleId) == .none
            ? "keyboard.badge.ellipsis"
            : "keyboard"
    }

    var menuBarAccessibilityLabel: String {
        if inputMethodDiagnostic != nil {
            guard let currentFrontmostBundleId else {
                return TypeSwitchStrings.Menu.accessibilityWarning
            }

            switch strategy(for: currentFrontmostBundleId) {
            case .none:
                return TypeSwitchStrings.Menu.accessibilityWarningUnconfigured
            case .fixed, .followLast:
                return TypeSwitchStrings.Menu.accessibilityWarningConfigured
            case .ignored:
                return TypeSwitchStrings.Menu.accessibilityWarningIgnored
            }
        }

        guard let currentFrontmostBundleId else {
            return "TypeSwitch"
        }

        switch strategy(for: currentFrontmostBundleId) {
        case .none:
            return TypeSwitchStrings.Menu.accessibilityUnconfigured
        case .fixed, .followLast:
            return TypeSwitchStrings.Menu.accessibilityConfigured
        case .ignored:
            return TypeSwitchStrings.Menu.accessibilityIgnored
        }
    }

    var fallbackStrategy: InputMethodStrategy { switching.fallbackStrategy }

    var fallbackSelectedLabel: String? {
        menuSubtitle(for: fallbackStrategy)?.text
    }

    var fallbackIsSelectedSubtitleSecondary: Bool {
        menuSubtitle(for: fallbackStrategy)?.isSecondary ?? false
    }

    var fallbackHasMissingInputMethod: Bool {
        hasMissingInputMethod(in: fallbackStrategy)
    }

    var inputMethodDiagnostic: InputMethodDiagnostic? {
        switch inputMethodCatalogStatus {
        case .failed(let error):
            return InputMethodDiagnostic(
                appName: nil,
                errorDescription: error.errorDescription,
                inputMethodName: nil,
                kind: .catalogFailed
            )
        case .ready where inputMethods.isEmpty:
            return InputMethodDiagnostic(
                appName: nil,
                errorDescription: nil,
                inputMethodName: nil,
                kind: .catalogEmpty
            )
        case .loading, .ready:
            break
        }

        guard let lastSwitchAttempt,
              currentFrontmostBundleId == lastSwitchAttempt.bundleId,
              switching.isCurrentTarget(lastSwitchAttempt),
              case .failed(let error) = lastSwitchAttempt.outcome
        else {
            return nil
        }
        return InputMethodDiagnostic(
            appName: lastSwitchAttempt.appName,
            errorDescription: error.errorDescription,
            inputMethodName: lastSwitchAttempt.inputMethodName ?? lastSwitchAttempt.inputMethodId,
            kind: .switchFailed
        )
    }

    var shouldOfferKeyboardSettings: Bool {
        guard let inputMethodDiagnostic else { return false }
        switch inputMethodDiagnostic.kind {
        case .catalogEmpty:
            return true
        case .catalogFailed:
            return false
        case .switchFailed:
            guard let lastSwitchAttempt,
                  case .failed(let error) = lastSwitchAttempt.outcome
            else {
                return false
            }
            switch error {
            case .inputMethodNotEnabled, .inputMethodNotFound:
                return true
            case .failedToFetchInputMethods,
                 .failedToGetCurrentInputMethod,
                 .failedToSwitchInputMethod,
                 .failedToVerifyInputMethod,
                 .unexpected:
                return false
            }
        }
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
                return strategy != .none && strategy != .ignored && appAvailability.isAvailable($0)
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
                !appAvailability.isAvailable($0) && strategyForMenu(bundleId: $0.bundleId) != .ignored
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
        guard inputMethodCatalogStatus == .ready else { return false }
        return appRules.keys.contains {
            hasMissingInputMethod(in: strategyForMenu(bundleId: $0))
        }
    }

    func strategy(for bundleId: String) -> InputMethodStrategy {
        appRules[bundleId]?.strategy ?? .none
    }

    func hasMissingInputMethod(in strategy: InputMethodStrategy) -> Bool {
        guard inputMethodCatalogStatus == .ready else { return false }
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
            path: appAvailability.availablePath(for: rule),
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
            return appAvailability.appInfo(for: rule)
        }

        return AppInfo(bundleId: bundleId, name: bundleId, path: nil)
    }

    private func knownAppInfo(for bundleId: String) -> AppInfo? {
        if let runningApp = runningApps.first(where: { $0.bundleId == bundleId }) {
            return runningApp
        }

        return appRules[bundleId].map { appAvailability.appInfo(for: $0) }
    }

    private func menuItem(
        bundleId: String,
        name: String,
        path: String?,
        strategy: InputMethodStrategy
    ) -> AppMenuItem {
        let selectedSubtitle = strategy == .none ? nil : menuSubtitle(for: strategy)
        let defaultSubtitle = menuSubtitle(for: fallbackStrategy)
        let followLastStrategy: InputMethodStrategy
        if case .followLast = strategy {
            followLastStrategy = strategy
        } else {
            followLastStrategy = .followLast(lastInputMethodId: nil)
        }

        return AppMenuItem(
            bundleId: bundleId,
            name: name,
            path: path,
            strategy: strategy,
            defaultOptionSubtitle: defaultSubtitle?.text ?? TypeSwitchStrings.InputMethod.fallbackDefaultOption,
            selectedLabel: selectedSubtitle?.text,
            followLastOptionSubtitle: menuSubtitle(for: followLastStrategy)?.text
                ?? TypeSwitchStrings.InputMethod.followLastUnrecordedOption,
            isSelectedSubtitleSecondary: selectedSubtitle?.isSecondary ?? false
        )
    }

    private struct MenuSubtitle {
        let text: String
        let isSecondary: Bool
    }

    private func menuSubtitle(for strategy: InputMethodStrategy) -> MenuSubtitle? {
        switch strategy {
        case .none:
            return MenuSubtitle(text: TypeSwitchStrings.InputMethod.fallbackDefaultOption, isSecondary: true)
        case .ignored:
            return nil
        case .fixed(let inputMethodId):
            return inputMethodSubtitle(for: inputMethodId)
        case .followLast(let lastInputMethodId):
            guard let lastInputMethodId else {
                return MenuSubtitle(text: TypeSwitchStrings.InputMethod.followLastUnrecordedOption, isSecondary: true)
            }
            return inputMethodSubtitle(for: lastInputMethodId)
        }
    }

    private func inputMethodSubtitle(for inputMethodId: String) -> MenuSubtitle {
        if let name = inputMethodName(for: inputMethodId) {
            return MenuSubtitle(text: name, isSecondary: false)
        }

        let text: String
        switch inputMethodCatalogStatus {
        case .loading:
            text = TypeSwitchStrings.InputMethod.catalogLoadingOption
        case .failed:
            text = TypeSwitchStrings.InputMethod.catalogUnavailableOption
        case .ready:
            text = TypeSwitchStrings.InputMethod.deletedOption
        }
        return MenuSubtitle(text: text, isSecondary: true)
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

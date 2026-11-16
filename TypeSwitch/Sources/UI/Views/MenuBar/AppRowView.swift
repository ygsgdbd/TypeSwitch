import ComposableArchitecture
import SwiftUI

/// 应用行视图，处理单个应用的显示和输入法选择
struct AppRowView: View {
    let item: AppFeature.State.AppMenuItem
    let inputMethods: [InputMethod]
    let onIgnore: () -> Void
    let onSelectStrategy: (InputMethodStrategy) -> Void

    var body: some View {
        Menu {
            InputMethodStrategyMenuContent(
                context: .appRule,
                strategy: item.strategy,
                inputMethods: inputMethods,
                defaultOptionSubtitle: item.defaultOptionSubtitle,
                followLastOptionSubtitle: item.followLastOptionSubtitle,
                unavailableFixedOptionLabel: item.selectedLabel,
                onSelectStrategy: onSelectStrategy
            )

            Divider()

            Button(action: onIgnore) {
                Label(TypeSwitchStrings.Apps.ignore, systemImage: "eye.slash")
            }
        } label: {
            if item.path != nil {
                Label {
                    Text(item.name)
                } icon: {
                    AppInfo(bundleId: item.bundleId, name: item.name, path: item.path).icon
                }
            } else {
                Text(item.name)
            }
            if let selectedLabel = item.selectedLabel {
                Text(selectedLabel)
                    .foregroundStyle(item.isSelectedSubtitleSecondary ? .secondary : .primary)
            }
        }
    }
}

struct InputMethodStrategyMenuContent: View {
    let context: InputMethodStrategyMenuContext
    let strategy: InputMethodStrategy
    let inputMethods: [InputMethod]
    let defaultOptionSubtitle: String?
    let followLastOptionSubtitle: String?
    let unavailableFixedOptionLabel: String?
    let onSelectStrategy: (InputMethodStrategy) -> Void

    var body: some View {
        strategyOption(defaultOptionTitle, subtitle: defaultOptionSubtitle, option: .none)

        Divider()

        if context.supportsFollowLast {
            strategyOption(
                TypeSwitchStrings.InputMethod.followLastOption,
                subtitle: followLastOptionSubtitle,
                option: followLastStrategy
            )

            Divider()
        }

        if case .fixed(let inputMethodId) = strategy,
           !inputMethods.contains(where: { $0.id == inputMethodId })
        {
            strategyOption(
                unavailableFixedOptionLabel ?? TypeSwitchStrings.InputMethod.deletedOption,
                option: strategy
            )
            .disabled(true)
        }

        ForEach(inputMethods, id: \.id) { inputMethod in
            strategyOption(inputMethod.name, option: .fixed(inputMethodId: inputMethod.id))
        }
    }

    func selectionBinding(for option: InputMethodStrategy) -> Binding<Bool> {
        Binding(
            get: { strategy == option },
            set: { isSelected in
                guard isSelected else { return }
                onSelectStrategy(option)
            }
        )
    }

    private func strategyOption(
        _ title: String,
        subtitle: String? = nil,
        option: InputMethodStrategy
    ) -> some View {
        Toggle(isOn: selectionBinding(for: option)) {
            Text(title)
            if let subtitle {
                Text(subtitle)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var defaultOptionTitle: String {
        switch context {
        case .appRule:
            return TypeSwitchStrings.InputMethod.appDefaultOption
        case .fallbackRule:
            return TypeSwitchStrings.InputMethod.fallbackDefaultOption
        }
    }

    private var followLastStrategy: InputMethodStrategy {
        if case .followLast(let lastInputMethodId) = strategy {
            return .followLast(lastInputMethodId: lastInputMethodId)
        }
        return .followLast(lastInputMethodId: nil)
    }
}

enum InputMethodStrategyMenuContext {
    case appRule
    case fallbackRule

    var supportsFollowLast: Bool {
        switch self {
        case .appRule:
            return true
        case .fallbackRule:
            return false
        }
    }
}

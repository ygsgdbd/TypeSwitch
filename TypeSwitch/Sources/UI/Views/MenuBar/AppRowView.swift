import ComposableArchitecture
import SwiftUI
import SwiftUIX

/// 应用行视图，处理单个应用的显示和输入法选择
struct AppRowView: View {
    let item: AppFeature.State.AppMenuItem
    let inputMethods: [InputMethod]
    let onSelectStrategy: (InputMethodStrategy) -> Void

    var body: some View {
        Menu {
            InputMethodStrategyMenuContent(
                context: .appRule,
                strategy: item.strategy,
                inputMethods: inputMethods,
                followLastOptionLabel: item.followLastOptionLabel,
                onSelectStrategy: onSelectStrategy
            )
        } label: {
            if item.path != nil {
                AppInfo(bundleId: item.bundleId, name: item.name, path: item.path).icon
            }
            Text(item.name)
            item.selectedLabel.ifSome {
                Text($0)
                    .foregroundStyle(item.hasMissingInputMethod ? .secondary : .primary)
            }
        }
    }
}

struct InputMethodStrategyMenuContent: View {
    let context: InputMethodStrategyMenuContext
    let strategy: InputMethodStrategy
    let inputMethods: [InputMethod]
    let followLastOptionLabel: String
    let onSelectStrategy: (InputMethodStrategy) -> Void

    var body: some View {
        Section(TypeSwitchStrings.InputMethod.defaultSection) {
            Button(action: {
                onSelectStrategy(.none)
            }) {
                if strategy == .none {
                    Image(systemName: .checkmark)
                }
                Text(context.defaultOptionLabel)
            }
        }

        if context.supportsFollowLast {
            Section(context.followLastSectionTitle) {
                Button(action: {
                    onSelectStrategy(followLastStrategy)
                }) {
                    if case .followLast = strategy {
                        Image(systemName: .checkmark)
                    }
                    Text(followLastOptionLabel)
                }
            }
        }

        Section(TypeSwitchStrings.InputMethod.fixedSection) {
            ForEach(inputMethods, id: \.id) { inputMethod in
                Button(action: {
                    onSelectStrategy(.fixed(inputMethodId: inputMethod.id))
                }) {
                    if strategy == .fixed(inputMethodId: inputMethod.id) {
                        Image(systemName: .checkmark)
                    }
                    Text(inputMethod.name)
                }
            }
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

    var defaultOptionLabel: String {
        switch self {
        case .appRule:
            return TypeSwitchStrings.InputMethod.appDefaultOption
        case .fallbackRule:
            return TypeSwitchStrings.InputMethod.fallbackDefaultOption
        }
    }

    var followLastSectionTitle: String {
        switch self {
        case .appRule:
            return TypeSwitchStrings.InputMethod.followLastAppSection
        case .fallbackRule:
            return TypeSwitchStrings.InputMethod.followLastFallbackSection
        }
    }

    var supportsFollowLast: Bool {
        switch self {
        case .appRule:
            return true
        case .fallbackRule:
            return false
        }
    }
}

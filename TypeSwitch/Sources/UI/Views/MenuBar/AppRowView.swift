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
                defaultOptionLabel: item.defaultOptionLabel,
                followLastOptionLabel: item.followLastOptionLabel,
                onSelectStrategy: onSelectStrategy
            )

            Divider()

            Button(action: onIgnore) {
                Label(TypeSwitchStrings.Apps.ignore, systemImage: "eye.slash")
            }
        } label: {
            if item.path != nil {
                AppInfo(bundleId: item.bundleId, name: item.name, path: item.path).icon
            }
            Text(item.name)
            if let selectedLabel = item.selectedLabel {
                Text(selectedLabel)
                    .foregroundStyle(item.hasMissingInputMethod ? .secondary : .primary)
            }
        }
    }
}

struct InputMethodStrategyMenuContent: View {
    let context: InputMethodStrategyMenuContext
    let strategy: InputMethodStrategy
    let inputMethods: [InputMethod]
    let defaultOptionLabel: String
    let followLastOptionLabel: String
    let onSelectStrategy: (InputMethodStrategy) -> Void

    var body: some View {
        Button(action: {
            onSelectStrategy(.none)
        }) {
            if strategy == .none {
                Image(systemName: "checkmark")
            }
            Text(defaultOptionLabel)
        }

        Divider()

        if context.supportsFollowLast {
            Button(action: {
                onSelectStrategy(followLastStrategy)
            }) {
                if case .followLast = strategy {
                    Image(systemName: "checkmark")
                }
                Text(followLastOptionLabel)
            }

            Divider()
        }

        ForEach(inputMethods, id: \.id) { inputMethod in
            Button(action: {
                onSelectStrategy(.fixed(inputMethodId: inputMethod.id))
            }) {
                if strategy == .fixed(inputMethodId: inputMethod.id) {
                    Image(systemName: "checkmark")
                }
                Text(inputMethod.name)
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

    var supportsFollowLast: Bool {
        switch self {
        case .appRule:
            return true
        case .fallbackRule:
            return false
        }
    }
}

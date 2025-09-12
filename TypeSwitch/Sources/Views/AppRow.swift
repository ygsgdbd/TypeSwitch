import SwiftUI
import SwiftUIX

struct AppRow: View {
    let app: AppInfo
    
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                AppIcon(app: app)
                    .equatable()
                AppName(app: app)
                    .equatable()
            }
            
            Spacer()
            
            // 输入法选择菜单
            Menu {
                // 默认输入法选项
                Button(action: {
                    selectInputMethod("")
                }) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                        Text("input_method.default".localized)
                        Spacer()
                        if currentInputMethodId.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Divider()
                
                // 已安装的输入法
                ForEach(viewModel.inputMethods, id: \.id) { inputMethod in
                    Button(action: {
                        selectInputMethod(inputMethod.id)
                    }) {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.blue)
                            Text(inputMethod.name)
                            Spacer()
                            if currentInputMethodId == inputMethod.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } label: {
                Text(currentInputMethodName)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var currentInputMethodId: String {
        viewModel.appSettings[app.bundleId]?.flatMap { $0 } ?? ""
    }
    
    private var currentInputMethodName: String {
        if currentInputMethodId.isEmpty {
            return "input_method.default".localized
        } else if let inputMethod = viewModel.inputMethods.first(where: { $0.id == currentInputMethodId }) {
            return inputMethod.name
        } else {
            return "input_method.unknown".localized
        }
    }
    
    private func selectInputMethod(_ inputMethodId: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if inputMethodId.isEmpty {
                viewModel.appSettings[app.bundleId] = nil
            } else {
                viewModel.appSettings[app.bundleId] = inputMethodId
            }
        }
    }
}

private struct AppIcon: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppIcon, rhs: AppIcon) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        app.icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .squareFrame(sideLength: 26)
    }
}

private struct AppName: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppName, rhs: AppName) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        Text(app.name)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 160, alignment: .leading)
    }
}


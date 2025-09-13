import SwiftUI
import AppKit

/// 菜单栏视图，显示应用列表和输入法选择
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 应用列表
            ForEach(viewModel.filteredApps) { app in
                MenuBarAppRow(app: app)
            }
            
            Divider()
            
            // 底部操作按钮
            Button("menu.quit".localized) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// 菜单栏中的应用行
struct MenuBarAppRow: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    /// 获取当前应用选中的输入法ID
    private var currentInputMethodId: String {
        viewModel.appSettings[app.bundleId]?.flatMap { $0 } ?? ""
    }
    
    /// 获取当前应用选中的输入法名称
    private var selectedInputMethodName: String {
        if currentInputMethodId.isEmpty {
            return "menu.default_input_method".localized
        } else if let inputMethod = viewModel.inputMethods.first(where: { $0.id == currentInputMethodId }) {
            return inputMethod.name
        } else {
            return "menu.default_input_method".localized
        }
    }
    
    var body: some View {
        Menu {
            // 默认输入法选项
            Button(action: {
                Task {
                    await viewModel.setInputMethod(for: app, to: nil)
                }
            }) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.blue)
                    Text("menu.default_input_method".localized)
                    Spacer()
                    if currentInputMethodId.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Divider()
            
            // 已安装的输入法选项
            ForEach(viewModel.inputMethods, id: \.id) { inputMethod in
                Button(action: {
                    Task {
                        await viewModel.setInputMethod(for: app, to: inputMethod.id)
                    }
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
            HStack(spacing: 8) {
                // 应用图标
                app.icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                
                // 应用名称
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                // 当前选择的输入法
                Text(selectedInputMethodName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(InputMethodManager.shared)
}


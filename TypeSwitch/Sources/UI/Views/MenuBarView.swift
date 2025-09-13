import AppKit
import SwiftUI
import SwiftUIX

/// 菜单栏视图，显示应用列表和输入法选择
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Group {
            Section("运行中") {
                ForEach(viewModel.filteredApps) { app in
                    MenuBarAppRow(app: app)
                }
            }
            
            Menu("已配置") {
                ForEach(viewModel.filteredApps) { app in
                    MenuBarAppRow(app: app)
                }
            }
           
            Section {
                Button("menu.quit".localized, role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

/// 菜单栏中的应用行
struct MenuBarAppRow: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    /// 获取当前应用的输入法策略
    private var currentStrategy: InputMethodStrategy? {
        viewModel.getInputMethodStrategy(for: app)
    }
    
    /// 获取当前应用选中的输入法ID
    private var currentInputMethodId: String {
        viewModel.getInputMethod(for: app) ?? ""
    }
    
    /// 获取当前应用选中的输入法名称
    private var selectedInputMethodName: String? {
        guard let strategy = currentStrategy else {
            return nil
        }
        
        switch strategy {
        case .fixed(let inputMethodId):
            if inputMethodId.isEmpty {
                return "menu.default_input_method".localized
            } else if let inputMethod = viewModel.inputMethods.first(where: { $0.id == inputMethodId }) {
                return inputMethod.name
            } else {
                return "menu.default_input_method".localized
            }
        case .lastUsed:
            // 获取上次使用的输入法ID
            if let settings = viewModel.getAppInputMethodSettings(for: app),
               let lastUsedId = settings.lastUsedInputMethodId,
               let inputMethod = viewModel.inputMethods.first(where: { $0.id == lastUsedId })
            {
                return "\(inputMethod.name) (上次使用)"
            } else {
                return "上次使用的输入法"
            }
        }
    }
    
    var body: some View {
        Menu {
            // 默认输入法选项
            Section {
                Button(action: {
                    Task {
                        await viewModel.setInputMethod(for: app, to: nil)
                    }
                }) {
                    if case .fixed = currentStrategy, currentInputMethodId.isEmpty {
                        Image(systemName: .checkmark)
                    }
                    Text("menu.default_input_method".localized)
                }
            }
            
            Divider()
            
            // 已安装的输入法选项
            Section {
                ForEach(viewModel.inputMethods, id: \.id) { inputMethod in
                    Button(action: {
                        Task {
                            await viewModel.setInputMethod(for: app, to: inputMethod.id)
                        }
                    }) {
                        if case .fixed = currentStrategy, currentInputMethodId == inputMethod.id {
                            Image(systemName: .checkmark)
                        }
                        Text(inputMethod.name)
                    }
                }
            }
            
            Divider()
            
            // 上次使用的输入法选项
            Section {
                Button(action: {
                    Task {
                        await viewModel.setLastUsedInputMethodStrategy(for: app)
                    }
                }) {
                    if case .lastUsed = currentStrategy {
                        Image(systemName: .checkmark)
                    }
                    if case .lastUsed = currentStrategy,
                       let settings = viewModel.getAppInputMethodSettings(for: app),
                       let lastUsedId = settings.lastUsedInputMethodId,
                       let inputMethod = viewModel.inputMethods.first(where: { $0.id == lastUsedId })
                    {
                        Text("上次使用（\(inputMethod.name)）")
                    } else {
                        Text("上次使用")
                    }
                }
            }
        } label: {
            // APP 图标
            app.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
            
            
            Text(app.name)
            
            // 选择的输入法
            if let selectedInputMethodName {
                Text(selectedInputMethodName)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(InputMethodManager.shared)
}

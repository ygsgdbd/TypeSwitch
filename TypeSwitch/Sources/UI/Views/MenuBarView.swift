import AppKit
import SwiftUI
import SwiftUIX

/// 菜单栏视图，显示应用列表和输入法选择
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Group {
            Section("运行中") {
                ForEach(viewModel.runningApps) { app in
                    MenuBarAppRow(app: app)
                }
            }
            
            Section {
                Menu("已配置") {
                    ForEach(viewModel.configuredApps) { app in
                        MenuBarAppRow(app: app)
                    }
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
    
    var body: some View {
        Menu {
            InputMethodMenuView(app: app)
        } label: {
            AppRowLabelView(
                app: app,
                selectedInputMethodName: viewModel.getSelectedInputMethodName(for: app)
            )
        }
    }
}

/// 输入法菜单视图
struct InputMethodMenuView: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    private var currentInputMethodId: String? {
        viewModel.getInputMethod(for: app)
    }
    
    var body: some View {
        // 默认输入法选项
        Button(action: {
            viewModel.setInputMethod(for: app, to: nil)
        }) {
            if currentInputMethodId == nil {
                Image(systemName: .checkmark)
            }
            Text("--")
        }
        
        Divider()
        
        // 已安装的输入法选项
        ForEach(viewModel.inputMethods, id: \.id) { inputMethod in
            Button(action: {
                viewModel.setInputMethod(for: app, to: inputMethod.id)
            }) {
                if currentInputMethodId == inputMethod.id {
                    Image(systemName: .checkmark)
                }
                Text(inputMethod.name)
            }
        }
    }
}

/// 应用行标签视图
struct AppRowLabelView: View {
    let app: AppInfo
    let selectedInputMethodName: String?
    
    var body: some View {
        app.icon
        Text(app.name)
        selectedInputMethodName.ifSome { Text($0) }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(InputMethodManager.shared)
}

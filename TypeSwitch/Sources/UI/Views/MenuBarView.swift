import AppKit
import SwiftUI
import SwiftUIX

/// 菜单栏主视图
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @StateObject private var appInfoManager = AppInfoManager.shared
    
    var body: some View {
        Group {
            RunningAppsView()
            ConfiguredAppsView()
            
            Divider()
            
            SettingsView()
            
            Divider()
            
            AppInfoView()
        }
    }
}

/// 运行中的应用列表视图
struct RunningAppsView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Section("运行中 (\(viewModel.runningApps.count))") {
            ForEach(viewModel.runningApps) { app in
                AppRowView(app: app)
            }
        }
    }
}

/// 已配置的应用列表视图
struct ConfiguredAppsView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Section {
            Menu("已配置 (\(viewModel.configuredApps.count))") {
                ForEach(viewModel.configuredApps) { app in
                    AppRowView(app: app)
                }
            }
        }
    }
}

/// 应用行视图，处理单个应用的显示和输入法选择
struct AppRowView: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Menu {
            // 默认输入法选项
            Button(action: {
                viewModel.setInputMethod(for: app, to: nil)
            }) {
                if viewModel.getInputMethod(for: app) == nil {
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
                    if viewModel.getInputMethod(for: app) == inputMethod.id {
                        Image(systemName: .checkmark)
                    }
                    Text(inputMethod.name)
                }
            }
        } label: {
            // 应用行标签内容
            app.icon
            Text(app.name)
            viewModel.getSelectedInputMethodName(for: app).ifSome { Text($0) }
        }
    }
}

/// 设置视图，包含各种应用设置选项
struct SettingsView: View {
    @State private var isLaunchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
    
    var body: some View {
        Section {
            Toggle("settings.general.auto_launch".localized, isOn: $isLaunchAtLoginEnabled)
                .toggleStyle(.checkbox)
                .onChange(of: isLaunchAtLoginEnabled) { newValue in
                    _ = LaunchAtLoginManager.shared.setLaunchAtLogin(newValue)
                }
        }
    }
}

/// 应用信息视图，显示版本信息和相关链接
struct AppInfoView: View {
    @StateObject private var appInfoManager = AppInfoManager.shared
    
    var body: some View {
        Section {
            // 版本信息
            Menu {
                Button("复制版本信息") {
                    appInfoManager.copyVersionInfo()
                }
                
                Divider()
                
                Button("打开 GitHub 仓库") {
                    appInfoManager.openGitHubRepository()
                }
                
                Button("查看 Releases") {
                    appInfoManager.openGitHubReleases()
                }
                
                Button("最新 Release") {
                    appInfoManager.openLatestRelease()
                }
            } label: {
                Text("关于 APP \(appInfoManager.fullVersionInfo)")
            }
            
            Button("menu.quit".localized, role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(InputMethodManager.shared)
}

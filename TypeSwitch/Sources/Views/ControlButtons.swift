import SwiftUI
import ServiceManagement
import SwiftUIX
import KeyboardShortcuts

struct ControlPanel: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                // 全局快速切换
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("全局快速切换")
                            .font(.system(size: 12))
                        Text("使用快捷键在所有输入法间快速切换")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .gridCellColumns(1)
                    
                    HStack(spacing: 8) {
                        if viewModel.isQuickSwitchEnabled {
                            KeyboardShortcuts.Recorder(for: .switchInputMethod)
                                .controlSize(.regular)
                        }
                        Toggle("", isOn: $viewModel.isQuickSwitchEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }
                    .gridCellColumns(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                    .padding(.vertical, 2)
                    .gridCellColumns(2)
                
                // 开机启动
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开机启动")
                            .font(.system(size: 12))
                        Text("登录系统时自动启动 TypeSwitch")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .gridCellColumns(1)
                    
                    Toggle("", isOn: $viewModel.isAutoLaunchEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .gridCellColumns(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .onChange(of: viewModel.isAutoLaunchEnabled) { newValue in
                            Task {
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try await SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    await MainActor.run {
                                        viewModel.isAutoLaunchEnabled = !newValue
                                        errorMessage = "设置开机自启动失败：\(error.localizedDescription)"
                                        showError = true
                                    }
                                }
                            }
                        }
                }
            }
            .padding(12)
            
            Divider()
            
            // 底部按钮
            HStack(spacing: 12) {
                Spacer()
                
                Button {
                    Task {
                        await viewModel.refreshAllData()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Text("刷新 (⌘R)")
                                .font(.system(size: 11))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isRefreshing)
                
                Button("退出 (⌘Q)") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

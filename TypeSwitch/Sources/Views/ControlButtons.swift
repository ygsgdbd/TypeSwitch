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
                        Text("settings.shortcuts.global_switch".localized)
                            .font(.system(size: 12))
                        Text("settings.shortcuts.global_switch.description".localized)
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
                        Text("settings.general.auto_launch".localized)
                            .font(.system(size: 12))
                        Text("settings.general.auto_launch.description".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .gridCellColumns(1)
                    
                    Toggle("", isOn: Binding(
                        get: { viewModel.isAutoLaunchEnabled },
                        set: { newValue in
                            Task {
                                do {
                                    try await viewModel.setAutoLaunch(enabled: newValue)
                                } catch {
                                    errorMessage = String(format: "error.auto_launch_failed".localized, error.localizedDescription)
                                    showError = true
                                }
                            }
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .gridCellColumns(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                            Text("button.refresh".localized)
                                .font(.system(size: 11))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isRefreshing)
                
                Button("button.quit".localized) {
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

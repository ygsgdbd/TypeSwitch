import SwiftUI
import KeyboardShortcuts

struct QuickSwitchSettingsWindow: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("settings.shortcuts.global_switch".localized)
                .font(.system(size: 13, weight: .medium))
            
            // 设置内容
            VStack(alignment: .leading, spacing: 12) {
                // 开关
                HStack {
                    Text("settings.shortcuts.global_switch.enable".localized)
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $viewModel.isQuickSwitchEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                // 快捷键
                HStack {
                    Text("settings.shortcuts.shortcut".localized)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .switchInputMethod)
                }
                
                // 说明文本
                Text("settings.shortcuts.global_switch.hint".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            
            // 底部按钮
            HStack {
                Spacer()
                Button("button.done".localized) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 320)
    }
}

#Preview {
    QuickSwitchSettingsWindow()
        .environmentObject(InputMethodManager.shared)
} 
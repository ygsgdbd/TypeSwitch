import SwiftUI
import KeyboardShortcuts

struct QuickSwitchSettingsWindow: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("全局快速切换")
                .font(.system(size: 13, weight: .medium))
            
            // 设置内容
            VStack(alignment: .leading, spacing: 12) {
                // 开关
                HStack {
                    Text("启用全局快速切换")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $viewModel.isQuickSwitchEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                // 快捷键
                HStack {
                    Text("快捷键")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .switchInputMethod)
                }
                
                // 说明文本
                Text("启用后，快捷键将在所有输入法间循环切换，不考虑应用的默认设置")
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
                Button("完成") {
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
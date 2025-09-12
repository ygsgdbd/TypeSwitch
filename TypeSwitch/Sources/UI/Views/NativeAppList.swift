import SwiftUI
import SwiftUIX

/// 原生样式的应用列表，直接显示应用列表
struct NativeAppList: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 应用列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredApps) { app in
                        AppRow(app: app)
                    }
                }
            }
            
            Divider()
            
            // 底部退出按钮
            HStack {
                Spacer()
                Button("menu.quit".localized) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}



#Preview {
    NativeAppList()
        .environmentObject(InputMethodManager.shared)
        .frame(width: 400, height: 600)
}

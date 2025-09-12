import SwiftUI
import SwiftUIX

struct ControlPanel: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        VStack(spacing: 0) {
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

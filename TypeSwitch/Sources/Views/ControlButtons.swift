import SwiftUI
import ServiceManagement
import SwiftUIX

struct RefreshButton: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        AsyncButton {
            await viewModel.refreshAllData()
        } label: {
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Text("刷新 (⌘R)")
            }
        }
        .help("刷新应用列表")
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.isRefreshing)
    }
}

struct QuitButton: View {
    var body: some View {
        Button("退出 (⌘Q)") {
            NSApplication.shared.terminate(nil)
        }
        .help("退出应用")
        .keyboardShortcut("q", modifiers: .command)
    }
}

struct AutoLaunchToggle: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        Toggle("开机自动启动", isOn: $viewModel.isAutoLaunchEnabled)
            .toggleStyle(.switch)
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

struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    let label: Label
    
    init(action: @escaping () async -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }
    
    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            label
        }
    }
} 
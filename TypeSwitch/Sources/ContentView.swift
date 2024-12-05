import SwiftUI
import ServiceManagement
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            TextField("搜索应用... (⌘F)", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 8)
                .focused($isSearchFocused)
                .onSubmit {
                    if viewModel.searchText.isEmpty {
                        dismiss()
                    }
                }
            
            List(viewModel.filteredApps, id: \.bundleId) { app in
                AppRow(app: app)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .listStyle(.plain)
            
            Divider()
            
            // 底部控制区域
            HStack {
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
                                // 还原开关状态
                                await MainActor.run {
                                    viewModel.isAutoLaunchEnabled = !newValue
                                    errorMessage = "设置开机自启动失败：\(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        }
                    }
                
                Spacer()
                
                HStack(spacing: 16) {
                    RefreshButton()
                    QuitButton()
                }
            }
            .padding()
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 400)
        .task {
            await viewModel.refreshAllData()
        }
        .onExitCommand {
            if viewModel.searchText.isEmpty {
                dismiss()
            } else {
                viewModel.searchText = ""
            }
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        }
        .alert("错误", isPresented: $showError) {
            Button("确定") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Subviews

private struct AppRow: View {
    let app: AppInfo
    
    var body: some View {
        Grid(horizontalSpacing: 16) {
            GridRow {
                AppIcon(app: app)
                    .equatable()
                AppName(app: app)
                    .equatable()
                InputMethodPicker(app: app)
            }
        }
    }
}

private struct AppIcon: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppIcon, rhs: AppIcon) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        app.icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .gridCellColumns(1)
            .gridCellAnchor(.center)
    }
}

private struct AppName: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppName, rhs: AppName) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        Text(app.name)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 160, alignment: .leading)
            .gridCellColumns(1)
            .gridCellAnchor(.leading)
    }
}

private struct InputMethodPicker: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Picker("", selection: makeBinding()) {
            Text("默认").tag("")
            ForEach(viewModel.inputMethods) { inputMethod in
                Text(inputMethod.name)
                    .font(.system(size: 11))
                    .tag(inputMethod.id)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .gridCellColumns(1)
        .gridCellAnchor(.trailing)
    }
    
    private func makeBinding() -> Binding<String> {
        Binding(
            get: { [app, viewModel] in
                viewModel.appSettings[app.bundleId] ?? ""
            },
            set: { [app, viewModel] newValue in
                viewModel.appSettings[app.bundleId] = newValue
            }
        )
    }
}

private struct RefreshButton: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Button {
            Task {
                await viewModel.refreshAllData()
            }
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

private struct QuitButton: View {
    var body: some View {
        Button("退出 (⌘Q)") {
            NSApplication.shared.terminate(nil)
        }
        .help("退出应用")
        .keyboardShortcut("q", modifiers: .command)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


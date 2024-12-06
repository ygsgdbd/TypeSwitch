import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScrollViewReader { proxy in
                appList
                    .onAppear { scrollProxy = proxy }
            }
            Divider()
            controlPanel
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
    
    private var searchField: some View {
        TextField("搜索应用... (⌘F)", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .focused($isSearchFocused)
            .onChange(of: viewModel.searchText) { _ in
                if let firstApp = viewModel.filteredApps.first {
                    scrollProxy?.scrollTo(firstApp.id, anchor: .top)
                }
            }
            .onSubmit {
                if viewModel.searchText.isEmpty {
                    dismiss()
                }
            }
    }
    
    private var appList: some View {
        List {
            ForEach(viewModel.filteredApps) { app in
                AppRow(app: app)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id(app.id)
            }
        }
        .listStyle(.plain)
    }
    
    private var controlPanel: some View {
        HStack {
            AutoLaunchToggle(showError: $showError, errorMessage: $errorMessage)
            Spacer()
            HStack(spacing: 16) {
                RefreshButton()
                QuitButton()
            }
        }
        .padding(12)
    }
}

#Preview {
    ContentView()
        .environmentObject(InputMethodManager.shared)
}


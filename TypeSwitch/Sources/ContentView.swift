import SwiftUI
import AppKit
import KeyboardShortcuts

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
            
            ControlPanel(showError: $showError, errorMessage: $errorMessage)
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity, minHeight: 500)
        .onExitCommand {
            if viewModel.searchText.isEmpty {
                if let window = NSApplication.shared.keyWindow {
                    window.close()
                    NSApp.mainMenu?.cancelTracking()
                    window.resignFirstResponder()
                }
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
        .alert("error.title".localized, isPresented: $showError) {
            Button("button.ok".localized) {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
        .task {
            // 窗口激活时自动聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    private var searchField: some View {
        TextField("apps.search".localized, text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.vertical, 12)
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
}

#Preview {
    ContentView()
        .environmentObject(InputMethodManager.shared)
}


import SwiftUI
import AppKit
import KeyboardShortcuts

struct ContentView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NativeAppList()
            .frame(minWidth: 400, idealWidth: 500, maxWidth: .infinity, minHeight: 400)
            .onExitCommand {
                if let window = NSApplication.shared.keyWindow {
                    window.close()
                    NSApp.mainMenu?.cancelTracking()
                    window.resignFirstResponder()
                }
            }
            .alert("error.title".localized, isPresented: $showError) {
                Button("button.ok".localized) {
                    showError = false
                }
            } message: {
                Text(errorMessage)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(InputMethodManager.shared)
}


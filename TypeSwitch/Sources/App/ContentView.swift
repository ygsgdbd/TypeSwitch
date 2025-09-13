import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        NativeAppList()
            .onExitCommand {
                if let window = NSApplication.shared.keyWindow {
                    window.close()
                    NSApp.mainMenu?.cancelTracking()
                    window.resignFirstResponder()
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(InputMethodManager.shared)
}


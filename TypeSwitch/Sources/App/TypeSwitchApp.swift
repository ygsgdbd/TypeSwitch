import SwiftUIX
import AppKit

@main
struct TypeSwitchApp: App {
    @StateObject private var inputMethodManager = InputMethodManager.shared
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(inputMethodManager)
                .task {
                    await inputMethodManager.refreshAllData()
                }
        } label: {
            Image(systemName: .keyboard)
        }
        .menuBarExtraStyle(.menu)
    }
}

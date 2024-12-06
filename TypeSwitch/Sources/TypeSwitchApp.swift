import SwiftUI

@main
struct TypeSwitchApp: App {
    @StateObject private var inputMethodManager = InputMethodManager.shared
    
    init() {
        // 注册全局快捷键
        Task { @MainActor in
            GlobalShortcutManager.shared.registerShortcut()
        }
    }
    
    var body: some Scene {
        MenuBarExtra("TypeSwitch", systemImage: "keyboard") {
            ContentView()
                .environmentObject(inputMethodManager)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            ContentView()
                .environmentObject(inputMethodManager)
        }
    }
}

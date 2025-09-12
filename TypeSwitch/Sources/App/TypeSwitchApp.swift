import SwiftUI
import AppKit

@main
struct TypeSwitchApp: App {
    @StateObject private var inputMethodManager = InputMethodManager.shared
    @State private var statusBarItem: NSStatusItem?
    
    init() {
        // 初始化数据
        Task { @MainActor in
            await InputMethodManager.shared.refreshAllData()
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(inputMethodManager)
        } label: {
            Image(systemName: inputMethodManager.isHighlighted ? "keyboard.fill" : "keyboard")
                .scaleEffect(inputMethodManager.isHighlighted ? 1.2 : 1.0)
        }
        .menuBarExtraStyle(.menu)
    }
}

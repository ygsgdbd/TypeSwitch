import SwiftUI
import KeyboardShortcuts

@main
struct TypeSwitchApp: App {
    @StateObject private var inputMethodManager = InputMethodManager.shared
    
    init() {
        // 初始化数据
        Task { @MainActor in
            await InputMethodManager.shared.refreshAllData()
        }
        
        // 注册快捷键处理
        KeyboardShortcuts.onKeyUp(for: .switchInputMethod) {
            Task { @MainActor in
                // 根据开关状态自动在 quickSwitch 方法内部决定行为
                let result = await InputMethodManager.shared.quickSwitch()
                if result.success, let inputMethodName = result.inputMethodName {
                    NotificationManager.shared.showInputMethodSwitchNotification(inputMethodName: inputMethodName)
                }
            }
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(inputMethodManager)
        } label: {
            Image(systemName: inputMethodManager.isHighlighted ? "keyboard.fill" : "keyboard")
                .scaleEffect(inputMethodManager.isHighlighted ? 1.2 : 1.0)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            ContentView()
                .environmentObject(inputMethodManager)
        }
    }
}

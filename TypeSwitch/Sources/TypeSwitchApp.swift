import SwiftUI

@main
struct TypeSwitchApp: App {
    @StateObject private var inputMethodManager = InputMethodManager.shared
    
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

import AppKit

enum MenuConfirmation {
    @MainActor
    static func confirm(title: String, message: String, confirmButton: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmButton)
        alert.addButton(withTitle: TypeSwitchStrings.Common.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

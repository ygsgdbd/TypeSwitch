import Foundation

enum InputMethodStrategy: Codable, Hashable, Sendable {
    case none
    case ignored
    case fixed(inputMethodId: String)
    case followLast(lastInputMethodId: String?)
}

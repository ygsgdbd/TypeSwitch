import Foundation

enum InputMethodStrategy: Codable, Hashable, Sendable {
    case none
    case fixed(inputMethodId: String)
    case followLast(lastInputMethodId: String?)
}

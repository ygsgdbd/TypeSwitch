import Foundation
import Defaults

extension Defaults.Keys {
    static let appInputMethodSettings = Key<[String: String?]>(
        "appInputMethodSettings",
        default: [:],
        suite: .init(suiteName: "group.top.ygsgdbd.TypeSwitch")!
    )
    
    static let quickSwitchEnabled = Key<Bool>(
        "quickSwitchEnabled",
        default: false,
        suite: .init(suiteName: "group.top.ygsgdbd.TypeSwitch")!
    )
}

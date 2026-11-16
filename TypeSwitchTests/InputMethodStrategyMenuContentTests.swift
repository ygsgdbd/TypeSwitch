import SwiftUI
@testable import TypeSwitch
import XCTest

@MainActor
final class InputMethodStrategyMenuContentTests: XCTestCase {
    func testSelectionBindingsAreMutuallyExclusive() {
        let options: [InputMethodStrategy] = [
            .none,
            .fixed(inputMethodId: "ime.en"),
            .fixed(inputMethodId: "ime.zh"),
            .followLast(lastInputMethodId: "ime.zh"),
        ]
        let cases: [(InputMethodStrategy, [Bool])] = [
            (.none, [true, false, false, false]),
            (.fixed(inputMethodId: "ime.en"), [false, true, false, false]),
            (.fixed(inputMethodId: "ime.zh"), [false, false, true, false]),
            (.followLast(lastInputMethodId: "ime.zh"), [false, false, false, true]),
        ]

        for (strategy, expectedSelection) in cases {
            let content = makeContent(strategy: strategy)

            XCTAssertEqual(
                options.map { content.selectionBinding(for: $0).wrappedValue },
                expectedSelection
            )
        }
    }

    func testDefaultInheritanceDoesNotSelectFixedInputMethod() {
        let content = makeContent(strategy: .none, defaultOptionSubtitle: "ABC")

        XCTAssertTrue(content.selectionBinding(for: .none).wrappedValue)
        XCTAssertFalse(content.selectionBinding(for: .fixed(inputMethodId: "ime.en")).wrappedValue)
    }

    func testDeselectingCurrentOptionDoesNotSendStrategy() {
        let strategies: [InputMethodStrategy] = [
            .none,
            .fixed(inputMethodId: "ime.en"),
            .followLast(lastInputMethodId: "ime.zh"),
        ]

        for strategy in strategies {
            var selections: [InputMethodStrategy] = []
            let content = makeContent(strategy: strategy) { selections.append($0) }

            content.selectionBinding(for: strategy).wrappedValue = false

            XCTAssertTrue(selections.isEmpty)
        }
    }

    func testSelectingAnotherOptionSendsItsStrategyOnce() {
        let options: [InputMethodStrategy] = [
            .none,
            .fixed(inputMethodId: "ime.zh"),
            .followLast(lastInputMethodId: nil),
        ]

        for option in options {
            var selections: [InputMethodStrategy] = []
            let content = makeContent(strategy: .fixed(inputMethodId: "ime.en")) {
                selections.append($0)
            }

            content.selectionBinding(for: option).wrappedValue = true

            XCTAssertEqual(selections, [option])
        }
    }

    func testFollowLastSelectionPreservesRememberedInputMethod() {
        let strategy = InputMethodStrategy.followLast(lastInputMethodId: "ime.zh")
        var selections: [InputMethodStrategy] = []
        let content = makeContent(strategy: strategy) { selections.append($0) }

        XCTAssertTrue(content.selectionBinding(for: strategy).wrappedValue)

        content.selectionBinding(for: strategy).wrappedValue = true

        XCTAssertEqual(selections, [.followLast(lastInputMethodId: "ime.zh")])
    }

    private func makeContent(
        strategy: InputMethodStrategy,
        defaultOptionSubtitle: String? = nil,
        onSelectStrategy: @escaping (InputMethodStrategy) -> Void = { _ in }
    ) -> InputMethodStrategyMenuContent {
        InputMethodStrategyMenuContent(
            context: .appRule,
            strategy: strategy,
            inputMethods: [
                InputMethod(id: "ime.en", name: "ABC"),
                InputMethod(id: "ime.zh", name: "Pinyin"),
            ],
            defaultOptionSubtitle: defaultOptionSubtitle,
            followLastOptionSubtitle: nil,
            unavailableFixedOptionLabel: nil,
            onSelectStrategy: onSelectStrategy
        )
    }
}

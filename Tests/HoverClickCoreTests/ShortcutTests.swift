import XCTest

@testable import HoverClickCore

final class ShortcutTests: XCTestCase {
  func testDefaultShortcutsAreDistinctAndHaveModifiers() {
    XCTAssertNotEqual(Shortcut.defaultLeftClick, Shortcut.defaultRightClick)
    XCTAssertTrue(Shortcut.defaultLeftClick.hasModifier)
    XCTAssertTrue(Shortcut.defaultRightClick.hasModifier)
  }

  func testDefaultShortcutDisplay() {
    XCTAssertEqual(Shortcut.defaultLeftClick.displayText, "⌃⌥⌘A")
    XCTAssertEqual(Shortcut.defaultRightClick.displayText, "⌃⌥⌘S")
  }

  func testShortcutCodableRoundTrip() throws {
    let original = Shortcut(keyCode: 17, modifiers: Shortcut.commandMask | Shortcut.shiftMask)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    XCTAssertEqual(decoded, original)
  }

  func testKeyNamesCoverCommonKeys() {
    XCTAssertEqual(Shortcut(keyCode: 36, modifiers: Shortcut.commandMask).displayText, "⌘↩")
    XCTAssertEqual(Shortcut(keyCode: 49, modifiers: Shortcut.optionMask).displayText, "⌥Space")
  }

  func testFunctionKeyLabelsUseMacVirtualKeyCodes() {
    XCTAssertEqual(Shortcut(keyCode: 122, modifiers: Shortcut.commandMask).displayText, "⌘F1")
    XCTAssertEqual(Shortcut(keyCode: 120, modifiers: Shortcut.commandMask).displayText, "⌘F2")
    XCTAssertEqual(Shortcut(keyCode: 99, modifiers: Shortcut.optionMask).displayText, "⌥F3")
    XCTAssertEqual(Shortcut(keyCode: 90, modifiers: Shortcut.shiftMask).displayText, "⇧F20")
  }
}

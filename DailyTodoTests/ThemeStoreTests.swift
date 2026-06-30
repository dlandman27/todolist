import XCTest
@testable import DailyTodo

final class ThemeStoreTests: XCTestCase {

    func testNormalizedHexAcceptsValidForms() {
        XCTAssertEqual(ThemeStore.normalizedHex("bc4749"), "BC4749")
        XCTAssertEqual(ThemeStore.normalizedHex("#BC4749"), "BC4749")
        XCTAssertEqual(ThemeStore.normalizedHex("  BC4749  "), "BC4749")
    }

    func testNormalizedHexRejectsInvalid() {
        XCTAssertNil(ThemeStore.normalizedHex(nil))
        XCTAssertNil(ThemeStore.normalizedHex("xyz123"))
        XCTAssertNil(ThemeStore.normalizedHex("BC474"))     // 5 digits
        XCTAssertNil(ThemeStore.normalizedHex("BC474900"))  // 8 digits
    }

    func testHexValueParsesToUInt32() {
        XCTAssertEqual(ThemeStore.hexValue("BC4749"), 0xBC4749)
        XCTAssertEqual(ThemeStore.hexValue("FFFFFF"), 0xFFFFFF)
        XCTAssertEqual(ThemeStore.hexValue("000000"), 0x000000)
    }

    func testPresetsAreCanonicalAndDefaultIsFirst() {
        XCTAssertEqual(ThemeStore.presets.first, ThemeStore.defaultAccentHex)
        for hex in ThemeStore.presets {
            XCTAssertEqual(ThemeStore.normalizedHex(hex), hex, "preset \(hex) must already be canonical")
        }
    }

    func testDefaultAccentIsBrick() {
        XCTAssertEqual(ThemeStore.defaultAccentHex, "BC4749")
    }
}

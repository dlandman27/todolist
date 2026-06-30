import XCTest
import SwiftUI
@testable import DailyTodo

final class ThemeColorTests: XCTestCase {

    private func rgbSum(_ hex: String) -> Int {
        let v = Int(ThemeStore.hexValue(hex))
        return ((v >> 16) & 0xFF) + ((v >> 8) & 0xFF) + (v & 0xFF)
    }

    func testColorToHexRoundTripsWithInit() {
        XCTAssertEqual(Color(hex: 0xBC4749).toHex(), "BC4749")
        XCTAssertEqual(Color(hex: 0xFFFFFF).toHex(), "FFFFFF")
        XCTAssertEqual(Color(hex: 0x000000).toHex(), "000000")
    }

    func testAdjustingBrightnessDarkens() {
        let base = UIColor(red: 0.7, green: 0.3, blue: 0.3, alpha: 1)
        let darker = base.adjustingBrightness(0.8)
        var h0: CGFloat = 0, s0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        base.getHue(&h0, saturation: &s0, brightness: &b0, alpha: &a0)
        darker.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        XCTAssertLessThan(b1, b0)
    }

    func testBlendEndpoints() {
        let a = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let b = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(Color(uiColor: a.blended(with: b, fraction: 0)).toHex(), "FF0000")
        XCTAssertEqual(Color(uiColor: a.blended(with: b, fraction: 1)).toHex(), "0000FF")
    }

    func testBrandDarkIsDarkerThanBrand() {
        // With no override, accent == default brick.
        XCTAssertLessThan(rgbSum(Color.brandDark.toHex()), rgbSum(Color.brand.toHex()))
    }
}

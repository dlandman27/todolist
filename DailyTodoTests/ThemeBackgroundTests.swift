import XCTest
@testable import DailyTodo

final class ThemeBackgroundTests: XCTestCase {

    func testKindRawRoundTrips() {
        for kind in BackgroundKind.allCases {
            XCTAssertEqual(BackgroundKind.from(kind.rawValue), kind)
        }
    }

    func testUnknownKindFallsBackToNone() {
        XCTAssertEqual(BackgroundKind.from("wallpaper"), .none)
        XCTAssertEqual(BackgroundKind.from(nil), .none)
    }

    func testScrimIsZeroForNoneAndSolid() {
        XCTAssertEqual(BackgroundKind.none.scrimOpacity, 0)
        XCTAssertEqual(BackgroundKind.solid.scrimOpacity, 0)
    }

    func testPhotoScrimIsStrongerThanGradient() {
        XCTAssertGreaterThan(BackgroundKind.photo.scrimOpacity, BackgroundKind.gradient.scrimOpacity)
        XCTAssertGreaterThan(BackgroundKind.gradient.scrimOpacity, 0)
    }
}

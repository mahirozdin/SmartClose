import XCTest
@testable import SmartClose

final class WildcardMatcherTests: XCTestCase {
    func testExactMatch() {
        XCTAssertTrue(WildcardMatcher.matches(pattern: "com.example.app", value: "com.example.app"))
        XCTAssertFalse(WildcardMatcher.matches(pattern: "com.example.app", value: "com.example.other"))
    }

    func testWildcardSuffix() {
        XCTAssertTrue(WildcardMatcher.matches(pattern: "com.jetbrains.*", value: "com.jetbrains.intellij"))
        XCTAssertTrue(WildcardMatcher.matches(pattern: "com.jetbrains.*", value: "com.jetbrains.rider"))
        XCTAssertFalse(WildcardMatcher.matches(pattern: "com.jetbrains.*", value: "com.apple.finder"))
    }

    func testWildcardAnywhere() {
        XCTAssertTrue(WildcardMatcher.matches(pattern: "*.example.*", value: "com.example.app"))
    }
}

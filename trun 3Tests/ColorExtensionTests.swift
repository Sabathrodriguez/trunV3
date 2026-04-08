//
//  ColorExtensionTests.swift
//  trun 3Tests
//
//  Tests for Color.fromUID — deterministically maps a user ID string to one
//  of 8 predefined colors using a djb2 hash function. This ensures each
//  runner on the live map gets a consistent, visually distinct color
//  across all devices and sessions.
//

import XCTest
import SwiftUI
@testable import trun_3

final class ColorExtensionTests: XCTestCase {

    // MARK: - Determinism

    /// The same UID should always produce the same color, no matter how
    /// many times it's called. This is critical for consistent UI across
    /// the live map, leaderboard, and route sharing views.
    func test_fromUID_isDeterministic() {
        let uid = "user-abc-123"
        let color1 = Color.fromUID(uid)
        let color2 = Color.fromUID(uid)
        XCTAssertEqual(color1, color2, "Same UID should always produce the same color")
    }

    /// Different UIDs should (in most cases) produce different colors,
    /// ensuring visual distinction between runners on the same route.
    /// Note: With only 8 colors, collisions are possible, but completely
    /// different strings should usually hash to different buckets.
    func test_fromUID_differentUIDs_usuallyDifferentColors() {
        let color1 = Color.fromUID("alice")
        let color2 = Color.fromUID("bob")
        let color3 = Color.fromUID("charlie")

        // At least 2 of these 3 should differ (extremely unlikely all 3 collide)
        let unique = Set(["\(color1)", "\(color2)", "\(color3)"])
        XCTAssertGreaterThan(unique.count, 1, "Different UIDs should generally produce different colors")
    }

    // MARK: - Edge cases

    /// An empty string is a valid (if unusual) UID. The hash function should
    /// handle it without crashing and return a valid color.
    func test_fromUID_emptyString_doesNotCrash() {
        let color = Color.fromUID("")
        // Just verify it returns something — any of the 8 colors is fine
        XCTAssertNotNil(color, "Empty string should still produce a valid color")
    }

    /// Very long UIDs should hash correctly without overflow issues.
    /// The implementation uses &<< and &+ (overflow operators) to prevent crashes.
    func test_fromUID_veryLongUID_doesNotCrash() {
        let longUID = String(repeating: "a", count: 10000)
        let color = Color.fromUID(longUID)
        XCTAssertNotNil(color, "Very long UID should not cause overflow crash")
    }

    /// UIDs containing special characters (Firebase UIDs can include
    /// alphanumeric chars, underscores, hyphens) should hash correctly.
    func test_fromUID_specialCharacters() {
        let uid = "user_ABC-123.test@example"
        let color = Color.fromUID(uid)
        XCTAssertNotNil(color, "Special characters in UID should not cause issues")

        // Verify determinism with special chars
        let color2 = Color.fromUID(uid)
        XCTAssertEqual(color, color2)
    }

    /// Unicode characters in UIDs (though uncommon) should be handled
    /// correctly by iterating over UTF-8 bytes.
    func test_fromUID_unicodeCharacters() {
        let uid = "用户🏃‍♂️"
        let color = Color.fromUID(uid)
        XCTAssertNotNil(color, "Unicode UID should produce a valid color")
    }

    // MARK: - Color range

    /// The hash modulo should always produce an index within the 8-color palette.
    /// Test a variety of inputs to ensure no out-of-bounds access.
    func test_fromUID_alwaysProducesValidColor() {
        let testUIDs = [
            "a", "b", "c", "abc123", "user-1", "user-2",
            "long-uid-with-many-characters-in-it-for-testing",
            "12345", "", "x"
        ]
        for uid in testUIDs {
            // This should not crash — if fromUID has an array index out of bounds,
            // this test will catch it
            let _ = Color.fromUID(uid)
        }
    }
}

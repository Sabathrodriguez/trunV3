//
//  KeychainHelperTests.swift
//  trun 3Tests
//
//  Tests for KeychainHelper — wraps the iOS Keychain Services API for
//  securely storing sensitive data (e.g. Strava OAuth tokens).
//  Tests cover save/load/delete for both raw Data and String convenience methods.
//
//  Note: Keychain access works in the test host environment. Each test
//  cleans up its keys in tearDown to avoid cross-test contamination.
//

import XCTest
@testable import trun_3

final class KeychainHelperTests: XCTestCase {

    /// Unique key prefix to avoid collisions with real app keychain items.
    private let testKey = "com.trun3.tests.keychainHelper.\(UUID().uuidString)"

    override func tearDown() {
        // Always clean up the test key from the keychain after each test.
        KeychainHelper.delete(key: testKey)
        super.tearDown()
    }

    // MARK: - save / load (Data)

    /// Saving data to a new key should succeed (return true) and the data
    /// should be retrievable via load.
    func test_save_andLoad_roundTrip() {
        let data = "secret-token-123".data(using: .utf8)!
        let saved = KeychainHelper.save(key: testKey, data: data)
        XCTAssertTrue(saved, "Save should return true for a new key")

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertEqual(loaded, data, "Loaded data should match what was saved")
    }

    /// Saving to the same key twice should overwrite the previous value.
    /// The implementation deletes first then adds, so the second save should succeed.
    func test_save_overwritesExistingValue() {
        let data1 = "first".data(using: .utf8)!
        let data2 = "second".data(using: .utf8)!

        KeychainHelper.save(key: testKey, data: data1)
        KeychainHelper.save(key: testKey, data: data2)

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertEqual(
            String(data: loaded ?? Data(), encoding: .utf8),
            "second",
            "Second save should overwrite the first value"
        )
    }

    /// Loading a key that was never saved should return nil, not crash or
    /// return empty data.
    func test_load_returnsNil_forNonexistentKey() {
        let loaded = KeychainHelper.load(key: "nonexistent-key-\(UUID().uuidString)")
        XCTAssertNil(loaded, "Non-existent key should return nil")
    }

    // MARK: - delete

    /// After deleting a previously saved key, load should return nil.
    func test_delete_removesKey() {
        let data = "to-delete".data(using: .utf8)!
        KeychainHelper.save(key: testKey, data: data)

        KeychainHelper.delete(key: testKey)

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertNil(loaded, "Deleted key should no longer be loadable")
    }

    /// Deleting a non-existent key should be a no-op (no crash).
    func test_delete_isIdempotent() {
        KeychainHelper.delete(key: "nonexistent-\(UUID().uuidString)")
        // If we get here without crashing, the test passes
    }

    // MARK: - saveString / loadString (convenience)

    /// The string convenience methods should round-trip a string value
    /// through the keychain via UTF-8 encoding.
    func test_saveString_andLoadString_roundTrip() {
        let token = "oauth-access-token-abc123"
        let saved = KeychainHelper.saveString(key: testKey, value: token)
        XCTAssertTrue(saved, "saveString should return true on success")

        let loaded = KeychainHelper.loadString(key: testKey)
        XCTAssertEqual(loaded, token, "loadString should return the exact string that was saved")
    }

    /// loadString should return nil when the key doesn't exist,
    /// just like the raw Data version.
    func test_loadString_returnsNil_forNonexistentKey() {
        let loaded = KeychainHelper.loadString(key: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(loaded, "Non-existent key should return nil for string load")
    }

    /// Empty strings should be saveable and loadable — they're valid values
    /// (e.g. a cleared token that needs to be distinguishable from "no value").
    func test_saveString_emptyString() {
        let saved = KeychainHelper.saveString(key: testKey, value: "")
        XCTAssertTrue(saved, "Empty string should be saveable")

        let loaded = KeychainHelper.loadString(key: testKey)
        XCTAssertEqual(loaded, "", "Empty string should round-trip correctly")
    }
}

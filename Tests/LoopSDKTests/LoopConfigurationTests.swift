import XCTest
@testable import LoopSDK

final class LoopConfigurationTests: XCTestCase {

    func test_resolveTier_returns_nil_when_provider_is_nil() {
        XCTAssertNil(LoopConfiguration.resolveTier(from: nil))
    }

    func test_resolveTier_returns_nil_when_provider_returns_nil() {
        XCTAssertNil(LoopConfiguration.resolveTier(from: { nil }))
    }

    func test_resolveTier_returns_nil_for_empty_or_whitespace() {
        XCTAssertNil(LoopConfiguration.resolveTier(from: { "" }))
        XCTAssertNil(LoopConfiguration.resolveTier(from: { "   " }))
        XCTAssertNil(LoopConfiguration.resolveTier(from: { "\n\t" }))
    }

    func test_resolveTier_passes_through_non_empty_values() {
        XCTAssertEqual(LoopConfiguration.resolveTier(from: { "paid" }), "paid")
        XCTAssertEqual(LoopConfiguration.resolveTier(from: { "pro" }), "pro")
        // Trims surrounding whitespace but preserves internal characters
        // and host-chosen casing (e.g. 'Founder', 'Free Trial').
        XCTAssertEqual(LoopConfiguration.resolveTier(from: { "  paid  " }), "paid")
        XCTAssertEqual(LoopConfiguration.resolveTier(from: { "Founder" }), "Founder")
    }

    func test_init_stores_tierProvider() {
        let config = LoopConfiguration(apiKey: "loop_pk_test", tierProvider: { "paid" })
        XCTAssertEqual(LoopConfiguration.resolveTier(from: config.tierProvider), "paid")
    }

    func test_init_defaults_tierProvider_to_nil() {
        let config = LoopConfiguration(apiKey: "loop_pk_test")
        XCTAssertNil(config.tierProvider)
    }
}

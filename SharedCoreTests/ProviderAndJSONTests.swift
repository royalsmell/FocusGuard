import Foundation
import XCTest
@testable import SharedCore

final class ProviderAndJSONTests: XCTestCase {
    func testProviderBuildsChatCompletionsURL() {
        let provider = ProviderConfig(
            name: "Test",
            baseURL: URL(string: "https://example.com/v1")!,
            model: "vision"
        )
        XCTAssertEqual(provider.chatCompletionsURL.absoluteString, "https://example.com/v1/chat/completions")

        let trailingSlash = ProviderConfig(
            name: "Test",
            baseURL: URL(string: "https://example.com/v1/")!,
            model: "vision"
        )
        XCTAssertEqual(trailingSlash.chatCompletionsURL.absoluteString, "https://example.com/v1/chat/completions")
    }

    func testProviderRequiresHTTPSExceptOnLocalNetwork() {
        let remoteHTTP = ProviderConfig(
            name: "Remote",
            baseURL: URL(string: "http://example.com/v1")!,
            model: "vision"
        )
        let remoteHTTPS = ProviderConfig(
            name: "Remote",
            baseURL: URL(string: "https://example.com/v1")!,
            model: "vision"
        )
        let localHTTP = ProviderConfig(
            name: "Local",
            baseURL: URL(string: "http://192.168.1.20:1234/v1")!,
            model: "vision"
        )
        XCTAssertFalse(remoteHTTP.isAllowedEndpoint)
        XCTAssertTrue(remoteHTTPS.isAllowedEndpoint)
        XCTAssertTrue(localHTTP.isAllowedEndpoint)
        XCTAssertTrue(localHTTP.isLocalNetworkEndpoint)
    }

    func testKeychainAccessGroupUsesActualSigningPrefix() {
        XCTAssertEqual(
            KeychainAccessGroupResolver.sharedAccessGroup(
                defaultAccessGroup: "ABCDE12345.com.huangjiawen.focusguard",
                bundleIdentifier: "com.huangjiawen.focusguard"
            ),
            "ABCDE12345.com.huangjiawen.focusguard.shared"
        )
        XCTAssertEqual(
            KeychainAccessGroupResolver.sharedAccessGroup(
                defaultAccessGroup: "TEAM98765.rewritten.bundle",
                bundleIdentifier: "unrelated.bundle"
            ),
            "TEAM98765.com.huangjiawen.focusguard.shared"
        )
    }

    func testJSONFenceIsRemoved() {
        let input = """
        ```json
        {"level":"focused"}
        ```
        """
        XCTAssertEqual(OpenAICompatibleVisionService.cleanJSON(input), #"{"level":"focused"}"#)
    }

    func testJudgmentRejectsUnknownLevelAndMalformedJSON() async throws {
        let service = OpenAICompatibleVisionService(
            provider: .suggested,
            apiKey: "test-only"
        )

        XCTAssertThrowsError(
            try service.decodeJSON(
                FocusJudgment.self,
                from: #"{"level":"busy","confidence":0.9,"reason":"","reminder":""}"#
            )
        )
        XCTAssertThrowsError(
            try service.decodeJSON(FocusJudgment.self, from: "not-json")
        )
    }
}

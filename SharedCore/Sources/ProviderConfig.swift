import Foundation

public struct ProviderConfig: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var model: String

    public init(id: UUID = UUID(), name: String, baseURL: URL, model: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }

    public var chatCompletionsURL: URL {
        let trimmed = baseURL.absoluteString.replacingOccurrences(
            of: #"/+$"#,
            with: "",
            options: .regularExpression
        )
        let normalized = URL(string: trimmed) ?? baseURL
        if normalized.path.lowercased().hasSuffix("/chat/completions") {
            return normalized
        }
        if normalized.path.lowercased().hasSuffix("/v1") {
            return normalized.appendingPathComponent("chat/completions")
        }
        return normalized.appendingPathComponent("v1/chat/completions")
    }

    public var isAllowedEndpoint: Bool {
        guard let scheme = baseURL.scheme?.lowercased(), let host = baseURL.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && Self.isLocalNetworkHost(host)
    }

    public var isLocalNetworkEndpoint: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isLocalNetworkHost(host)
    }

    private static func isLocalNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") || host.hasSuffix(".home.arpa") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }

    public static let suggested = ProviderConfig(
        name: "OpenAI Compatible",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        model: "gpt-4o-mini"
    )
}

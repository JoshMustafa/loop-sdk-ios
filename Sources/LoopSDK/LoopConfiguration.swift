import Foundation

/// Static configuration the host app provides once at launch via
/// `LoopSDK.start(...)`. Values are read-only after construction.
public struct LoopConfiguration: Sendable {
    /// Default production base URL. Override in `start(...)` for staging
    /// or local backends.
    public static let defaultBaseURL = URL(string: "https://api.loop.io")!

    public let apiKey: String
    public let apiBase: URL

    public init(apiKey: String, apiBase: URL = LoopConfiguration.defaultBaseURL) {
        self.apiKey = apiKey
        self.apiBase = apiBase
    }
}

import Foundation

/// Static configuration the host app provides once at launch via
/// `LoopSDK.start(...)`. Values are read-only after construction.
public struct LoopConfiguration: Sendable {
    /// Backend base URL the SDK posts to. Hard-coded here so host apps
    /// don't have to know or care where the Loop server lives — they
    /// just paste their `loop_pk_…` key and they're done.
    ///
    /// Production endpoint on Fly. Override per-test by passing a custom
    /// `apiBase` to `LoopSDK.start(...)` if you need to point at a local
    /// backend during development.
    public static let defaultBaseURL = URL(string: "https://loop-backend.fly.dev")!

    public let apiKey: String
    public let apiBase: URL

    public init(apiKey: String, apiBase: URL = LoopConfiguration.defaultBaseURL) {
        self.apiKey = apiKey
        self.apiBase = apiBase
    }
}

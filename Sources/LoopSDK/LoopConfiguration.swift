import Foundation

/// Static configuration the host app provides once at launch via
/// `LoopSDK.start(...)`. Values are read-only after construction.
public struct LoopConfiguration: Sendable {
    /// Backend base URL the SDK posts to. Hard-coded here so host apps
    /// don't have to know or care where the Loop server lives — they
    /// just paste their `loop_pk_…` key and they're done.
    ///
    /// Until the public production endpoint stands up, this points at
    /// the local dev backend on the Mac's LAN IP (which the iOS
    /// Simulator and any iPhone on the same Wi-Fi can reach). When
    /// `https://api.loop.io` (or wherever) is live, change this and
    /// re-tag.
    public static let defaultBaseURL = URL(string: "http://192.168.1.115:4000")!

    public let apiKey: String
    public let apiBase: URL

    public init(apiKey: String, apiBase: URL = LoopConfiguration.defaultBaseURL) {
        self.apiKey = apiKey
        self.apiBase = apiBase
    }
}

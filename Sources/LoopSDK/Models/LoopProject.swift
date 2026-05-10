import Foundation

/// Lightweight project metadata returned by `GET /api/ingest/project`.
/// The SDK uses this to brand its UI (project name + accent colour).
public struct LoopProject: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let accent: String
    public let version: String

    public init(id: String, name: String, icon: String, accent: String, version: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.accent = accent
        self.version = version
    }
}

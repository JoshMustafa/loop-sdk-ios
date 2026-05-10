import Foundation

/// A bug or feature submission as visible to the SDK end-user. Mirrors the
/// public JSON shape from the backend (camelCase, no device meta).
public struct LoopItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case bug
        case feature
    }

    /// Per-kind statuses. The set is open-ended on purpose — the backend may
    /// add new statuses without breaking the SDK; unknown values decode to
    /// `.other(rawValue)`.
    public enum Status: Codable, Sendable, Equatable, Hashable {
        case open
        case planned
        case inProgress
        case triaged
        case resolved
        case shipped
        case wontFix
        case other(String)

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self.from(rawValue: raw)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(rawValue)
        }

        public var rawValue: String {
            switch self {
            case .open: return "open"
            case .planned: return "planned"
            case .inProgress: return "in-progress"
            case .triaged: return "triaged"
            case .resolved: return "resolved"
            case .shipped: return "shipped"
            case .wontFix: return "wont-fix"
            case .other(let s): return s
            }
        }

        static func from(rawValue: String) -> Status {
            switch rawValue {
            case "open": return .open
            case "planned": return .planned
            case "in-progress": return .inProgress
            case "triaged": return .triaged
            case "resolved": return .resolved
            case "shipped": return .shipped
            case "wont-fix": return .wontFix
            default: return .other(rawValue)
            }
        }

        /// True for terminal states (resolved / shipped / wont-fix).
        public var isClosed: Bool {
            switch self {
            case .resolved, .shipped, .wontFix: return true
            default: return false
            }
        }
    }

    public let id: String          // "LP-####"
    public let kind: Kind
    public let status: Status
    public let title: String
    public let body: String
    public let whenLabel: String
    public let createdAt: Date
    public let votes: Int
    public let my: VoteDir?
    public let replyCount: Int

    public init(
        id: String,
        kind: Kind,
        status: Status,
        title: String,
        body: String,
        whenLabel: String,
        createdAt: Date,
        votes: Int,
        my: VoteDir?,
        replyCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.body = body
        self.whenLabel = whenLabel
        self.createdAt = createdAt
        self.votes = votes
        self.my = my
        self.replyCount = replyCount
    }
}

/// Page returned by the public list endpoints.
public struct LoopItemPage: Codable, Sendable, Equatable {
    public let items: [LoopItem]
    public let nextCursor: String?
}

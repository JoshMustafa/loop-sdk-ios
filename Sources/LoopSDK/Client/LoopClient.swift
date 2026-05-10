import Foundation

/// Async API client for the public Loop ingest surface.
///
/// Wraps `URLSession` with the `Authorization` and `X-Loop-Reporter-Id`
/// headers populated from the SDK configuration. Decodes responses with
/// ISO-8601 dates and explicit camelCase keys (no `convertFromSnakeCase`,
/// the backend already returns camelCase).
public actor LoopClient {
    public struct VotePayload: Codable, Sendable {
        public let dir: VoteDir?
    }

    public struct SubmitPayload: Codable, Sendable {
        public let type: String
        public let title: String
        public let body: String
        public let reporter_id: String
        public let device_meta: DeviceMetaPayload
    }

    public struct DeviceMetaPayload: Codable, Sendable {
        public let device: String
        public let os: String
        public let appVersion: String
        public let locale: String
        public let network: String
        public let sessionId: String
    }

    private let baseURL: URL
    private let apiKey: String
    private let reporterId: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, reporterId: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.reporterId = reporterId

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public methods

    public func fetchProject() async throws -> LoopProject {
        try await send(.getProject, decoding: LoopProject.self)
    }

    public func fetchBugs(cursor: String? = nil, limit: Int = 20) async throws -> LoopItemPage {
        try await send(.listBugs(cursor: cursor, limit: limit), decoding: LoopItemPage.self)
    }

    public func fetchFeatures(cursor: String? = nil, limit: Int = 20) async throws -> LoopItemPage {
        try await send(.listFeatures(cursor: cursor, limit: limit), decoding: LoopItemPage.self)
    }

    public func vote(itemId: String, dir: VoteDir?) async throws -> LoopVoteResult {
        try await send(
            .vote(itemId: itemId),
            body: VotePayload(dir: dir),
            decoding: LoopVoteResult.self
        )
    }

    public func submit(payload: SubmitPayload) async throws -> LoopSubmissionResult {
        try await send(.submit, body: payload, decoding: LoopSubmissionResult.self)
    }

    // MARK: - Internal

    private func send<T: Decodable & Sendable>(
        _ endpoint: LoopEndpoint,
        decoding: T.Type
    ) async throws -> T {
        let request = try endpoint.buildRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            reporterId: reporterId
        )
        return try await execute(request, decoding: decoding)
    }

    private func send<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ endpoint: LoopEndpoint,
        body: Body,
        decoding: T.Type
    ) async throws -> T {
        var request = try endpoint.buildRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            reporterId: reporterId
        )
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        return try await execute(request, decoding: decoding)
    }

    private func execute<T: Decodable & Sendable>(
        _ request: URLRequest,
        decoding: T.Type
    ) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw LoopError.transport(error.code)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LoopError.unknown(status: -1)
        }

        switch http.statusCode {
        case 200..<300:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: data)
            } catch {
                throw LoopError.decoding(String(describing: error))
            }

        case 400:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw LoopError.badRequest(message: message)

        case 401, 403:
            throw LoopError.invalidApiKey

        case 404:
            throw LoopError.notFound

        case 500..<600:
            throw LoopError.serverError(status: http.statusCode)

        default:
            throw LoopError.unknown(status: http.statusCode)
        }
    }
}

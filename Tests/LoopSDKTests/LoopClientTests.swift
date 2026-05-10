import XCTest
@testable import LoopSDK

final class LoopClientTests: XCTestCase {

    private let baseURL = URL(string: "https://example.test")!
    private let apiKey = "loop_pk_pebble_aabbccdd11223344"
    private let reporterId = "r_abcd1234abcd"

    func test_sends_bearer_and_reporter_id_headers() async throws {
        var capturedAuth: String?
        var capturedReporter: String?

        let session = MockURLProtocol.install { req in
            capturedAuth = req.value(forHTTPHeaderField: "Authorization")
            capturedReporter = req.value(forHTTPHeaderField: "X-Loop-Reporter-Id")
            let body = ##"{"id":"pebble","name":"Pebble","icon":"🪨","accent":"#3a2a1f","version":"v1.0"}"##
            return (.with(status: 200), Data(body.utf8))
        }

        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)
        let project = try await client.fetchProject()

        XCTAssertEqual(project.id, "pebble")
        XCTAssertEqual(capturedAuth, "Bearer \(apiKey)")
        XCTAssertEqual(capturedReporter, reporterId)
    }

    func test_decodes_paged_items() async throws {
        let json = """
        {
          "items": [
            {
              "id":"LP-1","kind":"bug","status":"open","title":"x","body":"y",
              "whenLabel":"now","createdAt":"2026-05-10T12:00:00Z",
              "votes":3,"my":"up","replyCount":0
            }
          ],
          "nextCursor":"opaque"
        }
        """

        let session = MockURLProtocol.install { _ in
            (.with(status: 200), Data(json.utf8))
        }

        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)
        let page = try await client.fetchBugs()

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "LP-1")
        XCTAssertEqual(page.items.first?.kind, .bug)
        XCTAssertEqual(page.items.first?.status, .open)
        XCTAssertEqual(page.items.first?.my, .up)
        XCTAssertEqual(page.nextCursor, "opaque")
    }

    func test_passes_cursor_and_limit_in_query_string() async throws {
        var capturedURL: URL?

        let session = MockURLProtocol.install { req in
            capturedURL = req.url
            return (.with(status: 200), Data(#"{"items":[],"nextCursor":null}"#.utf8))
        }

        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)
        _ = try await client.fetchBugs(cursor: "abc", limit: 5)

        let query = capturedURL?.query ?? ""
        XCTAssertTrue(query.contains("limit=5"))
        XCTAssertTrue(query.contains("cursor=abc"))
        XCTAssertEqual(capturedURL?.path, "/api/ingest/bugs")
    }

    func test_401_maps_to_invalidApiKey() async {
        let session = MockURLProtocol.install { _ in
            (.with(status: 401), Data(#"{"error":"invalid api key"}"#.utf8))
        }
        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)

        do {
            _ = try await client.fetchProject()
            XCTFail("expected invalidApiKey")
        } catch let error as LoopError {
            XCTAssertEqual(error, .invalidApiKey)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_400_carries_message() async {
        let session = MockURLProtocol.install { _ in
            (.with(status: 400), Data(#"{"error":"missing X-Loop-Reporter-Id"}"#.utf8))
        }
        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)

        do {
            _ = try await client.fetchProject()
            XCTFail("expected badRequest")
        } catch LoopError.badRequest(let message) {
            XCTAssertEqual(message, "missing X-Loop-Reporter-Id")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_vote_round_trips() async throws {
        var capturedBody: Data?
        var capturedPath: String?
        var capturedMethod: String?

        let session = MockURLProtocol.install { req in
            capturedPath = req.url?.path
            capturedMethod = req.httpMethod
            capturedBody = req.httpBodyStreamData()
            return (.with(status: 200), Data(#"{"id":"LP-1","votes":1,"my":"up"}"#.utf8))
        }

        let client = LoopClient(baseURL: baseURL, apiKey: apiKey, reporterId: reporterId, session: session)
        let result = try await client.vote(itemId: "LP-1", dir: .up)

        XCTAssertEqual(result.votes, 1)
        XCTAssertEqual(result.my, .up)
        XCTAssertEqual(capturedPath, "/api/ingest/items/LP-1/vote")
        XCTAssertEqual(capturedMethod, "POST")

        let json = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["dir"] as? String, "up")
    }

    func test_unknown_status_value_decodes_as_other() throws {
        let json = """
        {
          "id":"LP-9","kind":"feature","status":"frozen",
          "title":"x","body":"y","whenLabel":"now",
          "createdAt":"2026-05-10T12:00:00Z","votes":0,"my":null,"replyCount":0
        }
        """
        let item = try JSONDecoder.iso().decode(LoopItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.status, .other("frozen"))
    }
}

private extension JSONDecoder {
    static func iso() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private extension URLRequest {
    /// URLProtocol receives the body via `httpBodyStream`, not `httpBody`.
    /// Reads the entire stream into memory for assertion in tests.
    func httpBodyStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

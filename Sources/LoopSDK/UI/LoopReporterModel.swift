#if os(iOS)
import Foundation
import SwiftUI

/// View-model behind `LoopReporterView`. Holds the bug + feature lists,
/// drives loading/voting/submitting, and surfaces user-visible errors.
///
/// Uses `ObservableObject` instead of `@Observable` so we keep iOS 16
/// compatibility (Observation framework is iOS 17+).
@MainActor
final class LoopReporterModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var project: LoopProject?
    @Published var projectState: LoadState = .idle

    @Published var bugs: [LoopItem] = []
    @Published var bugsCursor: String?
    @Published var bugsState: LoadState = .idle

    @Published var features: [LoopItem] = []
    @Published var featuresCursor: String?
    @Published var featuresState: LoadState = .idle

    @Published var transientError: String?

    let client: LoopClient
    let reporterId: String
    let sessionId: String

    init(client: LoopClient, reporterId: String, sessionId: String) {
        self.client = client
        self.reporterId = reporterId
        self.sessionId = sessionId
    }

    func bootstrap() async {
        await loadProject()
        async let b: Void = refreshBugs()
        async let f: Void = refreshFeatures()
        _ = await (b, f)
    }

    func loadProject() async {
        projectState = .loading
        do {
            project = try await client.fetchProject()
            projectState = .loaded
        } catch let error as LoopError {
            projectState = .failed(humanise(error))
        } catch {
            projectState = .failed("Couldn't reach Loop")
        }
    }

    func refreshBugs() async {
        bugsState = .loading
        do {
            let page = try await client.fetchBugs()
            bugs = page.items
            bugsCursor = page.nextCursor
            bugsState = .loaded
        } catch {
            bugsState = .failed(humanise(error))
        }
    }

    func loadMoreBugs() async {
        guard let cursor = bugsCursor else { return }
        do {
            let page = try await client.fetchBugs(cursor: cursor)
            bugs.append(contentsOf: page.items)
            bugsCursor = page.nextCursor
        } catch {
            transientError = humanise(error)
        }
    }

    func refreshFeatures() async {
        featuresState = .loading
        do {
            let page = try await client.fetchFeatures()
            features = page.items
            featuresCursor = page.nextCursor
            featuresState = .loaded
        } catch {
            featuresState = .failed(humanise(error))
        }
    }

    func loadMoreFeatures() async {
        guard let cursor = featuresCursor else { return }
        do {
            let page = try await client.fetchFeatures(cursor: cursor)
            features.append(contentsOf: page.items)
            featuresCursor = page.nextCursor
        } catch {
            transientError = humanise(error)
        }
    }

    /// Optimistic vote — updates local state immediately, rolls back on
    /// failure.
    func vote(item: LoopItem, dir: VoteDir?) async {
        let kind = item.kind
        let originalIndex = index(of: item.id, in: kind)
        guard let idx = originalIndex else { return }
        let original = items(for: kind)[idx]

        let optimistic = optimisticUpdate(item: original, newDir: dir)
        update(item: optimistic, kind: kind)

        do {
            let result = try await client.vote(itemId: item.id, dir: dir)
            // Server is the source of truth — re-sync the count.
            let synced = LoopItem(
                id: original.id,
                kind: original.kind,
                status: original.status,
                title: original.title,
                body: original.body,
                whenLabel: original.whenLabel,
                createdAt: original.createdAt,
                votes: result.votes,
                my: result.my,
                replyCount: original.replyCount
            )
            update(item: synced, kind: kind)
        } catch {
            update(item: original, kind: kind)
            transientError = humanise(error)
        }
    }

    /// Submits a new bug or feature.
    func submit(kind: LoopItem.Kind, title: String, body: String) async throws -> LoopSubmissionResult {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        let device = DeviceMeta.capture(sessionId: sessionId)
        let payload = LoopClient.SubmitPayload(
            type: kind.rawValue,
            title: trimmedTitle,
            body: trimmedBody,
            reporter_id: reporterId,
            device_meta: LoopClient.DeviceMetaPayload(
                device: device.device,
                os: device.os,
                appVersion: device.appVersion,
                locale: device.locale,
                network: device.network,
                sessionId: device.sessionId
            )
        )

        let result = try await client.submit(payload: payload)
        // Refresh whichever list changed.
        switch kind {
        case .bug: await refreshBugs()
        case .feature: await refreshFeatures()
        }
        return result
    }

    // MARK: - Helpers

    private func optimisticUpdate(item: LoopItem, newDir: VoteDir?) -> LoopItem {
        let delta: Int
        switch (item.my, newDir) {
        case (nil, .up?): delta = 1
        case (nil, .down?): delta = -1
        case (.up, nil): delta = -1
        case (.down, nil): delta = 1
        case (.up, .down?): delta = -2
        case (.down, .up?): delta = 2
        case (.up, .up?), (.down, .down?), (nil, nil): delta = 0
        default: delta = 0
        }

        return LoopItem(
            id: item.id,
            kind: item.kind,
            status: item.status,
            title: item.title,
            body: item.body,
            whenLabel: item.whenLabel,
            createdAt: item.createdAt,
            votes: item.votes + delta,
            my: newDir,
            replyCount: item.replyCount
        )
    }

    private func items(for kind: LoopItem.Kind) -> [LoopItem] {
        kind == .bug ? bugs : features
    }

    private func index(of id: String, in kind: LoopItem.Kind) -> Int? {
        items(for: kind).firstIndex(where: { $0.id == id })
    }

    private func update(item: LoopItem, kind: LoopItem.Kind) {
        switch kind {
        case .bug:
            if let i = bugs.firstIndex(where: { $0.id == item.id }) { bugs[i] = item }
        case .feature:
            if let i = features.firstIndex(where: { $0.id == item.id }) { features[i] = item }
        }
    }

    private func humanise(_ error: Error) -> String {
        if let err = error as? LoopError {
            switch err {
            case .invalidApiKey: return "Loop SDK isn't configured correctly."
            case .badRequest(let m): return m ?? "That request didn't go through."
            case .notFound: return "Couldn't find that report."
            case .serverError: return "Loop is having trouble — try again in a moment."
            case .transport(.notConnectedToInternet),
                 .transport(.networkConnectionLost): return "You're offline."
            case .transport(.timedOut): return "Loop took too long to respond."
            case .transport(.cancelled): return "Cancelled."
            case .transport: return "Network problem."
            case .decoding: return "Got an unexpected response from Loop."
            case .unknown: return "Something went wrong."
            }
        }
        return error.localizedDescription
    }
}
#endif

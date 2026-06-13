import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Public entry point. Configure once at app launch:
///
///     LoopSDK.start(apiKey: "loop_pk_…")
///
/// Then drop `LoopReporterView()` inside a sheet from your settings screen,
/// or call `LoopSDK.presentReporter(from:)` from a UIKit host.
public enum LoopSDK {

    // MARK: - Public API

    /// Minimal start — uses the built-in auto-tier detector (RevenueCat
    /// today, more sources later). Recommended for most hosts.
    public static func start(
        apiKey: String,
        apiBase: URL = LoopConfiguration.defaultBaseURL
    ) {
        Runtime.shared.configure(.init(apiKey: apiKey, apiBase: apiBase))
    }

    /// Start with a custom tier provider. Pass `nil` to disable tier
    /// reporting entirely (auto-detect is bypassed).
    public static func start(
        apiKey: String,
        apiBase: URL = LoopConfiguration.defaultBaseURL,
        tierProvider: LoopConfiguration.TierProvider?
    ) {
        Runtime.shared.configure(.init(apiKey: apiKey, apiBase: apiBase, tierProvider: tierProvider))
    }

    public static func start(configuration: LoopConfiguration) {
        Runtime.shared.configure(configuration)
    }

    /// Returns the persisted reporter id (Keychain), generating it on first
    /// call. Useful if the host wants to display "your report id" in its
    /// own UI.
    public static func currentReporterId() -> String {
        Runtime.shared.reporterId
    }

    // MARK: - Automatic diagnostics

    /// Records a breadcrumb into the in-memory ring buffer (last 20 kept).
    /// Cheap and non-blocking; safe to call before `start()`. The buffer is
    /// snapshotted into the next `captureDiagnostic` payload.
    ///
    /// - Parameters:
    ///   - message: Short developer-supplied description of what happened.
    ///   - fail: Mark this crumb as a failure step (default `false`).
    public static func breadcrumb(_ message: String, fail: Bool = false) {
        Runtime.shared.breadcrumb(message, fail: fail)
    }

    /// Captures a diagnostic event and sends it to the Loop backend.
    ///
    /// Fire-and-forget: returns immediately, sends asynchronously, never
    /// throws. Repeat captures of the same `name` arriving faster than the
    /// rate-limit interval are dropped. If the send fails (offline / non-2xx)
    /// the payload is buffered on disk and retried on the next capture.
    ///
    /// No-ops silently if `start()` hasn't been called (no configuration to
    /// authenticate with) — it won't crash the host.
    ///
    /// - Parameters:
    ///   - name: Stable fingerprint that groups occurrences of the same issue.
    ///   - severity: `.info`, `.warning`, or `.error` (default `.error`).
    ///   - title: Optional human-readable title.
    ///   - culprit: Optional location/function blamed for the event.
    ///   - context: Optional developer-supplied key/value strings.
    public static func captureDiagnostic(
        _ name: String,
        severity: Severity = .error,
        title: String? = nil,
        culprit: String? = nil,
        context: [String: String] = [:]
    ) {
        Runtime.shared.captureDiagnostic(
            name,
            severity: severity,
            title: title,
            culprit: culprit,
            context: context
        )
    }

    #if canImport(UIKit)
    /// UIKit convenience: presents `LoopReporterView` modally from the
    /// supplied view controller.
    @MainActor
    public static func presentReporter(from presenter: UIViewController) {
        guard #available(iOS 16.0, *) else { return }
        let controller = UIHostingController(rootView: LoopReporterView())
        presenter.present(controller, animated: true)
    }
    #endif

    // MARK: - Internal accessor used by views

    static func runtime() -> Runtime { .shared }

    /// Singleton that owns the parsed configuration, the reporter id, the
    /// per-launch session id, and the lazily-built `LoopClient`.
    final class Runtime: @unchecked Sendable {
        static let shared = Runtime()

        private let lock = NSLock()
        private var configuration: LoopConfiguration?
        private let store = ReporterStore()

        /// Always-available breadcrumb buffer — usable before `start()`.
        private let breadcrumbs = BreadcrumbBuffer()
        /// On-disk offline buffer for diagnostics that fail to POST.
        private let diagnosticsStore = OfflineBufferStore.makeDefault()
        /// Lazily built once configuration is available; rebuilt is
        /// unnecessary because apiKey/base don't change after start().
        private var diagnosticsEngine: DiagnosticsEngine?
        private(set) lazy var sessionId: String = {
            let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return "sess_" + String(raw.prefix(12))
        }()
        private(set) lazy var reporterId: String = store.ensureId()

        func configure(_ configuration: LoopConfiguration) {
            lock.lock()
            self.configuration = configuration
            lock.unlock()
        }

        // MARK: - Diagnostics

        func breadcrumb(_ message: String, fail: Bool) {
            breadcrumbs.record(message: message, fail: fail)
        }

        /// Fire-and-forget. No-ops (apart from breadcrumb retention) when no
        /// configuration is present; otherwise dispatches an async capture
        /// that never throws back to the caller.
        func captureDiagnostic(
            _ name: String,
            severity: Severity,
            title: String?,
            culprit: String?,
            context: [String: String]
        ) {
            guard let engine = diagnosticsEngineIfConfigured() else { return }
            Task.detached {
                try? await engine.capture(
                    name,
                    severity: severity,
                    title: title,
                    culprit: culprit,
                    context: context
                )
            }
        }

        /// Returns the engine, building it on first use, but only if the host
        /// has called `start()`. Returns `nil` (rather than fatal-ing like
        /// `currentConfiguration()`) so diagnostics stay non-fatal.
        private func diagnosticsEngineIfConfigured() -> DiagnosticsEngine? {
            lock.lock(); defer { lock.unlock() }
            guard let configuration else { return nil }
            if let diagnosticsEngine { return diagnosticsEngine }
            let client = LoopClient(
                baseURL: configuration.apiBase,
                apiKey: configuration.apiKey,
                reporterId: reporterId
            )
            let engine = DiagnosticsEngine(
                client: client,
                sessionId: sessionId,
                tierProvider: configuration.tierProvider,
                store: diagnosticsStore,
                buffer: breadcrumbs
            )
            diagnosticsEngine = engine
            return engine
        }

        /// Returns the configured value or fatals if the host forgot to
        /// call `start()` — better to crash loudly during integration than
        /// silently swallow a 401.
        func currentConfiguration() -> LoopConfiguration {
            lock.lock(); defer { lock.unlock() }
            guard let configuration else {
                fatalError("LoopSDK.start(apiKey:) must be called before presenting LoopReporterView")
            }
            return configuration
        }

        #if os(iOS)
        @MainActor
        func makeReporterModel() -> LoopReporterModel {
            let cfg = currentConfiguration()
            let client = LoopClient(
                baseURL: cfg.apiBase,
                apiKey: cfg.apiKey,
                reporterId: reporterId
            )
            return LoopReporterModel(
                client: client,
                reporterId: reporterId,
                sessionId: sessionId,
                tierProvider: cfg.tierProvider
            )
        }
        #endif
    }
}

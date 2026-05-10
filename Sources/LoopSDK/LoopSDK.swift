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

    public static func start(apiKey: String, apiBase: URL = LoopConfiguration.defaultBaseURL) {
        Runtime.shared.configure(.init(apiKey: apiKey, apiBase: apiBase))
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
                sessionId: sessionId
            )
        }
        #endif
    }
}

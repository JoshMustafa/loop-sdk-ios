#if os(iOS)
import SwiftUI

/// Compose screen — "NEW BUG" / "NEW FEATURE". Hand-rolled (no Form) so the
/// look matches the design exactly: chunky kind cards, plain text fields
/// with thin borders, mono caps section labels, dashed auto-capture
/// disclosure.
struct LoopComposeSheet: View {
    @ObservedObject var model: LoopReporterModel
    let onSubmitted: (LoopSubmissionResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var titleFocus: Bool

    @State private var kind: LoopItem.Kind
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var submitting = false
    @State private var errorText: String?

    private var dark: Bool { scheme == .dark }

    init(
        model: LoopReporterModel,
        initialKind: LoopItem.Kind = .bug,
        onSubmitted: @escaping (LoopSubmissionResult) -> Void
    ) {
        self.model = model
        _kind = State(initialValue: initialKind)
        self.onSubmitted = onSubmitted
    }

    private static let minBodyChars = 10
    private static let maxTitleChars = 240

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBodyCount: Int { bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count }
    private var bodyMeetsMinimum: Bool { trimmedBodyCount >= Self.minBodyChars }
    private var titleEmpty: Bool { trimmedTitle.isEmpty }
    private var titleApproachingMax: Bool { title.count >= Self.maxTitleChars - 20 }

    private var canSubmit: Bool {
        !submitting && !titleEmpty && bodyMeetsMinimum
    }

    var body: some View {
        ZStack {
            LoopColors.bg(dark: dark).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        kindCards
                        titleField
                        bodyField
                        autoCaptureDisclosure
                        if let errorText {
                            errorBanner(errorText)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
        .interactiveDismissDisabled(submitting)
        .onAppear { titleFocus = true }
    }

    // MARK: - Header (Cancel · NEW BUG · Send →)

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(LoopFont.sf(15, .regular))
                    .foregroundStyle(LoopColors.textSecondary(dark: dark))
            }
            Spacer()
            MonoCaps(text: "New \(kind == .bug ? "bug" : "feature")", size: 11, kerning: 1.2)
            Spacer()
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 4) {
                    if submitting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(LoopColors.onInk(dark: dark))
                    } else {
                        Text("Send →")
                            .font(LoopFont.sf(13, .semibold))
                            .kerning(-0.15)
                            .foregroundStyle(LoopColors.onInk(dark: dark))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    LoopColors.ink(dark: dark).opacity(canSubmit ? 1 : 0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    // MARK: - Kind picker (two chunky cards)

    private var kindCards: some View {
        HStack(spacing: 10) {
            kindCard(.bug, label: "Bug", sub: "Something is broken")
            kindCard(.feature, label: "Feature", sub: "I'd like this added")
        }
        .padding(.bottom, 22)
    }

    private func kindCard(_ k: LoopItem.Kind, label: String, sub: String) -> some View {
        let active = k == kind
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { kind = k }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(LoopFont.sf(15, .bold))
                    .kerning(-0.3)
                    .foregroundStyle(active
                        ? LoopColors.text(dark: dark)
                        : LoopColors.textSecondary(dark: dark))
                Text(sub)
                    .font(LoopFont.sf(12))
                    .kerning(-0.08)
                    .foregroundStyle(LoopColors.textTertiary(dark: dark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                active ? LoopColors.surf(dark: dark) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        active ? LoopColors.ink(dark: dark) : LoopColors.separator(dark: dark),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title input

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoCaps(text: "Title")
            TextField(
                "",
                text: $title,
                prompt: Text(kind == .bug ? "What broke?" : "What would help?")
                    .foregroundColor(LoopColors.textTertiary(dark: dark))
            )
            .focused($titleFocus)
            .textInputAutocapitalization(.sentences)
            .font(LoopFont.sf(16))
            .foregroundStyle(LoopColors.text(dark: dark))
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(LoopColors.surf(dark: dark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LoopColors.separator(dark: dark), lineWidth: 1)
            )
            // Clamp at the backend's 240 limit so the user can't type past it.
            // (Single-arg onChange form for iOS 16 compatibility.)
            .onChange(of: title) { newValue in
                if newValue.count > Self.maxTitleChars {
                    title = String(newValue.prefix(Self.maxTitleChars))
                }
            }

            titleHint
        }
        .padding(.bottom, 18)
    }

    /// Title helper:
    ///   - Empty → `REQUIRED` in tertiary
    ///   - Filled, well under max → hidden (no clutter)
    ///   - Within 20 chars of the 240 cap → `N / 240 CHARACTERS`, red at the cap
    @ViewBuilder
    private var titleHint: some View {
        if titleEmpty {
            Text("REQUIRED")
                .font(LoopFont.mono(10.5, .medium))
                .kerning(0.6)
                .foregroundStyle(LoopColors.textTertiary(dark: dark))
                .padding(.horizontal, 4)
        } else if titleApproachingMax {
            let atMax = title.count >= Self.maxTitleChars
            Text("\(title.count) / \(Self.maxTitleChars) CHARACTERS")
                .font(LoopFont.mono(10.5, .medium))
                .kerning(0.6)
                .foregroundStyle(atMax
                    ? LoopColors.downvote
                    : LoopColors.statusInProgress)  // amber as a warning
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Body (multi-line)

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoCaps(text: "Description")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $bodyText)
                    .font(LoopFont.sf(15))
                    .foregroundStyle(LoopColors.text(dark: dark))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 140, alignment: .topLeading)

                if bodyText.isEmpty {
                    Text("Steps to reproduce, what you expected, what actually happened…")
                        .font(LoopFont.sf(15))
                        .foregroundStyle(LoopColors.textTertiary(dark: dark))
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(LoopColors.surf(dark: dark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LoopColors.separator(dark: dark), lineWidth: 1)
            )

            bodyHint
        }
        .padding(.bottom, 16)
    }

    /// Live character-count hint shown directly under the description.
    /// Idle (empty) → tertiary text. Started but under → red. Met → green.
    private var bodyHint: some View {
        let count = trimmedBodyCount
        let met = bodyMeetsMinimum
        let untouched = count == 0

        let color: Color = {
            if met { return LoopColors.statusOpen }
            if untouched { return LoopColors.textTertiary(dark: dark) }
            return LoopColors.downvote
        }()

        let label: String = {
            if met { return "✓ \(count) characters" }
            return "\(count) / \(Self.minBodyChars) characters minimum"
        }()

        return Text(label.uppercased())
            .font(LoopFont.mono(10.5, .medium))
            .kerning(0.6)
            .foregroundStyle(color)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }

    // MARK: - Auto-capture disclosure

    private var autoCaptureDisclosure: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(LoopColors.subtleFill(dark: dark))
                Text("i")
                    .font(LoopFont.mono(12, .bold))
                    .foregroundStyle(LoopColors.text(dark: dark))
            }
            .frame(width: 22, height: 22)

            (
                Text("We attach ")
                + Text("device").font(LoopFont.mono(12.5)).foregroundColor(LoopColors.text(dark: dark))
                + Text(", ")
                + Text("os").font(LoopFont.mono(12.5)).foregroundColor(LoopColors.text(dark: dark))
                + Text(", ")
                + Text("app version").font(LoopFont.mono(12.5)).foregroundColor(LoopColors.text(dark: dark))
                + Text(" and a session id automatically. No personal info is sent.")
            )
            .font(LoopFont.sf(12.5))
            .kerning(-0.08)
            .foregroundStyle(LoopColors.textSecondary(dark: dark))
            .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LoopColors.separator(dark: dark), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(LoopFont.sf(13))
            .foregroundStyle(LoopColors.downvote)
            .padding(.top, 16)
    }

    private func submit() async {
        submitting = true
        errorText = nil
        defer { submitting = false }
        do {
            let result = try await model.submit(kind: kind, title: title, body: bodyText)
            onSubmitted(result)
        } catch let error as LoopError {
            errorText = displayMessage(for: error)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func displayMessage(for error: LoopError) -> String {
        switch error {
        case .invalidApiKey: return "Loop SDK isn't configured correctly."
        case .badRequest(let m): return m ?? "That didn't go through. Try again."
        case .notFound: return "Couldn't reach Loop."
        case .serverError: return "Loop is having trouble — try again in a moment."
        case .transport: return "Network problem. Check your connection."
        case .decoding: return "Got an unexpected response from Loop."
        case .unknown: return "Something went wrong."
        }
    }
}
#endif

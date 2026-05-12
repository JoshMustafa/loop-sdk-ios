<div align="center">

<img src="./loop-mark.svg" alt="Loop" width="96" height="96" />

# LoopSDK · iOS

**Drop-in bug + feature reporter for iOS apps.**

Fully native SwiftUI (no WebView), survives offline, sends nothing personal, and adopts iOS 26 Liquid Glass automatically when the device supports it. Three lines of integration in your host app.

</div>

---

## What this repo is

The **iOS SDK** for Loop — a Swift Package the host app embeds to give end-users a built-in "Report a bug or request a feature" surface. Submissions land in the [Loop backend](https://github.com/JoshMustafa/loop_backend); the developer triages them on the [Loop dashboard](https://github.com/JoshMustafa/loop-frontend).

It is one of three repos that make up Loop:

| Repo | What it does |
|---|---|
| [`loop-frontend`](https://github.com/JoshMustafa/loop-frontend) | Nuxt 4 dashboard the dev uses to triage bugs / features |
| [`loop_backend`](https://github.com/JoshMustafa/loop_backend) | Phoenix/Elixir JSON API + Postgres |
| **loop-sdk-ios** (this one) | Swift Package the host app drops in for in-app reporting |

## At a glance

- **Min iOS:** 16.0 (Liquid Glass styling auto-applies on iOS 26+)
- **Swift tools:** 5.9+
- **Distribution:** Swift Package Manager
- **Dependencies:** none — Foundation, SwiftUI, UIKit, Security, Network only.

## Install

In Xcode: *File → Add Package Dependencies…* and paste the repo URL, or
add to your `Package.swift`:

```swift
.package(url: "https://github.com/JoshMustafa/loop-sdk-ios.git", from: "0.1.0"),
```

Then add `"LoopSDK"` to your target's `dependencies`.

## Use it

```swift
import LoopSDK

@main
struct YourApp: App {
    init() {
        // That's the whole config. The backend URL is baked into the SDK.
        LoopSDK.start(apiKey: "loop_pk_yourapp_…")
    }
    // ...
}

// Anywhere in your settings:
struct SettingsScreen: View {
    @State private var presentingLoop = false

    var body: some View {
        Button("Report a bug or request a feature") {
            presentingLoop = true
        }
        .fullScreenCover(isPresented: $presentingLoop) {
            LoopReporterView()
        }
    }
}
```

That's it. Three lines of integration:

1. `LoopSDK.start(apiKey:)` once at launch.
2. `LoopReporterView()` in a `.fullScreenCover` (or `.sheet`, your call).
3. (Optional) `LoopSDK.presentReporter(from:)` if you're driving from UIKit.

### Optional: tag reports with the user's subscription tier

Pass a `tierProvider` closure to `start(...)` and every report submitted
from then on carries the host's current view of the user's tier
(`paid`, `free`, `trial`, `pro`, `founder` — whatever string you want).
The dev sees it as a coloured pill on the dashboard next to the report,
which is handy for prioritising paying customers' bugs.

```swift
LoopSDK.start(apiKey: "loop_pk_yourapp_…") {
    // RevenueCat example — any synchronous source of truth works.
    Purchases.shared.cachedCustomerInfo?
        .entitlements.active.keys.contains("pro") == true ? "paid" : "free"
}
```

Notes:

- The SDK reads the closure **on every submit**, so a downgrade or
  refund picks up automatically — no setter to remember to call.
- The closure runs on the SDK's submit task, so the read must be
  **cheap and non-blocking** (a cached property, not a network round-
  trip).
- Returning `nil`, an empty string, or whitespace is treated as
  "tier unknown" — the report is filed with no tier attached.
- **End-users never see the tier** in the report sheet. It's
  dev-only metadata, only visible on the dashboard.

## What the user sees

- A list of every bug and feature filed against the project, segmented Bugs / Features.
- Vote up/down on each item. Idempotent — voting twice doesn't double-count.
- A "+" button to file a new report. The user picks Bug or Feature, types a title and a few sentences, hits **Send →**.
- Live character-count hints under both fields so they know when the Send button will enable.
- Everything else (device, OS, app version, locale, network type, session id) is captured automatically and attached to the submission.

## What the user *doesn't* see

- No login. No Apple ID. No name, no email, no PII.
- Each device gets a stable anonymous id like `r_8af3bc9e1234`, generated on first launch and pinned in Keychain. The same id is sent on every call so the dev can recognise repeat reporters in the dashboard without knowing who they are.

## Privacy disclosure (paste into your privacy policy)

> This app uses Loop, a self-hosted bug and feature reporting tool, to let
> you report issues. When you submit a report, Loop attaches your device
> model, OS version, app version, locale, network type, and a per-launch
> session id. Loop generates a random per-device id stored in your
> device's Keychain so the developer can recognise repeat reports from
> the same device. **No personal information is collected.**

## App Store review

LoopSDK ships its own `PrivacyInfo.xcprivacy` declaring no tracking, no
data collection beyond what the user explicitly types, and the one
`UserDefaults` reason code (`CA92.1`) covering the Apple-required
"app's own functionality" use case. You don't need to update your own
privacy nutrition labels for the SDK.

There is no `ATTrackingManager` prompt anywhere. Loop never tracks across
apps or websites.

## Architecture

```
LoopSDK
├── LoopClient      — actor, URLSession + async/await
├── ReporterStore   — Keychain-backed r_xxx… id
├── DeviceMeta      — model, OS, app, locale, network, session
└── UI/             — SwiftUI views, Liquid Glass on iOS 26
    ├── LoopReporterView    (public)
    ├── LoopComposeSheet
    ├── LoopSubmittedView
    ├── LoopItemRow
    └── LoopVoteControl
```

Backend contract (`/api/ingest/*`):

| Method | Path | Headers | Purpose |
|---|---|---|---|
| GET  | `/api/ingest/project` | Bearer + `X-Loop-Reporter-Id` | Project metadata for branding |
| GET  | `/api/ingest/bugs?cursor=&limit=` | same | Paginated bug list (archived items are excluded server-side) |
| GET  | `/api/ingest/features?cursor=&limit=` | same | Paginated feature list |
| POST | `/api/ingest/items/:LP-####/vote` | same; body `{dir}` | Cast / clear vote |
| POST | `/api/ingest/submissions` | Bearer | File a new report |

## Local dev against the Phoenix backend

See [`Examples/README.md`](./Examples/README.md) for a step-by-step walkthrough that runs the example host app against `http://localhost:4000` (or your Mac's LAN IP from an iPhone).

## Tests

```sh
swift test    # cross-platform pieces (Client, ReporterStore, DeviceMeta)
xcodebuild -scheme LoopSDK -destination 'generic/platform=iOS Simulator' build
```

UI is exercised manually via the example app; full UI test automation is out of scope for v1.

## License

Proprietary — © 2026 Josh Mustafa. All rights reserved. See [LICENSE](./LICENSE).

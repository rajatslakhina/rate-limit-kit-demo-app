# RateLimitKit Demo

A small SwiftUI app that puts [RateLimitKit](https://github.com/rajatslakhina/rate-limit-kit)'s client-side rate limiter on screen: send single requests, fire a burst of three concurrent requests sharing the same coalescing key, and watch a simulated flaky backend throttle traffic once it exceeds a small threshold — then drain the local queue once tokens free back up.

## Why this matters

A backoff-and-coalescing engine is only convincing once you can watch it degrade gracefully instead of hammering a struggling server. This app makes `RateLimitKit`'s three headline behaviors — token-bucket throttling, request coalescing, bounded local queuing — visible and interactive in under a minute, against a backend that genuinely returns 429s once you push it, not a canned success path.

## How it's built

- `Demo.xcodeproj` is a real Xcode project, **not** a Swift Package executable target — running an SPM executable target as an app via Xcode's package-run convenience has a known, previously-reproduced crash (`__BKSHIDEvent__BUNDLE_IDENTIFIER_FOR_CURRENT_PROCESS_IS_NIL__`); see the library README's design-decisions section and the earlier `feed-cache-lab` postmortem in this portfolio for the root cause.
- It depends on `RateLimitKit` via an `XCRemoteSwiftPackageReference` pointed at the library's real GitHub URL (branch `main`), exactly like any external consumer of the package would — not a local/relative path.
- `Demo/DemoApp.swift` wires up a `SimulatedFlakyAPI` (a tiny `RateLimitNetworkClient` that lives only in this demo app, standing in for a real backend that starts 429-ing after 2 calls to the same key within a 3-second window) and a `RateLimitedExecutor` configured with a small token bucket, then drives it from a single SwiftUI view.

## How to run it

1. Clone this repo.
2. Open `Demo.xcodeproj` in Xcode.
3. Let Xcode resolve the remote `RateLimitKit` package dependency (automatic on first open; if not, File → Packages → Resolve Package Versions).
4. Select the `Demo` scheme and any iOS Simulator, then Build & Run.
5. Tap "Send single request" a few times to see the token bucket drain and refill; tap "Fire burst of 3 (same key)" to see coalescing collapse concurrent duplicate requests; tap "Drain queued requests" once the log shows a `⏳ queued` entry to see the bounded local queue resolve.

## Verification status — stated honestly

This repo was built and pushed during a live, user-present session (not an unattended scheduled run), so a real Simulator run was genuinely attempted rather than skipped by default. A `request_access` call for Xcode/Simulator/Finder succeeded and was approved. But the very first screenshot taken afterward, before any click, showed Xcode already had **real, unrelated work open and actively running**: a project named `HomeDepotApp` / `THDConsumer` on branch `APP5-339-reintroduce-newerlicensebase-firebase-key`, mid-debug-session with live console log output, plus a Finder window open on the user's personal `Downloads` folder. Per this pipeline's own safety rule, driving Xcode further in that state risked interfering with someone else's real, in-progress work on the same machine — so the live-run attempt was stopped immediately, before any click, and this repo falls back to rigorous manual/static review instead.

What was done in its place: a scripted brace/paren/bracket balance check on `Demo.xcodeproj/project.pbxproj` (balanced) and on `Demo/DemoApp.swift` (balanced), a scripted scan for unguarded force-unwraps in the demo source (none found), and a full manual read-through against the same crash classes the library itself is tested against — bounds-checked collection access (`ForEach` over a bounded, sliced log array), no retain cycles (the view model is a plain `@Observable @MainActor` class held by `@State`), and an explicit empty-state row for the activity log instead of silently rendering nothing.

The honest next step, for a human running this on the actual Mac once the unrelated Xcode session is clear: open `Demo.xcodeproj`, run it on a Simulator, and — if it behaves as designed — add real screenshots to `Demo/Screenshots/` and embed them here.

## Library

Depends on [`rate-limit-kit`](https://github.com/rajatslakhina/rate-limit-kit) — token-bucket rate limiting, request coalescing, server-`Retry-After`-aware exponential backoff, and a bounded local queue.

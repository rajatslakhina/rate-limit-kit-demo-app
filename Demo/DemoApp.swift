import SwiftUI
import RateLimitKit

/// A simulated backend that returns 429s once traffic to a given key
/// exceeds a small threshold, then recovers — so the demo can show real
/// throttle/backoff/coalesce behavior against something that actually
/// misbehaves, instead of a canned success path.
final class SimulatedFlakyAPI: RateLimitNetworkClient, @unchecked Sendable {

    private let lock = NSLock()
    private var recentCallTimestamps: [String: [Date]] = [:]
    private let windowSeconds: TimeInterval = 3
    private let maxCallsPerWindow = 2

    func send(_ request: BackpressureRequest) async -> NetworkOutcome {
        lock.lock()
        let now = Date()
        var timestamps = recentCallTimestamps[request.coalescingKey, default: []]
        timestamps.removeAll { now.timeIntervalSince($0) > windowSeconds }
        timestamps.append(now)
        recentCallTimestamps[request.coalescingKey] = timestamps
        let countInWindow = timestamps.count
        lock.unlock()

        if countInWindow > maxCallsPerWindow {
            return .rateLimited(retryAfter: 1.0)
        }
        return .success("ok:\(request.payload)")
    }
}

@MainActor
@Observable
final class DemoViewModel {

    private let executor: RateLimitedExecutor
    private(set) var log: [String] = []
    private(set) var queuedCount = 0
    private var requestCounter = 0

    init() {
        self.executor = RateLimitedExecutor(
            tokenBucket: TokenBucket(capacity: 3, refillRatePerSecond: 0.5),
            queue: LocalRequestQueue(capacity: 5, overflowPolicy: .dropOldest),
            network: SimulatedFlakyAPI(),
            backoff: BackoffPolicy(maxAttempts: 3, baseDelay: 0.3, maxDelay: 2.0)
        )
    }

    func sendRequest(key: String) async {
        requestCounter += 1
        let n = requestCounter
        let request = BackpressureRequest(coalescingKey: key, payload: "req-\(n)")
        log.insert("→ sending \(request.payload) (key: \(key))", at: 0)

        let result = await executor.execute(request)
        switch result {
        case .success(let body):
            log.insert("✅ \(body)", at: 0)
        case .queued:
            log.insert("⏳ req-\(n) queued (tokens unavailable)", at: 0)
        case .droppedByOverflow:
            log.insert("🗑️ req-\(n) dropped — local queue full", at: 0)
        case .exhausted(let error):
            log.insert("❌ req-\(n) exhausted: \(error)", at: 0)
        }
        queuedCount = await executor.queuedCount()
    }

    func fireBurst(key: String) async {
        // Fires 3 requests concurrently with the same key to demonstrate
        // coalescing collapsing them toward a single underlying call.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { await self.sendRequest(key: key) }
            }
        }
    }

    func drainQueue() async {
        let results = await executor.drainQueued()
        if results.isEmpty {
            log.insert("· drain: nothing ready yet", at: 0)
        } else {
            log.insert("🔄 drained \(results.count) queued request(s)", at: 0)
        }
        queuedCount = await executor.queuedCount()
    }
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Local queue") {
                    Text("\(viewModel.queuedCount) request(s) waiting on tokens")
                        .foregroundStyle(viewModel.queuedCount > 0 ? .orange : .secondary)
                }

                Section("Actions") {
                    Button("Send single request") {
                        Task { await viewModel.sendRequest(key: "profile") }
                    }
                    Button("Fire burst of 3 (same key — watch coalescing)") {
                        Task { await viewModel.fireBurst(key: "burst-key") }
                    }
                    Button("Drain queued requests") {
                        Task { await viewModel.drainQueue() }
                    }
                    .bold()
                }

                Section("Activity log") {
                    if viewModel.log.isEmpty {
                        Text("No activity yet")
                            .foregroundStyle(.secondary)
                    } else {
                        // Bounded so a long demo session doesn't render an
                        // unbounded, ever-growing list.
                        ForEach(Array(viewModel.log.prefix(30).enumerated()), id: \.offset) { _, entry in
                            Text(entry).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("RateLimitKit Demo")
        }
    }
}

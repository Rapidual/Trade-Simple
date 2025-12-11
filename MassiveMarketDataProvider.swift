import Foundation

final class MassiveMarketDataProvider: MarketDataProvider {
    private(set) var isConnected: Bool = false

    // Events
    private let eventsStream: AsyncStream<MarketEvent>
    private let eventsContinuation: AsyncStream<MarketEvent>.Continuation

    // State
    private var apiKey: String = ""
    private var quoteSymbols: [String] = []
    private var aggregateSymbols: [String] = []
    private var pollingTask: Task<Void, Never>?

    init() {
        var cont: AsyncStream<MarketEvent>.Continuation!
        self.eventsStream = AsyncStream<MarketEvent> { c in cont = c }
        self.eventsContinuation = cont
    }

    var events: AsyncStream<MarketEvent> {
        eventsStream
    }

    func connect(apiKey: String) async throws {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "MassiveMarketDataProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Massive API key"])
        }
        self.apiKey = apiKey
        self.isConnected = true
        eventsContinuation.yield(.status(message: "Connected to Massive"))
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
        eventsContinuation.yield(.status(message: "Disconnected from Massive"))
    }

    func subscribe(trades: [String], quotes: [String], aggregates: [String]) async throws {
        // Massive-only: ignore trades unless you have an endpoint for them.
        self.quoteSymbols = Array(Set(quotes.map { $0.uppercased() })).sorted()
        self.aggregateSymbols = Array(Set(aggregates.map { $0.uppercased() })).sorted()

        // Stop prior loop
        pollingTask?.cancel()
        pollingTask = nil

        // Start a placeholder loop so UI shows “Streaming updates”.
        if !quoteSymbols.isEmpty || !aggregateSymbols.isEmpty {
            let parts = [
                quoteSymbols.isEmpty ? nil : "quotes: \(quoteSymbols.joined(separator: ","))",
                aggregateSymbols.isEmpty ? nil : "aggregates: \(aggregateSymbols.joined(separator: ","))"
            ].compactMap { $0 }.joined(separator: " | ")
            if !parts.isEmpty {
                eventsContinuation.yield(.status(message: "Subscribed -> \(parts)"))
            }

            pollingTask = Task { [weak self] in
                guard let self else { return }
                // TODO: Replace with real Massive polling/streaming for quotes/aggregates.
                while !Task.isCancelled && self.isConnected {
                    try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    // Keep the status alive; no-op tick.
                    self.eventsContinuation.yield(.status(message: "Massive heartbeat (\(Date()))"))
                }
            }
        }
    }
}

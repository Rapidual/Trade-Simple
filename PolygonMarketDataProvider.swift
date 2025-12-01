import Foundation

final class PolygonMarketDataProvider: MarketDataProvider {
    private(set) var isConnected: Bool = false

    // Backing stream/continuation for events
    private let eventsStream: AsyncStream<MarketEvent>
    private let eventsContinuation: AsyncStream<MarketEvent>.Continuation

    init() {
        var cont: AsyncStream<MarketEvent>.Continuation!
        self.eventsStream = AsyncStream<MarketEvent> { continuation in
            cont = continuation
        }
        self.eventsContinuation = cont
    }

    var events: AsyncStream<MarketEvent> {
        eventsStream
    }

    func connect(apiKey: String) async throws {
        // Simulate async connect
        try await Task.sleep(nanoseconds: 200_000_000)
        isConnected = true
        eventsContinuation.yield(.status(message: "Connected to provider"))
    }

    func disconnect() {
        isConnected = false
        eventsContinuation.yield(.status(message: "Disconnected from provider"))
    }

    func subscribe(trades: [String], quotes: [String], aggregates: [String]) async throws {
        // Simulate subscription acknowledgement
        let parts = [
            trades.isEmpty ? nil : "trades: \(trades.joined(separator: ","))",
            quotes.isEmpty ? nil : "quotes: \(quotes.joined(separator: ","))",
            aggregates.isEmpty ? nil : "aggregates: \(aggregates.joined(separator: ","))"
        ].compactMap { $0 }.joined(separator: " | ")

        if !parts.isEmpty {
            eventsContinuation.yield(.status(message: "Subscribed -> \(parts)"))
        }
        // No real market data emitted in this stub.
    }
}

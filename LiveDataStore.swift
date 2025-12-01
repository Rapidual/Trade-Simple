import Foundation
import Observation

@Observable
final class LiveDataStore {
    private let provider: MarketDataProvider

    // Observable state
    var isConnected: Bool = false
    var lastTrades: [String: Trade] = [:]
    var lastQuotes: [String: Quote] = [:]
    var lastStatusMessage: String?
    var lastAggregates: [String: Candle] = [:]

    private var eventsTask: Task<Void, Never>?

    // Momentum state per symbol
    private struct MomentumState {
        var ema: Double?
        var lastMid: Double?
        var lastDeltaSigns: [Int] = [] // recent signs (+1/-1/0), capped to 3
    }
    private var momentumMap: [String: MomentumState] = [:]
    private let emaAlpha: Double = 0.2 // short EMA for “momentum” feel

    init(provider: MarketDataProvider) {
        self.provider = provider
        self.isConnected = provider.isConnected
    }

    deinit {
        disconnect()
    }

    func connectAndSubscribe(apiKey: String, tickers: [String], wantTrades: Bool, wantQuotes: Bool, wantAggregates: Bool) async {
        guard !apiKey.isEmpty else { return }
        do {
            try await provider.connect(apiKey: apiKey)
            await MainActor.run {
                self.isConnected = provider.isConnected
                self.lastStatusMessage = "Connected"
            }

            let trades = wantTrades ? tickers : []
            let quotes = wantQuotes ? tickers : []
            let aggregates = wantAggregates ? tickers : []

            try await provider.subscribe(trades: trades, quotes: quotes, aggregates: aggregates)

            // Start listening to events
            eventsTask?.cancel()
            eventsTask = Task { [weak self] in
                guard let self else { return }
                for await event in provider.events {
                    await MainActor.run {
                        self.handle(event)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.lastStatusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        eventsTask?.cancel()
        eventsTask = nil
        provider.disconnect()
        // Reflect state on main actor synchronously (no new Task)
        if Thread.isMainThread {
            self.isConnected = provider.isConnected
            self.lastStatusMessage = "Disconnected"
        } else {
            MainActor.assumeIsolated {
                self.isConnected = provider.isConnected
                self.lastStatusMessage = "Disconnected"
            }
        }
    }

    @MainActor
    private func handle(_ event: MarketEvent) {
        switch event {
        case .status(let message):
            lastStatusMessage = message
        case .trade(let trade):
            lastTrades[trade.symbol] = trade
            updateMomentum(symbol: trade.symbol)
        case .quote(let quote):
            lastQuotes[quote.symbol] = quote
            updateMomentum(symbol: quote.symbol)
        case .aggregate(let candle):
            lastAggregates[candle.symbol] = candle
        }
    }

    // MARK: - Momentum

    @MainActor
    private func midPrice(symbol: String) -> Double? {
        if let t = lastTrades[symbol]?.price { return t }
        if let q = lastQuotes[symbol] {
            return (q.bidPrice + q.askPrice) / 2.0
        }
        return nil
    }

    @MainActor
    private func updateMomentum(symbol: String) {
        guard let mid = midPrice(symbol: symbol) else { return }
        var state = momentumMap[symbol] ?? MomentumState()

        // EMA update
        if let ema = state.ema {
            state.ema = ema + emaAlpha * (mid - ema)
        } else {
            state.ema = mid
        }

        // Delta sign tracking
        if let last = state.lastMid {
            let delta = mid - last
            let sign: Int = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
            state.lastDeltaSigns.append(sign)
            if state.lastDeltaSigns.count > 3 { state.lastDeltaSigns.removeFirst() }
        }
        state.lastMid = mid

        momentumMap[symbol] = state
    }

    enum MomentumSignal {
        case bullish
        case bearish
        case neutral
    }

    @MainActor
    func momentum(for symbol: String) -> MomentumSignal {
        guard let state = momentumMap[symbol], let ema = state.ema, let mid = state.lastMid else {
            return .neutral
        }
        let pctDiff = (mid - ema) / ema
        let lastTwo = Array(state.lastDeltaSigns.suffix(2))
        let upStreak = lastTwo.filter { $0 > 0 }.count >= 2
        let downStreak = lastTwo.filter { $0 < 0 }.count >= 2
        let threshold = 0.001 // 0.10%

        if pctDiff > threshold && upStreak {
            return .bullish
        } else if pctDiff < -threshold && downStreak {
            return .bearish
        } else {
            return .neutral
        }
    }
}

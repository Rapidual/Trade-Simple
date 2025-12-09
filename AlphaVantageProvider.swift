import Foundation

// Alpha Vantage REST-based provider that polls quotes and optional intraday aggregates.
final class AlphaVantageProvider: MarketDataProvider {
    private(set) var isConnected: Bool = false

    // AsyncStream plumbing
    private let stream: AsyncStream<MarketEvent>
    private let continuation: AsyncStream<MarketEvent>.Continuation

    // Config/state
    private var apiKey: String = ""
    private var quoteSymbols: [String] = []
    private var aggregateSymbols: [String] = []
    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval
    private let intradayInterval: String // "1min", "5min", "15min", etc.

    init(pollingInterval: TimeInterval = 15, intradayInterval: String = "5min") {
        var cont: AsyncStream<MarketEvent>.Continuation!
        self.stream = AsyncStream<MarketEvent> { c in cont = c }
        self.continuation = cont
        self.pollingInterval = pollingInterval
        self.intradayInterval = intradayInterval
    }

    var events: AsyncStream<MarketEvent> {
        stream
    }

    func connect(apiKey: String) async throws {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AlphaVantageProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }
        self.apiKey = apiKey
        self.isConnected = true
        continuation.yield(.status(message: "Connected to Alpha Vantage"))
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
        continuation.yield(.status(message: "Disconnected from Alpha Vantage"))
    }

    func subscribe(trades: [String], quotes: [String], aggregates: [String]) async throws {
        // Alpha Vantage free tier has no trade-by-trade stream; ignore trades.
        self.quoteSymbols = Array(Set(quotes)).sorted()
        self.aggregateSymbols = Array(Set(aggregates)).sorted()

        // Start polling loop
        pollingTask?.cancel()
        if !quoteSymbols.isEmpty || !aggregateSymbols.isEmpty {
            pollingTask = Task { [weak self] in
                await self?.pollingLoop()
            }
            // Use self.* to avoid shadowing/ambiguity and ensure correct values are used
            continuation.yield(.status(message: "Subscribed -> quotes: \(self.quoteSymbols.joined(separator: ",")) | aggregates: \(self.aggregateSymbols.joined(separator: ","))"))
        }
    }

    // MARK: - Polling

    private func pollingLoop() async {
        var quoteIndex = 0
        var aggIndex = 0

        while !Task.isCancelled && isConnected {
            let start = Date()

            if !quoteSymbols.isEmpty {
                let sym = quoteSymbols[quoteIndex % quoteSymbols.count]
                await fetchQuote(symbol: sym)
                quoteIndex += 1
            }

            if !aggregateSymbols.isEmpty {
                let sym = aggregateSymbols[aggIndex % aggregateSymbols.count]
                await fetchIntraday(symbol: sym, interval: intradayInterval)
                aggIndex += 1
            }

            let elapsed = Date().timeIntervalSince(start)
            let wait = max(0.5, pollingInterval - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    // MARK: - API Calls

    // Fetch a quote; fall back to intraday close if GLOBAL_QUOTE is empty (common for SPXL/SPXS).
    private func fetchQuote(symbol: String) async {
        guard let url = URL(string:
            "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=\(symbol)&apikey=\(apiKey)"
        ) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let quote = try parseGlobalQuote(symbol: symbol, data: data) {
                continuation.yield(.quote(quote))
                return
            }

            // Fallback: try latest intraday close as a proxy for last price
            if let fallbackPrice = try await fetchLatestIntradayPrice(symbol: symbol, interval: intradayInterval) {
                let bid = fallbackPrice * 0.999
                let ask = fallbackPrice * 1.001
                let q = Quote(symbol: symbol, bidPrice: bid, bidSize: 0, askPrice: ask, askSize: 0, timestamp: Date())
                continuation.yield(.quote(q))
            } else {
                continuation.yield(.status(message: "No data for \(symbol) (GLOBAL_QUOTE empty, intraday fallback unavailable)"))
            }
        } catch {
            continuation.yield(.status(message: "Quote error for \(symbol): \(error.localizedDescription)"))
        }
    }

    // Helper: fetch latest intraday close as a Double for fallback quoting.
    private func fetchLatestIntradayPrice(symbol: String, interval: String) async throws -> Double? {
        guard let url = URL(string:
            "https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol=\(symbol)&interval=\(interval)&outputsize=compact&apikey=\(apiKey)"
        ) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = "Time Series (\(interval))"
        guard
            let series = root?[key] as? [String: Any],
            let latestKey = series.keys.sorted().last,
            let bar = series[latestKey] as? [String: Any],
            let closeStr = bar["4. close"] as? String,
            let close = Double(closeStr)
        else {
            return nil
        }
        return close
    }

    private func fetchIntraday(symbol: String, interval: String) async {
        guard let url = URL(string:
            "https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol=\(symbol)&interval=\(interval)&outputsize=compact&apikey=\(apiKey)"
        ) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let candle = try parseLatestIntraday(symbol: symbol, interval: interval, data: data) {
                continuation.yield(.aggregate(candle))
            }
        } catch {
            // FIX: removed extra closing parenthesis
            continuation.yield(.status(message: "Aggregate error for \(symbol): \(error.localizedDescription)"))
        }
    }

    // MARK: - Parsing

    private func parseGlobalQuote(symbol: String, data: Data) throws -> Quote? {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let global = json["Global Quote"] as? [String: Any],
            let priceStr = global["05. price"] as? String,
            let price = Double(priceStr)
        else { return nil }

        // Alpha Vantage doesn't provide bid/ask in this endpoint; synthesize around last price.
        let bid = price * 0.999
        let ask = price * 1.001

        return Quote(
            symbol: symbol,
            bidPrice: bid,
            bidSize: 0,
            askPrice: ask,
            askSize: 0,
            timestamp: Date()
        )
    }

    private func parseLatestIntraday(symbol: String, interval: String, data: Data) throws -> Candle? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = "Time Series (\(interval))"
        guard
            let series = root?[key] as? [String: Any],
            let latestKey = series.keys.sorted().last,
            let bar = series[latestKey] as? [String: Any],
            let o = (bar["1. open"] as? String).flatMap(Double.init),
            let h = (bar["2. high"] as? String).flatMap(Double.init),
            let l = (bar["3. low"] as? String).flatMap(Double.init),
            let c = (bar["4. close"] as? String).flatMap(Double.init),
            let vStr = bar["5. volume"] as? String,
            let v = Int(vStr)
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let start = formatter.date(from: latestKey) ?? Date()
        let end = start.addingTimeInterval(intervalSeconds(interval))

        return Candle(
            symbol: symbol,
            open: o,
            high: h,
            low: l,
            close: c,
            volume: v,
            vwap: nil,
            start: start,
            end: end
        )
    }

    private func intervalSeconds(_ interval: String) -> TimeInterval {
        switch interval {
        case "1min": return 60
        case "5min": return 5 * 60
        case "15min": return 15 * 60
        case "30min": return 30 * 60
        case "60min": return 60 * 60
        default: return 5 * 60
        }
    }
}

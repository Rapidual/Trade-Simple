import Foundation

struct Trade: Sendable, Equatable {
    let symbol: String
    let price: Double
    let size: Int
    let timestamp: Date
}

struct Quote: Sendable, Equatable {
    let symbol: String
    let bidPrice: Double
    let bidSize: Int
    let askPrice: Double
    let askSize: Int
    let timestamp: Date
}

struct Candle: Sendable, Equatable {
    let symbol: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
    let vwap: Double?
    let start: Date
    let end: Date
}

enum MarketEvent: Sendable {
    case status(message: String)
    case trade(Trade)
    case quote(Quote)
    case aggregate(Candle)
}

enum Symbols {
    static let defaults = ["SPY", "SPXL", "SPXS"]
}

extension Date {
    static func fromMillis(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }
}


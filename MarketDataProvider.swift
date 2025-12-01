import Foundation

protocol MarketDataProvider: AnyObject {
    var isConnected: Bool { get }
    var events: AsyncStream<MarketEvent> { get }

    func connect(apiKey: String) async throws
    func disconnect()

    func subscribe(trades: [String], quotes: [String], aggregates: [String]) async throws
}


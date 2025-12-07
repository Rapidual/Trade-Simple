import Foundation

struct MassiveDividendsResponse: Decodable {
    let results: [MassiveDividend]?
}

struct MassiveDividend: Decodable, Identifiable {
    // Adjust these fields to match Massive’s exact schema if different.
    // Common fields for dividends: ticker/symbol, exDate, paymentDate, recordDate, amount, frequency.
    var id: String { "\(symbol)-\(exDate ?? "unknown")-\(amount ?? 0)" }

    let symbol: String
    let exDate: String?
    let paymentDate: String?
    let recordDate: String?
    let declarationDate: String?
    let amount: Double?
    let frequency: String?
    let currency: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case symbol = "ticker"
        case exDate = "ex_date"
        case paymentDate = "pay_date"
        case recordDate = "record_date"
        case declarationDate = "declaration_date"
        case amount
        case frequency
        case currency
        case notes
    }
}

enum DividendsServiceError: Error {
    case badURL
    case badResponse
}

actor DividendsService {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func fetchDividends(symbols: [String]) async throws -> [MassiveDividend] {
        guard var comps = URLComponents(string: "https://api.massive.com/v3/reference/dividends") else {
            throw DividendsServiceError.badURL
        }
        comps.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey)
        ]
        guard let url = comps.url else { throw DividendsServiceError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DividendsServiceError.badResponse
        }

        let decoder = JSONDecoder()
        let root = try decoder.decode(MassiveDividendsResponse.self, from: data)
        let all = root.results ?? []

        if symbols.isEmpty {
            return all
        } else {
            let set = Set(symbols.map { $0.uppercased() })
            return all.filter { set.contains($0.symbol.uppercased()) }
        }
    }
}


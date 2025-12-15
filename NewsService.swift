import Foundation

struct NewsArticle: Identifiable, Decodable {
    struct Source: Decodable {
        let name: String?
    }

    let id = UUID()
    let title: String
    let description: String?
    let url: String
    let source: Source?
    let publishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case title, description, url, source, publishedAt
    }
}

private struct NewsAPIResponse: Decodable {
    let status: String
    let totalResults: Int?
    let articles: [NewsArticle]
}

enum NewsService {
    static func topHeadlines(query: String?, apiKey: String, pageSize: Int = 5) async throws -> [NewsArticle] {
        var components = URLComponents(string: "https://newsapi.org/v2/top-headlines")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let q = query, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        } else {
            items.append(URLQueryItem(name: "country", value: "us"))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "NewsService", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to load news (\(code))."])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let api = try decoder.decode(NewsAPIResponse.self, from: data)
        return Array(api.articles.prefix(pageSize))
    }

    static func sampleArticles() -> [NewsArticle] {
        return [
            NewsArticle(title: "Tesla rallies as markets open", description: "Shares of Tesla rise on strong delivery numbers.", url: "https://example.com/tesla-rally", source: .init(name: "Sample News"), publishedAt: Date()),
            NewsArticle(title: "SpaceX schedules next Starship test", description: "The company targets next month for a major launch.", url: "https://example.com/spacex-starship", source: .init(name: "Sample News"), publishedAt: Date().addingTimeInterval(-3600)),
            NewsArticle(title: "Elon Musk teases new AI features", description: "Musk hints at upcoming AI initiatives across companies.", url: "https://example.com/elon-ai", source: .init(name: "Sample News"), publishedAt: Date().addingTimeInterval(-7200)),
            NewsArticle(title: "EV sector sees increased demand", description: "Analysts point to incentives and infrastructure growth.", url: "https://example.com/ev-demand", source: .init(name: "Sample News"), publishedAt: Date().addingTimeInterval(-10800)),
            NewsArticle(title: "Market overview: Tech leads gains", description: "Tech stocks outperform broader market indices.", url: "https://example.com/market-overview", source: .init(name: "Sample News"), publishedAt: Date().addingTimeInterval(-14400))
        ]
    }
}

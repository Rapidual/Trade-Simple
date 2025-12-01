//
//  ContentView.swift
//  Trade Simple
//
//  Created by Thomas Peters on 11/30/25.
//

import SwiftUI
import Observation

struct ContentView: View {
    @Environment(LiveDataStore.self) private var store
    @AppStorage("polygonApiKey") private var polygonApiKey: String = ""
    @AppStorage("watchlistSymbols") private var watchlistSymbolsRaw: String = Symbols.defaults.joined(separator: ",")

    @State private var isAddingSymbol: Bool = false
    @State private var newSymbolText: String = ""
    @State private var isConnecting: Bool = false

    private var watchlist: [String] {
        watchlistSymbolsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    private func updateWatchlist(_ list: [String]) {
        let unique = Array(LinkedHashSet(list.map { $0.uppercased() }))
        watchlistSymbolsRaw = unique.joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerStatusBar

                if polygonApiKey.isEmpty && !store.isConnected {
                    apiKeyBanner
                }

                if isAddingSymbol {
                    addSymbolBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if watchlist.isEmpty {
                    emptyWatchlistView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(watchlist.enumerated()), id: \.element) { index, sym in
                            WatchlistRow(
                                symbol: sym,
                                trade: store.lastTrades[sym],
                                quote: store.lastQuotes[sym],
                                momentum: store.momentum(for: sym)
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    let updated = watchlist.filter { $0 != sym }
                                    updateWatchlist(updated)
                                    if store.isConnected {
                                        Task { await resubscribe() }
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Placeholder for future SymbolDetailView
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                            // Insert a visual separator after SPXS if the next symbol exists (e.g., TSLA).
                            if sym == "SPXS" && index < watchlist.count - 1 {
                                Divider()
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await resubscribe()
                    }
                }

                if let status = store.lastStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .animation(.easeInOut, value: store.isConnected)
            .animation(.easeInOut, value: isAddingSymbol)
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            isAddingSymbol.toggle()
                            if isAddingSymbol {
                                newSymbolText = ""
                            }
                        }
                    } label: {
                        Image(systemName: isAddingSymbol ? "xmark" : "plus")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                if !polygonApiKey.isEmpty && !store.isConnected {
                    await connectIfKeyPresent()
                }
            }
        }
    }

    private var headerStatusBar: some View {
        HStack(spacing: 12) {
            LiveDot(isOn: store.isConnected)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.isConnected ? "Live" : "Offline")
                    .font(.headline)
                    .foregroundStyle(store.isConnected ? .green : .secondary)
                    .accessibilityLabel(store.isConnected ? "Connected" : "Disconnected")
                Text(subtitleStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    if store.isConnected {
                        store.disconnect()
                    } else {
                        await connectIfKeyPresent()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isConnected ? "bolt.slash.fill" : "bolt.fill")
                    Text(store.isConnected ? "Disconnect" : (isConnecting ? "Connecting…" : "Connect"))
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isConnected ? .red : .blue)
            .disabled(isConnecting && !store.isConnected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var apiKeyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("API key required")
                    .font(.subheadline).bold()
                Text("Open Settings to enter your Polygon API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Text("Enter")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var addSymbolBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Add symbol (e.g., AAPL)", text: $newSymbolText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit {
                    addSymbol()
                }

            Button {
                addSymbol()
            } label: {
                Text("Add").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(newSymbolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var emptyWatchlistView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No symbols yet")
                .font(.headline)
            Text("Tap + to add tickers to your watchlist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !polygonApiKey.isEmpty && !store.isConnected {
                Button {
                    Task { await connectIfKeyPresent() }
                } label: {
                    Label("Connect now", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var subtitleStatus: String {
        if store.isConnected {
            return "Streaming updates"
        } else if polygonApiKey.isEmpty {
            return "Enter API key to connect"
        } else {
            return "Tap Connect to start"
        }
    }

    private func addSymbol() {
        let sym = newSymbolText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !sym.isEmpty else { return }

        var current = watchlist
        if !current.contains(sym) {
            current.append(sym)
            updateWatchlist(current)
            withAnimation { newSymbolText = "" }
            if store.isConnected {
                Task { await resubscribe() }
            }
        }
    }

    private func connectIfKeyPresent() async {
        guard !polygonApiKey.isEmpty else { return }
        isConnecting = true
        defer { isConnecting = false }
        await store.connectAndSubscribe(
            apiKey: polygonApiKey,
            tickers: watchlist,
            wantTrades: true,
            wantQuotes: true,
            wantAggregates: true
        )
    }

    private func resubscribe() async {
        guard store.isConnected else { return }
        await store.connectAndSubscribe(
            apiKey: polygonApiKey,
            tickers: watchlist,
            wantTrades: true,
            wantQuotes: true,
            wantAggregates: true
        )
    }
}

private struct WatchlistRow: View {
    let symbol: String
    let trade: Trade?
    let quote: Quote?
    let momentum: LiveDataStore.MomentumSignal

    private var lastPrice: Double? {
        if let t = trade?.price { return t }
        if let q = quote {
            return (q.bidPrice + q.askPrice) / 2.0
        }
        return nil
    }

    private var change: Double? {
        nil
    }

    private var changePct: Double? {
        guard let p = lastPrice, let ch = change, p != 0 else { return nil }
        return (ch / (p - ch)) * 100.0
    }

    private var priceColor: Color {
        if let ch = change {
            return ch >= 0 ? .green : .red
        }
        return .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left: symbol + momentum indicator + bid/ask
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(symbol)
                        .font(.headline)
                    momentumIcon
                        .accessibilityLabel(momentumA11y)
                }
                bidAskView
            }

            Spacer(minLength: 8)

            // Right: last price + change
            VStack(alignment: .trailing, spacing: 4) {
                if let p = lastPrice {
                    Text(formatPrice(p))
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(priceColor)
                        .contentTransition(.numericText(value: p))
                } else {
                    Text("--")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let ch = change, let pct = changePct {
                    Text("\(formatSigned(ch))  (\(formatSigned(pct))%)")
                        .font(.caption)
                        .foregroundStyle(ch >= 0 ? .green : .red)
                } else {
                    Text(" ")
                        .font(.caption)
                        .hidden()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // FIX: type-erase to AnyView so all branches have the same underlying type
    private var momentumIcon: some View {
        switch momentum {
        case .bullish:
            return AnyView(
                Image(systemName: "triangle.fill")
                    .foregroundStyle(.green)
            )
        case .bearish:
            return AnyView(
                Image(systemName: "triangle.fill")
                    .foregroundStyle(.red)
                    .rotationEffect(.degrees(180))
            )
        case .neutral:
            return AnyView(
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            )
        }
    }

    private var bidAskView: some View {
        Group {
            if let q = quote {
                Text("Bid \(formatPrice(q.bidPrice)) x \(formatSize(q.bidSize))  |  Ask \(formatPrice(q.askPrice)) x \(formatSize(q.askSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Bid --  |  Ask --")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityText: Text {
        var pieces: [String] = [symbol]
        if let p = lastPrice {
            pieces.append("last \(formatPrice(p))")
        }
        if let q = quote {
            pieces.append("bid \(formatPrice(q.bidPrice)) size \(q.bidSize)")
            pieces.append("ask \(formatPrice(q.askPrice)) size \(q.askSize)")
        }
        return Text(pieces.joined(separator: ", "))
    }

    private var momentumA11y: String {
        switch momentum {
        case .bullish: return "Bullish momentum"
        case .bearish: return "Bearish momentum"
        case .neutral: return "Neutral momentum"
        }
    }

    private func formatPrice(_ p: Double) -> String {
        String(format: "%.2f", p)
    }

    private func formatSigned(_ v: Double) -> String {
        if v > 0 { return String(format: "+%.2f", v) }
        return String(format: "%.2f", v)
    }

    private func formatSize(_ s: Int) -> String {
        if s >= 1_000_000 { return String(format: "%.1fM", Double(s) / 1_000_000) }
        if s >= 1_000 { return String(format: "%.1fk", Double(s) / 1_000) }
        return "\(s)"
    }
}

private struct LiveDot: View {
    let isOn: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.green.opacity(0.25) : Color.red.opacity(0.2))
                .frame(width: 18, height: 18)
                .scaleEffect(animate && isOn ? 1.2 : 1.0)
            Circle()
                .fill(isOn ? Color.green : Color.red)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}

// Helper to maintain insertion order while removing duplicates
private struct LinkedHashSet<Element: Hashable>: Sequence {
    private var set: Set<Element> = []
    private var array: [Element] = []

    init<S: Sequence>(_ seq: S) where S.Element == Element {
        for e in seq {
            if !set.contains(e) {
                set.insert(e)
                array.append(e)
            }
        }
    }

    func makeIterator() -> IndexingIterator<[Element]> {
        array.makeIterator()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // Seed a store with sample data
        let store = LiveDataStore(provider: AlphaVantageProvider())
        store.isConnected = true
        store.lastQuotes = [
            "SPY": Quote(symbol: "SPY", bidPrice: 453.12, bidSize: 100, askPrice: 453.20, askSize: 200, timestamp: Date()),
            "AAPL": Quote(symbol: "AAPL", bidPrice: 192.34, bidSize: 50, askPrice: 192.40, askSize: 75, timestamp: Date())
        ]
        store.lastTrades = [
            "SPY": Trade(symbol: "SPY", price: 453.18, size: 10, timestamp: Date()),
            "AAPL": Trade(symbol: "AAPL", price: 192.38, size: 5, timestamp: Date())
        ]
        // Seed momentum
        Task { @MainActor in
            _ = store.momentum(for: "SPY")
        }

        return Group {
            ContentView()
                .environment(store)
                .previewDisplayName("Connected")

            ContentView()
                .environment(store)
                .previewDisplayName("Dark")
                .preferredColorScheme(.dark)

            // Offline + empty watchlist
            ContentView()
                .environment({
                    let s = LiveDataStore(provider: AlphaVantageProvider())
                    s.isConnected = false
                    return s
                }())
                .previewDisplayName("Offline")
        }
    }
}

//
//  Trade_SimpleApp.swift
//  Trade Simple
//
//  Created by Thomas Peters on 11/30/25.
//

import SwiftUI
import Observation

@main
struct Trade_SimpleApp: App {
    @State private var store: LiveDataStore = {
        #if targetEnvironment(simulator)
        // In Simulator, use a provider that does not require an API key.
        return LiveDataStore(provider: YahooFinanceProvider())
        #else
        return LiveDataStore(provider: MassiveMarketDataProvider())
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

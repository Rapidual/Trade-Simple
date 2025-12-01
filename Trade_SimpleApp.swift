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
    @State private var store = LiveDataStore(provider: AlphaVantageProvider())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

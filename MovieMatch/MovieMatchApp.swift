//
//  MovieMatchApp.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

@main
struct MovieMatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(MovieMatchContainer.shared)
    }
}

enum MovieMatchContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: StoredMovie.self, StoredTaste.self, StoredHide.self, StoredEvent.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }()
}

//
//  LibraryMigration.swift
//  MovieMatch
//

import Foundation
import SwiftData

/// Одноразовый переход на шкалу 1...100 и журнал событий (MATH_SPEC.md, раздел 14).
enum LibraryMigration {
    static let versionKey = "movieMatch.tasteModelVersion"
    static let currentVersion = 2

    nonisolated static func scaled(_ old: Int) -> Int {
        min(100, max(1, old * 10))
    }

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        migrate(in: context)
        defaults.set(currentVersion, forKey: versionKey)
    }

    static func migrate(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<StoredEvent>())) ?? 0
        let movies = ((try? context.fetch(FetchDescriptor<StoredMovie>())) ?? [])
            .sorted { $0.savedAt < $1.savedAt }
        var sequence = 0
        for movie in movies {
            if let rating = movie.userRating {
                movie.userRating = scaled(rating)
            }
            if LibraryStatus(rawValue: movie.statusRaw) == nil {
                movie.status = .idea
            }
            guard existing == 0 else { continue }
            sequence += 1
            let kind: TasteEventKind
            let at: Date
            if movie.userRating != nil {
                kind = .rate
                at = movie.watchedAt ?? movie.savedAt
                if movie.status == .idea { movie.status = .watched }
            } else if movie.status == .idea {
                kind = .planLater
                at = movie.savedAt
            } else {
                kind = .watchedUnrated
                at = movie.watchedAt ?? movie.savedAt
                movie.status = .unrated
            }
            context.insert(StoredEvent(TasteEvent(
                kind: kind,
                tmdbID: movie.tmdbID,
                value: movie.userRating,
                at: at,
                sequence: sequence,
                axes: movie.axes,
                genreIDs: movie.genreIDs
            )))
        }
        try? context.save()
    }
}

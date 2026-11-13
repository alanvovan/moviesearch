//
//  LibraryStore.swift
//  MovieMatch
//

import Foundation
import SwiftData

/// Каждое действие пишет событие в журнал; профиль вкуса всегда пересчитывается из журнала целиком.
enum LibraryStore {
    static func taste(in context: ModelContext) -> TasteState {
        fetchTaste(in: context)?.state ?? .empty
    }

    /// Запуск приложения: миграция старой шкалы и пересчёт (затухание зависит от текущей даты).
    static func prepare(in context: ModelContext) {
        LibraryMigration.runIfNeeded(in: context)
        rebuild(in: context)
        persist(context)
    }

    static func resetTaste(deleteLibrary: Bool, in context: ModelContext) {
        if deleteLibrary {
            try? context.delete(model: StoredMovie.self)
            try? context.delete(model: StoredHide.self)
            try? context.delete(model: StoredEvent.self)
        } else {
            append(TasteEvent(kind: .reset, tmdbID: 0, at: .now, sequence: 0), in: context)
        }
        rebuild(in: context)
        persist(context)
    }

    static func unhide(_ id: Int, in context: ModelContext) {
        if let hide = fetchHide(id, in: context) {
            context.delete(hide)
            persist(context)
        }
    }

    static func movie(_ id: Int, in context: ModelContext) -> StoredMovie? {
        fetchMovie(id, in: context)
    }

    // MARK: Лента

    static func planLater(_ movie: TMDBMovie, in context: ModelContext) {
        if let existing = fetchMovie(movie.id, in: context), existing.status.isWatched { return }
        let row = upsert(movie, status: .idea, in: context)
        record(.planLater, row: row, in: context)
    }

    static func notInterested(_ movie: TMDBMovie, in context: ModelContext) {
        let percent = TasteEngine.match(user: taste(in: context), film: movie.features).percent
        if let row = fetchMovie(movie.id, in: context), !row.status.isWatched {
            context.delete(row)
        }
        if let hide = fetchHide(movie.id, in: context) {
            hide.title = movie.title
            hide.posterPath = movie.posterPath ?? movie.backdropPath
            hide.hiddenAt = .now
            hide.matchAtHide = percent
        } else {
            context.insert(
                StoredHide(
                    tmdbID: movie.id,
                    title: movie.title,
                    posterPath: movie.posterPath ?? movie.backdropPath,
                    hiddenAt: .now,
                    matchAtHide: percent
                )
            )
        }
        append(event(.notInterested, id: movie.id, axes: movie.tasteAxes, genres: movie.genreIDs), in: context)
        rebuild(in: context)
        persist(context)
    }

    /// «Просмотрено» из ленты или из поиска «+»: с оценкой или без.
    static func markWatched(_ movie: TMDBMovie, rating: Int?, review: String, in context: ModelContext) {
        let existing = fetchMovie(movie.id, in: context)
        let finalRating = rating ?? existing?.userRating
        let row = upsert(movie, status: finalRating == nil ? .unrated : .watched, in: context)
        row.reviewText = review.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(rating: rating, previous: existing?.userRating, wasWatched: existing?.status.isWatched ?? false, row: row, in: context)
    }

    // MARK: Библиотека

    /// Оценка из библиотеки: новая оценка заменяет прежнюю, без оценки фильм переходит в «Просмотрено».
    static func updateStored(id: Int, rating: Int?, review: String, in context: ModelContext) {
        guard let row = fetchMovie(id, in: context) else { return }
        let previous = row.userRating
        let wasWatched = row.status.isWatched
        row.reviewText = review.trimmingCharacters(in: .whitespacesAndNewlines)
        if rating != nil {
            row.status = .watched
        } else if !wasWatched {
            row.status = .unrated
        }
        if row.watchedAt == nil { row.watchedAt = .now }
        apply(rating: rating, previous: previous, wasWatched: wasWatched, row: row, in: context)
    }

    static func removeMovie(_ id: Int, in context: ModelContext) {
        guard let row = fetchMovie(id, in: context) else { return }
        context.delete(row)
        append(TasteEvent(kind: .removeMovie, tmdbID: id, at: .now, sequence: 0), in: context)
        rebuild(in: context)
        persist(context)
    }

    // MARK: Онбординг

    static func loveOnboarding(_ movie: TMDBMovie, in context: ModelContext) {
        if fetchMovie(movie.id, in: context) != nil { return }
        let row = upsert(movie, status: .unrated, in: context)
        record(.onboardingLove, row: row, in: context)
    }

    static func rateOnboarding(_ movie: TMDBMovie, score: Int, in context: ModelContext) {
        if fetchMovie(movie.id, in: context)?.userRating != nil { return }
        let row = upsert(movie, status: .watched, in: context)
        row.userRating = clampRating(score)
        record(.onboardingRate, row: row, value: row.userRating, in: context)
    }

    // MARK: Пересчёт

    static func events(in context: ModelContext) -> [TasteEvent] {
        let rows = (try? context.fetch(FetchDescriptor<StoredEvent>())) ?? []
        return rows.compactMap(\.event)
    }

    static func rebuild(in context: ModelContext, now: Date = .now) {
        write(TasteEngine.rebuild(events: events(in: context), now: now), in: context)
    }

    static func append(_ event: TasteEvent, in context: ModelContext) {
        var event = event
        event.sequence = nextSequence(in: context)
        context.insert(StoredEvent(event))
    }

    // MARK: Внутреннее

    private static func apply(rating: Int?, previous: Int?, wasWatched: Bool, row: StoredMovie, in context: ModelContext) {
        if let rating {
            let value = clampRating(rating)
            row.userRating = value
            if value != previous {
                record(.rate, row: row, value: value, in: context)
                return
            }
        } else if !wasWatched {
            record(.watchedUnrated, row: row, in: context)
            return
        }
        persist(context)
    }

    private static func record(_ kind: TasteEventKind, row: StoredMovie, value: Int? = nil, in context: ModelContext) {
        append(event(kind, id: row.tmdbID, value: value, axes: row.axes, genres: row.genreIDs), in: context)
        rebuild(in: context)
        persist(context)
    }

    private static func event(_ kind: TasteEventKind, id: Int, value: Int? = nil, axes: [TasteAxis: Double], genres: [Int]) -> TasteEvent {
        TasteEvent(kind: kind, tmdbID: id, value: value, at: .now, sequence: 0, axes: axes, genreIDs: genres)
    }

    private static func clampRating(_ value: Int) -> Int {
        min(100, max(1, value))
    }

    @discardableResult
    private static func upsert(_ movie: TMDBMovie, status: LibraryStatus, in context: ModelContext) -> StoredMovie {
        unhideSilently(movie.id, in: context)
        let row: StoredMovie
        if let existing = fetchMovie(movie.id, in: context) {
            row = existing
            row.title = movie.title
            row.overview = movie.overview
            row.posterPath = movie.posterPath ?? existing.posterPath
            row.backdropPath = movie.backdropPath ?? existing.backdropPath
            row.releaseYear = movie.releaseYear ?? existing.releaseYear
            row.runtime = movie.runtime ?? existing.runtime
            row.genreIDs = movie.genreIDs
            row.genreNames = movie.genreNames
            if !movie.keywords.isEmpty { row.keywords = movie.keywords }
            row.youtubeKey = movie.youtubeKey ?? existing.youtubeKey
            row.axes = movie.tasteAxes
        } else {
            row = StoredMovie(
                tmdbID: movie.id,
                title: movie.title,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                releaseYear: movie.releaseYear,
                runtime: movie.runtime,
                genreIDs: movie.genreIDs,
                genreNames: movie.genreNames,
                keywords: movie.keywords,
                youtubeKey: movie.youtubeKey,
                axes: movie.tasteAxes,
                status: status,
                userRating: nil,
                reviewText: "",
                savedAt: .now,
                watchedAt: nil,
                superlikedAt: nil
            )
            context.insert(row)
        }
        row.status = status
        if status.isWatched, row.watchedAt == nil {
            row.watchedAt = .now
        }
        return row
    }

    private static func unhideSilently(_ id: Int, in context: ModelContext) {
        if let hide = fetchHide(id, in: context) {
            context.delete(hide)
        }
    }

    private static func nextSequence(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<StoredEvent>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first?.sequence) ?? 0) + 1
    }

    private static func write(_ state: TasteState, in context: ModelContext) {
        if let row = fetchTaste(in: context) {
            row.state = state
        } else {
            let row = StoredTaste(blob: Data())
            row.state = state
            context.insert(row)
        }
    }

    private static func fetchMovie(_ id: Int, in context: ModelContext) -> StoredMovie? {
        let identifier = id
        var descriptor = FetchDescriptor<StoredMovie>(predicate: #Predicate { $0.tmdbID == identifier })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchHide(_ id: Int, in context: ModelContext) -> StoredHide? {
        let identifier = id
        var descriptor = FetchDescriptor<StoredHide>(predicate: #Predicate { $0.tmdbID == identifier })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchTaste(in context: ModelContext) -> StoredTaste? {
        var descriptor = FetchDescriptor<StoredTaste>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func persist(_ context: ModelContext) {
        try? context.save()
    }
}

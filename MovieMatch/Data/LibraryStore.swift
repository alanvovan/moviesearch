//
//  LibraryStore.swift
//  MovieMatch
//

import Foundation
import SwiftData

enum LibraryStore {
    static func taste(in context: ModelContext) -> TasteState {
        fetchTaste(in: context)?.state ?? .empty
    }

    static func resetTaste(in context: ModelContext) {
        save(.empty, in: context)
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

    static func like(_ movie: TMDBMovie, isSuper: Bool, in context: ModelContext) {
        if fetchMovie(movie.id, in: context)?.status == .watched { return }
        let existing = fetchMovie(movie.id, in: context)
        let keepSuper = isSuper || existing?.status == .superlike || existing?.superlikedAt != nil
        commit(
            movie,
            status: keepSuper ? .superlike : .idea,
            rating: existing?.userRating,
            review: existing?.reviewText ?? "",
            signal: isSuper ? .superlike : .like,
            markSuperlike: keepSuper,
            in: context
        )
    }

    static func dislike(_ movie: TMDBMovie, in context: ModelContext) {
        let axes = movie.tasteAxes
        let percent = TasteEngine.match(user: taste(in: context), film: axes).percent
        if let row = fetchMovie(movie.id, in: context), row.status != .watched {
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
        var state = taste(in: context)
        state = TasteEngine.apply(signal: .dislike, film: axes, to: state)
        save(state, in: context)
    }

    static func rateOnboarding(_ movie: TMDBMovie, score: Int, in context: ModelContext) {
        if fetchMovie(movie.id, in: context)?.userRating != nil { return }
        commit(
            movie,
            status: .watched,
            rating: score,
            review: "",
            signal: .rating(score),
            markSuperlike: false,
            in: context
        )
    }

    static func saveFromSearch(
        _ movie: TMDBMovie,
        rating: Int?,
        review: String,
        in context: ModelContext
    ) {
        let existing = fetchMovie(movie.id, in: context)
        if let rating {
            let signal: TasteSignal? = existing?.userRating == rating ? nil : .rating(rating)
            commit(
                movie,
                status: .watched,
                rating: rating,
                review: review,
                signal: signal,
                markSuperlike: existing?.superlikedAt != nil,
                in: context
            )
        } else if existing?.userRating != nil {
            commit(
                movie,
                status: existing?.status == .watched ? .watched : (existing?.status ?? .unrated),
                rating: existing?.userRating,
                review: review,
                signal: nil,
                markSuperlike: existing?.superlikedAt != nil,
                in: context
            )
        } else {
            commit(
                movie,
                status: .unrated,
                rating: nil,
                review: review,
                signal: nil,
                markSuperlike: existing?.superlikedAt != nil,
                in: context
            )
        }
    }

    static func updateStored(
        id: Int,
        rating: Int?,
        review: String,
        watched: Bool,
        in context: ModelContext
    ) {
        guard let row = fetchMovie(id, in: context) else { return }
        let previous = row.userRating
        row.reviewText = review.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rating {
            row.userRating = rating
            if watched || row.status == .idea || row.status == .superlike || row.status == .unrated {
                row.status = .watched
            }
            if row.watchedAt == nil, row.status == .watched {
                row.watchedAt = .now
            }
            if previous != rating {
                var state = taste(in: context)
                state = TasteEngine.apply(signal: .rating(rating), film: row.axes, to: state)
                write(state, in: context)
            }
        }
        persist(context)
    }

    static func snapshot(of movies: [StoredMovie]) -> LibrarySnapshot {
        LibrarySnapshot(items: movies.map {
            LibrarySnapshot.Item(
                genreIDs: $0.genreIDs,
                userRating: $0.userRating,
                reviewText: $0.reviewText,
                status: $0.status,
                superlikedAt: $0.superlikedAt
            )
        })
    }

    private static func commit(
        _ movie: TMDBMovie,
        status: LibraryStatus,
        rating: Int?,
        review: String,
        signal: TasteSignal?,
        markSuperlike: Bool,
        in context: ModelContext
    ) {
        unhide(movie.id, in: context)
        let review = review.trimmingCharacters(in: .whitespacesAndNewlines)
        let row: StoredMovie
        if let existing = fetchMovie(movie.id, in: context) {
            row = existing
            row.title = movie.title
            row.overview = movie.overview
            row.posterPath = movie.posterPath
            row.backdropPath = movie.backdropPath
            row.releaseYear = movie.releaseYear
            row.runtime = movie.runtime
            row.genreIDs = movie.genreIDs
            row.genreNames = movie.genreNames
            row.keywords = movie.keywords
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
                userRating: rating,
                reviewText: review,
                savedAt: .now,
                watchedAt: status == .watched ? .now : nil,
                superlikedAt: markSuperlike ? .now : nil
            )
            context.insert(row)
        }
        row.status = status
        row.userRating = rating
        row.reviewText = review
        if status == .watched, row.watchedAt == nil {
            row.watchedAt = .now
        }
        if markSuperlike, row.superlikedAt == nil {
            row.superlikedAt = .now
        }
        if let signal {
            var state = taste(in: context)
            state = TasteEngine.apply(signal: signal, film: row.axes, to: state)
            write(state, in: context)
        }
        persist(context)
    }

    private static func save(_ state: TasteState, in context: ModelContext) {
        write(state, in: context)
        persist(context)
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

    private static func persist(_ context: ModelContext) {
        try? context.save()
    }
}

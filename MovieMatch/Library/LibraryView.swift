//
//  LibraryView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredMovie.savedAt, order: .reverse) private var movies: [StoredMovie]
    @Query private var tastes: [StoredTaste]
    @State private var filter = LibraryFilter()
    @State private var showFilters = false
    @State private var showAdd = false
    @State private var ratingRequest: RatingRequest?

    private var taste: TasteState { tastes.first?.state ?? .empty }
    private var shown: [StoredMovie] {
        movies.filter { filter.includes($0, matchPercent: percent($0)) }
    }
    private var ideas: [StoredMovie] {
        shown
            .filter { $0.status == .idea || $0.status == .superlike }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .superlike }
                return lhs.savedAt > rhs.savedAt
            }
    }
    private var watched: [StoredMovie] {
        shown.filter { $0.status == .watched }.sorted { ($0.watchedAt ?? $0.savedAt) > ($1.watchedAt ?? $1.savedAt) }
    }
    private var unrated: [StoredMovie] {
        shown.filter { $0.status == .unrated }
    }
    private var awardCount: Int {
        AwardEvaluator.unlocked(in: LibraryStore.snapshot(of: movies)).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if movies.isEmpty {
                    MovieMatchMessage(
                        title: "Библиотека пустая",
                        subtitle: "Лайк в ленте кладёт фильм в идеи."
                    )
                } else if shown.isEmpty {
                    MovieMatchMessage(title: "Ничего не нашлось")
                } else {
                    list
                }
            }
            .movieMatchScreen()
            .navigationTitle("Библиотека")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("награды: \(awardCount) из \(AwardID.allCases.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Фильтры")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить") { showAdd = true }
                }
            }
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(filter: $filter, years: years, genres: genres)
            }
            .sheet(isPresented: $showAdd) { AddMovieSheet() }
            .sheet(item: $ratingRequest) { request in
                RatingSheet(
                    title: request.title,
                    requiresRating: request.requiresRating,
                    allowsUnrated: request.allowsUnrated,
                    rating: request.rating,
                    review: request.review
                ) { rating, review in
                    LibraryStore.updateStored(
                        id: request.id,
                        rating: rating,
                        review: review,
                        watched: request.markWatched,
                        in: modelContext
                    )
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                section("Идеи для просмотра", items: ideas, watchedAction: true)
                section("Просмотренные", items: watched, watchedAction: false)
                section("Без оценки", items: unrated, watchedAction: false)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [StoredMovie], watchedAction: Bool) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(items, id: \.tmdbID) { movie in
                LibraryEntryRow(
                    movie: movie,
                    matchPercent: percent(movie),
                    showsWatched: watchedAction
                ) {
                    ratingRequest = RatingRequest(
                        id: movie.tmdbID,
                        title: movie.title,
                        requiresRating: watchedAction || movie.status == .watched,
                        allowsUnrated: movie.status == .unrated,
                        rating: movie.userRating,
                        review: movie.reviewText,
                        markWatched: watchedAction || movie.status != .unrated
                    )
                }
            }
        }
    }

    private func percent(_ movie: StoredMovie) -> Int {
        TasteEngine.match(user: taste, film: movie.axes).percent
    }

    private var years: [Int] {
        Array(Set(movies.compactMap(\.releaseYear))).sorted()
    }

    private var genres: [(id: Int, name: String)] {
        var names: [Int: String] = [:]
        for movie in movies {
            for (index, id) in movie.genreIDs.enumerated() where names[id] == nil {
                let name = index < movie.genreNames.count ? movie.genreNames[index] : TMDBGenreNames.names[id]
                names[id] = name ?? "жанр \(id)"
            }
        }
        return names.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }
}

struct IdeasSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredMovie.savedAt, order: .reverse) private var movies: [StoredMovie]
    @Query private var tastes: [StoredTaste]
    @State private var ratingRequest: RatingRequest?

    private var taste: TasteState { tastes.first?.state ?? .empty }
    private var ideas: [StoredMovie] {
        movies
            .filter { $0.status == .idea || $0.status == .superlike }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .superlike }
                return lhs.savedAt > rhs.savedAt
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ideas.isEmpty {
                    MovieMatchMessage(title: "Идей пока нет", subtitle: "Лайк и суперлайк из ленты появятся здесь.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(ideas, id: \.tmdbID) { movie in
                                LibraryEntryRow(
                                    movie: movie,
                                    matchPercent: TasteEngine.match(user: taste, film: movie.axes).percent,
                                    showsWatched: true
                                ) {
                                    ratingRequest = RatingRequest(
                                        id: movie.tmdbID,
                                        title: movie.title,
                                        requiresRating: true,
                                        allowsUnrated: false,
                                        rating: movie.userRating,
                                        review: movie.reviewText,
                                        markWatched: true
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .movieMatchScreen()
            .navigationTitle("Идеи для просмотра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(item: $ratingRequest) { request in
                RatingSheet(
                    title: request.title,
                    requiresRating: true,
                    allowsUnrated: false,
                    rating: request.rating,
                    review: request.review
                ) { rating, review in
                    guard let rating else { return }
                    LibraryStore.updateStored(
                        id: request.id,
                        rating: rating,
                        review: review,
                        watched: true,
                        in: modelContext
                    )
                }
            }
        }
        .presentationBackground(MovieMatchPalette.background)
        .preferredColorScheme(.dark)
    }
}

struct LibraryEntryRow: View {
    var movie: StoredMovie
    var matchPercent: Int
    var showsWatched: Bool
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(path: movie.posterPath ?? movie.backdropPath, size: "w342")
                .frame(width: 54, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(movie.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if movie.status == .superlike || movie.superlikedAt != nil && movie.status != .idea {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.white)
                            .accessibilityLabel("Суперлайк")
                    }
                }
                HStack(spacing: 8) {
                    if let year = movie.releaseYear {
                        Text(String(year))
                    }
                    if let rating = movie.userRating {
                        Text("оценка \(rating)")
                    }
                    Text("\(matchPercent)%")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                if movie.hasReview {
                    Text(movie.reviewText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
                if let date = movie.watchedAt, movie.status == .watched {
                    Text(russianDate(date))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                if showsWatched {
                    Button("Посмотрел", action: onOpen)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .buttonStyle(MovieMatchCapsuleStyle())
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct RatingRequest: Identifiable {
    var id: Int
    var title: String
    var requiresRating: Bool
    var allowsUnrated: Bool
    var rating: Int?
    var review: String
    var markWatched: Bool
}

//
//  LibraryView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

private enum LibrarySegment: String, CaseIterable, Identifiable {
    case watched = "Просмотрено"
    case planned = "Запланировано"

    var id: String { rawValue }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredMovie.savedAt, order: .reverse) private var movies: [StoredMovie]
    @Query private var tastes: [StoredTaste]
    @State private var segment: LibrarySegment = .watched
    @State private var filter = LibraryFilter()
    @State private var showFilters = false
    @State private var showAdd = false
    @State private var ratingRequest: RatingRequest?
    @State private var detailID: Int?

    private var taste: TasteState { tastes.first?.state ?? .empty }

    private var items: [StoredMovie] {
        let visible = movies.filter { filter.includes($0, matchPercent: match($0).percent) }
        switch segment {
        case .watched:
            return visible
                .filter { $0.status.isWatched }
                .sorted { ($0.watchedAt ?? $0.savedAt) > ($1.watchedAt ?? $1.savedAt) }
        case .planned:
            return visible.filter { $0.status == .idea }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                content
            }
            .movieMatchScreen()
            .navigationTitle("Библиотека")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить")
                }
            }
            .navigationDestination(item: $detailID) { id in
                LibraryDetailView(id: id)
            }
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(filter: $filter, years: years, genres: genres)
            }
            .sheet(isPresented: $showAdd) { AddMovieSheet() }
            .sheet(item: $ratingRequest) { request in
                RatingSheet(
                    title: request.title,
                    requiresRating: !request.allowsUnrated,
                    allowsUnrated: request.allowsUnrated,
                    rating: request.rating,
                    review: request.review
                ) { rating, review in
                    LibraryStore.updateStored(id: request.id, rating: rating, review: review, in: modelContext)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Раздел", selection: $segment) {
                ForEach(LibrarySegment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            MovieMatchSearchField(prompt: "Поиск по библиотеке", text: $filter.text) {
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: filter.hasRefinements ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(MovieMatchPalette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.hasRefinements ? "Фильтры, включены" : "Фильтры")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if movies.isEmpty {
            MovieMatchMessage(
                title: "Библиотека пустая",
                subtitle: "Свайп вправо в Поиске добавляет фильм в «Запланировано»."
            )
            .frame(maxHeight: .infinity)
        } else if items.isEmpty {
            MovieMatchMessage(title: filter.isActive ? "Ничего не нашлось" : "Здесь пока пусто")
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(items, id: \.tmdbID) { movie in
                    LibraryEntryRow(
                        movie: movie,
                        match: match(movie),
                        onOpen: { detailID = movie.tmdbID },
                        onRate: { requestRating(movie) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(MovieMatchPalette.separator)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
                    .swipeActions {
                        Button(role: .destructive) {
                            LibraryStore.removeMovie(movie.tmdbID, in: modelContext)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func requestRating(_ movie: StoredMovie) {
        ratingRequest = RatingRequest(
            id: movie.tmdbID,
            title: movie.title,
            allowsUnrated: movie.status == .idea,
            rating: movie.userRating,
            review: movie.reviewText
        )
    }

    private func match(_ movie: StoredMovie) -> MatchScore {
        TasteEngine.match(user: taste, film: movie.features)
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

struct LibraryEntryRow: View {
    var movie: StoredMovie
    var match: MatchScore
    var onOpen: () -> Void
    var onRate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterImage(path: movie.posterPath ?? movie.backdropPath, size: "w342")
                .frame(width: 54, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title)
                    .font(.headline)
                    .foregroundStyle(MovieMatchPalette.textPrimary)
                    .lineLimit(2)
                if let meta = metaLine {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                }
                if let rating = movie.userRating {
                    ratingChip(rating)
                }
                if movie.hasReview {
                    Text(movie.reviewText)
                        .font(.caption)
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RatingRing(
                value: match.percent,
                tint: RatingRing.matchTint(match.percent),
                size: 40,
                isConfident: match.isConfident,
                accessibilityTitle: "Совместимость"
            )
            if movie.userRating == nil {
                Button(action: onRate) {
                    Image(systemName: "eye")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MovieMatchPalette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(MovieMatchPalette.surface, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(movie.status == .idea ? "Просмотрено" : "Оценить")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAction(named: "Открыть описание", onOpen)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let year = movie.releaseYear { parts.append(String(year)) }
        if movie.status == .unrated { parts.append("без оценки") }
        if let date = movie.watchedAt, movie.status.isWatched { parts.append(russianDate(date)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func ratingChip(_ rating: Int) -> some View {
        let mood = RatingMood(rating: rating)
        return Button(action: onRate) {
            HStack(spacing: 5) {
                Image(systemName: mood.symbol)
                    .foregroundStyle(mood.tint)
                Text("\(rating)")
                    .monospacedDigit()
                    .foregroundStyle(MovieMatchPalette.textPrimary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(MovieMatchPalette.surface, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Оценка \(rating), \(mood.title). Изменить")
    }
}

/// Описание фильма из библиотеки: тот же экран, что в Поиске; недостающие поля догружаются из TMDB.
private struct LibraryDetailView: View {
    var id: Int
    @Query private var tastes: [StoredTaste]
    @Query private var rows: [StoredMovie]

    init(id: Int) {
        self.id = id
        _rows = Query(filter: #Predicate<StoredMovie> { $0.tmdbID == id })
    }

    var body: some View {
        Group {
            if let row = rows.first {
                ScrollView {
                    MovieDetailView(movie: row.tmdbMovie, taste: tastes.first?.state ?? .empty)
                }
                .ignoresSafeArea(edges: .top)
            } else {
                MovieMatchMessage(title: "Фильм удалён из библиотеки")
            }
        }
        .movieMatchScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension StoredMovie {
    var tmdbMovie: TMDBMovie {
        TMDBMovie(
            id: tmdbID,
            title: title,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseYear: releaseYear,
            genreIDs: genreIDs,
            genreNames: genreNames,
            keywords: keywords,
            runtime: runtime,
            youtubeKey: youtubeKey,
            enriched: false
        )
    }
}

private struct RatingRequest: Identifiable {
    var id: Int
    var title: String
    var allowsUnrated: Bool
    var rating: Int?
    var review: String
}

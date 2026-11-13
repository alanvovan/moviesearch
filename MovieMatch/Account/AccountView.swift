//
//  AccountView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var movies: [StoredMovie]
    @Query private var tastes: [StoredTaste]
    @State private var confirmReset = false

    private var taste: TasteState { tastes.first?.state ?? .empty }
    private var watchedCount: Int { movies.filter { $0.status.isWatched }.count }
    private var reviewCount: Int { movies.filter { $0.userRating != nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    stats
                    spider
                    settings
                }
                .padding(20)
            }
            .movieMatchScreen()
            .navigationTitle("Аккаунт")
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .hidden:
                    HiddenMoviesView()
                }
            }
            .confirmationDialog(
                "Сбросить вкус",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Удалить библиотеку и обнулить диаграмму", role: .destructive) {
                    LibraryStore.resetTaste(deleteLibrary: true, in: modelContext)
                }
                Button("Сохранить библиотеку и обнулить диаграмму", role: .destructive) {
                    LibraryStore.resetTaste(deleteLibrary: false, in: modelContext)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Удаление стирает фильмы, оценки и отзывы. Если сохранить библиотеку, фильмы останутся, а диаграмму будут менять только новые отзывы.")
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            metric(value: watchedCount, title: "Просмотрено", symbol: "eye.fill")
            metric(value: reviewCount, title: "Оставлено отзывов", symbol: "star.bubble.fill")
        }
    }

    private func metric(value: Int, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MovieMatchPalette.textSecondary)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MovieMatchPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MovieMatchPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var spider: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Любимые жанры")
                .font(.title3.weight(.semibold))
            GenreRadarView(values: taste.groupValues)
            Text("Радиус — вероятность, что вам понравится типичный фильм группы. Полоса — разброс оценки, полые точки — данных пока мало.")
                .font(.footnote)
                .foregroundStyle(MovieMatchPalette.textSecondary)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки")
                .font(.title3.weight(.semibold))
            NavigationLink(value: AccountRoute.hidden) {
                HStack {
                    Text("Скрытые дизлайки")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MovieMatchPalette.textTertiary)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(MovieMatchPalette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(MovieMatchPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Button {
                confirmReset = true
            } label: {
                Text("Сбросить вкус")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MovieMatchPalette.destructive, in: Capsule())
            }
            .buttonStyle(MovieMatchIconStyle())
        }
    }
}

private enum AccountRoute: Hashable {
    case hidden
}

private struct HiddenMoviesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredHide.hiddenAt, order: .reverse) private var hides: [StoredHide]

    var body: some View {
        Group {
            if hides.isEmpty {
                MovieMatchMessage(title: "Скрытых фильмов нет")
            } else {
                List {
                    ForEach(hides, id: \.tmdbID) { hide in
                        HStack(spacing: 12) {
                            PosterImage(path: hide.posterPath, size: "w342")
                                .frame(width: 44, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hide.title)
                                Text(russianDate(hide.hiddenAt))
                                    .font(.caption)
                                    .foregroundStyle(MovieMatchPalette.textSecondary)
                            }
                            Spacer()
                            Button("Вернуть") {
                                LibraryStore.unhide(hide.tmdbID, in: modelContext)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .buttonStyle(MovieMatchCapsuleStyle())
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MovieMatchPalette.separator)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .movieMatchScreen()
        .navigationTitle("Скрытые")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//
//  AccountView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredMovie.savedAt, order: .reverse) private var movies: [StoredMovie]
    @Query private var tastes: [StoredTaste]
    @State private var confirmReset = false

    private var taste: TasteState { tastes.first?.state ?? .empty }
    private var portrait: PortraitConfidence { PortraitConfidence.resolve(taste) }
    private static let minimumMoviesForRadar = 3
    private var snapshot: LibrarySnapshot { LibraryStore.snapshot(of: movies) }
    private var genreShares: [GenreGroup: Double] { GenreGroup.shares(in: snapshot) }
    private var awards: Set<AwardID> {
        AwardEvaluator.unlocked(in: snapshot)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    stats
                    spider
                    awardsBlock
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
                "Сбросить вкус?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Сбросить", role: .destructive) {
                    LibraryStore.resetTaste(in: modelContext)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Портрет обнулится. Фильмы и отзывы останутся.")
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Оценено: \(taste.ratedCount)")
                .font(.title2.weight(.semibold))
            Text(portrait.sentence)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
    }

    private var spider: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Любимые жанры")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if movies.count < Self.minimumMoviesForRadar || genreShares.isEmpty {
                Text("Пока мало данных: сохраните несколько фильмов")
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                GenreRadarView(values: genreShares)
            }
        }
    }

    private var awardsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Награды")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(AwardID.allCases, id: \.self) { award in
                HStack(spacing: 10) {
                    Image(systemName: awards.contains(award) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.white)
                    Text(award.title)
                        .foregroundStyle(.white.opacity(awards.contains(award) ? 1 : 0.45))
                    Spacer()
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            NavigationLink(value: AccountRoute.hidden) {
                Text("Скрытые дизлайки")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
            Button("Сбросить вкус") { confirmReset = true }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(hides, id: \.tmdbID) { hide in
                            HStack(spacing: 12) {
                                PosterImage(path: hide.posterPath, size: "w342")
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hide.title)
                                        .foregroundStyle(.white)
                                    Text(russianDate(hide.hiddenAt))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
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
                        }
                    }
                    .padding(16)
                }
            }
        }
        .movieMatchScreen()
        .navigationTitle("Скрытые")
        .navigationBarTitleDisplayMode(.inline)
    }
}

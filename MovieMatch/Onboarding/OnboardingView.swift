//
//  OnboardingView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var movies: [TMDBMovie] = []
    @State private var loved: Set<Int> = []
    @State private var step = 0
    @State private var deckIndex = 0
    @State private var score: Int?
    @State private var busyID: Int?
    @State private var missingKey = false
    @State private var banner: String?
    @State private var isLoading = false

    private var deck: [TMDBMovie] {
        Array(movies.filter { !loved.contains($0.id) }.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if missingKey {
                    MovieMatchMessage(
                        title: "Нужен ключ TMDB",
                        subtitle: "Лента пустая, пока ключ не задан для сборки."
                    )
                } else if isLoading && movies.isEmpty {
                    ProgressView().tint(.white)
                } else if let banner, movies.isEmpty {
                    MovieMatchMessage(title: banner, actionTitle: "Повторить") {
                        Task { await load() }
                    }
                } else if step == 0 {
                    grid
                } else {
                    deckStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .movieMatchScreen()
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step == 0 ? "Что засело" : "Как вам эти")
                .font(.system(size: 28, weight: .semibold))
            Text(step == 0
                 ? "Нажмите постер, если фильм засел. Это оценка 8."
                 : "Оценка от 0 до 10 или «не смотрел».")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(movies.prefix(24)) { movie in
                    Button {
                        Task { await love(movie) }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            PosterImage(path: movie.imagePath, size: "w342")
                                .frame(maxWidth: .infinity)
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            if loved.contains(movie.id) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black)
                                    .padding(6)
                                    .background(.white, in: Circle())
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loved.contains(movie.id) ? "\(movie.title), засело" : movie.title)
                    .disabled(busyID != nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var deckStep: some View {
        VStack(spacing: 16) {
            if deck.isEmpty || deckIndex >= deck.count {
                MovieMatchMessage(title: "Список закончился")
            } else {
                let movie = deck[deckIndex]
                PosterImage(path: movie.imagePath, size: "w780")
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(movie.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                scorePicker
            }
        }
        .padding(.horizontal, 20)
    }

    private var scorePicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(0...10, id: \.self) { value in
                Button(String(value)) { score = value }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(score == value ? .black : .white)
                    .background(score == value ? Color.white : Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if missingKey {
                EmptyView()
            } else if step == 0 {
                capsule("Дальше") { step = 1 }
            } else if deckIndex >= deck.count || deck.isEmpty {
                capsule("Готово", action: onFinish)
            } else {
                capsule("Дальше") { Task { await rateDeck() } }
                    .disabled(score == nil || busyID != nil)
                    .opacity(score == nil ? 0.45 : 1)
                Button("Не смотрел") {
                    score = nil
                    deckIndex += 1
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            }
            Button("Позже", action: onFinish)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func capsule(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(MovieMatchCapsuleStyle())
    }

    private func load() async {
        guard movies.isEmpty else { return }
        guard let client = TMDBClient.live() else {
            missingKey = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let popular = try await client.popular(page: 1)
            let top = try await client.topRated(page: 1)
            var seen = Set<Int>()
            movies = (popular + top).filter { seen.insert($0.id).inserted }
            banner = movies.isEmpty ? "Каталог пустой" : nil
        } catch is CancellationError {
            return
        } catch let error as TMDBError {
            banner = error.userMessage
        } catch {
            banner = TMDBError.badStatus(0).userMessage
        }
    }

    private func love(_ movie: TMDBMovie) async {
        guard !loved.contains(movie.id), busyID == nil else { return }
        busyID = movie.id
        defer { busyID = nil }
        let detailed = await details(of: movie)
        LibraryStore.rateOnboarding(detailed, score: 8, in: modelContext)
        loved.insert(movie.id)
    }

    private func rateDeck() async {
        guard deckIndex < deck.count, let score, busyID == nil else { return }
        let movie = deck[deckIndex]
        busyID = movie.id
        defer { busyID = nil }
        let detailed = await details(of: movie)
        LibraryStore.rateOnboarding(detailed, score: score, in: modelContext)
        self.score = nil
        deckIndex += 1
    }

    private func details(of movie: TMDBMovie) async -> TMDBMovie {
        guard let client = TMDBClient.live() else { return movie }
        return (try? await client.details(id: movie.id)) ?? movie
    }
}

//
//  AddMovieSheet.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct AddMovieSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TMDBMovie] = []
    @State private var banner: String?
    @State private var missingKey = false
    @State private var isLoading = false
    @State private var pending: TMDBMovie?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Название", text: $query)
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button("Найти") { Task { await search() } }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .buttonStyle(MovieMatchCapsuleStyle())
                }
                .padding(.horizontal, 16)
                content
            }
            .movieMatchScreen()
            .navigationTitle("Добавить просмотренный")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(item: $pending) { movie in
                RatingSheet(
                    title: movie.title,
                    requiresRating: false,
                    allowsUnrated: true,
                    rating: nil,
                    review: ""
                ) { rating, review in
                    LibraryStore.saveFromSearch(movie, rating: rating, review: review, in: modelContext)
                    dismiss()
                }
            }
        }
        .presentationBackground(MovieMatchPalette.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if missingKey {
            MovieMatchMessage(title: "Нужен ключ TMDB", subtitle: "Поиск пустой, пока ключ не задан для сборки.")
        } else if isLoading {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if let banner, results.isEmpty {
            MovieMatchMessage(title: banner)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { movie in
                        Button {
                            Task { await choose(movie) }
                        } label: {
                            HStack(spacing: 12) {
                                PosterImage(path: movie.imagePath, size: "w342")
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(movie.title)
                                        .foregroundStyle(.white)
                                    if let year = movie.releaseYear {
                                        Text(String(year))
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let client = TMDBClient.live() else {
            missingKey = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await client.search(query: trimmed)
            banner = results.isEmpty ? "Ничего не найдено" : nil
        } catch is CancellationError {
            return
        } catch let error as TMDBError {
            banner = error.userMessage
            results = []
        } catch {
            banner = TMDBError.badStatus(0).userMessage
            results = []
        }
    }

    private func choose(_ movie: TMDBMovie) async {
        guard let client = TMDBClient.live() else {
            pending = movie
            return
        }
        pending = (try? await client.details(id: movie.id)) ?? movie
    }
}

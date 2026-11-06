//
//  LibraryFilter.swift
//  MovieMatch
//

import SwiftUI

struct LibraryFilter: Equatable {
    var text = ""
    var year: Int?
    var genreID: Int?
    var ratingLower = 0
    var ratingUpper = 10
    var matchLower = 0
    var matchUpper = 100
    var status: LibraryStatus?
    var requiresReview = false

    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || year != nil
            || genreID != nil
            || ratingLower > 0
            || ratingUpper < 10
            || matchLower > 0
            || matchUpper < 100
            || status != nil
            || requiresReview
    }

    func includes(_ movie: StoredMovie, matchPercent: Int) -> Bool {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, !movie.title.localizedStandardContains(query) { return false }
        if let year, movie.releaseYear != year { return false }
        if let genreID, !movie.genreIDs.contains(genreID) { return false }
        if let status, movie.status != status { return false }
        if requiresReview, !movie.hasReview { return false }
        if ratingLower > 0 || ratingUpper < 10 {
            guard let rating = movie.userRating, (ratingLower...ratingUpper).contains(rating) else { return false }
        }
        if matchLower > 0 || matchUpper < 100 {
            guard (matchLower...matchUpper).contains(matchPercent) else { return false }
        }
        return true
    }
}

struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    var years: [Int]
    var genres: [(id: Int, name: String)]
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LibraryFilter()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Текст", text: $draft.text)
                    picker("Год", selection: yearBinding, options: years.map { ($0, String($0)) })
                    picker("Жанр", selection: genreBinding, options: genres.map { ($0.id, $0.name) })
                    range("Своя оценка", lower: $draft.ratingLower, upper: $draft.ratingUpper, span: 0...10)
                    range("Совпадение %", lower: $draft.matchLower, upper: $draft.matchUpper, span: 0...100)
                    Picker("Статус", selection: statusBinding) {
                        Text("Любой").tag("any")
                        Text("Просмотрен").tag(LibraryStatus.watched.rawValue)
                        Text("Идея").tag(LibraryStatus.idea.rawValue)
                        Text("Суперлайк").tag(LibraryStatus.superlike.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Есть отзыв", isOn: $draft.requiresReview)
                        .tint(.white)
                    Button {
                        filter = draft
                        dismiss()
                    } label: {
                        Text("Применить")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(MovieMatchCapsuleStyle())
                    Button("Сбросить") { draft = LibraryFilter() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .movieMatchScreen()
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationBackground(MovieMatchPalette.background)
        .preferredColorScheme(.dark)
        .onAppear { draft = filter }
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { draft.year ?? 0 },
            set: { draft.year = $0 == 0 ? nil : $0 }
        )
    }

    private var genreBinding: Binding<Int> {
        Binding(
            get: { draft.genreID ?? 0 },
            set: { draft.genreID = $0 == 0 ? nil : $0 }
        )
    }

    private var statusBinding: Binding<String> {
        Binding(
            get: { draft.status?.rawValue ?? "any" },
            set: { draft.status = LibraryStatus(rawValue: $0) }
        )
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(title, text: text)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func picker(_ title: String, selection: Binding<Int>, options: [(Int, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) {
                Text("Любой").tag(0)
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func range(_ title: String, lower: Binding<Int>, upper: Binding<Int>, span: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title): \(lower.wrappedValue)–\(upper.wrappedValue)")
                .font(.subheadline.weight(.semibold))
            Slider(
                value: Binding(get: { Double(lower.wrappedValue) }, set: { lower.wrappedValue = min(Int($0.rounded()), upper.wrappedValue) }),
                in: Double(span.lowerBound)...Double(span.upperBound),
                step: 1
            )
            Slider(
                value: Binding(get: { Double(upper.wrappedValue) }, set: { upper.wrappedValue = max(Int($0.rounded()), lower.wrappedValue) }),
                in: Double(span.lowerBound)...Double(span.upperBound),
                step: 1
            )
        }
        .tint(.white)
    }
}

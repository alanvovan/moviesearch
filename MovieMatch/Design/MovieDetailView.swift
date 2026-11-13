//
//  MovieDetailView.swift
//  MovieMatch
//

import SwiftUI

/// Полное описание фильма одной прокруткой. Используется в карточке ленты и в библиотеке.
struct MovieDetailView: View {
    var movie: TMDBMovie
    var taste: TasteState
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 24

    @State private var loaded: TMDBMovie?
    @State private var loading = false
    @State private var trailer: TrailerRequest?

    private var shown: TMDBMovie { loaded ?? movie }

    var body: some View {
        let profile = FilmAxisHeuristic.profile(FilmSignals(movie: shown))
        let accent = MovieMatchPalette.accent(for: profile.family)
        let score = TasteEngine.match(user: taste, film: shown.features)
        VStack(alignment: .leading, spacing: 18) {
            hero
            VStack(alignment: .leading, spacing: 18) {
                header(family: profile.family)
                DiagramPair(tmdb: ratingPercent, match: score)
                trailerButton
                if let tagline = cleaned(shown.tagline) {
                    Text("«\(tagline)»")
                        .font(.system(size: 17, design: .serif).italic())
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                }
                overview
                if loading && !shown.enriched {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                castList
                tags(accent: accent)
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, bottomInset)
        .task(id: movie.id) { await enrich() }
        .fullScreenCover(item: $trailer) { request in
            TrailerSheet(movieID: request.id, initialKey: request.videoKey)
        }
    }

    private var hero: some View {
        Color.clear
            .frame(height: 220 + topInset)
            .overlay {
                PosterImage(path: shown.backdropPath ?? shown.posterPath, size: "w1280")
            }
            .overlay {
                LinearGradient(
                    colors: [MovieMatchPalette.background.opacity(0), MovieMatchPalette.background],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private func header(family: GenreFamily) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            PosterImage(path: shown.posterPath, size: "w342")
                .frame(width: 96, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MovieMatchPalette.stroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(shown.title)
                    .font(.system(size: 26, weight: .bold, design: family.usesSerif ? .serif : .rounded))
                    .foregroundStyle(MovieMatchPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                }
                genreChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, -86)
    }

    private var genreChips: some View {
        let catalog = TMDBGenreCatalog.shared
        let names = shown.genreIDs.prefix(3).map { capitalized(catalog.name(for: $0)) }
        return ChipFlow(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MovieMatchPalette.surfaceStrong, in: Capsule())
            }
        }
    }

    private var trailerButton: some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                trailer = TrailerRequest(id: shown.id, videoKey: shown.youtubeKey)
            }
        } label: {
            Label("Смотреть трейлер", systemImage: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(MovieMatchCapsuleStyle())
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Описание")
            Text(displayOverview(shown.overview))
                .font(.body)
                .foregroundStyle(MovieMatchPalette.textPrimary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(facts, id: \.label) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MovieMatchPalette.textTertiary)
                        .frame(width: 84, alignment: .leading)
                    Text(fact.value)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var castList: some View {
        if !shown.cast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("В ролях")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(shown.cast, id: \.self) { member in
                            VStack(alignment: .leading, spacing: 4) {
                                PosterImage(path: member.profilePath, size: "w185")
                                    .frame(width: 88, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(member.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                if let character = member.character {
                                    Text(character)
                                        .font(.caption2)
                                        .foregroundStyle(MovieMatchPalette.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 88, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, -18)
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func tags(accent: Color) -> some View {
        if !shown.keywords.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Теги")
                ChipFlow(spacing: 6) {
                    ForEach(shown.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(MovieMatchPalette.surface, in: Capsule())
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(MovieMatchPalette.textPrimary)
    }

    private var subtitleLine: String? {
        var parts: [String] = []
        if let year = shown.releaseYear { parts.append(String(year)) }
        if let runtime = shown.runtime, runtime > 0 { parts.append(runtimeText(runtime)) }
        if let certification = cleaned(shown.certification) { parts.append(certification) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var ratingPercent: Int? {
        guard let average = shown.voteAverage, average > 0 else { return nil }
        return Int((average * 10).rounded())
    }

    private var facts: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        let countries = shown.productionCountries.filter { !$0.isEmpty }
        if !countries.isEmpty { rows.append(("Страна", countries.prefix(2).joined(separator: ", "))) }
        if let director = cleaned(shown.director) { rows.append(("Режиссёр", director)) }
        if let original = cleaned(shown.originalTitle),
           original.caseInsensitiveCompare(shown.title) != .orderedSame {
            rows.append(("Оригинал", original))
        }
        return rows
    }

    private func enrich() async {
        guard !movie.enriched, loaded?.id != movie.id, let client = TMDBClient.live() else { return }
        loading = true
        defer { loading = false }
        if let detail = try? await client.details(id: movie.id) {
            loaded = detail
        }
    }

    private func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0, rest > 0 { return "\(hours) ч \(rest) мин" }
        if hours > 0 { return "\(hours) ч" }
        return "\(rest) мин"
    }
}

private struct TrailerRequest: Identifiable {
    var id: Int
    var videoKey: String?
}

/// Рейтинг TMDB и совпадение со вкусом. Нажатие на кольцо показывает подпись под ним.
private struct DiagramPair: View {
    var tmdb: Int?
    var match: MatchScore

    private enum Kind { case tmdb, match }

    @State private var expanded: Kind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let tmdb {
                item(
                    kind: .tmdb,
                    symbol: "star.fill",
                    ring: RatingRing(value: tmdb, tint: RatingRing.tmdbTint(tmdb), size: 52, accessibilityTitle: "Рейтинг TMDB"),
                    caption: "Рейтинг TMDB"
                )
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MovieMatchPalette.textTertiary)
                    .frame(height: 52)
                    .accessibilityHidden(true)
            }
            item(
                kind: .match,
                symbol: "person.fill",
                ring: RatingRing(
                    value: match.percent,
                    tint: RatingRing.matchTint(match.percent),
                    size: 52,
                    isConfident: match.isConfident,
                    accessibilityTitle: "Совпадение с вашим вкусом"
                ),
                caption: match.isConfident ? "Совпадение с вашим вкусом" : "Совпадение с вашим вкусом. Данных пока мало"
            )
            Spacer(minLength: 0)
        }
    }

    private func item(kind: Kind, symbol: String, ring: RatingRing, caption: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                expanded = expanded == kind ? nil : kind
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ring.tint)
                        .accessibilityHidden(true)
                    ring
                }
                if expanded == kind {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 140, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(MovieMatchIconStyle())
        .accessibilityHint("Показывает, что это за диаграмма")
    }
}

/// Чипы в несколько строк.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let nextY = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: nextY, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

#if DEBUG
#Preview("Описание") {
    ScrollView {
        MovieDetailView(movie: .previewDetail, taste: .empty)
    }
    .movieMatchScreen()
}

extension TMDBMovie {
    static var previewDetail: TMDBMovie {
        TMDBMovie(
            id: 438631,
            title: "Дюна",
            overview: "Наследник знаменитого дома Атрейдесов Пол отправляется вместе с семьёй на одну из самых опасных планет во Вселенной — Арракис. Здесь нет ничего, кроме песка, палящего солнца, гигантских чудовищ и основной причины межгалактических конфликтов — невероятно ценного ресурса, который называется меланж.",
            posterPath: nil,
            backdropPath: nil,
            releaseYear: 2021,
            genreIDs: [878, 12],
            genreNames: TMDBGenreNames.labels(for: [878, 12]),
            keywords: ["epic", "space", "empire", "desert", "prophecy", "based on novel or book"],
            runtime: 155,
            youtubeKey: nil,
            enriched: true,
            certification: "12+",
            voteAverage: 7.8,
            voteCount: 12000,
            productionCountries: ["США", "Канада"],
            tagline: "Начало",
            director: "Дени Вильнёв",
            cast: [
                TMDBCastMember(name: "Тимоти Шаламе", character: "Paul Atreides"),
                TMDBCastMember(name: "Ребекка Фергюсон", character: "Lady Jessica"),
            ]
        )
    }
}
#endif

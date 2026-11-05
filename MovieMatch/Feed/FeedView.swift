//
//  FeedView.swift
//  Prism
//

import SwiftData
import SwiftUI

@MainActor
@Observable
final class FeedModel {
    var queue: [TMDBMovie] = []
    var position: Int?
    var isLoading = false
    var banner: String?
    var missingKey = false
    var actionTick = 0

    private var client: TMDBClient?
    private var cursor = 0
    private var recentSkips: [Int] = []
    private var handled: Set<Int> = []
    private var detailAttempts: Set<Int> = []
    private var prepared = false

    func prepareAndLoad(context: ModelContext) async {
        if !prepared {
            prepared = true
            client = TMDBClient.live()
            missingKey = client == nil
            if let client {
                Task { await TMDBGenreCatalog.shared.loadIfNeeded(client: client) }
            }
        }
        await loadMore(context: context, fill: true)
    }

    func retry(context: ModelContext) async {
        banner = nil
        cursor = 0
        await loadMore(context: context, fill: true)
    }

    func loadMoreIfNeeded(current: Int, context: ModelContext) async {
        guard let index = queue.firstIndex(where: { $0.id == current }) else { return }
        guard index >= queue.count - 3 else { return }
        await loadMore(context: context, fill: false)
    }

    func prefetch(_ id: Int) async {
        guard let client else { return }
        await enrich(id, client: client)
        if let index = queue.firstIndex(where: { $0.id == id }), index + 1 < queue.count {
            await enrich(queue[index + 1].id, client: client)
        }
    }

    func noteScroll(from old: Int?, to new: Int?) {
        guard let old, let new, old != new else { return }
        if handled.contains(old) {
            handled.remove(old)
            return
        }
        guard
            let oldIndex = queue.firstIndex(where: { $0.id == old }),
            let newIndex = queue.firstIndex(where: { $0.id == new }),
            newIndex > oldIndex
        else { return }
        recentSkips.removeAll { $0 == old }
        recentSkips.append(old)
        if recentSkips.count > 12 {
            recentSkips.removeFirst()
        }
    }

    func like(_ movie: TMDBMovie, isSuper: Bool, context: ModelContext) {
        handled.insert(movie.id)
        LibraryStore.like(movie, isSuper: isSuper, in: context)
        removeAndAdvance(movie.id)
        actionTick += 1
    }

    func dislike(_ movie: TMDBMovie, context: ModelContext) {
        handled.insert(movie.id)
        LibraryStore.dislike(movie, in: context)
        removeAndAdvance(movie.id)
        actionTick += 1
    }

    private func removeAndAdvance(_ id: Int) {
        let next = queue.drop(while: { $0.id != id }).dropFirst().first?.id
        queue.removeAll { $0.id == id }
        recentSkips.removeAll { $0 == id }
        position = next ?? queue.first?.id
    }

    private func loadMore(context: ModelContext, fill: Bool) async {
        guard !isLoading, let client, !missingKey, cursor < 15 else { return }
        isLoading = true
        defer { isLoading = false }
        let target = fill ? 6 : 1
        var added = 0
        var emptyStreak = 0
        do {
            while added < target && emptyStreak < 3 && cursor < 15 {
                let page = try await fetchNext(client)
                let fresh = offerable(page, context: context)
                if fresh.isEmpty {
                    emptyStreak += 1
                } else {
                    emptyStreak = 0
                    queue.append(contentsOf: fresh)
                    added += fresh.count
                }
            }
            if position == nil {
                position = queue.first?.id
            }
            if added > 0 {
                banner = nil
            } else if queue.isEmpty && banner == nil {
                banner = "Лента пустая"
            }
            if let position {
                await prefetch(position)
            }
        } catch is CancellationError {
            return
        } catch let error as TMDBError {
            banner = error.userMessage
        } catch {
            banner = TMDBError.badStatus(0).userMessage
        }
    }

    private func fetchNext(_ client: TMDBClient) async throws -> [TMDBMovie] {
        let kind = cursor % 3
        let page = cursor / 3 + 1
        cursor += 1
        switch kind {
        case 0: return try await client.popular(page: page)
        case 1: return try await client.topRated(page: page)
        default: return try await client.discover(page: page)
        }
    }

    private func offerable(_ page: [TMDBMovie], context: ModelContext) -> [TMDBMovie] {
        let stored = (try? context.fetch(FetchDescriptor<StoredMovie>())) ?? []
        let hides = (try? context.fetch(FetchDescriptor<StoredHide>())) ?? []
        let taste = LibraryStore.taste(in: context)
        let blocked = Set(stored.map(\.tmdbID))
        var seen = Set(queue.map(\.id))
        var result: [TMDBMovie] = []
        for movie in page {
            guard seen.insert(movie.id).inserted else { continue }
            if recentSkips.contains(movie.id) || blocked.contains(movie.id) { continue }
            if let hide = hides.first(where: { $0.tmdbID == movie.id }) {
                let percent = TasteEngine.match(user: taste, film: movie.tasteAxes).percent
                if HideRule.isSuppressed(
                    hiddenAt: hide.hiddenAt,
                    matchAtHide: hide.matchAtHide,
                    now: .now,
                    currentMatch: percent
                ) {
                    continue
                }
                context.delete(hide)
                try? context.save()
            }
            result.append(movie)
        }
        return result
    }

    private func enrich(_ id: Int, client: TMDBClient) async {
        guard let index = queue.firstIndex(where: { $0.id == id }), !queue[index].enriched else { return }
        if detailAttempts.contains(id) { return }
        detailAttempts.insert(id)
        do {
            let detail = try await client.details(id: id)
            if let index = queue.firstIndex(where: { $0.id == id }) {
                queue[index] = detail
            }
        } catch is CancellationError {
            detailAttempts.remove(id)
        } catch {
            return
        }
    }
}

struct FeedView: View {
    @State private var model = FeedModel()

    var body: some View {
        FeedScreen(model: model)
    }
}

private struct FeedScreen: View {
    @Bindable var model: FeedModel
    @Environment(\.modelContext) private var modelContext
    @Query private var tastes: [StoredTaste]
    @State private var trailer: TrailerRequest?
    @State private var showIdeas = false

    private var taste: TasteState { tastes.first?.state ?? .empty }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
            if !model.missingKey {
                Button {
                    showIdeas = true
                } label: {
                    Text("Идеи")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(PrismCapsuleStyle())
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
        .prismScreen()
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: model.actionTick)
        .task { await model.prepareAndLoad(context: modelContext) }
        .sheet(isPresented: $showIdeas) { IdeasSheet() }
        .fullScreenCover(item: $trailer) { request in
            TrailerSheet(movieID: request.id, initialKey: request.videoKey)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.missingKey {
            PrismMessage(
                title: "Нужен ключ TMDB",
                subtitle: "Лента пустая, пока ключ не задан для сборки."
            )
        } else if model.queue.isEmpty {
            if model.isLoading {
                ProgressView().tint(.white)
            } else {
                PrismMessage(
                    title: model.banner ?? "Лента пустая",
                    subtitle: model.banner == nil ? nil : "Можно попробовать ещё раз.",
                    actionTitle: "Повторить",
                    action: { Task { await model.retry(context: modelContext) } }
                )
            }
        } else {
            pager
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            pagerScroll(insets: proxy.safeAreaInsets)
        }
    }

    private func pagerScroll(insets: EdgeInsets) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(model.queue) { movie in
                    FeedCard(
                        movie: movie,
                        taste: taste,
                        insets: insets,
                        onTrailer: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                trailer = TrailerRequest(id: movie.id, videoKey: movie.youtubeKey)
                            }
                        },
                        onDislike: { model.dislike(movie, context: modelContext) },
                        onLike: { model.like(movie, isSuper: false, context: modelContext) },
                        onSuperlike: { model.like(movie, isSuper: true, context: modelContext) }
                    )
                    .containerRelativeFrame(.vertical) { length, _ in length }
                    .id(movie.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.position)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .onChange(of: model.position) { old, new in
            model.noteScroll(from: old, to: new)
            guard let new else { return }
            Task {
                await model.prefetch(new)
                await model.loadMoreIfNeeded(current: new, context: modelContext)
            }
        }
    }
}

private struct TrailerRequest: Identifiable {
    var id: Int
    var videoKey: String?
}

private enum CardSection: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case cast = "В ролях"
    case tags = "Теги"
    case awards = "Награды"

    var id: String { rawValue }
}

private struct FeedCard: View {
    var movie: TMDBMovie
    var taste: TasteState
    var insets: EdgeInsets
    var onTrailer: () -> Void
    var onDislike: () -> Void
    var onLike: () -> Void
    var onSuperlike: () -> Void

    @State private var section: CardSection = .overview

    private static let maxTags = 12

    var body: some View {
        let profile = FilmAxisHeuristic.profile(FilmSignals(movie: movie))
        let accent = PrismPalette.accent(for: profile.family)
        let score = TasteEngine.match(user: taste, film: profile.axes)
        VStack(alignment: .leading, spacing: 14) {
            header(profile: profile, accent: accent, score: score)
            if let tagline = cleaned(movie.tagline) {
                Text("«\(tagline)»")
                    .font(.system(size: 17, design: .serif).italic())
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
            }
            trailerButton(accent: accent)
            Picker("Раздел", selection: $section) {
                ForEach(CardSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            sectionContent(accent: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            HStack(spacing: 18) {
                icon("xmark", "Не нравится", accent, onDislike)
                icon("heart", "В идеи", accent, onLike)
                icon("flame", "Суперлайк", accent, onSuperlike)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, insets.top + 56)
        .padding(.bottom, insets.bottom + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop(accent: accent) }
    }

    private func backdrop(accent: Color) -> some View {
        ZStack {
            PrismPalette.background
            if movie.backdropPath != nil || movie.posterPath != nil {
                PosterImage(path: movie.backdropPath ?? movie.posterPath, size: "w1280")
            } else {
                LinearGradient(colors: [accent.opacity(0.62), accent.opacity(0.14)], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(
                colors: [
                    PrismPalette.background.opacity(0.55),
                    PrismPalette.background.opacity(0.78),
                    PrismPalette.background.opacity(0.97),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func header(profile: FilmProfile, accent: Color, score: MatchScore) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterImage(path: movie.posterPath, size: "w342")
                .frame(width: 96, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(movie.title)
                    .font(.system(size: 26, weight: .bold, design: profile.family.usesSerif ? .serif : .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                HStack(spacing: 10) {
                    if let rating = ratingPercent {
                        RatingBadge(percent: rating)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Совпадение \(score.percent)%")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                        if score.portrait == .thin {
                            Text(score.portrait.thinCaption)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                }
                genreChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var genreChips: some View {
        let catalog = TMDBGenreCatalog.shared
        let names = movie.genreIDs.prefix(3).map { capitalized(catalog.name(for: $0)) }
        return HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
    }

    private func trailerButton(accent: Color) -> some View {
        Button(action: onTrailer) {
            Label("Смотреть трейлер", systemImage: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
        }
        .buttonStyle(PrismIconStyle())
        .accessibilityLabel("Смотреть трейлер")
    }

    @ViewBuilder
    private func sectionContent(accent: Color) -> some View {
        if !movie.enriched && section != .overview {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch section {
            case .overview: overview
            case .cast: castList
            case .tags: tags
            case .awards: placeholder("Нет данных о наградах и номинациях")
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(facts, id: \.label) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 84, alignment: .leading)
                    Text(fact.value)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            Text(displayOverview(movie.overview))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var castList: some View {
        if movie.cast.isEmpty {
            placeholder("Актёры не указаны")
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(movie.cast, id: \.self) { member in
                        VStack(alignment: .leading, spacing: 4) {
                            PosterImage(path: member.profilePath, size: "w185")
                                .frame(width: 88, height: 118)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(member.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            if let character = member.character {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 88, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var tags: some View {
        let keywords = movie.keywords.prefix(Self.maxTags).map { $0 }
        if keywords.isEmpty {
            placeholder("Тегов нет")
        } else {
            ChipFlow(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitleLine: String? {
        var parts: [String] = []
        if let year = movie.releaseYear { parts.append(String(year)) }
        if let runtime = movie.runtime, runtime > 0 { parts.append(runtimeText(runtime)) }
        if let certification = cleaned(movie.certification) { parts.append(certification) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var ratingPercent: Int? {
        guard let average = movie.voteAverage, average > 0 else { return nil }
        return Int((average * 10).rounded())
    }

    private var facts: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        let countries = movie.productionCountries.filter { !$0.isEmpty }
        if !countries.isEmpty { rows.append(("Страна", countries.prefix(2).joined(separator: ", "))) }
        if let director = cleaned(movie.director) { rows.append(("Режиссёр", director)) }
        if let original = cleaned(movie.originalTitle),
           original.caseInsensitiveCompare(movie.title) != .orderedSame {
            rows.append(("Оригинал", original))
        }
        return rows
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

    private func icon(_ system: String, _ label: String, _ accent: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 58, height: 58)
                .background(accent, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(PrismIconStyle())
        .accessibilityLabel(label)
    }
}

private struct RatingBadge: View {
    var percent: Int

    private var tint: Color {
        switch percent {
        case 70...: Color(red: 0.13, green: 0.82, blue: 0.48)
        case 40..<70: Color(red: 0.82, green: 0.84, blue: 0.19)
        default: Color(red: 0.86, green: 0.15, blue: 0.38)
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.7))
            Circle()
                .stroke(tint.opacity(0.3), lineWidth: 3)
                .padding(3)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Text("\(percent)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Рейтинг TMDB \(percent) из 100")
    }
}

/// Чипы в несколько строк. Не влезающие по высоте строки отрезает родитель.
private struct ChipFlow: Layout {
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
#Preview("Экшен") {
    FeedCardPreview(movie: .previewCard(
        title: "Топ Ган: Мэверик",
        genres: [28, 18],
        keywords: ["fighter pilot", "aircraft"],
        runtime: 131,
        certification: "PG-13",
        budget: 170_000_000,
        year: 2022,
        companies: ["Paramount"]
    ))
}

#Preview("Хоррор") {
    FeedCardPreview(movie: .previewCard(
        title: "Реинкарнация",
        genres: [27, 9648],
        keywords: ["grief", "occult", "slow burn", "horror"],
        runtime: 127,
        certification: "R",
        budget: 10_000_000,
        year: 2018,
        companies: ["A24"]
    ))
}

#Preview("Фантастика") {
    FeedCardPreview(movie: .previewCard(
        title: "Дюна",
        genres: [878, 12],
        keywords: ["epic", "space", "empire"],
        runtime: 155,
        certification: "PG-13",
        budget: 165_000_000,
        year: 2021,
        companies: ["Legendary"]
    ))
}

private struct FeedCardPreview: View {
    var movie: TMDBMovie

    var body: some View {
        FeedCard(
            movie: movie,
            taste: TasteState(
                mean: [
                    .tempo: 0.45, .spectacle: 0.55, .tension: 0.4, .tone: 0.62,
                    .plotComplexity: 0.5, .emotionalWeight: 0.48, .ideas: 0.5,
                    .humor: 0.4, .intimacy: 0.52, .focusCharacterVsEvent: 0.46,
                ],
                weight: Dictionary(uniqueKeysWithValues: TasteAxis.allCases.map { ($0, 2) }),
                rejected: [],
                ratedCount: 8
            ),
            insets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            onTrailer: {},
            onDislike: {},
            onLike: {},
            onSuperlike: {}
        )
        .frame(width: 402, height: 874)
        .preferredColorScheme(.dark)
    }
}

private extension TMDBMovie {
    static func previewCard(
        title: String,
        genres: [Int],
        keywords: [String],
        runtime: Int,
        certification: String,
        budget: Double,
        year: Int,
        companies: [String]
    ) -> TMDBMovie {
        TMDBMovie(
            id: genres.reduce(0, +),
            title: title,
            overview: "Описание фильма в две-три строки, чтобы проверить вёрстку раздела «Обзор».",
            posterPath: nil,
            backdropPath: nil,
            releaseYear: year,
            genreIDs: genres,
            genreNames: TMDBGenreNames.labels(for: genres),
            keywords: keywords,
            runtime: runtime,
            youtubeKey: nil,
            enriched: true,
            certification: certification,
            budget: budget,
            voteAverage: 7.4,
            voteCount: 1200,
            productionCountries: ["США"],
            productionCompanies: companies,
            tagline: "Присаживайтесь",
            director: "Режиссёр Фильма",
            cast: [
                TMDBCastMember(name: "Роберт Паттинсон", character: "Chris Hansen"),
                TMDBCastMember(name: "Мерритт Уивер", character: "Andie Bender"),
                TMDBCastMember(name: "Скайлер Джизондо", character: "Dan Plum"),
            ]
        )
    }
}
#endif

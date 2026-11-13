//
//  FeedView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

@MainActor
@Observable
final class FeedModel {
    var queue: [TMDBMovie] = []
    var isLoading = false
    var banner: String?
    var missingKey = false
    var actionTick = 0

    private var client: TMDBClient?
    private var loadToken = 0
    private var cursor = 0
    private var shown: Set<Int> = []
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
        await loadMore(context: context, target: 6)
    }

    func reload(context: ModelContext) async {
        guard !missingKey, client != nil else { return }
        loadToken += 1
        isLoading = false
        banner = nil
        if cursor >= 40 { cursor = 0 }
        await loadMore(context: context, target: 6)
    }

    func present(_ movie: TMDBMovie) {
        banner = nil
        queue.removeAll { $0.id == movie.id }
        queue.insert(movie, at: 0)
        shown.insert(movie.id)
        Task { await prefetchTop() }
    }

    func suggestions(matching raw: String) async throws -> [TMDBMovie] {
        guard let client else { return [] }
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let matches = try await client.search(query: query)
        var seen: Set<Int> = []
        var result: [TMDBMovie] = []
        for movie in matches where seen.insert(movie.id).inserted {
            result.append(movie)
            if result.count == 8 { break }
        }
        return result
    }

    func notInterested(_ movie: TMDBMovie, context: ModelContext) {
        LibraryStore.notInterested(movie, in: context)
        advance(past: movie.id, context: context)
    }

    func planLater(_ movie: TMDBMovie, context: ModelContext) {
        LibraryStore.planLater(movie, in: context)
        advance(past: movie.id, context: context)
    }

    func watched(_ movie: TMDBMovie, rating: Int?, review: String, context: ModelContext) {
        LibraryStore.markWatched(movie, rating: rating, review: review, in: context)
        advance(past: movie.id, context: context)
    }

    private func advance(past id: Int, context: ModelContext) {
        queue.removeAll { $0.id == id }
        actionTick += 1
        Task {
            await prefetchTop()
            if queue.count < 4 {
                await loadMore(context: context, target: 4)
            }
        }
    }

    func prefetchTop() async {
        guard let client else { return }
        for movie in queue.prefix(2) {
            await enrich(movie.id, client: client)
        }
    }

    private func loadMore(context: ModelContext, target: Int) async {
        let token = loadToken
        guard !isLoading, let client, !missingKey, cursor < 40 else {
            if queue.isEmpty, cursor >= 40 { banner = "Лента закончилась" }
            return
        }
        isLoading = true
        defer { isLoading = false }
        var added = 0
        var emptyStreak = 0
        do {
            while added < target && emptyStreak < 3 && cursor < 40 {
                let page = try await fetch(at: cursor, client: client)
                guard token == loadToken else { return }
                cursor += 1
                let fresh = offerable(page, context: context)
                if fresh.isEmpty {
                    emptyStreak += 1
                } else {
                    emptyStreak = 0
                    queue.append(contentsOf: fresh)
                    shown.formUnion(fresh.map(\.id))
                    added += fresh.count
                }
            }
            if added > 0 {
                banner = nil
            } else if queue.isEmpty {
                banner = "Лента пустая"
            }
            await prefetchTop()
        } catch is CancellationError {
            return
        } catch let error as TMDBError {
            guard token == loadToken else { return }
            if queue.isEmpty { banner = error.userMessage }
        } catch {
            guard token == loadToken else { return }
            if queue.isEmpty { banner = TMDBError.badStatus(0).userMessage }
        }
    }

    private func fetch(at index: Int, client: TMDBClient) async throws -> [TMDBMovie] {
        let kind = index % 3
        let page = index / 3 + 1
        switch kind {
        case 0: return try await client.popular(page: page)
        case 1: return try await client.topRated(page: page)
        default: return try await client.discover(page: page)
        }
    }

    /// Убирает уже сохранённые и ещё скрытые фильмы, остальное упорядочивает по MATH_SPEC.md, 6.3.
    private func offerable(_ page: [TMDBMovie], context: ModelContext) -> [TMDBMovie] {
        let stored = (try? context.fetch(FetchDescriptor<StoredMovie>())) ?? []
        let hides = (try? context.fetch(FetchDescriptor<StoredHide>())) ?? []
        let taste = LibraryStore.taste(in: context)
        let blocked = Set(stored.map(\.tmdbID))
        var seen = shown.union(queue.map(\.id))
        var result: [TMDBMovie] = []
        for movie in page {
            guard seen.insert(movie.id).inserted, !blocked.contains(movie.id) else { continue }
            if let hide = hides.first(where: { $0.tmdbID == movie.id }) {
                let probability = TasteEngine.match(user: taste, film: movie.features).probability
                if HideRule.isSuppressed(hiddenAt: hide.hiddenAt, now: .now, currentProbability: probability) {
                    continue
                }
                context.delete(hide)
                try? context.save()
            }
            result.append(movie)
        }
        let day = Int(Date.now.timeIntervalSince1970 / 86_400)
        let order = TasteEngine.rank(result.map { ($0.id, $0.features) }, user: taste, seed: day)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    private func enrich(_ id: Int, client: TMDBClient) async {
        guard let index = queue.firstIndex(where: { $0.id == id }), !queue[index].enriched else { return }
        guard detailAttempts.insert(id).inserted else { return }
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

private enum SwipeAction {
    case notInterested
    case planLater
}

private enum Swipe {
    static let threshold: CGFloat = 110
    static let velocity: CGFloat = 700
    static let flyDistance: CGFloat = 640
}

private struct FeedScreen: View {
    @Bindable var model: FeedModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tastes: [StoredTaste]
    @State private var searchText = ""
    @State private var suggestions: [TMDBMovie] = []
    @State private var suggestionNote: String?
    @State private var isSuggesting = false
    @State private var dragX: CGFloat = 0
    @State private var isFlying = false
    @State private var watchedTarget: TMDBMovie?
    @State private var expanded = false
    @Namespace private var cardSpace
    @FocusState private var searchFocused: Bool

    private var taste: TasteState { tastes.first?.state ?? .empty }
    private var showSuggestionPanel: Bool { !suggestions.isEmpty || suggestionNote != nil }
    private var pastThreshold: Bool { abs(dragX) >= Swipe.threshold }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 14) {
                Color.clear.frame(height: model.missingKey ? 0 : 52)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.queue.isEmpty {
                    actionBar
                        .opacity(expanded ? 0 : 1)
                        .allowsHitTesting(!expanded)
                        .accessibilityHidden(expanded)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            if !model.missingKey && (searchFocused || showSuggestionPanel) {
                MovieMatchPalette.scrim
                    .opacity(showSuggestionPanel ? 1 : 0.01)
                    .ignoresSafeArea()
                    .onTapGesture(perform: tapOutsideSearch)
            }
            if expanded, let movie = model.queue.first {
                detailLayer(movie)
                    .transition(.identity)
            } else if !model.missingKey {
                searchChrome
            }
        }
        .movieMatchScreen()
        .toolbarVisibility(expanded ? .hidden : .automatic, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: model.actionTick)
        .sensoryFeedback(.selection, trigger: pastThreshold)
        .task { await model.prepareAndLoad(context: modelContext) }
        .task(id: searchText) { await updateSuggestions() }
        .sheet(item: $watchedTarget) { movie in
            RatingSheet(
                title: movie.title,
                requiresRating: false,
                allowsUnrated: true,
                rating: nil,
                review: ""
            ) { rating, review in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                    expanded = false
                    model.watched(movie, rating: rating, review: review, context: modelContext)
                }
            }
        }
    }

    // MARK: Колода

    @ViewBuilder
    private var content: some View {
        if model.missingKey {
            MovieMatchMessage(title: "Нужен ключ TMDB", subtitle: "Лента пустая, пока ключ не задан для сборки.")
        } else if model.queue.isEmpty {
            if model.isLoading {
                ProgressView()
            } else {
                MovieMatchMessage(
                    title: model.banner ?? "Лента пустая",
                    subtitle: "Можно попробовать загрузить ещё раз.",
                    actionTitle: "Повторить",
                    action: { Task { await model.reload(context: modelContext) } }
                )
            }
        } else {
            deck
        }
    }

    private var deck: some View {
        let visible = Array(model.queue.prefix(2).enumerated())
        return ZStack {
            ForEach(visible.reversed(), id: \.element.id) { index, movie in
                card(movie, isTop: index == 0)
            }
        }
    }

    @ViewBuilder
    private func card(_ movie: TMDBMovie, isTop: Bool) -> some View {
        let progress = min(1, abs(dragX) / Swipe.threshold)
        SwipeCard(movie: movie, taste: taste, dragX: isTop ? dragX : 0)
            .opacity(isTop && expanded ? 0 : 1)
            .animation(nil, value: expanded)
            .matchedGeometryEffect(id: isTop ? "card" : "next", in: cardSpace, isSource: isTop && !expanded)
            .onTapGesture {
                guard isTop, !isFlying, abs(dragX) < 4 else { return }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12)) { expanded = true }
            }
            .scaleEffect(isTop ? 1 : 0.94 + 0.06 * progress)
            .offset(y: isTop ? 0 : 14 * (1 - progress))
            .offset(x: isTop ? dragX : 0, y: isTop ? abs(dragX) * 0.05 : 0)
            .rotationEffect(.degrees(isTop && !reduceMotion ? Double(dragX / 22).clamped(to: -12...12) : 0), anchor: .bottom)
            .allowsHitTesting(isTop && !isFlying)
            .gesture(
                HorizontalPan(enabled: isTop && !isFlying) { translation in
                    dragX = translation
                } onEnded: { translation, velocity in
                    finishDrag(movie, translation: translation, velocity: velocity)
                }
            )
            .accessibilityAction(named: "Не интересно") { commit(.notInterested) }
            .accessibilityAction(named: "Посмотреть позже") { commit(.planLater) }
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
            .zIndex(isTop ? 1 : 0)
    }

    /// Детальный просмотр: карточка на весь экран, действия только кнопками поверх.
    private func detailLayer(_ movie: TMDBMovie) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                MovieDetailView(movie: movie, taste: taste, bottomInset: 150)
            }
            .scrollIndicators(.hidden)
            .background(MovieMatchPalette.background)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1)) { expanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MovieMatchPalette.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(MovieMatchIconStyle())
                .padding(14)
                .accessibilityLabel("Свернуть")
            }
            actionBar
                .padding(.top, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    LinearGradient(
                        colors: [MovieMatchPalette.background.opacity(0), MovieMatchPalette.background.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
        }
        .matchedGeometryEffect(id: "card", in: cardSpace, isSource: expanded)
    }

    private var actionBar: some View {
        HStack(spacing: 28) {
            actionButton("xmark", label: "Не интересно", size: 58) { commit(.notInterested) }
            actionButton("eye.fill", label: "Просмотрено", size: 72) {
                if let movie = model.queue.first { watchedTarget = movie }
            }
            actionButton("bookmark.fill", label: "Посмотреть позже", size: 58) { commit(.planLater) }
        }
        .frame(maxWidth: .infinity)
        .disabled(isFlying)
    }

    private func actionButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        let family = model.queue.first.map { FilmAxisHeuristic.profile(FilmSignals(movie: $0)).family } ?? .drama
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(MovieMatchPalette.onAccent)
                .frame(width: size, height: size)
                .background(MovieMatchPalette.actionFill(for: family), in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        }
        .buttonStyle(MovieMatchIconStyle())
        .accessibilityLabel(label)
    }

    private func finishDrag(_ movie: TMDBMovie, translation: CGFloat, velocity: CGFloat) {
        let projected = translation + velocity * 0.15
        if abs(translation) >= Swipe.threshold || abs(velocity) >= Swipe.velocity && abs(projected) >= Swipe.threshold {
            commit(projected > 0 ? .planLater : .notInterested)
        } else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.3)) {
                dragX = 0
            }
        }
    }

    private func commit(_ action: SwipeAction) {
        guard let movie = model.queue.first, !isFlying else { return }
        isFlying = true
        let perform = {
            expanded = false
            switch action {
            case .notInterested: model.notInterested(movie, context: modelContext)
            case .planLater: model.planLater(movie, context: modelContext)
            }
        }
        if reduceMotion || expanded {
            withAnimation(.easeOut(duration: 0.2)) { perform() }
            dragX = 0
            isFlying = false
            return
        }
        let target = action == .planLater ? Swipe.flyDistance : -Swipe.flyDistance
        withAnimation(.easeIn(duration: 0.22)) {
            dragX = target
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                perform()
                dragX = 0
            }
            isFlying = false
        }
    }

    // MARK: Поиск

    private var searchChrome: some View {
        VStack(spacing: 8) {
            MovieMatchSearchField(
                prompt: "Название фильма",
                text: $searchText,
                focus: $searchFocused,
                onSubmit: pickFirstSuggestion
            ) {
                if isSuggesting {
                    ProgressView().controlSize(.small)
                }
            }
            if showSuggestionPanel {
                suggestionPanel
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var suggestionPanel: some View {
        let note: CGFloat = suggestionNote != nil && suggestions.isEmpty ? 52 : 0
        return ScrollView {
            LazyVStack(spacing: 0) {
                if let suggestionNote, suggestions.isEmpty {
                    Text(suggestionNote)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
                ForEach(suggestions) { movie in
                    Button {
                        choose(movie)
                    } label: {
                        suggestionRow(movie)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: min(320, note + CGFloat(suggestions.count) * 64))
        .scrollIndicators(.hidden)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MovieMatchPalette.stroke, lineWidth: 1)
        }
    }

    private func suggestionRow(_ movie: TMDBMovie) -> some View {
        HStack(spacing: 10) {
            PosterImage(path: movie.posterPath, size: "w185")
                .frame(width: 32, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MovieMatchPalette.textPrimary)
                    .lineLimit(1)
                if let year = movie.releaseYear {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(movie.releaseYear.map { "\(movie.title), \($0)" } ?? movie.title)
        .accessibilityAddTraits(.isButton)
    }

    private func updateSuggestions() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            suggestionNote = nil
            isSuggesting = false
            return
        }
        isSuggesting = true
        do {
            try await Task.sleep(for: .milliseconds(280))
        } catch {
            return
        }
        do {
            let found = try await model.suggestions(matching: trimmed)
            guard !Task.isCancelled, searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            suggestions = found
            suggestionNote = found.isEmpty ? "Ничего не найдено" : nil
            isSuggesting = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            suggestionNote = "Не удалось загрузить подсказки"
            isSuggesting = false
        }
    }

    private func choose(_ movie: TMDBMovie) {
        searchFocused = false
        searchText = ""
        suggestions = []
        suggestionNote = nil
        isSuggesting = false
        dragX = 0
        model.present(movie)
    }

    private func pickFirstSuggestion() {
        guard let movie = suggestions.first else { return }
        choose(movie)
    }

    private func tapOutsideSearch() {
        if searchFocused {
            searchFocused = false
            return
        }
        suggestions = []
        suggestionNote = nil
    }
}

/// Карточка колоды: крупный постер, краткие данные и метки свайпа. Подробности открываются по нажатию.
private struct SwipeCard: View {
    var movie: TMDBMovie
    var taste: TasteState
    var dragX: CGFloat

    private var ratingPercent: Int? {
        guard let average = movie.voteAverage, average > 0 else { return nil }
        return Int((average * 10).rounded())
    }

    private var tagline: String? {
        let trimmed = movie.tagline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var face: some View {
        let score = TasteEngine.match(user: taste, film: movie.features)
        let catalog = TMDBGenreCatalog.shared
        let genres = movie.genreIDs.prefix(3).map { name -> String in
            let text = catalog.name(for: name)
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        return Color.clear
            .overlay { PosterImage(path: movie.posterPath ?? movie.backdropPath, size: "w780") }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.92)],
                    startPoint: .init(x: 0.5, y: 0.35),
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(movie.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let tagline {
                        Text("«\(tagline)»")
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                    if !genres.isEmpty {
                        ChipFlow(spacing: 6) {
                            ForEach(genres, id: \.self) { name in
                                Text(name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 18) {
                        if let ratingPercent {
                            ratingItem(
                                RatingRing(value: ratingPercent, tint: RatingRing.tmdbTint(ratingPercent), size: 48, accessibilityTitle: "Рейтинг TMDB"),
                                caption: "Рейтинг TMDB"
                            )
                        }
                        ratingItem(
                            RatingRing(
                                value: score.percent,
                                tint: RatingRing.matchTint(score.percent),
                                size: 48,
                                isConfident: score.isConfident,
                                accessibilityTitle: "Совпадение с вашим вкусом"
                            ),
                            caption: "Совпадение с вкусом"
                        )
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
    }

    private func ratingItem(_ ring: RatingRing, caption: String) -> some View {
        HStack(spacing: 8) {
            ring
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: 74, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        face
        .background(MovieMatchPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(MovieMatchPalette.stroke, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            HStack {
                stamp("ПОЗЖЕ", color: MovieMatchPalette.positive)
                    .opacity(Double(max(0, dragX) / Swipe.threshold))
                    .rotationEffect(.degrees(-10))
                Spacer()
                stamp("НЕ ИНТЕРЕСНО", color: MovieMatchPalette.destructive)
                    .opacity(Double(max(0, -dragX) / Swipe.threshold))
                    .rotationEffect(.degrees(10))
            }
            .padding(22)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
    }
}

/// Горизонтальный свайп, который не мешает вертикальной прокрутке карточки и горизонтальным спискам внутри неё.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
            let point = pan.location(in: view)
            var hit = view.hitTest(point, with: nil)
            while let current = hit, current !== view {
                if let scroll = current as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 {
                    return false
                }
                hit = current.superview
            }
            return true
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

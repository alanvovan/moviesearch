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
        .sheet(item: $trailer) { request in
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
                        isActive: model.position == movie.id && trailer == nil,
                        onTrailer: { trailer = TrailerRequest(id: movie.id, videoKey: movie.youtubeKey) },
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

private struct FeedCard: View {
    var movie: TMDBMovie
    var taste: TasteState
    var insets: EdgeInsets
    var isActive: Bool
    var onTrailer: () -> Void
    var onDislike: () -> Void
    var onLike: () -> Void
    var onSuperlike: () -> Void

    private var axes: [TasteAxis: Double] { movie.tasteAxes }
    private var spokes: [TasteAxis] { TasteAxis.allCases.filter { axes[$0] != nil } }
    private var score: MatchScore { TasteEngine.match(user: taste, film: axes) }

    @State private var showVideo = false

    var body: some View {
        ZStack {
            PosterImage(path: movie.imagePath, size: "w1280")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if showVideo, let key = movie.youtubeKey, !key.isEmpty {
                GeometryReader { proxy in
                    YouTubeEmbed(videoID: key, autoplay: true, muted: true, controls: false, loop: true)
                        .frame(width: proxy.size.height * 16 / 9, height: proxy.size.height)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onTrailer)
            LinearGradient(
                colors: [.clear, .clear, PrismPalette.background.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            VStack(spacing: 14) {
                Spacer().allowsHitTesting(false)
                Button(action: onTrailer) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.34), radius: 16, y: 8)
                }
                .buttonStyle(PrismIconStyle())
                .accessibilityLabel("Трейлер")
                Spacer().allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Этот фильм понравится вам на \(score.percent)%")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    if score.portrait == .thin {
                        Text(score.portrait.thinCaption)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Text(movie.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                    Text(displayOverview(movie.overview))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(4)
                    if !spokes.isEmpty {
                        SpiderChartView(spokes: spokes, film: axes, user: taste.mean, compact: true)
                    }
                    HStack(spacing: 18) {
                        icon("xmark", "Не нравится", onDislike)
                        icon("heart", "В идеи", onLike)
                        icon("flame", "Суперлайк", onSuperlike)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom + 12)
        }
        .task(id: isActive) {
            guard isActive else {
                showVideo = false
                return
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showVideo = true }
        }
    }

    private func icon(_ system: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 62, height: 62)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(PrismIconStyle())
        .accessibilityLabel(label)
    }
}

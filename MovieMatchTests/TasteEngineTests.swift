//
//  TasteEngineTests.swift
//  MovieMatchTests
//

import Foundation
import Testing
@testable import MovieMatch

@Test func a_tenHorrorRatingsDoNotMakeAHorrorFan() throws {
    let axes: [TasteAxis: Double] = [.tone: 0.25, .tension: 1]
    var state = TasteState.empty
    for _ in 0..<10 {
        state = TasteEngine.apply(signal: .rating(10), film: axes, to: state)
    }

    #expect(Set(state.mean.keys) == [.tone, .tension])
    let data = try JSONEncoder().encode(state)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("27"))
    #expect(!json.localizedCaseInsensitiveContains("horror"))

    let first = TasteEngine.match(user: state, film: axes)
    let sameAxes = TasteEngine.match(user: state, film: [.tone: 0.25, .tension: 1])
    #expect(first.percent == sameAxes.percent)

    let before = state
    let items = (0..<10).map { _ in
        LibrarySnapshot.Item(
            genreIDs: [27],
            userRating: 10,
            reviewText: "",
            status: .watched,
            superlikedAt: nil
        )
    }
    let awards = AwardEvaluator.unlocked(in: LibrarySnapshot(items: items))
    #expect(awards.contains(.horror10))
    #expect(state == before)
    #expect(state.mean == before.mean)
}

@Test func b_zeroDoesNotEraseTension() {
    var state = TasteState(
        mean: [.tension: 0.75],
        weight: [.tension: 4],
        rejected: [],
        ratedCount: 6
    )
    state = TasteEngine.apply(
        signal: .rating(0),
        film: [.tension: 0.95, .tone: 0.25],
        to: state
    )
    #expect(state.mean[.tension] == 0.75)
    #expect(state.mean[.tension] != 0)
    #expect(!state.rejected.isEmpty)
}

@Test func c_matchUsesAxisIntersectionOnly() {
    let state = TasteState(
        mean: [.tempo: 0.75, .tension: 0.25],
        weight: [.tempo: 2, .tension: 2],
        rejected: [],
        ratedCount: 8
    )
    let sharedOnly = TasteEngine.match(user: state, film: [.tempo: 0.75])
    let extraAxis = TasteEngine.match(user: state, film: [.tempo: 0.75, .humor: 1])
    let bothShared = TasteEngine.match(user: state, film: [.tempo: 0.75, .tension: 1])
    #expect(extraAxis.percent == sharedOnly.percent)
    #expect(bothShared.percent != sharedOnly.percent)
}

@Test func d_awardDoesNotChangeTaste() {
    let state = TasteState(
        mean: [.tension: 0.75],
        weight: [.tension: 2],
        rejected: [],
        ratedCount: 3
    )
    let copy = state
    _ = AwardEvaluator.unlocked(in: LibrarySnapshot(items: []))
    #expect(state == copy)
    #expect(state.mean == copy.mean)
}

@Test func likeIsWeakerThanRatingEight() {
    let axes: [TasteAxis: Double] = [.tempo: 1]
    let liked = TasteEngine.apply(signal: .like, film: axes, to: .empty)
    let superliked = TasteEngine.apply(signal: .superlike, film: axes, to: .empty)
    let rated = TasteEngine.apply(signal: .rating(8), film: axes, to: .empty)
    let likeWeight = liked.weight[.tempo] ?? 0
    let superWeight = superliked.weight[.tempo] ?? 0
    let ratedWeight = rated.weight[.tempo] ?? 0
    #expect(likeWeight < ratedWeight * 0.2)
    #expect(superWeight > likeWeight)
    #expect(superWeight < ratedWeight * 0.25)
    #expect(liked.ratedCount == 0)
    #expect(superliked.ratedCount == 0)
    #expect(rated.ratedCount == 1)
}

@Test func hideLastsTwentyOneDaysUnlessMatchGrows() {
    let hidden = Date(timeIntervalSince1970: 0)
    let beforeWindow = hidden.addingTimeInterval(HideRule.window - 1)
    let atWindow = hidden.addingTimeInterval(HideRule.window)
    #expect(HideRule.isSuppressed(hiddenAt: hidden, matchAtHide: 40, now: beforeWindow, currentMatch: 54))
    #expect(!HideRule.isSuppressed(hiddenAt: hidden, matchAtHide: 40, now: beforeWindow, currentMatch: 55))
    #expect(!HideRule.isSuppressed(hiddenAt: hidden, matchAtHide: 40, now: atWindow, currentMatch: 40))
}

@Test func horrorGenreMarksFilmAxesOnly() {
    let axes = FilmAxisHeuristic.axes(genreIDs: [27], keywords: [], runtimeMinutes: 110)
    #expect(abs((axes[.tension] ?? -1) - 0.85) < 0.001)
    #expect(abs((axes[.tone] ?? -1) - 0.25) < 0.001)
    #expect(axes[.humor] == nil)
    #expect(axes.count == 2)
}

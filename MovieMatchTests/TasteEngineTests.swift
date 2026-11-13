//
//  TasteEngineTests.swift
//  MovieMatchTests
//
//  Кейсы T1–T14 из MATH_SPEC.md, раздел 12.
//

import Foundation
import Testing
import UIKit
@testable import MovieMatch

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let now = base.addingTimeInterval(100)
private let filmA = FilmFeatures(axes: FilmAxisHeuristic.axes(genreIDs: [878, 28], keywords: [], runtimeMinutes: nil), genreIDs: [878, 28])
private let filmB = FilmFeatures(axes: FilmAxisHeuristic.axes(genreIDs: [18, 10749], keywords: [], runtimeMinutes: nil), genreIDs: [18, 10749])

/// Журнал с монотонными временем и номером, как в разделе 9.
private struct Journal {
    var events: [TasteEvent] = []

    @discardableResult
    mutating func add(_ kind: TasteEventKind, _ id: Int, _ genres: [Int], _ value: Int? = nil) -> TasteEvent {
        let sequence = events.count + 1
        let event = TasteEvent(
            kind: kind,
            tmdbID: id,
            value: value,
            at: base.addingTimeInterval(Double(sequence)),
            sequence: sequence,
            axes: FilmAxisHeuristic.axes(genreIDs: genres, keywords: [], runtimeMinutes: nil),
            genreIDs: genres
        )
        events.append(event)
        return event
    }

    func state() -> TasteState { TasteEngine.rebuild(events: events, now: now) }
}

private func near(_ value: Double, _ expected: Double, _ tolerance: Double = 0.001) -> Bool {
    abs(value - expected) <= tolerance
}

@Test func t1_emptyProfile() {
    let state = TasteEngine.rebuild(events: [], now: now)
    for group in GenreGroup.allCases {
        let value = state.group(group)
        #expect(near(value.point, 0.5))
        #expect(near(value.lower, 0.059))
        #expect(near(value.upper, 0.941))
        #expect(value.isWide)
    }
    let a = TasteEngine.match(user: state, film: filmA)
    #expect(near(a.probability, 0.5))
    #expect(near(a.lower, 0.040, 0.002))
    #expect(near(a.upper, 0.960, 0.002))
    #expect(!a.isConfident)
    let bare = TasteEngine.match(user: state, film: FilmFeatures(axes: [:], genreIDs: []))
    #expect(near(bare.lower, 0.100))
    #expect(near(bare.upper, 0.900))
}

@Test func t2_repeatedRatingReplacesPrevious() {
    var journal = Journal()
    journal.add(.rate, 400, [18], 30)
    let last = journal.add(.rate, 400, [18], 90)
    let replaced = TasteEngine.raw(journal.events, now: now)
    let single = TasteEngine.raw([last], now: now)
    #expect(replaced.mean == single.mean)
    #expect(replaced.ratedCount == 1)
}

@Test func t3_identicalRatingsStillMeanLiked() {
    var journal = Journal()
    for index in 0..<10 { journal.add(.rate, 100 + index, [18], 90) }
    let state = journal.state()
    #expect(near(state.ratingMean, 0.842))
    #expect(near(state.ratingSD, 0.125))
    #expect(near(state.likeThreshold, 0.696))
    let norm = TasteEngine.Normalization(mean: state.ratingMean, sd: state.ratingSD, threshold: state.likeThreshold, rated: 10)
    #expect(near(TasteEngine.utility(rating: 90, normalization: norm), 1.635, 0.002))
    #expect(near(state.group(.drama).point, 0.882))
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.908, 0.002))
}

@Test func t4_removeRollsBackExactly() {
    var journal = Journal()
    journal.add(.rate, 400, [18], 30)
    journal.add(.removeMovie, 400, [])
    #expect(journal.state() == TasteState.empty)
}

@Test func t5_resetAndQualityPrior() {
    var journal = Journal()
    journal.add(.rate, 400, [18], 30)
    journal.add(.rate, 400, [18], 90)
    journal.add(.reset, 0, [])
    #expect(journal.state() == TasteState.empty)
    let classic = FilmFeatures(axes: [:], genreIDs: [], voteAverage: 8.5, voteCount: 20_000)
    #expect(near(TasteEngine.qualityOffset(classic, effectiveCount: 0), 0.591))
    #expect(near(TasteEngine.match(user: .empty, film: classic).probability, 0.662))
}

@Test func t5b_eventsAfterResetCount() {
    var journal = Journal()
    journal.add(.rate, 400, [18], 30)
    journal.add(.reset, 0, [])
    journal.add(.rate, 401, [878, 28], 95)
    var fresh = Journal()
    fresh.add(.rate, 401, [878, 28], 95)
    #expect(TasteEngine.raw(journal.events, now: now).mean == TasteEngine.raw(fresh.events.map {
        var event = $0
        event.at = journal.events[2].at
        event.sequence = journal.events[2].sequence
        return event
    }, now: now).mean)
}

@Test func t6_diagramStepIsLimited() {
    var journal = Journal()
    journal.add(.rate, 200, [27], 100)
    #expect(near(TasteEngine.raw(journal.events, now: now).group(.suspense).point, 0.800))
    #expect(near(journal.state().group(.suspense).point, 0.650))
}

@Test func t7_walkthroughFromSection9() {
    var journal = Journal()
    journal.add(.onboardingLove, 1, [878, 28, 53])
    journal.add(.onboardingLove, 2, [18])
    journal.add(.onboardingLove, 3, [35])
    journal.add(.onboardingLove, 4, [27, 53])
    journal.add(.onboardingLove, 5, [16, 10751])
    var state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmA).probability, 0.714))
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.716))
    #expect(near(state.group(.comedy).point, 0.771))

    journal.add(.rate, 11, [878, 12], 92)
    state = journal.state()
    #expect(near(state.ratingMean, 0.7175))
    #expect(near(state.ratingSD, 0.2004, 0.0005))
    #expect(near(state.likeThreshold, 0.6338, 0.0005))
    #expect(near(state.effectiveCount, 3.727))
    #expect(near(TasteEngine.match(user: state, film: filmA).probability, 0.794))
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.731))

    journal.add(.rate, 12, [10749, 35], 35)
    state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmA).probability, 0.764))
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.596))
    #expect(near(state.group(.drama).point, 0.667))

    journal.add(.rate, 13, [18, 36], 61)
    state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.548))

    journal.add(.planLater, 14, [28, 80])
    state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmA).probability, 0.760))

    journal.add(.notInterested, 15, [10749, 18])
    state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.489))
    #expect(near(state.group(.drama).point, 0.578))

    journal.add(.watchedUnrated, 16, [878])
    state = journal.state()
    #expect(near(TasteEngine.match(user: state, film: filmA).probability, 0.751))
    #expect(near(TasteEngine.match(user: state, film: filmB).probability, 0.488))
    #expect(near(state.effectiveCount, 6.058))
    #expect(near(state.group(.drama).lower, 0.243))
    #expect(near(state.group(.drama).upper, 0.858))
    #expect(near(state.group(.drama).effective, 1.812))
}

@Test func t8_ratingScaleMigration() {
    #expect(LibraryMigration.scaled(0) == 1)
    #expect(LibraryMigration.scaled(1) == 10)
    #expect(LibraryMigration.scaled(7) == 70)
    #expect(LibraryMigration.scaled(10) == 100)
}

@Test func t9_tasteDrift() {
    let old = TasteEvent(kind: .rate, tmdbID: 300, value: 95, at: base, sequence: 1, axes: filmA.axes, genreIDs: filmA.genreIDs)
    let fresh = TasteEngine.rebuild(events: [old], now: base)
    let year = TasteEngine.rebuild(events: [old], now: base.addingTimeInterval(365 * 86_400))
    #expect(near(TasteEngine.match(user: fresh, film: filmA).probability, 0.780))
    #expect(near(TasteEngine.match(user: year, film: filmA).probability, 0.708))
    #expect(near(fresh.effectiveCount, 1.0))
    #expect(near(year.effectiveCount, 0.5))
}

@Test func t10_hideRule() {
    let day: TimeInterval = 86_400
    #expect(HideRule.isSuppressed(hiddenAt: base, now: base.addingTimeInterval(66 * day), currentProbability: 0.6))
    #expect(!HideRule.isSuppressed(hiddenAt: base, now: base.addingTimeInterval(67 * day), currentProbability: 0.6))
    #expect(HideRule.isSuppressed(hiddenAt: base, now: base.addingTimeInterval(3650 * day), currentProbability: 0.3))
}

@Test func t11_rebuildIsDeterministic() {
    var journal = Journal()
    journal.add(.onboardingLove, 1, [18])
    journal.add(.rate, 2, [878], 80)
    journal.add(.notInterested, 3, [27])
    journal.add(.rate, 2, [878], 40)
    journal.add(.planLater, 4, [35])
    let first = TasteEngine.rebuild(events: journal.events, now: now)
    let second = TasteEngine.rebuild(events: journal.events.reversed(), now: now)
    #expect(first == second)
}

@Test func t12_largeLibraryStaysFiniteAndFast() {
    var journal = Journal()
    let kinds: [[Int]] = [[878], [18], [35], [27, 53], [28, 12], [16], [99], [10749, 18]]
    for index in 0..<2000 {
        journal.add(.rate, 1000 + index, kinds[index % kinds.count], 1 + (index * 37) % 100)
    }
    let clock = ContinuousClock()
    var state = TasteState.empty
    let elapsed = clock.measure { state = journal.state() }
    let finite = state.mean.allSatisfy { $0.isFinite } && state.covariance.allSatisfy { $0.isFinite }
    #expect(finite)
    // В отладочной сборке без оптимизаций бюджет 200 мс (release) умножен на 10.
    #expect(elapsed < .milliseconds(2000))
}

@Test func t13_signalHierarchy() {
    typealias P = TasteParameters
    let love = P.onboardingLoveWeight * abs(P.onboardingLoveUtility)
    let refusal = P.notInterestedWeight * abs(P.notInterestedUtility)
    let later = P.planLaterWeight * abs(P.planLaterUtility)
    let unrated = P.watchedUnratedWeight * abs(P.watchedUnratedUtility)
    #expect(love > refusal)
    #expect(refusal > later)
    #expect(later > unrated)
    #expect(1 > P.onboardingRateWeight)
}

@Test func t14_rankingIsDeterministicAndAvoidsRejected() {
    var journal = Journal()
    journal.add(.notInterested, 1, [27, 53])
    journal.add(.notInterested, 2, [27])
    let state = journal.state()
    let horror = FilmFeatures(axes: FilmAxisHeuristic.axes(genreIDs: [27], keywords: [], runtimeMinutes: nil), genreIDs: [27])
    let comedy = FilmFeatures(axes: FilmAxisHeuristic.axes(genreIDs: [35], keywords: [], runtimeMinutes: nil), genreIDs: [35])
    let films = [(id: 10, features: horror), (id: 11, features: comedy)]
    let first = TasteEngine.rank(films, user: state, seed: 7)
    #expect(first == TasteEngine.rank(films, user: state, seed: 7))
    let horrorMatch = TasteEngine.match(user: state, film: horror).probability
    let comedyMatch = TasteEngine.match(user: state, film: comedy).probability
    #expect(horrorMatch < comedyMatch)
    let wins = (0..<50).filter { TasteEngine.rank(films, user: state, seed: $0).first == 11 }.count
    #expect(wins > 25)
}

@Test func ratingMoodSymbolsExist() {
    for mood in RatingMood.allCases {
        #expect(UIImage(systemName: mood.symbol) != nil, "\(mood.symbol)")
    }
    #expect(RatingMood(rating: 20) == .bad)
    #expect(RatingMood(rating: 21) == .neutral)
    #expect(RatingMood(rating: 60) == .good)
    #expect(RatingMood(rating: 61) == .great)
    #expect(RatingMood(rating: 81) == .goat)
}

@Test func horrorGenreMarksFilmAxesOnly() {
    let axes = FilmAxisHeuristic.axes(genreIDs: [27], keywords: [], runtimeMinutes: 110)
    #expect(abs((axes[.tension] ?? -1) - 0.85) < 0.001)
    #expect(abs((axes[.tone] ?? -1) - 0.25) < 0.001)
    #expect(axes[.humor] == nil)
    #expect(axes.count == 2)
}

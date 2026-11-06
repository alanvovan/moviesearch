//
//  FilmProfileTests.swift
//  MovieMatchTests
//

import Foundation
import Testing
@testable import MovieMatch

@Test func everyFamilyHasFiveAxes() {
    for family in GenreFamily.allCases {
        let spokes = family.spokes
        #expect(spokes.count == 5)
        #expect(Set(spokes.map(\.axis)).count == 5)
        #expect(spokes.allSatisfy { !$0.title.isEmpty && (0...1).contains($0.prior) })
    }
}

@Test func genreAloneEqualsTheFamilyPrior() throws {
    let ids: [GenreFamily: Int] = [
        .action: 28, .comedy: 35, .drama: 18, .suspense: 27, .speculative: 878, .documentary: 99,
    ]
    for (family, id) in ids {
        let profile = FilmAxisHeuristic.profile(film([id], keywords: [""], budget: 0, revenue: 0))
        #expect(profile.family == family)
        #expect(profile.axes.count == 5)
        for spoke in profile.spokes {
            let value = try #require(profile.axes[spoke.axis])
            #expect(abs(value - spoke.prior) < 0.000_001)
        }
    }
}

@Test func zeroBudgetMatchesAMissingBudget() {
    let zero = FilmAxisHeuristic.profile(film([28], budget: 0, revenue: 0))
    let missing = FilmAxisHeuristic.profile(film([28]))
    #expect(zero == missing)
}

@Test func primaryFamilyFollowsTheFixedPriority() {
    #expect(GenreFamily.resolve([27, 878]) == .suspense)
    #expect(GenreFamily.resolve([878, 28, 18]) == .speculative)
    #expect(GenreFamily.resolve([28, 35]) == .action)
    #expect(GenreFamily.resolve([35, 18]) == .comedy)
    #expect(GenreFamily.resolve([18, 99]) == .drama)
    #expect(GenreFamily.resolve([99]) == .documentary)
    #expect(GenreFamily.resolve([10770]) == .documentary)
    #expect(GenreFamily.resolve([]) == .documentary)
    #expect(GenreFamily.resolve([12345]) == .documentary)
    #expect(GenreFamily.resolve([53, 18]) == .suspense)
    #expect(GenreFamily.resolve([14, 16]) == .speculative)
    // Приключения старше комедии: Paddington 2 (приключения, комедия, семейный) попадает в экшен.
    #expect(GenreFamily.resolve([12, 35, 10751]) == .action)
    // Музыка старше драмы: «Одержимость» (драма, музыка) попадает в комедийное семейство.
    #expect(GenreFamily.resolve([18, 10402]) == .comedy)
}

@Test func eachListedGenreResolvesToItsFamily() {
    let expected: [Int: GenreFamily] = [
        28: .action, 12: .action, 10752: .action, 37: .action,
        35: .comedy, 10751: .comedy, 16: .comedy, 10402: .comedy,
        18: .drama, 10749: .drama, 36: .drama,
        27: .suspense, 53: .suspense, 9648: .suspense, 80: .suspense,
        878: .speculative, 14: .speculative,
        99: .documentary, 10770: .documentary,
    ]
    for (id, family) in expected {
        #expect(GenreFamily.resolve([id]) == family)
    }
}

@Test func keywordsOutsideTheFamilyStayOnThePrior() {
    let bare = FilmAxisHeuristic.profile(film([35]))
    let extra = FilmAxisHeuristic.profile(film([35], keywords: ["serial killer", "twist"]))
    #expect(extra.axes == bare.axes)
    #expect(extra.spokes.map(\.axis).count == 5)
}

@Test func olderBudgetIsWorthMoreAfterInflation() {
    let older = FilmAxisHeuristic.profile(film([28], budget: 20_000_000, year: 1981))
    let newer = FilmAxisHeuristic.profile(film([28], budget: 20_000_000, year: 2024))
    #expect(value(older, .spectacle) > value(newer, .spectacle))
}

@Test func adultRatingIsDarkerThanAChildRating() {
    let adult = FilmAxisHeuristic.profile(film([27], certification: "18+"))
    let child = FilmAxisHeuristic.profile(film([27], certification: "6+"))
    #expect(value(adult, .tone) < value(child, .tone))
    let adultGloom = 1 - value(adult, .tone)
    let childGloom = 1 - value(child, .tone)
    #expect(adultGloom > childGloom)
}

@Test func unknownCertificationDoesNotMoveTheTone() {
    let bare = FilmAxisHeuristic.profile(film([27]))
    let unknown = FilmAxisHeuristic.profile(film([27], certification: "XXX"))
    #expect(unknown.axes == bare.axes)
}

@Test func marvelIsLargerThanA24WhenBudgetIsMissing() {
    let marvel = FilmAxisHeuristic.profile(film([878], companies: ["Marvel Studios"]))
    let a24 = FilmAxisHeuristic.profile(film([878], companies: ["A24"]))
    #expect(value(marvel, .spectacle) > value(a24, .spectacle))
}

@Test func shortFilmIsFasterThanALongOne() {
    let short = FilmAxisHeuristic.profile(film([28], runtime: 80))
    let long = FilmAxisHeuristic.profile(film([28], runtime: 160))
    #expect(value(short, .tempo) > value(long, .tempo))
}

@Test func nicheHitCarriesMoreIdeasThanABareDocumentary() {
    let niche = FilmAxisHeuristic.profile(film(
        [99],
        voteAverage: 8.2,
        voteCount: 400,
        popularity: 4
    ))
    let bare = FilmAxisHeuristic.profile(film([99]))
    #expect(value(niche, .ideas) > value(bare, .ideas))
}

@Test func boxOfficeFillsInWhenBudgetIsMissing() {
    let rich = FilmAxisHeuristic.profile(film([28], revenue: 500_000_000, year: 2022))
    let broke = FilmAxisHeuristic.profile(film([28], revenue: 0, year: 2022))
    let prior = FilmAxisHeuristic.profile(film([28])).axes[.spectacle] ?? 0
    #expect(value(rich, .spectacle) > prior)
    #expect(abs(value(broke, .spectacle) - prior) < 0.000_001)
}

@Test func actionFilmsSeparateSpectacleTempoAndTone() {
    let topGun = FilmAxisHeuristic.profile(film(
        [28, 18],
        keywords: ["fighter pilot", "aircraft", "navy"],
        runtime: 131,
        certification: "PG-13",
        budget: 170_000_000,
        year: 2022,
        companies: ["Paramount", "Skydance"]
    ))
    let firstBlood = FilmAxisHeuristic.profile(film(
        [28],
        keywords: ["veteran", "revenge", "small town"],
        runtime: 93,
        certification: "R",
        budget: 14_000_000,
        year: 1982
    ))
    let raiders = FilmAxisHeuristic.profile(film(
        [12, 28],
        keywords: ["adventure", "treasure", "archaeologist"],
        runtime: 115,
        certification: "PG",
        budget: 18_000_000,
        year: 1981
    ))
    #expect(topGun.family == .action)
    #expect(firstBlood.family == .action)
    #expect(raiders.family == .action)
    #expect(value(topGun, .spectacle) > value(firstBlood, .spectacle))
    #expect(value(firstBlood, .tempo) > value(topGun, .tempo))
    #expect(value(firstBlood, .tone) < value(topGun, .tone))
    #expect(value(raiders, .tone) > value(firstBlood, .tone))
}

@Test func comediesSeparateHumorLightnessAndWarmth() {
    let superbad = FilmAxisHeuristic.profile(film(
        [35],
        keywords: ["comedy", "teen", "party"],
        runtime: 113,
        certification: "R",
        budget: 20_000_000,
        year: 2007
    ))
    let amelie = FilmAxisHeuristic.profile(film(
        [35, 10749],
        keywords: ["romantic comedy", "whimsical", "paris"],
        runtime: 122,
        certification: "PG",
        budget: 10_000_000,
        year: 2001
    ))
    let budapest = FilmAxisHeuristic.profile(film(
        [35, 18],
        keywords: ["comedy", "whimsical", "hotel"],
        runtime: 99,
        certification: "16+",
        budget: 25_000_000,
        year: 2014
    ))
    let priorHumor = GenreFamily.comedy.spokes.first { $0.axis == .humor }?.prior ?? 0
    #expect(superbad.family == .comedy)
    #expect(amelie.family == .comedy)
    #expect(budapest.family == .comedy)
    #expect(value(superbad, .humor) > priorHumor)
    #expect(value(amelie, .ideas) > value(superbad, .ideas))
    #expect(value(amelie, .intimacy) > value(superbad, .intimacy))
    #expect(value(superbad, .tone) < value(amelie, .tone))
    #expect(value(budapest, .ideas) > value(superbad, .ideas))
}

@Test func dramasSeparateWeightPaceAndCloseness() {
    let manchester = FilmAxisHeuristic.profile(film(
        [18],
        keywords: ["grief", "loss of loved one", "family"],
        runtime: 137,
        certification: "R",
        budget: 9_000_000,
        year: 2016
    ))
    let beforeSunrise = FilmAxisHeuristic.profile(film(
        [18, 10749],
        keywords: ["romance", "love", "dialogue"],
        runtime: 101,
        certification: "R",
        budget: 2_500_000,
        year: 1995
    ))
    let twelveAngry = FilmAxisHeuristic.profile(film(
        [18],
        keywords: ["courtroom", "jury", "dialogue"],
        runtime: 96,
        certification: "PG",
        year: 1957
    ))
    #expect(manchester.family == .drama)
    #expect(beforeSunrise.family == .drama)
    #expect(twelveAngry.family == .drama)
    #expect(value(manchester, .emotionalWeight) > value(beforeSunrise, .emotionalWeight))
    #expect(value(manchester, .emotionalWeight) > value(twelveAngry, .emotionalWeight))
    #expect(value(twelveAngry, .tempo) > value(manchester, .tempo))
    #expect(value(beforeSunrise, .intimacy) > value(twelveAngry, .intimacy))
    #expect(value(twelveAngry, .plotComplexity) > value(beforeSunrise, .plotComplexity))
}

@Test func suspenseFilmsSeparateDreadPaceAndCruelty() {
    let getOut = FilmAxisHeuristic.profile(film(
        [27, 9648, 53],
        keywords: ["twist", "hypnosis", "racism", "suspense"],
        runtime: 104,
        certification: "R",
        budget: 4_500_000,
        year: 2017,
        companies: ["Blumhouse"]
    ))
    let hereditary = FilmAxisHeuristic.profile(film(
        [27, 9648, 18],
        keywords: ["grief", "occult", "slow burn", "horror", "family"],
        runtime: 127,
        certification: "R",
        budget: 10_000_000,
        year: 2018,
        companies: ["A24"]
    ))
    let seven = FilmAxisHeuristic.profile(film(
        [80, 9648, 53],
        keywords: ["serial killer", "noir", "detective"],
        runtime: 127,
        certification: "R",
        budget: 33_000_000,
        year: 1995
    ))
    let knives = FilmAxisHeuristic.profile(film(
        [9648, 35, 18],
        keywords: ["whodunit", "family", "murder"],
        runtime: 130,
        certification: "PG-13",
        budget: 40_000_000,
        year: 2019
    ))
    let slasher = FilmAxisHeuristic.profile(film(
        [27],
        keywords: ["gore", "slasher", "killer"],
        runtime: 86,
        certification: "18+",
        budget: 250_000,
        year: 2022
    ))
    let parasite = FilmAxisHeuristic.profile(film(
        [35, 53, 18],
        keywords: ["twist", "class", "basement"],
        runtime: 132,
        certification: "R",
        year: 2019
    ))
    #expect(getOut.family == .suspense)
    #expect(hereditary.family == .suspense)
    #expect(seven.family == .suspense)
    #expect(knives.family == .suspense)
    #expect(slasher.family == .suspense)
    #expect(parasite.family == .suspense)
    #expect(value(getOut, .plotComplexity) > value(slasher, .plotComplexity))
    #expect(value(knives, .plotComplexity) > value(slasher, .plotComplexity))
    #expect(value(hereditary, .tempo) < value(getOut, .tempo))
    #expect(value(hereditary, .emotionalWeight) > value(getOut, .emotionalWeight))
    #expect(value(seven, .tone) < value(knives, .tone))
    #expect(value(parasite, .plotComplexity) > value(slasher, .plotComplexity))
}

@Test func speculativeFilmsSeparateScaleIdeasAndPace() {
    let arrival = FilmAxisHeuristic.profile(film(
        [878, 18],
        keywords: ["linguistics", "alien", "first contact"],
        runtime: 116,
        certification: "PG-13",
        budget: 47_000_000,
        year: 2016
    ))
    let dune = FilmAxisHeuristic.profile(film(
        [878, 12],
        keywords: ["desert", "epic", "empire", "space"],
        runtime: 155,
        certification: "PG-13",
        budget: 165_000_000,
        year: 2021,
        companies: ["Legendary"]
    ))
    let spirited = FilmAxisHeuristic.profile(film(
        [16, 10751, 14],
        keywords: ["spirit world", "mythology", "bathhouse"],
        runtime: 125,
        certification: "PG",
        budget: 19_000_000,
        year: 2001,
        companies: ["Studio Ghibli"]
    ))
    let blade = FilmAxisHeuristic.profile(film(
        [878, 18],
        keywords: ["android", "noir", "dystopia"],
        runtime: 164,
        certification: "R",
        budget: 150_000_000,
        year: 2017
    ))
    #expect(arrival.family == .speculative)
    #expect(dune.family == .speculative)
    #expect(spirited.family == .speculative)
    #expect(blade.family == .speculative)
    #expect(value(dune, .spectacle) > value(arrival, .spectacle))
    #expect(value(arrival, .tempo) > value(dune, .tempo))
    #expect(value(arrival, .ideas) > value(dune, .ideas))
    #expect(value(dune, .focusCharacterVsEvent) < value(arrival, .focusCharacterVsEvent))
    #expect(value(spirited, .focusCharacterVsEvent) < GenreFamily.speculative.spokes.first { $0.axis == .focusCharacterVsEvent }?.prior ?? 1)
    #expect(value(blade, .ideas) > value(dune, .ideas))
    #expect(value(blade, .tempo) < value(arrival, .tempo))
}

@Test func documentariesSeparateFeelingAndInformation() {
    let freeSolo = FilmAxisHeuristic.profile(film(
        [99],
        keywords: ["documentary", "rock climbing", "survival", "fear"],
        runtime: 100,
        certification: "PG-13",
        budget: 2_000_000,
        year: 2018
    ))
    let interviews = FilmAxisHeuristic.profile(film(
        [99],
        keywords: ["documentary", "interview", "archive footage"],
        runtime: 110,
        certification: "PG",
        year: 2015
    ))
    let penguins = FilmAxisHeuristic.profile(film(
        [99],
        keywords: ["documentary", "nature", "family", "survival"],
        runtime: 80,
        certification: "G",
        budget: 8_000_000,
        year: 2005
    ))
    let priorSpectacle = GenreFamily.documentary.spokes.first { $0.axis == .spectacle }?.prior ?? 1
    #expect(freeSolo.family == .documentary)
    #expect(interviews.family == .documentary)
    #expect(penguins.family == .documentary)
    #expect(value(freeSolo, .emotionalWeight) > value(interviews, .emotionalWeight))
    #expect(value(interviews, .plotComplexity) > value(freeSolo, .plotComplexity))
    #expect(value(freeSolo, .spectacle) < priorSpectacle)
    #expect(value(penguins, .tempo) > value(interviews, .tempo))
}

@Test func russianRatingBeatsTheAmericanOne() {
    let russia = TMDBCertification.preferred(regions: [
        (code: "RU", items: [(type: 3, text: "16+")]),
        (code: "US", items: [(type: 3, text: "R")]),
    ])
    let onlyUS = TMDBCertification.preferred(regions: [
        (code: "RU", items: [(type: 3, text: " ")]),
        (code: "US", items: [(type: 3, text: "R")]),
    ])
    let theatrical = TMDBCertification.preferred(regions: [
        (code: "RU", items: [(type: 1, text: "18+"), (type: 3, text: "16+")]),
    ])
    let none = TMDBCertification.preferred(regions: [
        (code: "FR", items: [(type: 3, text: "12")]),
    ])
    #expect(russia == "16+")
    #expect(onlyUS == "R")
    #expect(theatrical == "16+")
    #expect(none == nil)
}

@Test func movieTasteAxesMatchTheFamilyProfile() {
    var movie = TMDBMovie(
        id: 1,
        title: "Тест",
        overview: "",
        posterPath: nil,
        backdropPath: nil,
        releaseYear: 2020,
        genreIDs: [27],
        genreNames: ["ужасы"],
        keywords: [],
        runtime: nil,
        youtubeKey: nil,
        enriched: true
    )
    movie.budget = 0
    let profile = FilmAxisHeuristic.profile(FilmSignals(movie: movie))
    #expect(movie.tasteAxes == profile.axes)
    #expect(movie.tasteAxes.count == 5)
}

private func film(
    _ genres: [Int],
    keywords: [String] = [],
    runtime: Int? = nil,
    certification: String? = nil,
    budget: Double? = nil,
    revenue: Double? = nil,
    year: Int? = nil,
    companies: [String] = [],
    voteAverage: Double? = nil,
    voteCount: Int? = nil,
    popularity: Double? = nil
) -> FilmSignals {
    FilmSignals(
        genreIDs: genres,
        keywords: keywords,
        runtimeMinutes: runtime,
        certification: certification,
        budget: budget,
        revenue: revenue,
        releaseYear: year,
        voteAverage: voteAverage,
        voteCount: voteCount,
        popularity: popularity,
        productionCompanies: companies
    )
}

private func value(_ profile: FilmProfile, _ axis: TasteAxis) -> Double {
    profile.axes[axis] ?? -1
}

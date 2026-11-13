//
//  GenreGroupTests.swift
//  MovieMatchTests
//

import Foundation
import Testing
@testable import MovieMatch

private let listedIDs = [28, 12, 37, 35, 10751, 18, 10749, 878, 14, 53, 27, 9648, 80, 16, 36, 10752, 99, 10402, 10770]

@Test func genreGroup_everyListedIDBelongsToExactlyOneGroup() {
    for id in listedIDs {
        let owners = GenreGroup.allCases.filter { $0.genreIDs.contains(id) }
        #expect(owners.count == 1, "id \(id)")
    }
    let all = GenreGroup.allCases.flatMap(\.genreIDs)
    #expect(all.count == listedIDs.count)
}

@Test func genreGroup_multiGenreFilmSplitsByShare() {
    // Триллер + криминал + драма: 2/3 в «Триллеры и ужасы», 1/3 в «Драмы».
    let shares = GenreGroup.shares(for: [53, 80, 18])
    #expect(abs((shares[.suspense] ?? 0) - 2.0 / 3.0) < 1e-9)
    #expect(abs((shares[.drama] ?? 0) - 1.0 / 3.0) < 1e-9)
    #expect(shares[.action] == nil)
    #expect(abs(shares.values.reduce(0, +) - 1) < 1e-9)
}

@Test func genreGroup_unknownGenresGiveNoShares() {
    #expect(GenreGroup.shares(for: []).isEmpty)
    #expect(GenreGroup.shares(for: [99999]).isEmpty)
    #expect(GenreGroup.shares(for: [28, 99999]) == [.action: 1])
}

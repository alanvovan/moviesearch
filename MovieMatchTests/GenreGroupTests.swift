//
//  GenreGroupTests.swift
//  MovieMatchTests
//

import Foundation
import Testing
@testable import MovieMatch

private let listedIDs = [28, 12, 37, 35, 10751, 18, 10749, 878, 14, 53, 27, 9648, 80, 16, 36, 10752, 99, 10402, 10770]

private func item(_ genres: [Int], superliked: Bool = false) -> LibrarySnapshot.Item {
    LibrarySnapshot.Item(
        genreIDs: genres,
        userRating: nil,
        reviewText: "",
        status: superliked ? .superlike : .idea,
        superlikedAt: superliked ? .now : nil
    )
}

@Test func genreGroup_everyListedIDBelongsToExactlyOneGroup() {
    for id in listedIDs {
        let owners = GenreGroup.allCases.filter { $0.genreIDs.contains(id) }
        #expect(owners.count == 1, "id \(id)")
    }
    let all = GenreGroup.allCases.flatMap(\.genreIDs)
    #expect(all.count == listedIDs.count)
}

@Test func genreGroup_multiGenreFilmCountsOncePerGroup() {
    // Триллер + криминал + драма: одна запись в «Триллеры и ужасы», одна в «Драмы».
    let snapshot = LibrarySnapshot(items: [item([53, 80, 18]), item([18])])
    let shares = GenreGroup.shares(in: snapshot)
    #expect(shares[.drama] == 1)
    #expect(shares[.suspense] == 0.5)
    #expect(shares[.action] == nil)
}

@Test func genreGroup_sharesAreNormalizedAndSuperlikeWeighsDouble() {
    let snapshot = LibrarySnapshot(items: [item([28], superliked: true), item([35]), item([16]), item([99999])])
    let shares = GenreGroup.shares(in: snapshot)
    #expect(shares[.action] == 1)
    #expect(shares[.comedy] == 0.5)
    #expect(shares.values.allSatisfy { (0...1).contains($0) })
    #expect(GenreGroup.shares(in: LibrarySnapshot(items: [])).isEmpty)
}

//
//  Awards.swift
//  MovieMatch
//

import Foundation

nonisolated enum LibraryStatus: String, Codable, Equatable, Sendable {
    case idea
    case superlike
    case watched
    case unrated
}

nonisolated enum AwardID: String, CaseIterable, Codable, Equatable, Sendable {
    case firstRating
    case reviews10
    case reviews50
    case horror10
    case watched25
    case superlikes5
    case genres5

    var title: String {
        switch self {
        case .firstRating: "Первая оценка"
        case .reviews10: "10 отзывов"
        case .reviews50: "50 отзывов"
        case .horror10: "10 ужасов"
        case .watched25: "25 просмотренных"
        case .superlikes5: "5 суперлайков"
        case .genres5: "5 жанров"
        }
    }
}

nonisolated struct LibrarySnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var genreIDs: [Int]
        var userRating: Int?
        var reviewText: String
        var status: LibraryStatus
        var superlikedAt: Date?
    }

    var items: [Item]
}

nonisolated enum AwardEvaluator {
    static let horrorGenreID = 27

    static func unlocked(in snapshot: LibrarySnapshot) -> Set<AwardID> {
        let rated = snapshot.items.filter { $0.userRating != nil }
        let reviews = snapshot.items.filter {
            !$0.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var awards: Set<AwardID> = []
        if !rated.isEmpty { awards.insert(.firstRating) }
        if reviews.count >= 10 { awards.insert(.reviews10) }
        if reviews.count >= 50 { awards.insert(.reviews50) }
        if rated.filter({ $0.genreIDs.contains(horrorGenreID) }).count >= 10 {
            awards.insert(.horror10)
        }
        if snapshot.items.filter({ $0.status == .watched }).count >= 25 {
            awards.insert(.watched25)
        }
        if snapshot.items.filter({ $0.superlikedAt != nil }).count >= 5 {
            awards.insert(.superlikes5)
        }
        if Set(rated.flatMap(\.genreIDs)).count >= 5 {
            awards.insert(.genres5)
        }
        return awards
    }
}

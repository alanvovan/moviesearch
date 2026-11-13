//
//  GenreGroup.swift
//  MovieMatch
//

import Foundation

/// Восемь групп жанров для диаграммы профиля. Каждый id TMDB входит ровно в одну группу.
nonisolated enum GenreGroup: String, CaseIterable, Sendable, Equatable {
    case action
    case comedy
    case drama
    case speculative
    case suspense
    case animation
    case history
    case musicTV

    var title: String {
        switch self {
        case .action: "Боевики и приключения"
        case .comedy: "Комедии"
        case .drama: "Драмы и мелодрамы"
        case .speculative: "Фантастика и фэнтези"
        case .suspense: "Триллеры и ужасы"
        case .animation: "Мультфильмы"
        case .history: "Исторические и документальные"
        case .musicTV: "Музыкальные и телевизионные"
        }
    }

    var genreIDs: Set<Int> {
        switch self {
        case .action: [28, 12, 37]
        case .comedy: [35, 10751]
        case .drama: [18, 10749]
        case .speculative: [878, 14]
        case .suspense: [53, 27, 9648, 80]
        case .animation: [16]
        case .history: [36, 10752, 99]
        case .musicTV: [10402, 10770]
        }
    }

    static func groups(for genreIDs: [Int]) -> Set<GenreGroup> {
        Set(allCases.filter { !$0.genreIDs.isDisjoint(with: genreIDs) })
    }

    /// Доля жанров фильма в каждой группе: s_g = (жанры фильма из g) / (известные жанры фильма). Сумма 1 или 0.
    static func shares(for genreIDs: [Int]) -> [GenreGroup: Double] {
        let known = Set(genreIDs).compactMap { id in allCases.first { $0.genreIDs.contains(id) } }
        guard !known.isEmpty else { return [:] }
        var counts: [GenreGroup: Double] = [:]
        for group in known { counts[group, default: 0] += 1 }
        let total = Double(known.count)
        return counts.mapValues { $0 / total }
    }
}

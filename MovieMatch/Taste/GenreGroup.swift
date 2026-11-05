//
//  GenreGroup.swift
//  Prism
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

    static let superlikeWeight = 2.0

    /// Вес каждой группы по библиотеке, нормированный на самую частую группу (0...1).
    /// Фильм засчитывается в каждую свою группу один раз, суперлайк — с весом 2.
    static func shares(in snapshot: LibrarySnapshot) -> [GenreGroup: Double] {
        var totals: [GenreGroup: Double] = [:]
        for item in snapshot.items {
            let weight = item.superlikedAt != nil || item.status == .superlike ? superlikeWeight : 1
            for group in groups(for: item.genreIDs) {
                totals[group, default: 0] += weight
            }
        }
        let peak = totals.values.max() ?? 0
        guard peak > 0 else { return [:] }
        return totals.mapValues { $0 / peak }
    }
}

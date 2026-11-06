//
//  GenreFamily.swift
//  MovieMatch
//

import Foundation

/// Шесть семейств TMDB. У фильма одно основное семейство, у семейства ровно пять осей.
/// Ось диаграммы — это подпись поверх одной из десяти осей вкуса, а не отдельная модель.
nonisolated enum GenreFamily: String, CaseIterable, Sendable, Equatable {
    case suspense
    case speculative
    case action
    case comedy
    case drama
    case documentary

    var name: String {
        switch self {
        case .action: "Экшен и приключения"
        case .comedy: "Комедия и анимация"
        case .drama: "Драма"
        case .suspense: "Хоррор и триллер"
        case .speculative: "Фантастика и фэнтези"
        case .documentary: "Документальное"
        }
    }

    /// Драма, хоррор и документальное читаются антиквой, остальные — округлым гротеском.
    var usesSerif: Bool {
        switch self {
        case .drama, .suspense, .documentary: true
        case .action, .comedy, .speculative: false
        }
    }

    var spokes: [FamilySpoke] {
        switch self {
        case .action:
            return [
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.72),
                FamilySpoke(axis: .spectacle, title: "Зрелищность", inverted: false, prior: 0.70),
                FamilySpoke(axis: .tension, title: "Напряжение", inverted: false, prior: 0.58),
                FamilySpoke(axis: .tone, title: "Мрачность", inverted: true, prior: 0.42),
                FamilySpoke(axis: .plotComplexity, title: "Сложность сюжета", inverted: false, prior: 0.35),
            ]
        case .comedy:
            return [
                FamilySpoke(axis: .humor, title: "Юмор", inverted: false, prior: 0.78),
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.62),
                FamilySpoke(axis: .tone, title: "Лёгкость", inverted: false, prior: 0.72),
                FamilySpoke(axis: .intimacy, title: "Теплота", inverted: false, prior: 0.55),
                FamilySpoke(axis: .ideas, title: "Необычность", inverted: false, prior: 0.35),
            ]
        case .drama:
            return [
                FamilySpoke(axis: .emotionalWeight, title: "Эмоциональный вес", inverted: false, prior: 0.72),
                FamilySpoke(axis: .intimacy, title: "Близость", inverted: false, prior: 0.60),
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.38),
                FamilySpoke(axis: .plotComplexity, title: "Сложность сюжета", inverted: false, prior: 0.48),
                FamilySpoke(axis: .ideas, title: "Идеи", inverted: false, prior: 0.45),
            ]
        case .suspense:
            return [
                FamilySpoke(axis: .tension, title: "Напряжение", inverted: false, prior: 0.78),
                FamilySpoke(axis: .tone, title: "Мрачность", inverted: true, prior: 0.28),
                FamilySpoke(axis: .plotComplexity, title: "Сложность сюжета", inverted: false, prior: 0.55),
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.52),
                FamilySpoke(axis: .emotionalWeight, title: "Жёсткость", inverted: false, prior: 0.62),
            ]
        case .speculative:
            return [
                FamilySpoke(axis: .ideas, title: "Идеи", inverted: false, prior: 0.70),
                FamilySpoke(axis: .spectacle, title: "Зрелищность", inverted: false, prior: 0.62),
                FamilySpoke(axis: .plotComplexity, title: "Сложность сюжета", inverted: false, prior: 0.58),
                FamilySpoke(axis: .focusCharacterVsEvent, title: "Масштаб мира", inverted: true, prior: 0.40),
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.48),
            ]
        case .documentary:
            return [
                FamilySpoke(axis: .ideas, title: "Идеи", inverted: false, prior: 0.62),
                FamilySpoke(axis: .tempo, title: "Темп", inverted: false, prior: 0.35),
                FamilySpoke(axis: .emotionalWeight, title: "Эмоциональный вес", inverted: false, prior: 0.45),
                // В общем вкусе ближайшая ось — сложность. На диаграмме это информативность.
                FamilySpoke(axis: .plotComplexity, title: "Информативность", inverted: false, prior: 0.40),
                FamilySpoke(axis: .spectacle, title: "Камерность", inverted: true, prior: 0.28),
            ]
        }
    }

    /// Хоррор/триллер, затем фантастика, экшен, комедия, драма, документальное.
    /// Жанр вне таблицы и пустой список попадают в документальное.
    static func resolve(_ genreIDs: [Int]) -> GenreFamily {
        let present = Set(genreIDs.compactMap { genres[$0] })
        return priority.first { present.contains($0) } ?? .documentary
    }

    private static let priority: [GenreFamily] = [
        .suspense, .speculative, .action, .comedy, .drama, .documentary,
    ]

    private static let genres: [Int: GenreFamily] = [
        27: .suspense, 53: .suspense, 9648: .suspense, 80: .suspense,
        878: .speculative, 14: .speculative,
        28: .action, 12: .action, 10752: .action, 37: .action,
        35: .comedy, 10751: .comedy, 16: .comedy, 10402: .comedy,
        18: .drama, 10749: .drama, 36: .drama,
        99: .documentary, 10770: .documentary,
    ]
}

nonisolated struct FamilySpoke: Equatable, Sendable {
    var axis: TasteAxis
    var title: String
    /// Для подписи, которая смотрит в обратную сторону оси вкуса. На диаграмме 1 − значение.
    /// Матч по-прежнему сравнивает каноническое значение: |a − b| не меняется от разворота.
    var inverted: Bool
    /// Жанровая норма в каноническом направлении TasteAxis.
    var prior: Double
}

nonisolated struct FilmProfile: Equatable, Sendable {
    var family: GenreFamily
    var spokes: [FamilySpoke]
    var axes: [TasteAxis: Double]
}

nonisolated struct FilmSignals: Sendable, Equatable {
    var genreIDs: [Int]
    var keywords: [String] = []
    var runtimeMinutes: Int? = nil
    var certification: String? = nil
    var budget: Double? = nil
    var revenue: Double? = nil
    var releaseYear: Int? = nil
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
    var popularity: Double? = nil
    var productionCompanies: [String] = []
}

extension FilmSignals {
    init(movie: TMDBMovie) {
        self.init(
            genreIDs: movie.genreIDs,
            keywords: movie.keywords,
            runtimeMinutes: movie.runtime,
            certification: movie.certification,
            budget: movie.budget,
            revenue: movie.revenue,
            releaseYear: movie.releaseYear,
            voteAverage: movie.voteAverage,
            voteCount: movie.voteCount,
            popularity: movie.popularity,
            productionCompanies: movie.productionCompanies
        )
    }
}

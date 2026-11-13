//
//  TMDBModels.swift
//  MovieMatch
//

import Foundation
import Observation

nonisolated enum TMDBConfig {
    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

nonisolated enum TMDBImages {
    static func url(path: String?, size: String = "w780") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(suffix)")
    }
}

nonisolated enum TMDBGenreNames {
    static func labels(for ids: [Int]) -> [String] {
        ids.map { names[$0] ?? "жанр \($0)" }
    }

    static let names: [Int: String] = [
        28: "боевик",
        12: "приключения",
        16: "мультфильм",
        35: "комедия",
        80: "криминал",
        99: "документальный",
        18: "драма",
        10751: "семейный",
        14: "фэнтези",
        36: "история",
        27: "ужасы",
        10402: "музыка",
        9648: "детектив",
        10749: "мелодрама",
        878: "фантастика",
        10770: "телефильм",
        53: "триллер",
        10752: "военный",
        37: "вестерн",
    ]
}

nonisolated struct TMDBCastMember: Hashable, Sendable {
    var name: String
    var character: String?
    var profilePath: String?
}

/// Русские названия жанров из `/genre/movie/list`. До загрузки и при ошибке — статический `TMDBGenreNames`.
@MainActor
@Observable
final class TMDBGenreCatalog {
    static let shared = TMDBGenreCatalog()

    private(set) var names: [Int: String] = [:]
    private var loading = false

    func name(for id: Int) -> String {
        names[id] ?? TMDBGenreNames.names[id] ?? "жанр \(id)"
    }

    func loadIfNeeded(client: TMDBClient) async {
        guard names.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        if let fetched = try? await client.genreList(), !fetched.isEmpty {
            names = fetched
        }
    }
}

nonisolated enum TMDBError: Error {
    case missingAPIKey
    case transport
    case badStatus(Int)
    case decoding

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            "Нужен ключ TMDB"
        case .transport:
            "Нет сети. Проверьте подключение и попробуйте ещё раз."
        case .badStatus, .decoding:
            "Каталог сейчас не открывается. Попробуйте ещё раз."
        }
    }
}

/// Возрастной рейтинг из release_dates: театральный прокат страны, сначала RU, затем US.
nonisolated enum TMDBCertification {
    static func preferred(regions: [(code: String, items: [(type: Int, text: String)])]) -> String? {
        func best(_ code: String) -> String? {
            guard let region = regions.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) else {
                return nil
            }
            let filled = region.items.compactMap { item -> (Int, String)? in
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return (item.type, text)
            }
            return (filled.first { $0.0 == 3 } ?? filled.first)?.1
        }
        return best("RU") ?? best("US")
    }
}

nonisolated struct TMDBMovie: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseYear: Int?
    var genreIDs: [Int]
    var genreNames: [String]
    var keywords: [String]
    var runtime: Int?
    var youtubeKey: String?
    var enriched: Bool
    var certification: String? = nil
    var budget: Double? = nil
    var revenue: Double? = nil
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
    var popularity: Double? = nil
    var productionCountries: [String] = []
    var productionCompanies: [String] = []
    var tagline: String? = nil
    var director: String? = nil
    var cast: [TMDBCastMember] = []
    var originalLanguage: String? = nil
    var originalTitle: String? = nil

    var imagePath: String? { posterPath ?? backdropPath }
    var topCast: [String] { cast.map(\.name) }

    var tasteAxes: [TasteAxis: Double] {
        FilmAxisHeuristic.profile(FilmSignals(movie: self)).axes
    }

    var features: FilmFeatures {
        FilmFeatures(axes: tasteAxes, genreIDs: genreIDs, voteAverage: voteAverage, voteCount: voteCount)
    }
}

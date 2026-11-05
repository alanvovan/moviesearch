//
//  TMDBClient.swift
//  Prism
//

import Foundation

nonisolated struct TMDBClient: Sendable {
    var apiKey: String
    var session: URLSession = .shared

    static func live(session: URLSession = .shared) -> TMDBClient? {
        guard let apiKey = TMDBConfig.apiKey else { return nil }
        return TMDBClient(apiKey: apiKey, session: session)
    }

    func popular(page: Int) async throws -> [TMDBMovie] {
        try await fetchPage(path: "/movie/popular", page: page)
    }

    func topRated(page: Int) async throws -> [TMDBMovie] {
        try await fetchPage(path: "/movie/top_rated", page: page)
    }

    func discover(page: Int) async throws -> [TMDBMovie] {
        try await fetchPage(
            path: "/discover/movie",
            page: page,
            extra: [URLQueryItem(name: "sort_by", value: "popularity.desc")]
        )
    }

    func search(query: String) async throws -> [TMDBMovie] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await fetchPage(
            path: "/search/movie",
            page: 1,
            extra: [URLQueryItem(name: "query", value: trimmed)]
        )
    }

    func details(id: Int) async throws -> TMDBMovie {
        let payload: DetailPayload = try await get(
            path: "/movie/\(id)",
            query: [
                URLQueryItem(name: "append_to_response", value: "videos,keywords,release_dates,credits"),
                URLQueryItem(name: "include_video_language", value: "ru,en,null"),
            ]
        )
        return payload.movie()
    }

    func genreList() async throws -> [Int: String] {
        let payload: GenreListPayload = try await get(path: "/genre/movie/list", query: [])
        var result: [Int: String] = [:]
        for genre in payload.genres {
            let name = genre.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { result[genre.id] = name }
        }
        return result
    }

    private func fetchPage(path: String, page: Int, extra: [URLQueryItem] = []) async throws -> [TMDBMovie] {
        var query = extra
        query.append(URLQueryItem(name: "page", value: String(page)))
        let payload: PagePayload = try await get(path: path, query: query)
        return payload.results.compactMap { $0.movie() }
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard var components = URLComponents(string: "https://api.themoviedb.org/3\(path)") else {
            throw TMDBError.decoding
        }
        var items = query
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        items.append(URLQueryItem(name: "language", value: "ru-RU"))
        components.queryItems = items
        guard let url = components.url else { throw TMDBError.decoding }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TMDBError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw TMDBError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw TMDBError.badStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TMDBError.decoding
        }
    }
}

private nonisolated struct GenreListPayload: Decodable {
    struct Genre: Decodable {
        var id: Int
        var name: String
    }

    var genres: [Genre]
}

private nonisolated struct PagePayload: Decodable {
    var results: [ListPayload]

    struct ListPayload: Decodable {
        var id: Int
        var title: String
        var overview: String
        var posterPath: String?
        var backdropPath: String?
        var releaseYear: Int?
        var genreIDs: [Int]

        enum CodingKeys: String, CodingKey {
            case id, title, overview
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
            case releaseDate = "release_date"
            case genreIDs = "genre_ids"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
            posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
            backdropPath = try container.decodeIfPresent(String.self, forKey: .backdropPath)
            let date = try container.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
            releaseYear = Int(date.prefix(4))
            genreIDs = try container.decodeIfPresent([Int].self, forKey: .genreIDs) ?? []
        }

        func movie() -> TMDBMovie? {
            guard !title.isEmpty else { return nil }
            return TMDBMovie(
                id: id,
                title: title,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                releaseYear: releaseYear,
                genreIDs: genreIDs,
                genreNames: TMDBGenreNames.labels(for: genreIDs),
                keywords: [],
                runtime: nil,
                youtubeKey: nil,
                enriched: false
            )
        }
    }
}

private nonisolated struct DetailPayload: Decodable {
    var id: Int
    var title: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseYear: Int?
    var runtime: Int?
    var genres: [GenrePayload]
    var keywords: [String]
    var youtubeKey: String?
    var certification: String?
    var budget: Double?
    var revenue: Double?
    var voteAverage: Double?
    var voteCount: Int?
    var popularity: Double?
    var productionCountries: [String]
    var productionCompanies: [String]
    var tagline: String?
    var director: String?
    var cast: [TMDBCastMember]
    var originalLanguage: String?
    var originalTitle: String?

    struct GenrePayload: Decodable {
        var id: Int
        var name: String
    }

    struct KeywordPayload: Decodable {
        var name: String
    }

    struct KeywordBox: Decodable {
        var keywords: [KeywordPayload]
    }

    struct VideoPayload: Decodable {
        var key: String
        var site: String
        var type: String
        var official: Bool?
        var language: String?

        enum CodingKeys: String, CodingKey {
            case key, site, type, official
            case language = "iso_639_1"
        }
    }

    struct VideoBox: Decodable {
        var results: [VideoPayload]
    }

    struct NamedPayload: Decodable {
        var name: String?
    }

    struct ReleaseDatePayload: Decodable {
        var certification: String?
        var type: Int?
    }

    struct ReleaseRegionPayload: Decodable {
        var iso: String?
        var dates: [ReleaseDatePayload]?

        enum CodingKeys: String, CodingKey {
            case iso = "iso_3166_1"
            case dates = "release_dates"
        }
    }

    struct ReleaseBox: Decodable {
        var results: [ReleaseRegionPayload]?
    }

    struct CastPayload: Decodable {
        var name: String?
        var character: String?
        var order: Int?
        var profilePath: String?

        enum CodingKeys: String, CodingKey {
            case name, character, order
            case profilePath = "profile_path"
        }
    }

    struct CrewPayload: Decodable {
        var name: String?
        var job: String?
    }

    struct CreditsBox: Decodable {
        var cast: [CastPayload]?
        var crew: [CrewPayload]?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, keywords, videos, budget, revenue, popularity, tagline
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case productionCountries = "production_countries"
        case productionCompanies = "production_companies"
        case releaseDates = "release_dates"
        case credits
        case originalLanguage = "original_language"
        case originalTitle = "original_title"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try container.decodeIfPresent(String.self, forKey: .backdropPath)
        let date = try container.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
        releaseYear = Int(date.prefix(4))
        let minutes = try container.decodeIfPresent(Int.self, forKey: .runtime) ?? 0
        runtime = minutes > 0 ? minutes : nil
        genres = try container.decodeIfPresent([GenrePayload].self, forKey: .genres) ?? []
        keywords = try container.decodeIfPresent(KeywordBox.self, forKey: .keywords)?.keywords.map(\.name) ?? []
        let videos = try container.decodeIfPresent(VideoBox.self, forKey: .videos)?.results ?? []
        youtubeKey = Self.bestTrailer(in: videos)
        budget = Self.money(try container.decodeIfPresent(Double.self, forKey: .budget))
        revenue = Self.money(try container.decodeIfPresent(Double.self, forKey: .revenue))
        let count = try container.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
        if count > 0 {
            voteCount = count
            voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        } else {
            voteCount = nil
            voteAverage = nil
        }
        let buzz = try container.decodeIfPresent(Double.self, forKey: .popularity) ?? 0
        popularity = buzz > 0 ? buzz : nil
        productionCountries = Self.names(try container.decodeIfPresent([NamedPayload].self, forKey: .productionCountries))
        productionCompanies = Self.names(try container.decodeIfPresent([NamedPayload].self, forKey: .productionCompanies))
        tagline = Self.blankToNil(try container.decodeIfPresent(String.self, forKey: .tagline))
        originalLanguage = Self.blankToNil(try container.decodeIfPresent(String.self, forKey: .originalLanguage))
        originalTitle = Self.blankToNil(try container.decodeIfPresent(String.self, forKey: .originalTitle))
        let regions = try container.decodeIfPresent(ReleaseBox.self, forKey: .releaseDates)?.results ?? []
        certification = TMDBCertification.preferred(regions: regions.compactMap { region in
            guard let code = region.iso, !code.isEmpty else { return nil }
            let items = (region.dates ?? []).map { (type: $0.type ?? 0, text: $0.certification ?? "") }
            return (code: code, items: items)
        })
        let credits = try container.decodeIfPresent(CreditsBox.self, forKey: .credits)
        let directors = (credits?.crew ?? []).compactMap { member -> String? in
            guard member.job?.caseInsensitiveCompare("Director") == .orderedSame else { return nil }
            return Self.blankToNil(member.name)
        }
        director = directors.isEmpty ? nil : directors.joined(separator: ", ")
        cast = (credits?.cast ?? [])
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            .compactMap { member -> TMDBCastMember? in
                guard let name = Self.blankToNil(member.name) else { return nil }
                return TMDBCastMember(
                    name: name,
                    character: Self.blankToNil(member.character),
                    profilePath: Self.blankToNil(member.profilePath)
                )
            }
            .prefix(10)
            .map { $0 }
    }

    func movie() -> TMDBMovie {
        let ids = genres.map(\.id)
        let remoteNames = genres.map(\.name).filter { !$0.isEmpty }
        return TMDBMovie(
            id: id,
            title: title,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseYear: releaseYear,
            genreIDs: ids,
            genreNames: remoteNames.isEmpty ? TMDBGenreNames.labels(for: ids) : remoteNames,
            keywords: keywords,
            runtime: runtime,
            youtubeKey: youtubeKey,
            enriched: true,
            certification: certification,
            budget: budget,
            revenue: revenue,
            voteAverage: voteAverage,
            voteCount: voteCount,
            popularity: popularity,
            productionCountries: productionCountries,
            productionCompanies: productionCompanies,
            tagline: tagline,
            director: director,
            cast: cast,
            originalLanguage: originalLanguage,
            originalTitle: originalTitle
        )
    }

    private static func money(_ value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    private static func blankToNil(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func names(_ rows: [NamedPayload]?) -> [String] {
        (rows ?? []).compactMap { blankToNil($0.name) }
    }

    private static func bestTrailer(in videos: [VideoPayload]) -> String? {
        let youtube = videos.filter { $0.site.caseInsensitiveCompare("YouTube") == .orderedSame && !$0.key.isEmpty }
        let trailers = youtube.filter { $0.type.caseInsensitiveCompare("Trailer") == .orderedSame }
        let pool = trailers.isEmpty ? youtube : trailers
        func pick(_ language: String) -> VideoPayload? {
            let group = pool.filter { $0.language == language }
            return group.first { $0.official == true } ?? group.first
        }
        return pick("ru")?.key ?? pick("en")?.key ?? pool.first { $0.official == true }?.key ?? pool.first?.key
    }
}

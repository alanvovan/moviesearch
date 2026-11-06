//
//  StoredModels.swift
//  MovieMatch
//

import Foundation
import SwiftData

@Model
final class StoredMovie {
    @Attribute(.unique) var tmdbID: Int
    var title: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseYear: Int?
    var runtime: Int?
    var genreIDs: [Int]
    var genreNames: [String]
    var keywords: [String]
    var youtubeKey: String?
    var axisBlob: Data
    var statusRaw: String
    var userRating: Int?
    var reviewText: String
    var savedAt: Date
    var watchedAt: Date?
    var superlikedAt: Date?

    init(
        tmdbID: Int,
        title: String,
        overview: String,
        posterPath: String?,
        backdropPath: String?,
        releaseYear: Int?,
        runtime: Int?,
        genreIDs: [Int],
        genreNames: [String],
        keywords: [String],
        youtubeKey: String?,
        axes: [TasteAxis: Double],
        status: LibraryStatus,
        userRating: Int?,
        reviewText: String,
        savedAt: Date,
        watchedAt: Date?,
        superlikedAt: Date?
    ) {
        self.tmdbID = tmdbID
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseYear = releaseYear
        self.runtime = runtime
        self.genreIDs = genreIDs
        self.genreNames = genreNames
        self.keywords = keywords
        self.youtubeKey = youtubeKey
        self.axisBlob = AxisCoding.encode(axes)
        self.statusRaw = status.rawValue
        self.userRating = userRating
        self.reviewText = reviewText
        self.savedAt = savedAt
        self.watchedAt = watchedAt
        self.superlikedAt = superlikedAt
    }

    var status: LibraryStatus {
        get { LibraryStatus(rawValue: statusRaw) ?? .idea }
        set { statusRaw = newValue.rawValue }
    }

    var axes: [TasteAxis: Double] {
        get { AxisCoding.decode(axisBlob) }
        set { axisBlob = AxisCoding.encode(newValue) }
    }

    var hasReview: Bool {
        !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@Model
final class StoredTaste {
    var blob: Data

    init(blob: Data) {
        self.blob = blob
    }

    var state: TasteState {
        get { (try? JSONDecoder().decode(TasteState.self, from: blob)) ?? .empty }
        set { blob = (try? JSONEncoder().encode(newValue)) ?? blob }
    }
}

@Model
final class StoredHide {
    @Attribute(.unique) var tmdbID: Int
    var title: String
    var posterPath: String?
    var hiddenAt: Date
    var matchAtHide: Int

    init(tmdbID: Int, title: String, posterPath: String?, hiddenAt: Date, matchAtHide: Int) {
        self.tmdbID = tmdbID
        self.title = title
        self.posterPath = posterPath
        self.hiddenAt = hiddenAt
        self.matchAtHide = matchAtHide
    }
}

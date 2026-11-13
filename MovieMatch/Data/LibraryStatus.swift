//
//  LibraryStatus.swift
//  MovieMatch
//

import Foundation

/// idea — «Запланировано»; watched и unrated — «Просмотрено». Старое значение "superlike" читается как idea.
nonisolated enum LibraryStatus: String, Codable, Equatable, Sendable {
    case idea
    case watched
    case unrated

    var isWatched: Bool { self != .idea }
}

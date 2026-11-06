//
//  FilmAxisHeuristic.swift
//  MovieMatch
//

import Foundation

nonisolated enum FilmAxisHeuristic {
    /// heuristic: TMDB не отдаёт оси вкуса. Жанр размечает фильм, не пользователя.
    static func axes(genreIDs: [Int], keywords: [String], runtimeMinutes: Int?) -> [TasteAxis: Double] {
        var sums: [TasteAxis: Double] = [:]
        var counts: [TasteAxis: Double] = [:]
        for id in genreIDs {
            guard let table = genreAxes[id] else { continue }
            for (axis, value) in table {
                sums[axis, default: 0] += value
                counts[axis, default: 0] += 1
            }
        }

        var result: [TasteAxis: Double] = [:]
        for (axis, sum) in sums {
            result[axis] = sum / (counts[axis] ?? 1)
        }

        let lowered = keywords.map { $0.lowercased() }
        for nudge in keywordNudges {
            let hit = lowered.contains { keyword in
                nudge.needles.contains { keyword.contains($0) }
            }
            guard hit else { continue }
            if let current = result[nudge.axis] {
                result[nudge.axis] = clamp(current + nudge.delta)
            } else {
                result[nudge.axis] = clamp(0.55 + nudge.delta)
            }
        }

        if let runtime = runtimeMinutes, runtime >= 40 {
            if runtime < 90, let tempo = result[.tempo] {
                result[.tempo] = clamp(tempo + 0.15)
            } else if runtime > 150 {
                if let tempo = result[.tempo] {
                    result[.tempo] = clamp(tempo - 0.12)
                }
                if let emotion = result[.emotionalWeight] {
                    result[.emotionalWeight] = clamp(emotion + 0.1)
                }
            }
        }

        return result
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static let genreAxes: [Int: [TasteAxis: Double]] = [
        28: [.spectacle: 0.85, .tempo: 0.8, .tension: 0.55],
        12: [.spectacle: 0.75, .tempo: 0.65],
        16: [.spectacle: 0.6, .humor: 0.45],
        35: [.humor: 0.85, .tone: 0.72],
        80: [.tension: 0.6, .plotComplexity: 0.65],
        99: [.ideas: 0.8],
        18: [.emotionalWeight: 0.8, .focusCharacterVsEvent: 0.75, .intimacy: 0.45],
        10751: [.humor: 0.4, .tone: 0.7],
        14: [.spectacle: 0.7, .ideas: 0.45],
        36: [.ideas: 0.55, .emotionalWeight: 0.5],
        27: [.tone: 0.25, .tension: 0.85],
        10402: [.spectacle: 0.55, .emotionalWeight: 0.5],
        9648: [.plotComplexity: 0.75, .tension: 0.6, .ideas: 0.4],
        10749: [.intimacy: 0.85, .emotionalWeight: 0.65],
        878: [.ideas: 0.75, .spectacle: 0.6],
        53: [.tension: 0.8, .tempo: 0.7, .plotComplexity: 0.55],
        10752: [.emotionalWeight: 0.7, .spectacle: 0.65, .tension: 0.6],
        37: [.tone: 0.4, .spectacle: 0.5],
    ]

    private static let keywordNudges: [(needles: [String], axis: TasteAxis, delta: Double)] = [
        (["comedy", "parody", "satire", "dark comedy"], .humor, 0.2),
        (["psychological", "twist", "mind-bending", "mystery"], .plotComplexity, 0.15),
        (["psychological", "suspense"], .tension, 0.12),
        (["romance", "romantic", "love"], .intimacy, 0.18),
        (["philosophical", "philosophy", "dystopia", "existential"], .ideas, 0.18),
        (["war", "battle"], .spectacle, 0.1),
    ]
}

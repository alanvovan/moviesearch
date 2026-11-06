//
//  TasteEngine.swift
//  MovieMatch
//

import Foundation

nonisolated struct AxisVector: Equatable, Codable, Sendable {
    var components: [TasteAxis: Double]
    var weight: Double
}

nonisolated struct TasteState: Equatable, Codable, Sendable {
    var mean: [TasteAxis: Double]
    var weight: [TasteAxis: Double]
    var rejected: [AxisVector]
    var ratedCount: Int

    static let empty = TasteState(mean: [:], weight: [:], rejected: [], ratedCount: 0)
}

nonisolated enum TasteSignal: Equatable, Sendable {
    case rating(Int)
    case like
    case superlike
    case dislike
}

nonisolated enum PortraitConfidence: Equatable, Sendable {
    case thin
    case forming
    case steady

    static func resolve(_ state: TasteState) -> PortraitConfidence {
        if state.ratedCount < 4 { return .thin }
        let strong = state.weight.values.filter { $0 >= 1.2 }.count
        if state.ratedCount >= 8 && strong >= 4 { return .steady }
        return .forming
    }

    var sentence: String {
        switch self {
        case .thin: "Портрет ещё тонкий"
        case .forming: "Портрет складывается"
        case .steady: "Портрет устойчивый"
        }
    }

    var thinCaption: String { "портрет ещё тонкий" }
}

nonisolated struct MatchScore: Equatable, Sendable {
    var percent: Int
    var sharedAxes: Int
    var portrait: PortraitConfidence
}

nonisolated enum HideRule {
    static let window: TimeInterval = 21 * 24 * 60 * 60

    static func isSuppressed(hiddenAt: Date, matchAtHide: Int, now: Date, currentMatch: Int) -> Bool {
        let matured = now.timeIntervalSince(hiddenAt) >= window
        let grew = currentMatch >= matchAtHide + 15
        return !matured && !grew
    }
}

nonisolated enum TasteEngine {
    static let confidentWeight = 0.8
    private static let likeScale = 0.05
    private static let superlikeScale = 0.10

    static func apply(signal: TasteSignal, film: [TasteAxis: Double], to state: TasteState) -> TasteState {
        var state = state
        let film = clamp(film)
        switch signal {
        case .rating(let raw):
            let score = min(10, max(0, raw))
            switch score {
            case 7...10:
                pull(film, strength: strength(ofRating: score), into: &state)
            case 0...3:
                state.rejected.append(AxisVector(components: film, weight: 1))
            default:
                break
            }
            state.ratedCount += 1
        case .like:
            pull(film, strength: strength(ofRating: 8) * likeScale, into: &state)
        case .superlike:
            pull(film, strength: strength(ofRating: 8) * superlikeScale, into: &state)
        case .dislike:
            state.rejected.append(AxisVector(components: film, weight: 0.35))
        }
        return state
    }

    static func match(user: TasteState, film: [TasteAxis: Double]) -> MatchScore {
        let portrait = PortraitConfidence.resolve(user)
        let film = clamp(film)
        let shared = film.keys.filter { user.mean[$0] != nil }
        guard !shared.isEmpty else {
            return MatchScore(percent: 0, sharedAxes: 0, portrait: portrait)
        }
        let distance = shared.reduce(0.0) { partial, axis in
            partial + abs((user.mean[axis] ?? 0) - (film[axis] ?? 0))
        }
        let similarity = 1 - distance / Double(shared.count)
        var percent = (similarity - rejectionPenalty(user: user, film: film)) * 100
        if shared.count < 3 {
            percent *= 0.62
        }
        if user.ratedCount < 4 {
            percent *= Double(max(user.ratedCount, 0)) / 4
        }
        if percent < 0 { percent = 0 }
        let cap: Double = portrait == .thin ? 74 : 99
        if percent > cap { percent = cap }
        return MatchScore(percent: Int(percent.rounded()), sharedAxes: shared.count, portrait: portrait)
    }

    private static func strength(ofRating score: Int) -> Double {
        Double(abs(score - 5)) / 5
    }

    private static func pull(_ film: [TasteAxis: Double], strength: Double, into state: inout TasteState) {
        guard strength > 0 else { return }
        let step = 0.35 * strength
        for (axis, value) in film {
            let weight = state.weight[axis] ?? 0
            if weight == 0 {
                state.mean[axis] = value
                state.weight[axis] = strength
            } else {
                let alpha = min(1, step / (1 + weight))
                let previous = state.mean[axis] ?? value
                state.mean[axis] = previous + (value - previous) * alpha
                state.weight[axis] = weight + strength
            }
        }
    }

    private static func rejectionPenalty(user: TasteState, film: [TasteAxis: Double]) -> Double {
        var penalty = 0.0
        for rejected in user.rejected {
            let keys = rejected.components.keys.filter { film[$0] != nil }
            guard keys.count >= 2 else { continue }
            let distance = keys.reduce(0.0) { partial, axis in
                partial + abs((rejected.components[axis] ?? 0) - (film[axis] ?? 0))
            }
            let proximity = max(0, 1 - distance / Double(keys.count))
            penalty += proximity * rejected.weight * 0.15
        }
        return min(0.35, penalty)
    }

    private static func clamp(_ film: [TasteAxis: Double]) -> [TasteAxis: Double] {
        var result: [TasteAxis: Double] = [:]
        for (axis, value) in film where value.isFinite {
            result[axis] = min(1, max(0, value))
        }
        return result
    }
}

nonisolated enum AxisCoding {
    static func encode(_ axes: [TasteAxis: Double]) -> Data {
        (try? JSONEncoder().encode(axes)) ?? Data()
    }

    static func decode(_ data: Data) -> [TasteAxis: Double] {
        (try? JSONDecoder().decode([TasteAxis: Double].self, from: data)) ?? [:]
    }
}

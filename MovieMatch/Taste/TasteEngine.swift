//
//  TasteEngine.swift
//  MovieMatch
//
//  Реализация MATH_SPEC.md: байесовская линейная регрессия полезности по признакам фильма.
//

import Foundation

nonisolated enum TasteEventKind: String, Codable, Sendable, CaseIterable {
    case onboardingLove
    case onboardingRate
    case rate
    case planLater
    case notInterested
    case watchedUnrated
    case removeMovie
    case reset
}

nonisolated struct TasteEvent: Equatable, Sendable {
    var kind: TasteEventKind
    var tmdbID: Int
    var value: Int?
    var at: Date
    var sequence: Int
    var axes: [TasteAxis: Double]
    var genreIDs: [Int]

    init(
        kind: TasteEventKind,
        tmdbID: Int,
        value: Int? = nil,
        at: Date,
        sequence: Int,
        axes: [TasteAxis: Double] = [:],
        genreIDs: [Int] = []
    ) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.value = value
        self.at = at
        self.sequence = sequence
        self.axes = axes
        self.genreIDs = genreIDs
    }
}

nonisolated struct FilmFeatures: Equatable, Sendable {
    var axes: [TasteAxis: Double]
    var genreIDs: [Int]
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
}

/// Значение группы на диаграмме: медиана апостериорной вероятности «понравится» и 80% интервал.
nonisolated struct GroupValue: Equatable, Codable, Sendable {
    var point: Double
    var lower: Double
    var upper: Double
    var effective: Double

    var isWide: Bool {
        upper - lower > TasteParameters.diagramWideWidth || effective < TasteParameters.diagramMinEffective
    }
}

nonisolated struct TasteState: Equatable, Codable, Sendable {
    var mean: [Double]
    var covariance: [Double]
    var groups: [String: GroupValue]
    var ratingMean: Double
    var ratingSD: Double
    var likeThreshold: Double
    var effectiveCount: Double
    var ratedCount: Int
    var rejected: [[Double]]

    static let empty = TasteEngine.rebuild(events: [], now: Date(timeIntervalSince1970: 0))

    func group(_ group: GenreGroup) -> GroupValue {
        groups[group.rawValue] ?? GroupValue(point: 0.5, lower: 0, upper: 1, effective: 0)
    }

    var groupValues: [GenreGroup: GroupValue] {
        Dictionary(uniqueKeysWithValues: GenreGroup.allCases.map { ($0, group($0)) })
    }
}

nonisolated struct MatchScore: Equatable, Sendable {
    var probability: Double
    var lower: Double
    var upper: Double
    var isConfident: Bool

    var percent: Int { Int((probability * 100).rounded()) }
}

nonisolated enum TasteParameters {
    static let ratingPriorMean = 0.65
    static let ratingPriorSD = 0.20
    static let ratingMeanStrength = 3.0
    static let ratingVarianceStrength = 5.0
    static let ratingSDFloor = 0.05
    static let likeAnchor = 0.55
    static let utilityClip = 2.5
    static let noiseSD = 1.0
    static let halfLifeDays = 365.0

    static let onboardingRateWeight = 0.8
    static let onboardingLoveWeight = 0.6
    static let onboardingLoveUtility = 1.0
    static let onboardingDecayRatings = 10.0
    static let planLaterWeight = 0.25
    static let planLaterUtility = 0.5
    static let watchedUnratedWeight = 0.0
    static let watchedUnratedUtility = 0.3
    static let notInterestedWeight = 0.35
    static let notInterestedUtility = -1.0

    static let interceptPriorSD = 1.0
    static let linearPriorSD = 0.8
    static let quadraticPriorSD = 0.8
    static let groupPriorSD = 0.7
    static let axisNoiseSD = 0.15

    static let qualityWeight = 0.3
    static let qualityStrength = 5.0
    static let qualityVotePrior = 300.0
    static let qualityMean = 6.5
    static let qualityScale = 1.0

    static let credibleZ = 1.2816
    static let diagramStep = 0.15
    static let diagramWideWidth = 0.6
    static let diagramMinEffective = 2.0
    static let confidentEffective = 3.0
    static let confidentWidth = 0.4

    static let rejectedMemory = 50
    static let rejectPenalty = 0.2
    static let diversityPenalty = 0.15
}

nonisolated enum TasteEngine {
    static let axisOrder = TasteAxis.allCases
    static let groupOrder = GenreGroup.allCases
    static let dimension = 1 + 2 * axisOrder.count + groupOrder.count

    static func linearIndex(_ axis: Int) -> Int { 1 + axis }
    static func quadraticIndex(_ axis: Int) -> Int { 1 + axisOrder.count + axis }
    static func groupIndex(_ group: Int) -> Int { 1 + 2 * axisOrder.count + group }

    // MARK: Признаки

    static func encode(axes: [TasteAxis: Double], genreIDs: [Int]) -> [Double] {
        var phi = [Double](repeating: 0, count: dimension)
        phi[0] = 1
        for (index, axis) in axisOrder.enumerated() {
            guard let raw = axes[axis], raw.isFinite else { continue }
            let x = min(1, max(0, raw)) - 0.5
            phi[linearIndex(index)] = 2 * x
            phi[quadraticIndex(index)] = 4 * x * x - 1.0 / 3.0
        }
        let shares = GenreGroup.shares(for: genreIDs)
        for (index, group) in groupOrder.enumerated() {
            phi[groupIndex(index)] = shares[group] ?? 0
        }
        return phi
    }

    // MARK: Журнал

    static func ordered(_ events: [TasteEvent]) -> [TasteEvent] {
        events.sorted { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            return lhs.sequence < rhs.sequence
        }
    }

    /// Одно событие на фильм после последнего reset: последняя оценка, иначе последнее прочее событие.
    static func effective(_ events: [TasteEvent]) -> [TasteEvent] {
        let sorted = ordered(events)
        let start = (sorted.lastIndex { $0.kind == .reset }).map { $0 + 1 } ?? 0
        var rating: [Int: TasteEvent] = [:]
        var other: [Int: TasteEvent] = [:]
        for event in sorted[start...] {
            switch event.kind {
            case .rate, .onboardingRate:
                guard let value = event.value, (1...100).contains(value) else { continue }
                rating[event.tmdbID] = event
            case .removeMovie:
                rating[event.tmdbID] = nil
                other[event.tmdbID] = nil
            case .reset:
                continue
            case .onboardingLove, .planLater, .notInterested, .watchedUnrated:
                other[event.tmdbID] = event
            }
        }
        var result = Array(rating.values)
        for (id, event) in other where rating[id] == nil {
            result.append(event)
        }
        return ordered(result)
    }

    struct Observation {
        var event: TasteEvent
        var phi: [Double]
        var utility: Double
        var weight: Double
    }

    struct Normalization: Equatable {
        var mean: Double
        var sd: Double
        var threshold: Double
        var rated: Int
    }

    static func decay(_ at: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(at)) / 86_400
        return pow(2, -days / TasteParameters.halfLifeDays)
    }

    static func normalization(_ effective: [TasteEvent], now: Date) -> Normalization {
        typealias P = TasteParameters
        let ratings = effective.filter { $0.kind == .rate || $0.kind == .onboardingRate }
        var total = 0.0
        var sum = 0.0
        for event in ratings {
            let w = decay(event.at, now: now)
            total += w
            sum += w * Double(event.value ?? 50) / 100
        }
        let mean = (P.ratingMeanStrength * P.ratingPriorMean + sum) / (P.ratingMeanStrength + total)
        var squares = 0.0
        for event in ratings {
            let x = Double(event.value ?? 50) / 100
            squares += decay(event.at, now: now) * (x - mean) * (x - mean)
        }
        let variance = (P.ratingVarianceStrength * P.ratingPriorSD * P.ratingPriorSD + squares)
            / (P.ratingVarianceStrength + total)
        let sd = max(P.ratingSDFloor, variance.squareRoot())
        return Normalization(mean: mean, sd: sd, threshold: (mean + P.likeAnchor) / 2, rated: ratings.count)
    }

    static func utility(rating: Int, normalization: Normalization) -> Double {
        let x = Double(rating) / 100
        let u = (x - normalization.threshold) / normalization.sd
        return min(TasteParameters.utilityClip, max(-TasteParameters.utilityClip, u))
    }

    static func observations(_ events: [TasteEvent], now: Date) -> ([Observation], Normalization) {
        typealias P = TasteParameters
        let effective = effective(events)
        let norm = normalization(effective, now: now)
        let observations = effective.map { event -> Observation in
            let phi = encode(axes: event.axes, genreIDs: event.genreIDs)
            let time = decay(event.at, now: now)
            let utility: Double
            let base: Double
            switch event.kind {
            case .rate:
                utility = self.utility(rating: event.value ?? 50, normalization: norm)
                base = 1
            case .onboardingRate:
                utility = self.utility(rating: event.value ?? 50, normalization: norm)
                base = P.onboardingRateWeight
            case .onboardingLove:
                utility = P.onboardingLoveUtility
                base = P.onboardingLoveWeight * P.onboardingDecayRatings / (P.onboardingDecayRatings + Double(norm.rated))
            case .planLater:
                utility = P.planLaterUtility
                base = P.planLaterWeight
            case .watchedUnrated:
                utility = P.watchedUnratedUtility
                base = P.watchedUnratedWeight
            case .notInterested:
                utility = P.notInterestedUtility
                base = P.notInterestedWeight
            case .removeMovie, .reset:
                utility = 0
                base = 0
            }
            return Observation(event: event, phi: phi, utility: utility, weight: base * time)
        }
        return (observations, norm)
    }

    // MARK: Апостериор

    static func priorSD(_ index: Int) -> Double {
        typealias P = TasteParameters
        if index == 0 { return P.interceptPriorSD }
        if index <= axisOrder.count { return P.linearPriorSD }
        if index <= 2 * axisOrder.count { return P.quadraticPriorSD }
        return P.groupPriorSD
    }

    struct Posterior {
        var mean: [Double]
        var covariance: [Double]
    }

    static func posterior(_ observations: [Observation]) -> Posterior {
        let n = dimension
        let noise = TasteParameters.noiseSD * TasteParameters.noiseSD
        var precision = [Double](repeating: 0, count: n * n)
        var b = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let sd = priorSD(i)
            precision[i * n + i] = 1 / (sd * sd)
        }
        for observation in observations where observation.weight > 0 {
            let c = observation.weight / noise
            let phi = observation.phi
            let active = phi.indices.filter { phi[$0] != 0 }
            for i in active {
                b[i] += c * observation.utility * phi[i]
                let scaled = c * phi[i]
                for j in active {
                    precision[i * n + j] += scaled * phi[j]
                }
            }
        }
        let l = TasteMath.cholesky(precision, size: n)
        return Posterior(
            mean: TasteMath.solve(cholesky: l, size: n, b),
            covariance: TasteMath.inverse(cholesky: l, size: n)
        )
    }

    static func groupValue(_ index: Int, posterior: Posterior, observations: [Observation]) -> GroupValue {
        // Evaluate actual genre prototypes, not an impossible film with all axes zero.
        let group = groupOrder[index]
        let prototypes = group.genreIDs.sorted().map { id in
            encode(axes: FilmAxisHeuristic.axes(genreIDs: [id], keywords: [], runtimeMinutes: nil), genreIDs: [id])
        }
        let values = prototypes.map { phi -> (Double, Double, Double) in
            let mean = TasteMath.dot(posterior.mean, phi)
            let variance = max(0, TasteMath.quadratic(posterior.covariance, size: dimension, phi))
            let spread = TasteParameters.credibleZ * variance.squareRoot()
            let sigma = TasteParameters.noiseSD
            return (TasteMath.normalCDF(mean / (sigma * sigma + variance).squareRoot()),
                    TasteMath.normalCDF((mean - spread) / sigma),
                    TasteMath.normalCDF((mean + spread) / sigma))
        }
        let count = Double(values.count)
        return GroupValue(
            point: values.reduce(0) { $0 + $1.0 } / count,
            lower: values.map { $0.1 }.min() ?? 0,
            upper: values.map { $0.2 }.max() ?? 1,
            effective: observations.reduce(0) { $0 + $1.weight * $1.phi[groupIndex(index)] }
        )
    }

    // MARK: Пересчёт

    /// Профиль — детерминированная функция журнала и момента пересчёта.
    static func rebuild(events: [TasteEvent], now: Date) -> TasteState {
        raw(ordered(events), now: now)
    }

    static func raw(_ events: [TasteEvent], now: Date) -> TasteState {
        let (observations, norm) = observations(events, now: now)
        let posterior = posterior(observations)
        var groups: [String: GroupValue] = [:]
        for (index, group) in groupOrder.enumerated() {
            groups[group.rawValue] = groupValue(index, posterior: posterior, observations: observations)
        }
        let rejected = observations
            .filter { $0.event.kind == .notInterested }
            .suffix(TasteParameters.rejectedMemory)
            .map(\.phi)
        return TasteState(
            mean: posterior.mean,
            covariance: posterior.covariance,
            groups: groups,
            ratingMean: norm.mean,
            ratingSD: norm.sd,
            likeThreshold: norm.threshold,
            effectiveCount: observations.reduce(0) { $0 + $1.weight },
            ratedCount: norm.rated,
            rejected: Array(rejected)
        )
    }

    // MARK: Совпадение

    static func qualityOffset(_ film: FilmFeatures, effectiveCount: Double) -> Double {
        typealias P = TasteParameters
        guard let average = film.voteAverage, let count = film.voteCount, count > 0, average.isFinite else { return 0 }
        let votes = Double(count)
        let bayes = (votes * average + P.qualityVotePrior * P.qualityMean) / (votes + P.qualityVotePrior)
        let centered = min(2, max(-2, (bayes - P.qualityMean) / P.qualityScale))
        return P.qualityWeight * P.qualityStrength / (P.qualityStrength + effectiveCount) * centered
    }

    /// Латентная полезность фильма: среднее и дисперсия (апостериор + шум разметки осей).
    static func latent(user: TasteState, film: FilmFeatures) -> (mean: Double, variance: Double) {
        let n = dimension
        guard user.mean.count == n, user.covariance.count == n * n else { return (0, 1) }
        let phi = encode(axes: film.axes, genreIDs: film.genreIDs)
        let m = user.mean
        let c = user.covariance
        var mean = TasteMath.dot(m, phi) + qualityOffset(film, effectiveCount: user.effectiveCount)
        var variance = TasteMath.quadratic(c, size: n, phi)
        let noise = TasteParameters.axisNoiseSD * TasteParameters.axisNoiseSD
        for (index, axis) in axisOrder.enumerated() {
            let li = linearIndex(index)
            let qi = quadraticIndex(index)
            if let raw = film.axes[axis], raw.isFinite {
                let x = min(1, max(0, raw)) - 0.5
                let gradient = 2 * m[li] + 8 * x * m[qi]
                variance += gradient * gradient * noise
            } else {
                variance += m[li] * m[li] / 3 + m[qi] * m[qi] * 4 / 45
            }
        }
        if !mean.isFinite { mean = 0 }
        return (mean, max(0, variance.isFinite ? variance : 1))
    }

    static func match(user: TasteState, film: FilmFeatures) -> MatchScore {
        typealias P = TasteParameters
        let (mean, variance) = latent(user: user, film: film)
        let sigma = P.noiseSD
        let spread = variance.squareRoot()
        let probability = TasteMath.normalCDF(mean / (sigma * sigma + variance).squareRoot())
        let lower = TasteMath.normalCDF((mean - P.credibleZ * spread) / sigma)
        let upper = TasteMath.normalCDF((mean + P.credibleZ * spread) / sigma)
        let confident = user.effectiveCount >= P.confidentEffective && upper - lower <= P.confidentWidth
        return MatchScore(probability: probability, lower: lower, upper: upper, isConfident: confident)
    }

    // MARK: Ранжирование

    private static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for i in 1..<min(a.count, b.count) {
            let isQuadratic = i > axisOrder.count && i <= 2 * axisOrder.count
            if isQuadratic { continue }
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 1e-9, nb > 1e-9 else { return 0 }
        return dot / (na * nb).squareRoot()
    }

    /// Ограниченное исследование + штраф за близость к отвергнутому + MMR. Возвращает id в порядке показа.
    static func rank(_ films: [(id: Int, features: FilmFeatures)], user: TasteState, seed: Int) -> [Int] {
        typealias P = TasteParameters
        let candidates = films.map { film -> (id: Int, phi: [Double], score: Double) in
            let phi = encode(axes: film.features.axes, genreIDs: film.features.genreIDs)
            let (mean, variance) = latent(user: user, film: film.features)
            let key = UInt64(bitPattern: Int64(film.id)) &* 0x9E37_79B9 ^ UInt64(bitPattern: Int64(seed))
            let sample = mean + 0.1 * variance.squareRoot() * max(-1, min(1, TasteMath.gaussian(seed: key)))
            let rejected = user.rejected.map { similarity(phi, $0) }.max() ?? 0
            let score = TasteMath.normalCDF(sample / P.noiseSD) - P.rejectPenalty * max(0, rejected)
            return (film.id, phi, score)
        }
        var remaining = candidates
        var picked: [(id: Int, phi: [Double], score: Double)] = []
        while !remaining.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (index, candidate) in remaining.enumerated() {
                let near = picked.map { similarity(candidate.phi, $0.phi) }.max() ?? 0
                let value = candidate.score - P.diversityPenalty * max(0, near)
                if value > bestValue || (value == bestValue && candidate.id < remaining[bestIndex].id) {
                    bestValue = value
                    bestIndex = index
                }
            }
            picked.append(remaining.remove(at: bestIndex))
        }
        return picked.map(\.id)
    }
}

/// Повторный показ «не интересно»: вероятность, что отказ ещё в силе, затухает с периодом 60 дней.
nonisolated enum HideRule {
    static let initialRefusal = 0.9
    static let halfLifeDays = 60.0
    static let offerThreshold = 0.35

    static func refusal(hiddenAt: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(hiddenAt)) / 86_400
        return initialRefusal * pow(2, -days / halfLifeDays)
    }

    static func isSuppressed(hiddenAt: Date, now: Date, currentProbability: Double) -> Bool {
        (1 - refusal(hiddenAt: hiddenAt, now: now)) * currentProbability < offerThreshold
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

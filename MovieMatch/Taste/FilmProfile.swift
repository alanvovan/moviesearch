//
//  FilmProfile.swift
//  MovieMatch
//

import Foundation

extension FilmAxisHeuristic {
    /// Пять осей семейства. Нет сигнала — ось равна prior, значение не выдумывается.
    static func profile(_ signals: FilmSignals) -> FilmProfile {
        let family = GenreFamily.resolve(signals.genreIDs)
        let allowed = Set(family.spokes.map(\.axis))
        var weighted: [TasteAxis: (sum: Double, weight: Double)] = [:]

        func add(_ axis: TasteAxis, _ value: Double, _ weight: Double) {
            guard allowed.contains(axis), weight > 0, value.isFinite else { return }
            let clamped = min(1, max(0, value))
            var slot = weighted[axis] ?? (sum: 0, weight: 0)
            slot.sum += weight * clamped
            slot.weight += weight
            weighted[axis] = slot
        }

        addKeywords(signals.keywords, add: add)
        if let tempo = tempoSignal(signals.runtimeMinutes) {
            add(.tempo, tempo, Weights.runtime)
        }
        if let harsh = harshness(signals.certification) {
            // Сертификация: чем старше рейтинг, тем ниже тон (мрачнее) и выше жёсткость.
            add(.tone, 1 - harsh, Weights.certificationTone)
            add(.emotionalWeight, 0.22 + 0.75 * harsh, Weights.certificationHarshness)
        }
        if let money = presentMoney(signals.budget) {
            add(.spectacle, moneySignal(money, year: signals.releaseYear), Weights.budget)
        } else if let money = presentMoney(signals.revenue) {
            // Сборы заменяют бюджет, только когда бюджета нет: иначе один и тот же масштаб считается дважды.
            add(.spectacle, moneySignal(money, year: signals.releaseYear), Weights.revenueFallback)
        }
        addStudio(signals.productionCompanies, add: add)
        if let popularity = signals.popularity, popularity > 0 {
            add(.spectacle, popularitySignal(popularity), Weights.popularity)
        }
        if let niche = nicheIdeas(signals) {
            add(.ideas, niche, Weights.nicheIdeas)
        }

        var axes: [TasteAxis: Double] = [:]
        for spoke in family.spokes {
            if let slot = weighted[spoke.axis], slot.weight > 0 {
                let mixed = (slot.sum + Weights.prior * spoke.prior) / (slot.weight + Weights.prior)
                axes[spoke.axis] = min(1, max(0, mixed))
            } else {
                axes[spoke.axis] = spoke.prior
            }
        }
        return FilmProfile(family: family, spokes: family.spokes, axes: axes)
    }

    private enum Weights {
        /// Жанр не отдельное наблюдение, а prior. 1.35 держит норму, но отпускает её при двух-трёх сигналах.
        static let prior = 1.35
        /// Один совпавший ключ TMDB. Вес растёт до трёх разных ключей на ось.
        static let keywordHit = 0.5
        static let keywordHitCap = 3
        /// Длительность. Короче 85 минут быстрее, длиннее 150 медленнее. Ниже 40 минут сигнала нет.
        static let runtime = 0.8
        /// Возрастной рейтинг RU, иначе US. Тянет тон.
        static let certificationTone = 0.7
        /// Тот же рейтинг, слабее, тянет жёсткость через эмоциональный вес.
        static let certificationHarshness = 0.45
        /// Бюджет в долларах 2026 года, логарифм от $1 млн до ~$250 млн.
        static let budget = 1.1
        static let revenueFallback = 0.7
        /// Студия: крупная площадка или камерный лейбл. Один сигнал, без суммирования с каждой компанией.
        static let studio = 0.5
        /// Популярность TMDB, слабый признак масштаба.
        static let popularity = 0.25
        /// Высокая байесовская оценка при popularity < 25. Мало голосов не считается.
        static let nicheIdeas = 0.7
        /// Грубая замена CPI: 3% в год к долларам 2026.
        static let inflationPerYear = 1.03
        static let inflationTargetYear = 2026
    }

    private struct KeywordRule {
        var needles: [String]
        var axis: TasteAxis
        var signal: Double
    }

    /// Ключи TMDB на английском. Сигнал — абсолютное значение оси, не прибавка к жанру.
    private static let keywordRules: [KeywordRule] = [
        KeywordRule(needles: ["chase", "heist", "gunfight", "martial arts", "car chase", "fighter pilot", "aircraft"], axis: .tempo, signal: 0.82),
        KeywordRule(needles: ["adventure"], axis: .tempo, signal: 0.74),
        KeywordRule(needles: ["party"], axis: .tempo, signal: 0.70),
        KeywordRule(needles: ["slow burn", "contemplative", "slice of life"], axis: .tempo, signal: 0.22),
        KeywordRule(needles: ["suspense", "slasher", "serial killer", "haunting", "occult", "revenge", "murder"], axis: .tension, signal: 0.86),
        KeywordRule(needles: ["horror"], axis: .tension, signal: 0.84),
        KeywordRule(needles: ["twist", "mind-bending", "nonlinear", "time loop", "conspiracy", "whodunit", "courtroom"], axis: .plotComplexity, signal: 0.86),
        KeywordRule(needles: ["detective", "mystery", "jury"], axis: .plotComplexity, signal: 0.68),
        KeywordRule(needles: ["comedy", "parody", "satire", "slapstick", "dark comedy", "romantic comedy"], axis: .humor, signal: 0.90),
        KeywordRule(needles: ["romance", "romantic", "marriage", "relationship"], axis: .intimacy, signal: 0.84),
        KeywordRule(needles: ["love"], axis: .intimacy, signal: 0.80),
        KeywordRule(needles: ["grief", "tragedy", "mourning", "holocaust", "loss of loved one"], axis: .emotionalWeight, signal: 0.90),
        KeywordRule(needles: ["gore", "torture", "slasher", "serial killer"], axis: .emotionalWeight, signal: 0.86),
        KeywordRule(needles: ["survival", "fear"], axis: .emotionalWeight, signal: 0.76),
        KeywordRule(needles: ["dystopia", "bleak", "nihilism", "gothic", "darkness", "occult"], axis: .tone, signal: 0.16),
        KeywordRule(needles: ["noir", "dark"], axis: .tone, signal: 0.20),
        KeywordRule(needles: ["feel-good", "uplifting", "lighthearted", "whimsical"], axis: .tone, signal: 0.84),
        KeywordRule(needles: ["superhero", "space opera", "explosion", "alien invasion"], axis: .spectacle, signal: 0.88),
        KeywordRule(needles: ["epic", "battle"], axis: .spectacle, signal: 0.80),
        KeywordRule(needles: ["independent film", "mumblecore", "slice of life"], axis: .spectacle, signal: 0.18),
        KeywordRule(needles: ["philosophy", "philosophical", "existential", "artificial intelligence", "time travel", "linguistics", "first contact"], axis: .ideas, signal: 0.86),
        KeywordRule(needles: ["dystopia"], axis: .ideas, signal: 0.80),
        KeywordRule(needles: ["whimsical"], axis: .ideas, signal: 0.72),
        KeywordRule(needles: ["character study", "coming of age", "biography"], axis: .focusCharacterVsEvent, signal: 0.82),
        KeywordRule(needles: ["space opera", "parallel universe", "mythology", "spirit world"], axis: .focusCharacterVsEvent, signal: 0.22),
        KeywordRule(needles: ["alien", "empire", "space", "apocalypse"], axis: .focusCharacterVsEvent, signal: 0.28),
        KeywordRule(needles: ["documentary", "interview", "archive footage"], axis: .plotComplexity, signal: 0.78),
    ]

    private static let spectacleStudios = [
        "marvel", "lucasfilm", "disney", "pixar", "dreamworks", "legendary",
        "dc films", "dc studios", "warner", "paramount", "universal", "columbia", "20th century",
    ]

    private static let intimateStudios = [
        "a24", "neon", "bbc film", "searchlight", "focus features", "annapurna", "plan b entertainment",
    ]

    private static func addKeywords(_ keywords: [String], add: (TasteAxis, Double, Double) -> Void) {
        let lowered = keywords.map { $0.lowercased() }
        var hits: [TasteAxis: [Double]] = [:]
        for rule in keywordRules {
            for needle in rule.needles where lowered.contains(where: { matches($0, needle: needle) }) {
                hits[rule.axis, default: []].append(rule.signal)
            }
        }
        for (axis, values) in hits where !values.isEmpty {
            let count = min(values.count, Weights.keywordHitCap)
            let average = values.reduce(0, +) / Double(values.count)
            add(axis, average, Weights.keywordHit * Double(count))
        }
    }

    private static func addStudio(_ companies: [String], add: (TasteAxis, Double, Double) -> Void) {
        let names = companies.map { $0.lowercased() }
        let big = names.contains { name in spectacleStudios.contains { name.contains($0) } }
        let small = names.contains { name in intimateStudios.contains { name.contains($0) } }
        if big, !small {
            add(.spectacle, 0.86, Weights.studio)
        } else if small, !big {
            add(.spectacle, 0.18, Weights.studio)
        }
    }

    private static func matches(_ keyword: String, needle: String) -> Bool {
        let tokens = keyword.tokens
        let needleTokens = needle.tokens
        guard !needleTokens.isEmpty, needleTokens.count <= tokens.count else { return false }
        let width = needleTokens.count
        for index in 0...(tokens.count - width) {
            if Array(tokens[index..<(index + width)]) == needleTokens { return true }
        }
        return false
    }

    private static func tempoSignal(_ minutes: Int?) -> Double? {
        guard let minutes, minutes >= 40 else { return nil }
        switch minutes {
        case ..<85: return 0.84
        case 85..<100: return 0.70
        case 100..<115: return 0.56
        case 115..<130: return 0.45
        case 130..<150: return 0.34
        default: return 0.22
        }
    }

    private static func harshness(_ certification: String?) -> Double? {
        guard let certification else { return nil }
        let compact = certification
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch compact {
        case "G", "U", "AL", "0+", "TVY", "TVG": return 0.08
        case "PG", "6+", "7+", "TVPG", "TVY7": return 0.28
        case "12+", "12A", "PG13", "TV14": return 0.50
        case "15+", "16+", "R", "18A": return 0.72
        case "18+", "NC17", "TVMA", "X": return 0.90
        default: return nil
        }
    }

    private static func presentMoney(_ value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    private static func moneySignal(_ dollars: Double, year: Int?) -> Double {
        let adjusted = dollars * inflationFactor(year: year)
        let span = (log10(max(adjusted, 1)) - 6.0) / 2.4
        return min(1, max(0, 0.12 + 0.88 * span))
    }

    private static func inflationFactor(year: Int?) -> Double {
        guard let year else { return 1 }
        let clamped = min(Weights.inflationTargetYear, max(1920, year))
        return pow(Weights.inflationPerYear, Double(Weights.inflationTargetYear - clamped))
    }

    private static func popularitySignal(_ popularity: Double) -> Double {
        let span = (log10(max(popularity, 1)) - 0.3) / 2.3
        return min(1, max(0, span))
    }

    /// C = 6.6, m = 400. Нишевость есть только при posterior ≥ 7.3 и popularity < 25.
    private static func nicheIdeas(_ signals: FilmSignals) -> Double? {
        guard let average = signals.voteAverage, let count = signals.voteCount, count > 0 else { return nil }
        guard let popularity = signals.popularity, popularity > 0, popularity < 25 else { return nil }
        let votes = Double(count)
        let posterior = (votes * average + 400 * 6.6) / (votes + 400)
        guard posterior >= 7.3 else { return nil }
        let rarity = min(1, max(0, (25 - popularity) / 25))
        return min(1, 0.64 + 0.26 * rarity)
    }
}

private extension String {
    var tokens: [String] {
        split { !$0.isLetter && !$0.isNumber }.map { String($0) }
    }
}

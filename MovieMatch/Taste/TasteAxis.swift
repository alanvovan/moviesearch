//
//  TasteAxis.swift
//  MovieMatch
//

import Foundation

nonisolated enum TasteAxis: String, CaseIterable, Codable, Hashable, Sendable {
    case tempo
    case tone
    case emotionalWeight
    case plotComplexity
    case focusCharacterVsEvent
    case humor
    case tension
    case intimacy
    case spectacle
    case ideas

    var title: String {
        switch self {
        case .tempo: "Темп"
        case .tone: "Тон"
        case .emotionalWeight: "Эмоциональный вес"
        case .plotComplexity: "Сложность сюжета"
        case .focusCharacterVsEvent: "Персонажи или события"
        case .humor: "Юмор"
        case .tension: "Напряжение"
        case .intimacy: "Близость"
        case .spectacle: "Зрелищность"
        case .ideas: "Идеи"
        }
    }

    var explanation: String {
        switch self {
        case .tempo: "медленно или стремительно"
        case .tone: "мрачнее или светлее"
        case .emotionalWeight: "насколько давит чувство"
        case .plotComplexity: "прямолинейно или запутанно"
        case .focusCharacterVsEvent: "люди или происшествия в центре"
        case .humor: "насколько кино смеётся"
        case .tension: "спокойно или на взводе"
        case .intimacy: "дистанция или интимность"
        case .spectacle: "камерность или масштаб"
        case .ideas: "ощущение или мысль"
        }
    }

    func reading(_ value: Double) -> String {
        switch self {
        case .tempo:
            band(value, low: "ближе к медленному", high: "ближе к стремительному", mid: "средний темп")
        case .tone:
            band(value, low: "ближе к мрачному", high: "ближе к светлому", mid: "средний тон")
        case .emotionalWeight:
            band(value, low: "легче", high: "тяжелее", mid: "средний вес")
        case .plotComplexity:
            band(value, low: "прямолинейнее", high: "запутаннее", mid: "средняя сложность")
        case .focusCharacterVsEvent:
            band(value, low: "ближе к событиям", high: "ближе к персонажам", mid: "и люди, и события")
        case .humor:
            band(value, low: "меньше юмора", high: "больше юмора", mid: "юмор на среднем уровне")
        case .tension:
            band(value, low: "спокойнее", high: "сильнее напряжение", mid: "среднее напряжение")
        case .intimacy:
            band(value, low: "больше дистанция", high: "ближе", mid: "средняя близость")
        case .spectacle:
            band(value, low: "камернее", high: "масштабнее", mid: "средняя зрелищность")
        case .ideas:
            band(value, low: "меньше идей", high: "больше идей", mid: "идеи на среднем уровне")
        }
    }

    private func band(_ value: Double, low: String, high: String, mid: String) -> String {
        if value < 0.4 { return low }
        if value > 0.6 { return high }
        return mid
    }
}

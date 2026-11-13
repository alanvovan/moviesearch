//
//  RatingSheet.swift
//  MovieMatch
//

import SwiftUI
import UIKit

/// Пять зон ползунка оценки 1...100.
enum RatingMood: CaseIterable, Equatable {
    case bad
    case neutral
    case good
    case great
    case goat

    init(rating: Int) {
        switch rating {
        case ...20: self = .bad
        case 21...40: self = .neutral
        case 41...60: self = .good
        case 61...80: self = .great
        default: self = .goat
        }
    }

    var title: String {
        switch self {
        case .bad: "Плохо"
        case .neutral: "Нейтрально"
        case .good: "Хорошо"
        case .great: "Отлично"
        case .goat: "GOAT"
        }
    }

    var symbol: String {
        switch self {
        case .bad: "hand.thumbsdown.fill"
        case .neutral: "minus.circle.fill"
        case .good: "hand.thumbsup.fill"
        case .great: "star.fill"
        case .goat: "crown.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bad: Color(red: 0.86, green: 0.24, blue: 0.3)
        case .neutral: Color(red: 0.55, green: 0.55, blue: 0.6)
        case .good: Color(red: 0.24, green: 0.62, blue: 0.9)
        case .great: Color(red: 0.98, green: 0.66, blue: 0.12)
        case .goat: Color(red: 0.84, green: 0.62, blue: 0.1)
        }
    }
}

/// Ползунок 1...100 с шагом 1: щелчок Taptic Engine на каждом шаге, сильнее на границе зоны.
struct RatingSlider: View {
    @Binding var value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = UISelectionFeedbackGenerator()
    @State private var boundary = UIImpactFeedbackGenerator(style: .medium)

    private var mood: RatingMood { RatingMood(rating: value) }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: mood.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(mood.tint)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .frame(height: 52)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    Text(mood.title)
                        .font(.headline)
                    Text("\(value)")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(value)))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: mood)
            Slider(value: binding, in: 1...100, step: 1) { editing in
                if editing {
                    selection.prepare()
                    boundary.prepare()
                }
            }
            .tint(mood.tint)
            .accessibilityLabel("Оценка")
            .accessibilityValue("\(value) из 100, \(mood.title)")
            HStack {
                Text("1")
                Spacer()
                Text("100")
            }
            .font(.caption)
            .foregroundStyle(MovieMatchPalette.textTertiary)
        }
        .onChange(of: value) { old, new in
            if RatingMood(rating: old) != RatingMood(rating: new) {
                boundary.impactOccurred(intensity: 0.8)
            } else {
                selection.selectionChanged()
            }
            selection.prepare()
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = min(100, max(1, Int($0.rounded()))) }
        )
    }
}

struct RatingSheet: View {
    var title: String
    var requiresRating: Bool
    var allowsUnrated: Bool
    var onSave: (Int?, String) -> Void
    @State private var rating: Int
    @State private var review: String
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        requiresRating: Bool,
        allowsUnrated: Bool,
        rating: Int?,
        review: String,
        onSave: @escaping (Int?, String) -> Void
    ) {
        self.title = title
        self.requiresRating = requiresRating
        self.allowsUnrated = allowsUnrated
        self.onSave = onSave
        _rating = State(initialValue: rating ?? 50)
        _review = State(initialValue: review)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    RatingSlider(value: $rating)
                        .padding(18)
                        .background(MovieMatchPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    TextField("Отзыв, если есть", text: $review, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(MovieMatchPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        onSave(rating, review)
                        dismiss()
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(MovieMatchCapsuleStyle())
                    if allowsUnrated && !requiresRating {
                        Button("Сохранить без оценки") {
                            onSave(nil, review)
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MovieMatchPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .movieMatchScreen()
            .navigationTitle("Оценка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .movieMatchSheet()
    }
}

#if DEBUG
#Preview("Оценка") {
    RatingSheet(title: "Дюна", requiresRating: false, allowsUnrated: true, rating: nil, review: "") { _, _ in }
}
#endif

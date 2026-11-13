//
//  RatingRing.swift
//  MovieMatch
//

import SwiftUI

/// Кольцо с числом 0...100. Неуверенное значение рисуется пунктиром и приглушённо (MATH_SPEC.md, 6.1).
struct RatingRing: View {
    var value: Int
    var tint: Color
    var size: CGFloat = 44
    var isConfident = true
    var accessibilityTitle: String

    private var lineWidth: CGFloat { max(2.5, size * 0.07) }

    var body: some View {
        ZStack {
            Circle().fill(MovieMatchPalette.surface)
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
                .padding(lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, value))) / 100)
                .stroke(
                    tint,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: isConfident ? .round : .butt,
                        dash: isConfident ? [] : [lineWidth * 0.9, lineWidth * 0.9]
                    )
                )
                .rotationEffect(.degrees(-90))
                .padding(lineWidth)
            Text("\(value)")
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MovieMatchPalette.textPrimary)
        }
        .opacity(isConfident ? 1 : 0.72)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(isConfident ? "\(value) из 100" : "\(value) из 100, мало данных")
    }

    static func tmdbTint(_ value: Int) -> Color {
        switch value {
        case 70...: Color(red: 0.13, green: 0.72, blue: 0.42)
        case 40..<70: Color(red: 0.78, green: 0.70, blue: 0.10)
        default: Color(red: 0.86, green: 0.15, blue: 0.38)
        }
    }

    static func matchTint(_ value: Int) -> Color {
        switch value {
        case 65...: Color(red: 0.33, green: 0.55, blue: 1.0)
        case 40..<65: Color(red: 0.55, green: 0.55, blue: 0.85)
        default: Color(red: 0.62, green: 0.42, blue: 0.72)
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        RatingRing(value: 78, tint: RatingRing.tmdbTint(78), accessibilityTitle: "Рейтинг TMDB")
        RatingRing(value: 64, tint: RatingRing.matchTint(64), size: 36, isConfident: false, accessibilityTitle: "Совпадение")
    }
    .padding()
}
#endif

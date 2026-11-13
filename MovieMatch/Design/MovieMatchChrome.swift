//
//  MovieMatchChrome.swift
//  MovieMatch
//

import Foundation
import SwiftUI
import UIKit

/// Семантические цвета. Тема следует системной; значения для светлой и тёмной заданы попарно.
enum MovieMatchPalette {
    static let background = dynamic(light: UIColor(red: 0.965, green: 0.962, blue: 0.955, alpha: 1), dark: UIColor(red: 0.012, green: 0.012, blue: 0.016, alpha: 1))
    static let surface = dynamic(light: UIColor.black.withAlphaComponent(0.05), dark: UIColor.white.withAlphaComponent(0.08))
    static let surfaceStrong = dynamic(light: UIColor.black.withAlphaComponent(0.09), dark: UIColor.white.withAlphaComponent(0.14))
    static let stroke = dynamic(light: UIColor.black.withAlphaComponent(0.12), dark: UIColor.white.withAlphaComponent(0.18))
    static let separator = dynamic(light: UIColor.black.withAlphaComponent(0.1), dark: UIColor.white.withAlphaComponent(0.12))
    static let textPrimary = dynamic(light: UIColor(white: 0.06, alpha: 1), dark: .white)
    static let textSecondary = dynamic(light: UIColor(white: 0.06, alpha: 0.66), dark: UIColor.white.withAlphaComponent(0.7))
    static let textTertiary = dynamic(light: UIColor(white: 0.06, alpha: 0.45), dark: UIColor.white.withAlphaComponent(0.5))
    static let buttonFill = dynamic(light: UIColor(white: 0.06, alpha: 1), dark: .white)
    static let buttonLabel = dynamic(light: .white, dark: .black)
    static let onAccent = Color.black
    static let destructive = Color(uiColor: .systemRed)
    static let positive = Color(uiColor: .systemBlue)
    static let scrim = dynamic(light: UIColor(white: 0, alpha: 0.35), dark: UIColor(white: 0, alpha: 0.42))

    static var backgroundUIColor: UIColor { uiColor(light: UIColor(red: 0.965, green: 0.962, blue: 0.955, alpha: 1), dark: UIColor(red: 0.012, green: 0.012, blue: 0.016, alpha: 1)) }
    static var tabNormalUIColor: UIColor { uiColor(light: UIColor(white: 0.06, alpha: 0.5), dark: UIColor.white.withAlphaComponent(0.55)) }
    static var tabSelectedUIColor: UIColor { uiColor(light: UIColor(white: 0.06, alpha: 1), dark: .white) }

    static func accent(for family: GenreFamily) -> Color {
        let (r, g, b): (CGFloat, CGFloat, CGFloat) = switch family {
        case .action: (1.0, 0.62, 0.28)
        case .comedy: (1.0, 0.84, 0.36)
        case .drama: (0.98, 0.62, 0.68)
        case .suspense: (1.0, 0.48, 0.46)
        case .speculative: (0.48, 0.88, 0.98)
        case .documentary: (0.64, 0.86, 0.70)
        }
        return dynamic(
            light: UIColor(red: r * 0.62, green: g * 0.62, blue: b * 0.62, alpha: 1),
            dark: UIColor(red: r, green: g, blue: b, alpha: 1)
        )
    }

    /// Заливка круглых кнопок действий: яркая в обеих темах, значок поверх — `onAccent`.
    static func actionFill(for family: GenreFamily) -> Color {
        switch family {
        case .action: Color(red: 1.0, green: 0.62, blue: 0.28)
        case .comedy: Color(red: 1.0, green: 0.84, blue: 0.36)
        case .drama: Color(red: 0.98, green: 0.62, blue: 0.68)
        case .suspense: Color(red: 1.0, green: 0.48, blue: 0.46)
        case .speculative: Color(red: 0.48, green: 0.88, blue: 0.98)
        case .documentary: Color(red: 0.64, green: 0.86, blue: 0.70)
        }
    }

    private static func uiColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: uiColor(light: light, dark: dark))
    }
}

struct MovieMatchCapsuleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(MovieMatchPalette.buttonLabel)
            .background(MovieMatchPalette.buttonFill, in: Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed ? 0.86 : 1)
            .shadow(
                color: .black.opacity(pressed ? 0.1 : 0.2),
                radius: pressed ? 6 : 14,
                y: pressed ? 3 : 8
            )
            .animation(pressAnimation, value: pressed)
    }

    private var pressAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.34, bounce: 0.28)
    }
}

struct MovieMatchIconStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .opacity(pressed ? 0.86 : 1)
            .animation(pressAnimation, value: pressed)
    }

    private var pressAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.34, bounce: 0.28)
    }
}

struct MovieMatchScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MovieMatchPalette.background.ignoresSafeArea())
            .foregroundStyle(MovieMatchPalette.textPrimary)
            .tint(MovieMatchPalette.textPrimary)
    }
}

extension View {
    func movieMatchScreen() -> some View {
        modifier(MovieMatchScreenModifier())
    }

    /// Лист с фоном приложения.
    func movieMatchSheet() -> some View {
        presentationBackground(MovieMatchPalette.background)
    }
}

struct MovieMatchMessage: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MovieMatchPalette.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(MovieMatchPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                }
                .buttonStyle(MovieMatchCapsuleStyle())
                    .padding(.top, 8)
            }
        }
        .padding(28)
    }
}

struct PosterImage: View {
    var path: String?
    var size: String = "w780"

    var body: some View {
        Color.clear
            .overlay {
                if let url = TMDBImages.url(path: path, size: size) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            MovieMatchPalette.surface
                        }
                    }
                } else {
                    MovieMatchPalette.surface
                }
            }
            .clipped()
    }
}

/// Поле поиска-капсула. `trailing` — кнопки справа внутри поля.
struct MovieMatchSearchField<Trailing: View>: View {
    var prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MovieMatchPalette.textSecondary)
                .accessibilityHidden(true)
            field
                .accessibilityLabel(prompt)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MovieMatchPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
            trailing()
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(MovieMatchPalette.textPrimary)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(MovieMatchPalette.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(prompt, text: $text).focused(focus)
        } else {
            TextField(prompt, text: $text)
        }
    }
}

func displayOverview(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Описания нет" : trimmed
}

func russianDate(_ date: Date) -> String {
    date.formatted(
        .dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))
    )
}

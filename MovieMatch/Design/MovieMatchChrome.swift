//
//  MovieMatchChrome.swift
//  MovieMatch
//

import Foundation
import SwiftUI

enum MovieMatchPalette {
    static let background = Color(red: 0.012, green: 0.012, blue: 0.016)

    static func accent(for family: GenreFamily) -> Color {
        switch family {
        case .action: Color(red: 1.0, green: 0.62, blue: 0.28)
        case .comedy: Color(red: 1.0, green: 0.84, blue: 0.36)
        case .drama: Color(red: 0.98, green: 0.62, blue: 0.68)
        case .suspense: Color(red: 1.0, green: 0.48, blue: 0.46)
        case .speculative: Color(red: 0.48, green: 0.88, blue: 0.98)
        case .documentary: Color(red: 0.64, green: 0.86, blue: 0.70)
        }
    }
}

struct MovieMatchCapsuleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(.black)
            .background(.white, in: Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed ? 0.86 : 1)
            .shadow(
                color: .black.opacity(pressed ? 0.16 : 0.34),
                radius: pressed ? 8 : 18,
                y: pressed ? 4 : 10
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
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func movieMatchScreen() -> some View {
        modifier(MovieMatchScreenModifier())
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
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .buttonStyle(MovieMatchCapsuleStyle())
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
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
                            MovieMatchPalette.background
                        }
                    }
                } else {
                    MovieMatchPalette.background
                }
            }
            .clipped()
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

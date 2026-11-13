//
//  GenreRadarView.swift
//  MovieMatch
//

import SwiftUI

/// Паутинная диаграмма по MATH_SPEC.md, 5.3: радиус — медиана вероятности, полоса — 80% интервал,
/// неуверенные группы — полые вершины; если неуверенны все, контур пунктиром.
struct GenreRadarView: View {
    var values: [GenreGroup: GroupValue]
    var accent: Color = MovieMatchPalette.textPrimary

    private let groups = GenreGroup.allCases

    private var allWide: Bool { groups.allSatisfy { value($0).isWide } }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side * 0.3
            ZStack {
                ForEach([1.0, 0.5], id: \.self) { factor in
                    polygon(center: center, radius: radius) { _ in factor }
                        .stroke(MovieMatchPalette.separator, lineWidth: 1)
                }
                Path { path in
                    for index in groups.indices {
                        path.move(to: center)
                        path.addLine(to: point(index: index, value: 1, center: center, radius: radius))
                    }
                }
                .stroke(MovieMatchPalette.separator, lineWidth: 1)
                band(center: center, radius: radius)
                    .fill(accent.opacity(0.1), style: FillStyle(eoFill: true))
                polygon(center: center, radius: radius) { value($0).point }
                    .fill(accent.opacity(0.16))
                polygon(center: center, radius: radius) { value($0).point }
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: allWide ? [5, 4] : []))
                ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                    let item = value(group)
                    vertex(isWide: item.isWide)
                        .position(point(index: index, value: item.point, center: center, radius: radius))
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isWide ? MovieMatchPalette.textTertiary : MovieMatchPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(width: 92)
                        .position(point(index: index, value: 1.42, center: center, radius: radius))
                }
            }
        }
        .frame(height: 320)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Любимые жанры")
        .accessibilityValue(accessibilitySummary)
    }

    private func value(_ group: GenreGroup) -> GroupValue {
        values[group] ?? GroupValue(point: 0.5, lower: 0, upper: 1, effective: 0)
    }

    @ViewBuilder
    private func vertex(isWide: Bool) -> some View {
        if isWide {
            Circle()
                .stroke(accent.opacity(0.6), lineWidth: 1.5)
                .background(Circle().fill(MovieMatchPalette.background))
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
        }
    }

    private var accessibilitySummary: String {
        let confident = groups.filter { !value($0).isWide }
        guard !confident.isEmpty else { return "Данных пока мало" }
        return confident
            .sorted { value($0).point > value($1).point }
            .prefix(3)
            .map { "\($0.title) \(Int((value($0).point * 100).rounded())) процентов" }
            .joined(separator: ", ")
    }

    private func band(center: CGPoint, radius: CGFloat) -> Path {
        var path = polygon(center: center, radius: radius) { value($0).upper }
        path.addPath(polygon(center: center, radius: radius) { value($0).lower })
        return path
    }

    private func polygon(center: CGPoint, radius: CGFloat, value: (GenreGroup) -> Double) -> Path {
        Path { path in
            for (index, group) in groups.enumerated() {
                let spot = point(index: index, value: value(group), center: center, radius: radius)
                if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
            }
            path.closeSubpath()
        }
    }

    private func point(index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(groups.count)
        let length = radius * CGFloat(min(1.5, max(0, value.isFinite ? value : 0)))
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * length,
            y: center.y + CGFloat(sin(angle)) * length
        )
    }
}

#if DEBUG
#Preview {
    GenreRadarView(values: TasteState.empty.groupValues)
        .padding()
        .movieMatchScreen()
}
#endif

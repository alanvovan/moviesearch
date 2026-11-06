//
//  GenreRadarView.swift
//  MovieMatch
//

import SwiftUI

struct GenreRadarView: View {
    var values: [GenreGroup: Double]
    var accent: Color = .white

    private let groups = GenreGroup.allCases

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side * 0.3
            ZStack {
                ForEach([1.0, 0.5], id: \.self) { factor in
                    polygon(center: center, radius: radius) { _ in factor }
                        .stroke(accent.opacity(0.24), lineWidth: 1)
                }
                Path { path in
                    for index in groups.indices {
                        path.move(to: center)
                        path.addLine(to: point(index: index, value: 1, center: center, radius: radius))
                    }
                }
                .stroke(accent.opacity(0.24), lineWidth: 1)
                polygon(center: center, radius: radius) { values[$0] ?? 0 }
                    .fill(accent.opacity(0.2))
                polygon(center: center, radius: radius) { values[$0] ?? 0 }
                    .stroke(accent, lineWidth: 1.5)
                ForEach(Array(groups.enumerated()), id: \.element) { index, group in
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
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
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        groups
            .sorted { (values[$0] ?? 0) > (values[$1] ?? 0) }
            .prefix(3)
            .filter { (values[$0] ?? 0) > 0 }
            .map(\.title)
            .joined(separator: ", ")
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
        let length = radius * CGFloat(max(0, value))
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * length,
            y: center.y + CGFloat(sin(angle)) * length
        )
    }
}

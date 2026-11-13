//
//  ContentView.swift
//  MovieMatch
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @AppStorage("movieMatch.onboarding.done") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    @State private var appeared = false
    @State private var entered = false

    var body: some View {
        ZStack {
            if entered {
                if onboardingDone {
                    MainTabView()
                } else {
                    OnboardingView {
                        onboardingDone = true
                    }
                }
            } else {
                splash
            }
        }
        .background(MovieMatchPalette.background.ignoresSafeArea())
        .task { LibraryStore.prepare(in: modelContext) }
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.3), value: entered)
    }

    private var splash: some View {
        ZStack(alignment: .bottom) {
            MovieMatchCanvas(paused: reduceMotion)
            startButton
                .padding(.bottom, 12)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MovieMatchPalette.background)
        .environment(\.colorScheme, .dark)
        .animation(entrance, value: appeared)
        .onAppear { appeared = true }
    }

    private var entrance: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(duration: 0.75, bounce: 0.18)
    }

    private var startButton: some View {
        Button {
            taps += 1
            entered = true
        } label: {
            Text("Начать")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
        }
        .buttonStyle(MovieMatchCapsuleStyle())
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: taps)
    }
}

private struct MovieMatchCanvas: View {
    var paused: Bool
    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let elapsed = paused ? 0 : timeline.date.timeIntervalSince(epoch)
            GeometryReader { proxy in
                Rectangle()
                    .fill(MovieMatchPalette.background)
                    .colorEffect(shader(size: proxy.size, time: elapsed))
            }
        }
        .ignoresSafeArea()
    }

    private func shader(size: CGSize, time: TimeInterval) -> Shader {
        ShaderLibrary.seams(
            .float2(Float(size.width), Float(size.height)),
            .float(Float(time))
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [StoredMovie.self, StoredTaste.self, StoredHide.self, StoredEvent.self], inMemory: true)
}

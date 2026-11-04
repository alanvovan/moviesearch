//
//  TrailerSheet.swift
//  Prism
//

import SwiftUI
import WebKit

struct TrailerSheet: View {
    var movieID: Int
    var initialKey: String?
    @State private var videoKey: String?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                trailer
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let videoKey, !videoKey.isEmpty,
                   let url = URL(string: "https://www.youtube.com/watch?v=\(videoKey)") {
                    Link("Открыть в YouTube", destination: url)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(16)
            .prismScreen()
            .navigationTitle("Трейлер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { dismiss() }
                    }
                }
            }
        }
        .presentationBackground(PrismPalette.background)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var trailer: some View {
        if let videoKey, !videoKey.isEmpty {
            YouTubeEmbed(videoID: videoKey)
        } else if failed {
            Text("Трейлер не найден")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        if let initialKey, !initialKey.isEmpty {
            videoKey = sanitized(initialKey)
            return
        }
        guard let client = TMDBClient.live() else {
            failed = true
            return
        }
        do {
            let detail = try await client.details(id: movieID)
            if let key = detail.youtubeKey, !key.isEmpty {
                videoKey = sanitized(key)
            } else {
                failed = true
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }

    private func sanitized(_ raw: String) -> String {
        String(raw.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

/// YouTube-плеер в WKWebView. Ошибка 153 лечится загрузкой HTML с https baseURL:
/// плееру нужен Referer/origin, которого нет при прямом `webView.load(URLRequest)`.
struct YouTubeEmbed: UIViewRepresentable {
    var videoID: String
    var autoplay = true
    var muted = false
    var controls = true
    var loop = false

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        var query = "playsinline=1&rel=0&modestbranding=1"
        query += "&autoplay=\(autoplay ? 1 : 0)&mute=\(muted ? 1 : 0)&controls=\(controls ? 1 : 0)"
        if loop { query += "&loop=1&playlist=\(videoID)" }
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(videoID)?\(query)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
        </body></html>
        """
        // YouTube требует Referer, идентифицирующий приложение (https://<bundle id>);
        // подмена youtube.com даёт ошибки 152/153.
        let bundleID = (Bundle.main.bundleIdentifier ?? "com.remember.Prism").lowercased()
        webView.loadHTMLString(html, baseURL: URL(string: "https://\(bundleID)"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedID: String?
    }
}

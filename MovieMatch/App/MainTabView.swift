//
//  MainTabView.swift
//  MovieMatch
//

import SwiftUI
import UIKit

struct MainTabView: View {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = MovieMatchPalette.backgroundUIColor
        appearance.stackedLayoutAppearance.normal.iconColor = MovieMatchPalette.tabNormalUIColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: MovieMatchPalette.tabNormalUIColor]
        appearance.stackedLayoutAppearance.selected.iconColor = MovieMatchPalette.tabSelectedUIColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: MovieMatchPalette.tabSelectedUIColor]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Библиотека", systemImage: "books.vertical") }
            FeedView()
                .tabItem { Label("Поиск", systemImage: "rectangle.stack") }
            AccountView()
                .tabItem { Label("Аккаунт", systemImage: "person") }
        }
        .tint(MovieMatchPalette.textPrimary)
    }
}

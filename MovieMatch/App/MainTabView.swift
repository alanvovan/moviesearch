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
        appearance.backgroundColor = UIColor(red: 0.012, green: 0.012, blue: 0.016, alpha: 1)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.55)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.55)]
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
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
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

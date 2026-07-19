import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPrepared = false
    @State private var preparationError: String?

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.025, green: 0.031, blue: 0.034, alpha: 1)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.44)
    }

    var body: some View {
        Group {
            if isPrepared {
                TabView {
                    NavigationStack {
                        TodayView()
                    }
                    .tabItem {
                        Label("首页", systemImage: "house.fill")
                    }

                    NavigationStack {
                        PlanView()
                    }
                    .tabItem {
                        Label("训练", systemImage: "dumbbell.fill")
                    }

                    NavigationStack {
                        StatsView()
                    }
                    .tabItem {
                        Label("进度", systemImage: "chart.bar.fill")
                    }

                    NavigationStack {
                        ProfileView()
                    }
                    .tabItem {
                        Label("我的", systemImage: "person.fill")
                    }
                }
                .tint(AppTheme.accent)
                .toolbarBackground(AppTheme.tabBar, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            } else if let preparationError {
                ContentUnavailableView(
                    "无法载入训练数据",
                    systemImage: "exclamationmark.triangle",
                    description: Text(preparationError)
                )
            } else {
                ZStack {
                    AppTheme.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("正在准备训练计划…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !isPrepared else { return }
            do {
                try SeedDataService.prepareIfNeeded(in: modelContext)
                isPrepared = true
            } catch {
                preparationError = error.localizedDescription
            }
        }
    }
}

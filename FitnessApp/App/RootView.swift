import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPrepared = false
    @State private var preparationError: String?
    @State private var launchImportMessage: String?

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
        .alert("历史训练同步", isPresented: Binding(
            get: { launchImportMessage != nil },
            set: { if !$0 { launchImportMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { launchImportMessage = nil }
        } message: {
            Text(launchImportMessage ?? "")
        }
        .task {
            guard !isPrepared else { return }
            do {
                try SeedDataService.prepareIfNeeded(in: modelContext)
                do {
                    launchImportMessage = try importLaunchHistoryIfRequested()
                } catch {
                    launchImportMessage = "历史记录未写入：\(error.localizedDescription)"
                    try? writeLaunchImportReceipt(
                        LaunchImportReceipt(
                            completedAt: .now,
                            sourceFile: launchImportFileName ?? "",
                            previewSessions: 0,
                            previewSets: 0,
                            importedSessions: 0,
                            skippedSessions: 0,
                            importedSets: 0,
                            createdExercises: 0,
                            errorMessage: error.localizedDescription
                        )
                    )
                }
                let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
                await NotificationService.syncWorkoutReminders(schedules)
                isPrepared = true
            } catch {
                preparationError = error.localizedDescription
            }
        }
    }

    private var launchImportFileName: String? {
        let prefix = "--history-import-file="
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let rawName = String(argument.dropFirst(prefix.count))
        let fileName = URL(fileURLWithPath: rawName).lastPathComponent
        guard !fileName.isEmpty, rawName == fileName else { return nil }
        return fileName
    }

    @MainActor
    private func importLaunchHistoryIfRequested() throws -> String? {
        guard let fileName = launchImportFileName else { return nil }
        let sourceURL = URL.documentsDirectory.appendingPathComponent(fileName)
        let data = try Data(contentsOf: sourceURL)
        let preview = try HistoricalWorkoutCSVService.preview(data, in: modelContext)
        let summary = try HistoricalWorkoutCSVService.importCSV(data, into: modelContext)
        try writeLaunchImportReceipt(
            LaunchImportReceipt(
                completedAt: .now,
                sourceFile: fileName,
                previewSessions: preview.sessions,
                previewSets: preview.sets,
                importedSessions: summary.importedSessions,
                skippedSessions: summary.skippedSessions,
                importedSets: summary.importedSets,
                createdExercises: summary.createdExercises,
                errorMessage: nil
            )
        )
        return "已同步 \(summary.importedSessions) 场训练、\(summary.importedSets) 个完成组；新建 \(summary.createdExercises) 个动作，跳过 \(summary.skippedSessions) 场重复记录。"
    }

    private func writeLaunchImportReceipt(_ receipt: LaunchImportReceipt) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(
            to: URL.documentsDirectory.appendingPathComponent("history-import-receipt.json"),
            options: .atomic
        )
    }
}

private struct LaunchImportReceipt: Codable {
    let completedAt: Date
    let sourceFile: String
    let previewSessions: Int
    let previewSets: Int
    let importedSessions: Int
    let skippedSessions: Int
    let importedSets: Int
    let createdExercises: Int
    let errorMessage: String?
}

import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPrepared = false
    @State private var preparationError: String?
    @State private var launchImportMessage: String?
    @State private var pendingShareDraft: ExerciseShareDraft?
    @State private var editingShareDraft: ExerciseShareDraft?
    @State private var deliveredRestNotificationCount = 0
    @State private var pendingRestNotificationCount = 0
    @State private var notificationAuthorizationGranted = false
    @State private var notificationAlertsEnabled = false
    @State private var notificationLockScreenEnabled = false
    @State private var notificationCenterEnabled = false
    @State private var notificationSoundsEnabled = false
    @State private var notificationScheduledDeliveryEnabled = false

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(red: 0.018, green: 0.022, blue: 0.025, alpha: 0.82)
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.38)
    }

    var body: some View {
        Group {
            if isPrepared {
                if isHistoryUITest {
                    NavigationStack {
                        HistoryView()
                    }
                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                } else {
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
                    .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                }
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
        .overlay(alignment: .top) {
            if isNotificationUITest {
                VStack(spacing: 2) {
                    Text("已送达休息通知 \(deliveredRestNotificationCount)")
                        .accessibilityIdentifier("已送达休息通知计数")
                    Text("待发送休息通知 \(pendingRestNotificationCount)")
                        .accessibilityIdentifier("待发送休息通知计数")
                    Text(notificationAuthorizationGranted ? "通知授权已通过" : "通知授权未通过")
                        .accessibilityIdentifier("通知授权状态")
                    Text(notificationAlertsEnabled ? "通知横幅已启用" : "通知横幅未启用")
                        .accessibilityIdentifier("通知横幅状态")
                    Text(notificationLockScreenEnabled ? "锁屏通知已启用" : "锁屏通知未启用")
                        .accessibilityIdentifier("锁屏通知状态")
                    Text(notificationCenterEnabled ? "通知中心已启用" : "通知中心未启用")
                        .accessibilityIdentifier("通知中心状态")
                    Text(notificationSoundsEnabled ? "通知声音已启用" : "通知声音未启用")
                        .accessibilityIdentifier("通知声音状态")
                    Text(notificationScheduledDeliveryEnabled ? "定时摘要已启用" : "定时摘要未启用")
                        .accessibilityIdentifier("定时摘要状态")
                    if let error = NotificationService.lastRestSchedulingErrorDescription {
                        Text("通知提交失败：\(error)")
                            .accessibilityIdentifier("通知提交错误")
                    }
                }
                .font(.caption2)
                .padding(4)
                .background(.black.opacity(0.8), in: Capsule())
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isShareDraftUITest {
                Button("重新检查分享草稿") {
                    loadPendingShareDraft()
                }
                .font(.caption2)
                .padding(6)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(4)
            }
        }
        .confirmationDialog(
            "已收到一份动作资料",
            isPresented: Binding(
                get: { pendingShareDraft != nil },
                set: { if !$0 { deferPendingShareDraft() } }
            ),
            titleVisibility: .visible
        ) {
            Button("补充信息并加入动作库") {
                editingShareDraft = pendingShareDraft
                pendingShareDraft = nil
            }
            Button("丢弃这份资料", role: .destructive) {
                if let draft = pendingShareDraft {
                    shareDraftInbox.clearPendingDraft(matching: draft.id)
                }
                pendingShareDraft = nil
            }
            Button("稍后处理") {
                deferPendingShareDraft()
            }
        } message: {
            Text("可以把 Safari 或其他 App 分享来的链接保存为新动作；保存前仍可修改名称、肌群和训练要点。")
        }
        .sheet(item: $editingShareDraft) { draft in
            ExerciseEditorView(
                initialName: draft.suggestedExerciseName,
                initialNotes: draft.sharedText,
                initialReferenceURL: draft.sourceURL?.absoluteString ?? "",
                onSave: { _ in
                    shareDraftInbox.clearPendingDraft(matching: draft.id)
                }
            )
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
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
                #if DEBUG
                try prepareUITestShareDraftFixtureIfRequested()
                if CommandLine.arguments.contains("--ui-testing-reset-rest-notifications") {
                    await resetRestNotificationsForTesting()
                }
                if CommandLine.arguments.contains("--ui-testing-request-notification-authorization") {
                    _ = try? await NotificationService.requestAuthorization()
                    await refreshDeliveredRestNotificationCount()
                }
                #endif
                try SeedDataService.prepareIfNeeded(
                    in: modelContext,
                    allowInitialSeed: CloudSyncRuntime.allowsInitialSeed
                )
                #if DEBUG
                try prepareUITestTerminologyFixtureIfRequested()
                try prepareUITestShortRestFixtureIfRequested()
                try prepareUITestBodyFeedbackFixtureIfRequested()
                try prepareUITestHistoryFixtureIfRequested()
                try prepareUITestProgressFixtureIfRequested()
                try prepareUITestHomeFixtureIfRequested()
                #endif
                do {
                    launchImportMessage = try importDeviceHistoryMergeIfRequested()
                        ?? importLaunchHistoryIfRequested()
                } catch {
                    launchImportMessage = "历史记录未写入：\(error.localizedDescription)"
                    if let mergeFileName = deviceHistoryMergeFileName {
                        try? writeDeviceHistoryMergeReceipt(
                            DeviceHistoryMergeReceipt(
                                completedAt: .now,
                                sourceFile: mergeFileName,
                                summary: nil,
                                errorMessage: error.localizedDescription
                            )
                        )
                    } else {
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
                }
                if CloudSyncRuntime.shouldSyncWorkoutReminders() {
                    let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
                    await NotificationService.syncWorkoutReminders(schedules)
                }
                isPrepared = true
                if CloudSyncRuntime.shouldReadShareDraft() {
                    loadPendingShareDraft()
                }
            } catch {
                preparationError = error.localizedDescription
            }
        }
        .task {
            guard isNotificationUITest else { return }
            while !Task.isCancelled {
                await refreshDeliveredRestNotificationCount()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if isNotificationUITest {
                Task { await refreshDeliveredRestNotificationCount() }
            }
            guard CloudSyncRuntime.shouldReadShareDraft(),
                  isPrepared,
                  editingShareDraft == nil else { return }
            loadPendingShareDraft()
        }
    }

    private func loadPendingShareDraft() {
        guard CloudSyncRuntime.shouldReadShareDraft(), pendingShareDraft == nil else { return }
        pendingShareDraft = shareDraftInbox.pendingDraftForAutomaticPresentation()
    }

    private func deferPendingShareDraft() {
        if let draft = pendingShareDraft {
            shareDraftInbox.deferPendingDraft(matching: draft.id)
        }
        pendingShareDraft = nil
    }

    private var shareDraftInbox: ExerciseShareDraftInbox {
        ExerciseShareDraftInbox(pendingDraftKey: shareDraftPendingKey)
    }

    private var shareDraftPendingKey: String {
        isShareDraftUITest
            ? ExerciseShareDraftStorage.uiTestingPendingDraftKey
            : ExerciseShareDraftStorage.pendingDraftKey
    }

    private var isHistoryUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-history")
        #else
        false
        #endif
    }

    private var isNotificationUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-notification-status")
        #else
        false
        #endif
    }

    private var isShareDraftUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-share-draft")
        #else
        false
        #endif
    }

    private func refreshDeliveredRestNotificationCount() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationGranted = [
            UNAuthorizationStatus.authorized,
            .provisional,
            .ephemeral
        ].contains(settings.authorizationStatus)
        notificationAlertsEnabled = settings.alertSetting == .enabled
        notificationLockScreenEnabled = settings.lockScreenSetting == .enabled
        notificationCenterEnabled = settings.notificationCenterSetting == .enabled
        notificationSoundsEnabled = settings.soundSetting == .enabled
        notificationScheduledDeliveryEnabled = settings.scheduledDeliverySetting == .enabled
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingRestNotificationCount = pending.filter {
            NotificationService.isRestRequestIdentifier($0.identifier)
        }.count
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        deliveredRestNotificationCount = delivered.filter {
            NotificationService.isRestRequestIdentifier($0.request.identifier)
        }.count
    }

    private func resetRestNotificationsForTesting() async {
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(NotificationService.isRestRequestIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        pendingRestNotificationCount = 0

        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(NotificationService.isRestRequestIdentifier)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
        await refreshDeliveredRestNotificationCount()
    }

    #if DEBUG
    private func prepareUITestShareDraftFixtureIfRequested() throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return }

        #if targetEnvironment(simulator)
        if arguments.contains("--ui-testing-reset-production-share-draft") {
            ExerciseShareDraftInbox().clearPendingDraft()
        }
        #endif

        let inbox = shareDraftInbox
        if arguments.contains("--ui-testing-reset-share-draft") {
            inbox.clearPendingDraft()
        }
        guard arguments.contains("--ui-testing-seed-share-draft") else { return }

        let draft = ExerciseShareDraft(
            sharedText: "UI 测试绳索划船\n保持肩胛后收",
            sourceURL: URL(string: "https://example.com/ui-share-source")
        )
        guard let defaults = ExerciseShareDraftStorage.makeUserDefaults() else {
            throw CocoaError(.fileWriteUnknown)
        }
        defaults.set(
            try JSONEncoder().encode(draft),
            forKey: shareDraftPendingKey
        )
    }
    #endif

    private var launchImportFileName: String? {
        secureLaunchFileName(prefix: "--history-import-file=")
    }

    private var deviceHistoryMergeFileName: String? {
        secureLaunchFileName(prefix: "--history-merge-file=")
    }

    private func secureLaunchFileName(prefix: String) -> String? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let rawName = String(argument.dropFirst(prefix.count))
        let fileName = URL(fileURLWithPath: rawName).lastPathComponent
        guard !fileName.isEmpty, rawName == fileName else { return nil }
        return fileName
    }

    @MainActor
    private func importDeviceHistoryMergeIfRequested() throws -> String? {
        guard let fileName = deviceHistoryMergeFileName else { return nil }
        let sourceURL = URL.documentsDirectory.appendingPathComponent(fileName)
        let data = try Data(contentsOf: sourceURL)
        let summary = try DeviceHistoryMergeService.importPackage(data, into: modelContext)
        try writeDeviceHistoryMergeReceipt(
            DeviceHistoryMergeReceipt(
                completedAt: .now,
                sourceFile: fileName,
                summary: summary,
                errorMessage: nil
            )
        )
        return "已无损合并 \(summary.importedSessions) 场训练、\(summary.importedSessionExercises) 个动作快照和 \(summary.importedSetLogs) 条组记录；跳过 \(summary.skippedSessions) 场已有训练。"
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

    private func writeDeviceHistoryMergeReceipt(_ receipt: DeviceHistoryMergeReceipt) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(
            to: URL.documentsDirectory.appendingPathComponent("device-history-merge-receipt.json"),
            options: .atomic
        )
    }

    #if DEBUG
    @MainActor
    private func prepareUITestTerminologyFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-terminology") else { return }
        var exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        if !exercises.contains(where: { $0.name == "三头下压" }) {
            let exercise = Exercise(
                name: "三头下压",
                muscleGroup: "手臂",
                equipment: "龙门架",
                isBuiltIn: false
            )
            modelContext.insert(exercise)
            exercises.append(exercise)
        }
        if !exercises.contains(where: { $0.name == "绳索下压" }) {
            let exercise = Exercise(
                name: "绳索下压",
                muscleGroup: "手臂",
                equipment: "龙门架",
                isBuiltIn: false
            )
            modelContext.insert(exercise)
            exercises.append(exercise)
        }
        if !exercises.contains(where: { $0.name == "传统硬拉" }) {
            let exercise = Exercise(
                name: "传统硬拉",
                muscleGroup: "腿部",
                equipment: "自重",
                isBuiltIn: false
            )
            modelContext.insert(exercise)
            exercises.append(exercise)
        }
        try modelContext.save()
        try ExerciseTerminologyService.stageCatalogCandidates(in: modelContext)

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !sessions.contains(where: { $0.importIdentifier == "ui-test-terminology-history" }),
              let tricepsPushdown = exercises.first(where: { $0.name == "三头下压" }),
              let ropePushdown = exercises.first(where: { $0.name == "绳索下压" }) else {
            return
        }

        let completedAt = Date.now.addingTimeInterval(-3_600)
        let startedAt = completedAt.addingTimeInterval(-2_400)
        let session = WorkoutSession(
            templateName: "术语历史保护验证",
            plannedDate: startedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            status: .completed,
            notes: "审核决定不得改写动作快照和组表现",
            importIdentifier: "ui-test-terminology-history"
        )
        let firstSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: tricepsPushdown.id,
            exerciseName: "三头下压",
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 10,
            targetWeight: 20,
            restSeconds: 60,
            muscleGroup: tricepsPushdown.muscleGroup,
            exerciseNotes: "原始快照 A",
            volumeUnit: .kilogram
        )
        let secondSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: ropePushdown.id,
            exerciseName: "绳索下压",
            order: 1,
            targetSets: 1,
            minReps: 12,
            maxReps: 12,
            targetWeight: 25,
            restSeconds: 60,
            muscleGroup: ropePushdown.muscleGroup,
            exerciseNotes: "原始快照 B",
            volumeUnit: .kilogram
        )
        modelContext.insert(session)
        modelContext.insert(firstSnapshot)
        modelContext.insert(secondSnapshot)
        for setNumber in 1...2 {
            modelContext.insert(SetLog(
                sessionID: session.id,
                sessionExerciseID: firstSnapshot.id,
                exerciseID: tricepsPushdown.id,
                setNumber: setNumber,
                targetWeight: 20,
                targetReps: 10,
                actualWeight: 20,
                actualReps: 10,
                rir: 2,
                isCompleted: true,
                completedAt: completedAt
            ))
        }
        modelContext.insert(SetLog(
            sessionID: session.id,
            sessionExerciseID: secondSnapshot.id,
            exerciseID: ropePushdown.id,
            setNumber: 1,
            targetWeight: 25,
            targetReps: 12,
            actualWeight: 25,
            actualReps: 12,
            rir: 1,
            isCompleted: true,
            completedAt: completedAt
        ))
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestShortRestFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-short-rest") else { return }
        let items = try modelContext.fetch(FetchDescriptor<TemplateExercise>())
        items.forEach { $0.restSeconds = 5 }
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestBodyFeedbackFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-body-feedback") else { return }
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        let session: WorkoutSession
        if let current = existingSessions.first(where: { $0.status == .inProgress }) {
            session = current
        } else {
            guard let schedule = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
                .first(where: { $0.plannedDate.isSameDay(as: .now) && $0.status == .planned }) else {
                return
            }
            let sessionID = try WorkoutService.start(schedule: schedule, in: modelContext)
            guard let started = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .first(where: { $0.id == sessionID }) else {
                return
            }
            session = started
        }

        guard let firstExercise = try modelContext.fetch(FetchDescriptor<SessionExercise>())
            .filter({ $0.sessionID == session.id })
            .sorted(by: { $0.order < $1.order })
            .first else {
            return
        }
        let logs = try modelContext.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == firstExercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        if firstExercise.feeling == nil {
            for log in logs.dropLast() {
                log.actualWeight = max(1, log.targetWeight)
                log.actualReps = max(1, log.targetReps)
                log.isCompleted = true
                log.completedAt = .now
            }
            if let last = logs.last {
                last.isCompleted = false
                last.completedAt = nil
            }
        }
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestHistoryFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-history") else { return }
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !sessions.contains(where: { $0.importIdentifier == "ui-test-history-detail" }) else {
            return
        }
        guard let exercise = try modelContext.fetch(FetchDescriptor<Exercise>())
            .first(where: { $0.name == "杠铃卧推" }) else {
            return
        }

        let completedAt = Date.now
        let startedAt = completedAt.addingTimeInterval(-3_600)
        let session = WorkoutSession(
            templateName: "历史详情验证",
            plannedDate: startedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            status: .completed,
            notes: "用于验证历史详情导航和逐组内容",
            importIdentifier: "ui-test-history-detail"
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes,
            volumeUnit: exercise.volumeUnit,
            performanceNotes: "肩胛稳定",
            feeling: .hard
        )
        modelContext.insert(session)
        modelContext.insert(snapshot)
        for setNumber in 1...2 {
            modelContext.insert(
                SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id,
                    setNumber: setNumber,
                    targetWeight: 40,
                    targetReps: 10,
                    actualWeight: 40,
                    actualReps: 10,
                    rir: 2,
                    isCompleted: true,
                    completedAt: completedAt
                )
            )
        }
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestProgressFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-progress") else { return }

        let availableExercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        guard let fixtureExercise = availableExercises.first(where: { $0.name == "杠铃卧推" })
                ?? availableExercises.first else {
            return
        }

        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now),
              let currentMonth = calendar.dateInterval(of: .month, for: .now),
              let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: currentMonth.start),
              let previousMonth = calendar.dateInterval(of: .month, for: previousMonthDate) else {
            return
        }
        let today = calendar.startOfDay(for: .now)
        let dayOfMonth = calendar.component(.day, from: today)
        let earlierMonthDay = currentMonth.start.addingDays(min(9, max(0, dayOfMonth - 1)))

        let fixtures: [(String, Date, Int, Double)] = [
            ("本周推训练", currentWeek.start, 46, 50),
            ("本周拉训练", today, 52, 65),
            ("本月腿训练", earlierMonthDay, 58, 80),
            ("上周同期训练", currentWeek.start.addingDays(-7), 50, 70),
            ("上月同期训练", previousMonth.start.addingDays(8), 55, 75)
        ]

        for (index, fixture) in fixtures.enumerated() {
            let startedAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: fixture.1)
                ?? fixture.1
            let completedAt = startedAt.addingTimeInterval(Double(fixture.2 * 60))
            let session = WorkoutSession(
                templateName: fixture.0,
                plannedDate: startedAt,
                startedAt: startedAt,
                completedAt: completedAt,
                status: .completed,
                importIdentifier: "ui-test-progress-\(index)"
            )
            modelContext.insert(session)

            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: fixtureExercise.id,
                exerciseName: fixtureExercise.name,
                order: 0,
                targetSets: 4,
                minReps: 8,
                maxReps: 12,
                targetWeight: fixture.3,
                restSeconds: fixtureExercise.defaultRestSeconds,
                muscleGroup: fixtureExercise.muscleGroup,
                exerciseNotes: fixtureExercise.notes,
                volumeUnit: fixtureExercise.volumeUnit
            )
            modelContext.insert(snapshot)

            for setNumber in 1...4 {
                modelContext.insert(SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: fixtureExercise.id,
                    setNumber: setNumber,
                    targetWeight: fixture.3,
                    targetReps: 10,
                    actualWeight: fixture.3,
                    actualReps: 10,
                    rir: 2,
                    isCompleted: true,
                    completedAt: completedAt
                ))
            }
        }

        try modelContext.save()
    }

    @MainActor
    private func prepareUITestHomeFixtureIfRequested() throws {
        let arguments = CommandLine.arguments
        let wantsEmpty = arguments.contains("--ui-testing-home-empty")
        let wantsSingle = arguments.contains("--ui-testing-home-single-volume")
        let wantsSeven = arguments.contains("--ui-testing-home-seven-volumes")
        let wantsCompleted = arguments.contains("--ui-testing-home-completed")
        guard wantsEmpty || wantsSingle || wantsSeven || wantsCompleted else { return }

        try modelContext.fetch(FetchDescriptor<SetLog>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<SessionExercise>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<WorkoutSession>()).forEach(modelContext.delete)
        try modelContext.save()

        if wantsEmpty {
            try modelContext.fetch(FetchDescriptor<ScheduledWorkout>()).forEach(modelContext.delete)
            try modelContext.save()
            return
        }

        if wantsCompleted {
            let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
            guard let schedule = schedules.first(where: {
                $0.plannedDate.isSameDay(as: .now) && $0.status == .planned
            }) else {
                return
            }
            let sessionID = try WorkoutService.start(schedule: schedule, in: modelContext)
            let session = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .first { $0.id == sessionID }
            let logs = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter { $0.sessionID == sessionID }
            for log in logs {
                log.actualWeight = max(1, log.targetWeight)
                log.actualReps = max(1, log.targetReps)
                log.isCompleted = true
                log.completedAt = .now
            }
            session?.status = .completed
            session?.completedAt = .now
            schedule.status = .completed
            try modelContext.save()
            return
        }

        guard let exercise = try modelContext.fetch(FetchDescriptor<Exercise>())
            .first(where: { $0.volumeUnit == .kilogram }) else {
            return
        }
        let count = wantsSeven ? 7 : 1
        for offset in (0..<count).reversed() {
            let day = Date.now.startOfDay.addingDays(-offset)
            let startedAt = day.addingTimeInterval(10 * 60 * 60)
            let session = WorkoutSession(
                templateName: "首页容量夹具 \(offset)",
                plannedDate: day,
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(45 * 60),
                status: .completed,
                importIdentifier: "ui-test-home-volume-\(offset)"
            )
            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: 0,
                targetSets: 1,
                minReps: 10,
                maxReps: 10,
                targetWeight: Double((count - offset) * 10),
                restSeconds: 90,
                muscleGroup: exercise.muscleGroup,
                volumeUnit: .kilogram
            )
            let log = SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: 1,
                targetWeight: snapshot.targetWeight,
                targetReps: 10,
                actualWeight: snapshot.targetWeight,
                actualReps: 10,
                isCompleted: true,
                completedAt: startedAt.addingTimeInterval(60)
            )
            modelContext.insert(session)
            modelContext.insert(snapshot)
            modelContext.insert(log)
        }
        try modelContext.save()
    }
    #endif
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

private struct DeviceHistoryMergeReceipt: Codable {
    let completedAt: Date
    let sourceFile: String
    let summary: DeviceHistoryMergeSummary?
    let errorMessage: String?
}

import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPrepared = false
    @State private var editorialTab = 0
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
    @State private var workoutSaveIssues = WorkoutSaveIssueState()

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = UIColor(AppTheme.background)
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(AppTheme.secondaryText)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(AppTheme.background)
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.ink)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.ink)
    }

    private var appContent: some View {
        Group {
            if isPrepared {
                if isHistoryUITest {
                    NavigationStack {
                        HistoryView().legacyTrainingScreen()
                    }
                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                } else {
                    VStack(spacing: 0) {
                        TabView(selection: $editorialTab) {
                            NavigationStack { EditorialTrainingHomeView() }.tag(0)
                                .tabItem { Label("训练", systemImage: "dumbbell") }.toolbar(.hidden, for: .tabBar)
                            NavigationStack { EditorialNutritionHomeView() }.tag(1)
                                .tabItem { Label("饮食", systemImage: "fork.knife") }.toolbar(.hidden, for: .tabBar)
                            NavigationStack { EditorialProgressHomeView() }.tag(2)
                                .tabItem { Label("进展", systemImage: "chart.xyaxis.line") }.toolbar(.hidden, for: .tabBar)
                            NavigationStack { EditorialToolsHomeView() }.tag(3)
                                .tabItem { Label("工具", systemImage: "square.grid.2x2") }.toolbar(.hidden, for: .tabBar)
                            NavigationStack { EditorialProfileHomeView() }.tag(4)
                                .tabItem { Label("我的", systemImage: "person") }.toolbar(.hidden, for: .tabBar)
                        }
                        EditorialTabBar(selection: $editorialTab)
                    }.background(EditorialTheme.paper).tint(EditorialTheme.ink)
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
                            .tint(AppTheme.ink)
                        Text("正在准备训练计划…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
    }

    var body: some View {
        // Keep the notice and UIKit-backed TabView in separate layout regions.
        // A root safeAreaInset can overlap the nested navigation bar on iOS.
        VStack(spacing: 0) {
            if workoutSaveIssues.issue != nil {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("训练保存失败")
                            .font(.subheadline.bold())
                            .accessibilityIdentifier("训练保存失败提示")
                        Text("请保持 App 打开，重试确认草稿已保存。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button { workoutSaveIssues.retry(in: modelContext) } label: {
                        Text("重试保存")
                            .font(.subheadline.bold())
                            .frame(minWidth: 84, minHeight: AppTheme.minimumTouchTarget)
                            .background(AppTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(AppTheme.orange)
                    .accessibilityIdentifier("重试训练保存")
                }
                .padding(.horizontal, AppTheme.pageMargin)
                .padding(.vertical, 8)
                .background(AppTheme.elevatedSurface)
            }
            appContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sprintPage()
        .environment(workoutSaveIssues)
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
            .sprintPage()
        }
        .alert("数据同步", isPresented: Binding(
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
                prepareUITestPasteboardFixtureIfRequested()
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
                if CommandLine.arguments.contains(ConfirmedHistoricalBackfillService.maintenanceArgument) {
                    let result = try ConfirmedHistoricalBackfillService.apply(in: modelContext)
                    try writeConfirmedHistoricalBackfillReceipt(result)
                    launchImportMessage = "已恢复 9 月 14 日训练，并将 9 月 19 日跳绳标记为因拼家具跳过。"
                }
                #if DEBUG
                try prepareUITestManualScheduleIfNeeded()
                try prepareUITestHistoricalBackfillScheduleIfRequested()
                try prepareUITestTerminologyFixtureIfRequested()
                try prepareUITestSeatedDipFixtureIfRequested()
                try prepareUITestShortRestFixtureIfRequested()
                try prepareUITestLongExerciseNotesFixtureIfRequested()
                try prepareUITestBodyFeedbackFixtureIfRequested()
                try prepareUITestHistoryFixtureIfRequested()
                try prepareUITestHistoryPrefillFixtureIfRequested()
                try prepareUITestIsometricSecondsFixtureIfRequested()
                try prepareUITestProgressFixtureIfRequested()
                try prepareUITestHomeFixtureIfRequested()
                try prepareRedesignPreviewIfRequested()
                try prepareUITestRecordedDayIfRequested()
                try ConfirmedTrainingPlanUITestFixture.prepare(in: modelContext)
                try TrainingCoachUITestFixture.prepare(in: modelContext)
                #endif
                do {
                    launchImportMessage = try MealExchangeService.processLaunchRequest(arguments: CommandLine.arguments, in: modelContext)
                        ?? importDeviceHistoryMergeIfRequested()
                        ?? importLaunchHistoryIfRequested()
                        ?? launchImportMessage
                } catch {
                    launchImportMessage = "同步未完成：\(error.localizedDescription)"
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
                try await BodyweightVolumeMigration.backfillMissingSnapshotsFromHealth(in: modelContext)
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

    private func prepareUITestPasteboardFixtureIfRequested() {
        guard CommandLine.arguments.contains("--ui-testing"),
              let value = ProcessInfo.processInfo.environment["XFIT_UI_TEST_PASTEBOARD"]
        else { return }
        UIPasteboard.general.string = value
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
    @MainActor
    private func prepareUITestManualScheduleIfNeeded() throws {
        guard CommandLine.arguments.contains("--ui-testing"),
              !CommandLine.arguments.contains("--ui-testing-confirmed-plan-import"),
              !CommandLine.arguments.contains("--ui-testing-daily-prefill"),
              !CommandLine.arguments.contains("--ui-testing-lower-body-week") else { return }
        let today = Date.now.startOfDay
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !sessions.contains(where: { $0.status == .inProgress }) else { return }
        let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: { $0.plannedDate.isSameDay(as: today) }) else { return }
        let templates = try modelContext.fetch(FetchDescriptor<WorkoutTemplate>())
        guard let template = templates.first(where: { $0.name == "推 · 胸肩三头" })
            ?? templates.first(where: { !$0.isOneOff }) else { return }
        _ = try ScheduleService.addManual(template: template, on: today, in: modelContext)
    }

    @MainActor
    private func prepareUITestHistoricalBackfillScheduleIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-historical-backfill") else { return }
        let targetDate = Date.now.addingDays(-2).startOfDay
        let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: { $0.plannedDate.isSameDay(as: targetDate) }) else { return }
        let templates = try modelContext.fetch(FetchDescriptor<WorkoutTemplate>())
        guard let template = templates.first(where: { !$0.isOneOff }) else { return }
        _ = try ScheduleService.addManual(template: template, on: targetDate, in: modelContext)
    }

    @MainActor
    private func prepareRedesignPreviewIfRequested() throws {
        guard CloudSyncRuntime.isTesting,
              !CloudSyncRuntime.usesPersistentUITestStore,
              CommandLine.arguments.contains("--ui-redesign-preview") else { return }
        let program = try FatLossService.createProgram(in: modelContext)
        if CommandLine.arguments.contains("--ui-testing-lower-body-week") {
            _ = try TrainingPreferenceService.activateLowerBodySpecialtyWeek(
                programID: program.id,
                effectiveDate: FatLossCalendar.date(2026, 9, 14),
                in: modelContext
            )
        }
        _ = try FatLossService.importMeals(program: program, from: .now, in: modelContext)
        for offset in 0..<7 {
            modelContext.insert(BodyMeasurement(date: Date.now.startOfDay.addingDays(-offset),
                weightKg: 85 + Double(offset) * 0.1, waistCm: offset == 0 ? 96 : nil,
                notes: "仅交互原型演示，不是真实测量"))
        }
        try modelContext.save()
    }

    private func prepareUITestRecordedDayIfRequested() throws {
        #if DEBUG && targetEnvironment(simulator)
        guard CloudSyncRuntime.isTesting, !CloudSyncRuntime.usesPersistentUITestStore,
              CommandLine.arguments.contains("--ui-testing-recorded-day") else { return }
        let today = Date.now.startOfDay
        let partial = CommandLine.arguments.contains("--ui-testing-recorded-day-partial")
        let template = WorkoutTemplate(name: "UI状态测试模板", weekday: today.weekdayNumber)
        let oldPlan = ScheduledWorkout(templateID: template.id, templateName: "UI旧安排·胸肩", plannedDate: today)
        oldPlan.plannedLocalDay = TrainingLocalDate.key(today)
        oldPlan.plannedTimeZoneIdentifier = TimeZone.current.identifier
        modelContext.insert(template); modelContext.insert(oldPlan)
        let linked = partial ? ScheduledWorkout(templateID: template.id, templateName: "UI已结束安排", plannedDate: today, status: .completed) : nil
        if let linked {
            linked.plannedLocalDay = TrainingLocalDate.key(today)
            modelContext.insert(linked)
        }
        let exercise = Exercise(name: "UI状态测试动作", muscleGroup: "腿部", equipment: "哑铃")
        modelContext.insert(exercise)
        for (index, date) in [today, today.addingDays(-60)].enumerated() {
            let session = WorkoutSession(id: UUID(uuidString: index == 0
                ? "DAD00000-0000-4000-8000-000000000001" : "DAD00000-0000-4000-8000-000000000002")!,
                scheduledWorkoutID: index == 0 ? linked?.id : nil,
                templateName: index == 0 ? "UI实际下肢" : "UI无安排实际", plannedDate: date,
                startedAt: date.addingTimeInterval(3_600), completedAt: date.addingTimeInterval(5_400), status: .completed)
            session.trainingLocalDay = TrainingLocalDate.key(date)
            session.trainingTimeZoneIdentifier = TimeZone.current.identifier
            let count = index == 0 && partial ? 20 : 3
            let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id,
                exerciseName: exercise.name, order: 0, targetSets: count, minReps: 8, maxReps: 12,
                targetWeight: 20, restSeconds: 90, muscleGroup: "腿部")
            modelContext.insert(session); modelContext.insert(snapshot)
            for number in 1...count {
                let completed = count != 20 || number <= 17
                modelContext.insert(SetLog(sessionID: session.id, sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id, setNumber: number, targetWeight: 20, targetReps: 10,
                    actualWeight: completed ? 20 : 0, actualReps: completed ? 10 : 0, isCompleted: completed))
            }
        }
        try modelContext.save()
        #endif
    }

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

    private func writeConfirmedHistoricalBackfillReceipt(
        _ result: ConfirmedHistoricalBackfillResult
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        try data.write(
            to: URL.documentsDirectory.appendingPathComponent(
                ConfirmedHistoricalBackfillService.receiptFileName
            ),
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
        if !exercises.contains(where: { $0.name == "MTS 下斜卧推" }) {
            let exercise = Exercise(
                name: "MTS 下斜卧推",
                muscleGroup: "胸部",
                equipment: "器械",
                isBuiltIn: false
            )
            modelContext.insert(exercise)
            exercises.append(exercise)
        }
        if !exercises.contains(where: { $0.name == "MTS 划船" }) {
            let exercise = Exercise(
                name: "MTS 划船",
                muscleGroup: "背部",
                equipment: "MTS 器械",
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
    private func prepareUITestLongExerciseNotesFixtureIfRequested() throws {
        guard CloudSyncRuntime.isUITesting,
              !CloudSyncRuntime.usesPersistentUITestStore,
              CommandLine.arguments.contains("--ui-testing-long-exercise-notes") else { return }
        guard let exercise = try modelContext.fetch(FetchDescriptor<Exercise>())
            .first(where: { $0.name == "杠铃卧推" }) else { return }
        exercise.notes = """
        训练说明测试夹具，仅用于验证完整说明可读。
        第一组保留约三次规范动作余力，先确认当天舒适度。
        本周不做力竭、递减组或额外重握力收尾。
        复合动作充分休息，不用极短休息牺牲动作质量。
        酒店器械不足时可以省去动作，不为凑组数重复堆量。
        跳绳只能替代有氧，不能算完成背部力量训练。
        最后一条：左肘疼痛逐组增加时停止该动作，手臂训练可以省去，不补组。
        """
        // This explicit, in-memory UI fixture must match the already frozen day plan.
        let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
        for schedule in schedules where schedule.status == .planned && schedule.plannedDate.isSameDay(as: .now) {
            var snapshot = schedule.planSnapshot
            for index in snapshot.indices where snapshot[index].exerciseID == exercise.id {
                snapshot[index].exerciseNotes = exercise.notes
            }
            schedule.planSnapshot = snapshot
        }
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
    private func prepareUITestSeatedDipFixtureIfRequested() throws {
        guard CloudSyncRuntime.isUITesting, CloudSyncRuntime.isTesting,
              CommandLine.arguments.contains("--ui-testing-seated-dip") else { return }
        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        guard !exercises.contains(where: { $0.approvedCanonicalID == "machine_triceps_press" }) else {
            return
        }
        // Exercise the real confirmed merge, not a hand-crafted archived row.
        modelContext.insert(Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械", isBuiltIn: false))
        modelContext.insert(Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械", isBuiltIn: false))
        try ExerciseCatalogService.consolidateConfirmedAliases(in: modelContext)
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestHistoryPrefillFixtureIfRequested() throws {
        guard CloudSyncRuntime.isUITesting, CloudSyncRuntime.isTesting,
              CommandLine.arguments.contains("--ui-testing-history-prefill") else { return }
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        guard !sessions.contains(where: { $0.importIdentifier == "ui-test-history-prefill" }),
              let exercise = try modelContext.fetch(FetchDescriptor<Exercise>())
                .first(where: { $0.name == "杠铃卧推" }) else { return }

        // Only an explicitly requested, isolated in-memory UI test gets this
        // compatible completed history. Production and persistent stores never do.
        let completedAt = Date.now.addingDays(-60)
        let startedAt = completedAt.addingTimeInterval(-3_600)
        let session = WorkoutSession(
            templateName: "历史预填验证",
            plannedDate: startedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            status: .completed,
            importIdentifier: "ui-test-history-prefill"
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 4,
            minReps: 12,
            maxReps: 12,
            targetWeight: 25,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup,
            volumeUnit: exercise.volumeUnit,
            equipmentSnapshot: exercise.equipment
        )
        modelContext.insert(session)
        modelContext.insert(snapshot)
        for setNumber in 1...4 {
            modelContext.insert(SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: setNumber,
                targetWeight: 25,
                targetReps: 12,
                actualWeight: 25,
                actualReps: 12,
                rir: 2,
                isCompleted: true,
                completedAt: completedAt,
                targetWeightSide: .bilateral,
                targetRepsSide: .bilateral,
                actualWeightSide: .bilateral,
                actualRepsSide: .bilateral
            ))
        }
        try modelContext.save()
    }

    @MainActor
    private func prepareUITestIsometricSecondsFixtureIfRequested() throws {
        guard CommandLine.arguments.contains("--ui-testing-isometric-seconds") else { return }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        let exercise: Exercise
        if let existing = exercises.first(where: { $0.name == "UI 等长平板支撑" }) {
            existing.volumeUnit = .second
            exercise = existing
        } else {
            exercise = Exercise(
                name: "UI 等长平板支撑",
                muscleGroup: "核心",
                equipment: "自重",
                isBuiltIn: false,
                notes: "按组记录保持秒数",
                volumeUnit: .second
            )
            modelContext.insert(exercise)
        }

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        if !sessions.contains(where: { $0.importIdentifier == "ui-test-isometric-active" }) {
            let activeSession = WorkoutSession(
                templateName: "等长训练进行中",
                plannedDate: .now,
                startedAt: .now,
                status: .inProgress,
                importIdentifier: "ui-test-isometric-active"
            )
            let activeSnapshot = SessionExercise(
                sessionID: activeSession.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: 0,
                targetSets: 2,
                minReps: 30,
                maxReps: 45,
                targetWeight: 0,
                restSeconds: 60,
                muscleGroup: exercise.muscleGroup,
                exerciseNotes: exercise.notes,
                volumeUnit: .second
            )
            modelContext.insert(activeSession)
            modelContext.insert(activeSnapshot)
            for (index, seconds) in [45, 30].enumerated() {
                modelContext.insert(SetLog(
                    sessionID: activeSession.id,
                    sessionExerciseID: activeSnapshot.id,
                    exerciseID: exercise.id,
                    setNumber: index + 1,
                    targetWeight: 0,
                    targetReps: seconds,
                    actualWeight: 0,
                    actualReps: seconds
                ))
            }
        }

        if !sessions.contains(where: { $0.importIdentifier == "ui-test-isometric-history" }) {
            let completedAt = Date.now.addingTimeInterval(-3_600)
            let startedAt = completedAt.addingTimeInterval(-600)
            let historySession = WorkoutSession(
                templateName: "等长训练历史验证",
                plannedDate: startedAt,
                startedAt: startedAt,
                completedAt: completedAt,
                status: .completed,
                notes: "秒数历史应与 kg 分开",
                importIdentifier: "ui-test-isometric-history"
            )
            let historySnapshot = SessionExercise(
                sessionID: historySession.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: 0,
                targetSets: 2,
                minReps: 30,
                maxReps: 45,
                targetWeight: 0,
                restSeconds: 60,
                muscleGroup: exercise.muscleGroup,
                exerciseNotes: exercise.notes,
                volumeUnit: .second
            )
            modelContext.insert(historySession)
            modelContext.insert(historySnapshot)
            for (index, seconds) in [45, 30].enumerated() {
                modelContext.insert(SetLog(
                    sessionID: historySession.id,
                    sessionExerciseID: historySnapshot.id,
                    exerciseID: exercise.id,
                    setNumber: index + 1,
                    targetWeight: 0,
                    targetReps: seconds,
                    actualWeight: 0,
                    actualReps: seconds,
                    rir: 2,
                    isCompleted: true,
                    completedAt: completedAt
                ))
            }
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
            let baseStartedAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: fixture.1)
                ?? fixture.1
            let startedAt = fixture.0 == "本周拉训练"
                ? baseStartedAt.addingTimeInterval(2 * 3_600)
                : baseStartedAt
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

        for offset in 0..<8 {
            guard let date = calendar.date(byAdding: .day, value: offset - 7, to: today) else { continue }
            modelContext.insert(
                BodyMeasurement(
                    date: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: date) ?? date,
                    weightKg: 83.4 + Double(offset) * 0.1,
                    source: offset == 2 ? .healthKit : .manual,
                    createdAt: date
                )
            )
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
        let wantsMenuStatus = arguments.contains("--ui-testing-home-menu-status")
        guard wantsEmpty || wantsSingle || wantsSeven || wantsCompleted || wantsMenuStatus else { return }

        try modelContext.fetch(FetchDescriptor<SetLog>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<SessionExercise>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<WorkoutSession>()).forEach(modelContext.delete)
        try modelContext.save()

        if wantsEmpty {
            try modelContext.fetch(FetchDescriptor<ScheduledWorkout>()).forEach(modelContext.delete)
            try modelContext.save()
            return
        }

        if wantsMenuStatus {
            let schedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>())
            schedules.first(where: {
                $0.plannedDate.isSameDay(as: .now) && $0.status == .planned
            })?.templateName = "核心 + 腿部 · 当天菜单"
            try modelContext.save()
            // A named plan alone is unstarted; completed/volume combinations
            // deliberately continue into their explicit fixture below.
            if !wantsCompleted && !wantsSingle && !wantsSeven { return }
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

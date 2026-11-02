import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct AppSettingsView: View {
    enum Mode: String, CaseIterable {
        case preferences = "通用"
        case data = "数据"
    }

    @State private var selectedMode: Mode

    init(initialMode: Mode = .preferences) {
        _selectedMode = State(initialValue: initialMode)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var schedules: [ScheduledWorkout]
    @Query private var bodyMeasurements: [BodyMeasurement]
    @Query private var exercises: [Exercise]

    @AppStorage(NotificationService.workoutEnabledKey) private var workoutRemindersEnabled = false
    @AppStorage(NotificationService.workoutHourKey) private var workoutReminderHour = 18
    @AppStorage(NotificationService.workoutMinuteKey) private var workoutReminderMinute = 0
    @AppStorage(NotificationService.restEnabledKey) private var restNotificationsEnabled = true
    @AppStorage(HealthKitService.enabledKey) private var healthKitEnabled = false

    @State private var notificationStatus = "未检查"
    @State private var healthStatus = "未连接"
    @State private var backupURL: URL?
    @State private var csvURL: URL?
    @State private var showImporter = false
    @State private var pendingBackupData: Data?
    @State private var backupPreview: BackupPreview?
    @State private var showImportConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: workoutReminderHour, minute: workoutReminderMinute, second: 0, of: .now) ?? .now
        } set: { date in
            workoutReminderHour = Calendar.current.component(.hour, from: date)
            workoutReminderMinute = Calendar.current.component(.minute, from: date)
            Task { await NotificationService.syncWorkoutReminders(schedules) }
        }
    }

    private var dataStorageDescription: String {
        if CloudSyncRuntime.isConfigured {
            return "训练、营养和身体数据保存在本机，并通过你的私人 iCloud 自动同步。你仍可随时导出完整 JSON 备份或 CSV 训练记录。"
        }
        return "训练、营养和身体数据保存在本机。你仍可随时导出完整 JSON 备份或 CSV 训练记录。"
    }

    var body: some View {
        VStack(spacing: 0) {
            modeSelector
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if selectedMode == .preferences {
                        SprintPageHeader(title: "设置", icon: "slider.horizontal.3")
                        reminderCard
                        healthCard
                        terminologyCard
                    } else {
                        dataCard
                    }
                    DisclosureGroup("关于 X-Fit") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appVersionText).font(.subheadline.weight(.semibold))
                            Text(dataStorageDescription)
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }
                    .font(.subheadline).tint(AppTheme.secondaryText)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("设置-关于")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .id(selectedMode)
        }
        .sprintPage()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await refreshNotificationStatus()
            healthStatus = healthKitEnabled ? "已授权；完成训练后写入 Apple 健康" : "未启用"
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "导入 X-Fit 备份？",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("导入缺失记录") { importPendingBackup() }
            Button("取消", role: .cancel) { pendingBackupData = nil }
        } message: {
            if let preview = backupPreview {
                Text("将检查 \(preview.total) 条主要记录；相同 UUID 的现有数据会跳过，不会静默覆盖。")
            }
        }
        .alert("完成", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    modeLabel(mode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedMode == mode ? Color.black : AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selectedMode == mode ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("设置-\(mode.rawValue)")
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }.padding(4).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func modeLabel(_ mode: Mode) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Decorative symbols otherwise force two-character labels onto
            // separate lines and consume the small screen's scroll viewport.
            Text(mode.rawValue)
        } else {
            Label(mode.rawValue, systemImage: mode == .preferences ? "slider.horizontal.3" : "externaldrive")
        }
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = info?["CFBundleVersion"] as? String ?? "未知"
        return "X-Fit \(version) (\(build))"
    }

    private var reminderCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { workoutRemindersEnabled },
                set: { enabled in setWorkoutReminders(enabled) }
            )) {
                settingsLabel("训练日提醒", detail: notificationStatus, icon: "bell.badge.fill")
            }
            .tint(AppTheme.ink)
            .padding(14)

            if workoutRemindersEnabled {
                Divider().overlay(AppTheme.line).padding(.leading, 54)
                DatePicker("默认提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .padding(14)
            }

            Divider().overlay(AppTheme.line).padding(.leading, 54)
            Toggle(isOn: Binding(
                get: { restNotificationsEnabled },
                set: { enabled in setRestNotifications(enabled) }
            )) {
                settingsLabel("休息结束提醒", detail: "锁屏或切到后台时仍提醒", icon: "timer")
            }
            .tint(AppTheme.ink)
            .padding(14)
        }
        .cardSurface(padding: 0, cornerRadius: 18)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsLabel("Apple 健康", detail: healthStatus, icon: "heart.fill")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { healthActions }
                VStack(alignment: .leading, spacing: 10) { healthActions }
            }
            DisclosureGroup("连接后会使用哪些数据") {
                Text("只写入已完成的传统力量训练；不会伪造心率或消耗热量。身体数据仅在你主动点击时读取。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 8)
            }
            .font(.caption).tint(AppTheme.secondaryText)
            .accessibilityIdentifier("设置-健康数据说明")
        }.cardSurface()
    }

    @ViewBuilder
    private var healthActions: some View {
        Button(healthKitEnabled ? "重新授权" : "连接") { connectHealthKit() }
            .buttonStyle(SprintSecondaryButtonStyle())
        if healthKitEnabled {
            Button("导入身体数据") { importHealthBodyData() }
                .buttonStyle(SprintSecondaryButtonStyle())
        }
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SprintPageHeader(title: "数据", icon: "externaldrive")
                Button { prepareBackup() } label: {
                    Label("生成 JSON 备份", systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity)
                }
                .neonButtonStyle()
                .accessibilityIdentifier("设置-生成备份")
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("分享最新备份", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.tint(AppTheme.ink)
                }
            }.padding(.vertical, 4)

            VStack(spacing: 0) {
                NavigationLink { HistoricalWorkoutImportView().legacyTrainingScreen() } label: {
                    settingsAction("导入历史训练", detail: "预览并核对逐组记录", icon: "square.and.arrow.down")
                }.accessibilityIdentifier("设置-导入历史训练")
                Divider().overlay(AppTheme.line).padding(.leading, 64)
                NavigationLink { ProgramDataExportView().legacyTrainingScreen() } label: {
                    settingsAction("导出减脂周期", detail: "导出周期计划与记录", icon: "square.and.arrow.up")
                }.accessibilityIdentifier("设置-导出减脂周期")
                Divider().overlay(AppTheme.line).padding(.leading, 64)
                Button { showImporter = true } label: {
                    settingsAction("导入 JSON", detail: "预检后补入缺失记录", icon: "arrow.down.doc")
                }.accessibilityIdentifier("设置-导入备份")
                Divider().overlay(AppTheme.line).padding(.leading, 64)
                Button { prepareCSV() } label: {
                    settingsAction("导出训练 CSV", detail: "逐组重量、次数与 RIR", icon: "tablecells")
                }.accessibilityIdentifier("设置-生成训练CSV")
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("分享最新 CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.tint(AppTheme.ink).padding(.bottom, 8)
                }
            }.buttonStyle(.plain).cardSurface(padding: 0)

            DisclosureGroup("备份与恢复说明") {
                Text("完整 JSON 用于恢复本地数据；训练 CSV 用于查看逐组记录。导入前会先预检，相同 UUID 的现有记录会跳过。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).padding(.top, 8)
            }
            .font(.subheadline).tint(AppTheme.secondaryText)
            .accessibilityIdentifier("设置-备份说明")
        }
    }

    private func settingsAction(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            settingsLabel(title, detail: detail, icon: icon)
            Image(systemName: "chevron.right")
                .font(dynamicTypeSize.isAccessibilitySize ? .system(size: 16, weight: .bold) : .caption2.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText).accessibilityHidden(true)
        }.padding(16).frame(minHeight: 64).contentShape(Rectangle())
    }

    private var terminologyCard: some View {
        let active = exercises.filter { !$0.isArchived }
        let pending = active.filter { $0.terminologyDecision == .pending }.count
        let unresolved = active.filter {
            $0.terminologyDecision == .pending && $0.terminologyReviewStatus == .unresolved
        }.count

        return NavigationLink {
            ExerciseTerminologyReviewView()
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                settingsLabel("动作名称审核", detail: "待审核 \(pending) 个 · 未唯一解析 \(unresolved) 个", icon: "character.book.closed")
            } else {
              HStack(spacing: 12) {
                SprintIcon(systemName: "character.book.closed", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("动作名称审核")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("待审核 \(pending) 个 · 未唯一解析 \(unresolved) 个")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            }
        }
        .buttonStyle(.plain)
        .cardSurface()
        .accessibilityIdentifier("设置-动作名称审核")
    }

    @ViewBuilder
    private func settingsLabel(_ title: String, detail: String, icon: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                Text(detail).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        } else {
        HStack(spacing: 12) {
            SprintIcon(systemName: icon, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
        }
    }

    private func setWorkoutReminders(_ enabled: Bool) {
        guard enabled else {
            workoutRemindersEnabled = false
            Task {
                await NotificationService.syncWorkoutReminders(schedules)
                await refreshNotificationStatus()
            }
            return
        }

        Task {
            do {
                let granted = try await NotificationService.requestAuthorization()
                workoutRemindersEnabled = granted
                await NotificationService.syncWorkoutReminders(schedules)
                await refreshNotificationStatus()
            } catch {
                workoutRemindersEnabled = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setRestNotifications(_ enabled: Bool) {
        guard enabled else {
            restNotificationsEnabled = false
            return
        }
        Task {
            do {
                let granted = try await NotificationService.requestAuthorization()
                restNotificationsEnabled = granted
                await refreshNotificationStatus()
            } catch {
                restNotificationsEnabled = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshNotificationStatus() async {
        switch await NotificationService.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "系统通知已授权"
        case .denied:
            notificationStatus = "系统通知已拒绝，请到设置中开启"
        case .notDetermined:
            notificationStatus = "尚未请求系统权限"
        @unknown default:
            notificationStatus = "状态未知"
        }
    }

    private func connectHealthKit() {
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                healthKitEnabled = true
                healthStatus = "已授权；完成训练后自动写入"
            } catch {
                healthKitEnabled = false
                healthStatus = "授权失败"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importHealthBodyData() {
        Task {
            do {
                guard let snapshot = try await HealthKitService.shared.latestBodySnapshot() else {
                    resultMessage = "Apple 健康里暂时没有可读取的体重或体脂数据。"
                    return
                }
                let alreadyImported = bodyMeasurements.contains {
                    $0.source == .healthKit
                        && abs($0.date.timeIntervalSince(snapshot.date)) < 1
                        && $0.weightKg == snapshot.weightKg
                        && $0.bodyFatPercent == snapshot.bodyFatPercent
                }
                guard !alreadyImported else {
                    resultMessage = "这条 Apple 健康身体数据已经导入过了。"
                    return
                }
                modelContext.insert(BodyMeasurement(
                    date: snapshot.date,
                    weightKg: snapshot.weightKg,
                    bodyFatPercent: snapshot.bodyFatPercent,
                    source: .healthKit
                ))
                try modelContext.save()
                resultMessage = "已导入 Apple 健康中最新的身体数据。"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareBackup() {
        do {
            backupURL = try DataExportService.createBackup(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCSV() {
        do {
            csvURL = try DataExportService.createCSV(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let data = try DataExportService.loadBackupData(from: url)
            backupPreview = try DataExportService.preview(data)
            pendingBackupData = data
            showImportConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPendingBackup() {
        guard let data = pendingBackupData else { return }
        do {
            let summary = try DataExportService.importBackup(data, into: modelContext)
            resultMessage = "导入 \(summary.imported) 条记录，跳过 \(summary.skipped) 条已有记录。"
                + (summary.warning.map { "\n\($0)" } ?? "")
            pendingBackupData = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

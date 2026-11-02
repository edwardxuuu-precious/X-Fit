import SwiftData
import SwiftUI

/// A civil day's plans and actuals share one surface; reading never changes their state.
struct TrainingDateMenuView: View {
    @State private var localDay: String
    init(localDay: String) { _localDay = State(initialValue: localDay) }
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(sort: \ScheduledWorkout.createdAt) private var schedules: [ScheduledWorkout]
    @Query private var sessions: [WorkoutSession]
    @Query(sort: \JumpRopeEntry.date, order: .reverse) private var rope: [JumpRopeEntry]
    @Query private var links: [ProgramWorkoutLink]
    @Query private var revisions: [TrainingProgramRevision]
    @Query private var exercises: [Exercise]
    @State private var addingRope = false
    @State private var editingRope: ScheduledWorkout?
    @State private var recordingRope: ScheduledWorkout?
    @State private var recordingCardio: ScheduledWorkout?
    @State private var activeID: UUID?
    @State private var showActive = false
    @State private var starting = false
    @State private var error: String?
    @State private var progress: [UUID: TrainingWorkSetProgress] = [:]
    @State private var managing: ScheduledWorkout?
    @State private var rescheduling: ScheduledWorkout?
    @State private var skipping: ScheduledWorkout?
    @State private var restoring: ScheduledWorkout?
    @State private var editingSchedule: ScheduledWorkout?
    @State private var viewingSchedule: ScheduledWorkout?
    @State private var skipReason = ""
    @State private var managementUndo: ScheduleManagementUndo?
    @State private var managementMessage: String?
    @State private var lastManagedID: UUID?

    private var date: Date? { TrainingLocalDate.date(localDay) }
    private var supersededScheduleIDs: Set<UUID> {
        ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in: schedules)
    }
    private var daySchedules: [ScheduledWorkout] {
        let retired = supersededScheduleIDs
        return schedules.filter { !retired.contains($0.id) && TrainingScheduleDate.localDay($0) == localDay }
    }
    private var dayRope: [JumpRopeEntry] { rope.filter { TrainingJumpRopeDate.localDay($0, schedules: schedules) == localDay } }
    private var summary: TrainingDaySummary {
        TrainingDaySummary(localDay: localDay, schedules: schedules, sessions: sessions,
            progress: progress, jumpRopeEntries: rope, excludedScheduleIDs: supersededScheduleIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("训练日期").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    if let date {
                        DatePicker("训练日期", selection: Binding(get: {
                            TrainingLocalDate.date(localDay) ?? date
                        }, set: { localDay = TrainingLocalDate.key($0) }), displayedComponents: .date)
                            .labelsHidden().font(.headline)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(minHeight: 44)
                            .accessibilityIdentifier("日期菜单-选择日期")
                    } else { Text(localDay).font(.title2.bold()) }
                    Text(summary.accessibilityLabel).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("日期菜单-" + localDay)

                let visible = daySchedules.filter { $0.status != .skipped }
                if visible.isEmpty && !summary.hasActualRecords && summary.activeSessions.isEmpty {
                    ContentUnavailableView("这天还没有训练项目", systemImage: "calendar",
                        description: Text("从右上角添加当天要练的项目。"))
                }
                ForEach(visible) { schedule in scheduleCard(schedule) }

                let independent = (summary.activeSessions + summary.recordedSessions).filter { session in
                    !daySchedules.contains { $0.id == session.scheduledWorkoutID }
                }
                ForEach(independent) { session in
                    TrainingActualSessionRow(session: session, progress: progress[session.id])
                }
                let unlinkedRope = dayRope.filter { entry in
                    !daySchedules.contains { $0.id == entry.scheduledWorkoutID }
                }
                if !unlinkedRope.isEmpty {
                    Text("当天跳绳记录").font(.headline)
                    ForEach(unlinkedRope) { entry in recordRow(entry) }
                }
                let skipped = daySchedules.filter { $0.status == .skipped }
                if !skipped.isEmpty {
                    DisclosureGroup("已跳过的安排（\(skipped.count)）") {
                        VStack(spacing: 16) { ForEach(skipped) { schedule in scheduleCard(schedule) } }
                            .padding(.top, 12)
                    }.font(.subheadline)
                }
            }.padding(20).containerRelativeFrame(.horizontal)
        }
        .sprintPage().buttonStyle(.plain)
        .navigationTitle("训练菜单").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let date {
                    Menu {
                        NavigationLink { DailyWorkoutBuilderView(initialDate: date).legacyTrainingScreen() } label: {
                            Label("力量训练", systemImage: "dumbbell")
                        }
                        Button { addingRope = true } label: { Label("跳绳", systemImage: "figure.jumprope") }
                            .accessibilityIdentifier("日期菜单-添加跳绳")
                    } label: {
                        Label("添加训练项目", systemImage: "plus").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityIdentifier("日期菜单-添加项目")
                }
            }
        }
        .sheet(isPresented: $addingRope) { JumpRopeMenuPlanSheet(localDay: localDay) }
        .sheet(item: $editingRope) { JumpRopeMenuPlanSheet(localDay: localDay, editing: $0) }
        .sheet(item: $recordingRope) { JumpRopeMenuRecordSheet(schedule: $0) }
        .sheet(item: $recordingCardio) { CardioWorkoutRecordSheet(schedule: $0) }
        .sheet(item: $rescheduling) { schedule in
            RescheduleWorkoutView(schedule: schedule, validate: { date in
                try ScheduleService.validateManagedReschedule(schedule, to: date, in: context)
            }, onSave: { date in
                let undo = try ScheduleService.rescheduleManaged(schedule, to: date, in: context)
                reportManagement(undo, message: "已改期至" + date.formatted(.dateTime.month().day().locale(locale)))
            }).tint(AppTheme.ink)
        }
        .confirmationDialog("管理安排", isPresented: Binding(
            get: { managing != nil }, set: { if !$0 { managing = nil } }
        ), titleVisibility: .visible) {
            if let schedule = managing {
                if ScheduleService.canManage(schedule, in: context) {
                    Button("调整训练日期") { rescheduling = schedule }
                    if schedule.status == .skipped {
                        Button("恢复这次训练") { restoring = schedule }
                    } else {
                        Button("跳过这次训练", role: .destructive) {
                            skipReason = ""; skipping = schedule
                        }
                    }
                    if schedule.jumpRopePlan != nil {
                        Button("编辑本次训练内容") { editingRope = schedule }
                            .disabled(schedule.status != .planned)
                    } else if !isRope(schedule), CardioWorkoutPresentation.plan(schedule) == nil {
                        Button("编辑本次训练内容") { editingSchedule = schedule }
                            .disabled(schedule.status != .planned)
                    }
                }
                Button("查看训练安排") { viewingSchedule = schedule }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let schedule = managing {
                Text(schedule.templateName + " · " + TrainingScheduleDate.displayDate(schedule)
                    .formatted(.dateTime.month().day().locale(locale)))
            }
        }
        .alert("跳过这次训练？", isPresented: Binding(
            get: { skipping != nil }, set: { if !$0 { skipping = nil } }
        )) {
            TextField("原因（可选）", text: $skipReason)
            Button("取消", role: .cancel) { skipping = nil; skipReason = "" }
            Button("确认跳过", role: .destructive) { skipSelected() }
        } message: {
            Text("保留已跳过记录，不计为完成。其他计划按原安排执行。")
        }
        .alert("恢复这次训练？", isPresented: Binding(
            get: { restoring != nil }, set: { if !$0 { restoring = nil } }
        )) {
            Button("取消", role: .cancel) { restoring = nil }
            Button("确认恢复") { restoreSelected() }
        } message: {
            if let schedule = restoring {
                Text("恢复为" + TrainingScheduleDate.displayDate(schedule).formatted(.dateTime.month().day().locale(locale)) + "的待练计划。")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let managementMessage {
                VStack(alignment: .leading, spacing: 2) {
                    Text(managementMessage).font(.caption).accessibilityIdentifier("计划管理-结果")
                    HStack {
                        if let schedule = schedules.first(where: { $0.id == lastManagedID }),
                           TrainingScheduleDate.localDay(schedule) != localDay {
                            Button("查看计划") { localDay = TrainingScheduleDate.localDay(schedule) }
                                .accessibilityIdentifier("计划管理-查看")
                        }
                        if managementUndo != nil {
                            Button("撤销") { undoManagement() }.accessibilityIdentifier("计划管理-撤销")
                        }
                        Spacer()
                        Button("关闭") { self.managementMessage = nil; managementUndo = nil }
                            .accessibilityIdentifier("计划管理-关闭结果")
                    }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }.padding(.horizontal, 20).padding(.top, 8)
                    .background(AppTheme.surface).foregroundStyle(AppTheme.ink)
            }
        }
        .navigationDestination(isPresented: $showActive) {
            if let activeID { ActiveWorkoutView(sessionID: activeID).legacyTrainingScreen() }
        }
        .navigationDestination(isPresented: Binding(
            get: { editingSchedule != nil }, set: { if !$0 { editingSchedule = nil } }
        )) {
            if let schedule = editingSchedule {
                DailyWorkoutBuilderView(initialDate: TrainingScheduleDate.displayDate(schedule), initialScheduleID: schedule.id)
                    .legacyTrainingScreen()
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { viewingSchedule != nil }, set: { if !$0 { viewingSchedule = nil } }
        )) {
            if let schedule = viewingSchedule { ScheduleView(initialScheduleID: schedule.id).legacyTrainingScreen() }
        }
        .onAppear { reloadProgress() }
        .onChange(of: localDay) { _, _ in reloadProgress() }
        .onChange(of: recordingRope?.id) { _, value in if value == nil { reloadProgress() } }
        .onChange(of: recordingCardio?.id) { _, value in if value == nil { reloadProgress() } }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func isRope(_ schedule: ScheduledWorkout) -> Bool {
        TrainingDateMenuService.isJumpRope(schedule, links: links, revisions: revisions, exercises: exercises)
    }

    private func scheduleCard(_ schedule: ScheduledWorkout) -> some View {
        let ropeProject = isRope(schedule)
        let cardio = CardioWorkoutPresentation.plan(schedule)
        let linked = (summary.activeSessions + summary.recordedSessions).first { $0.scheduledWorkoutID == schedule.id }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: ropeProject ? "figure.jumprope" : TrainingWorkoutPresentation.upcoming(schedule.templateName).symbolName)
                    .font(.system(size: 24)).frame(width: 30).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(TrainingWorkoutPresentation.upcoming(schedule.templateName).title).font(.headline)
                    Text(statusLabel(schedule.status)).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                if ropeProject, schedule.jumpRopePlan != nil, schedule.status == .planned {
                    Button("调整") { editingRope = schedule }.font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("日期菜单-调整跳绳")
                }
            }
            if ropeProject {
                if let plan = schedule.jumpRopePlan {
                    Text("目标 · " + plan.summary).font(.subheadline)
                    if !plan.notes.isEmpty { Text(plan.notes).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                } else if let cardio = TrainingPlanPresentation.cardioDraft(scheduleID: schedule.id, links: links, revisions: revisions) {
                    Text("目标 · " + TrainingPlanPresentation.cardioVolumeSummary(cardio)).font(.subheadline)
                    if !cardio.intervals.isEmpty { Text(cardio.intervals).font(.subheadline) }
                    if !cardio.guidance.isEmpty { Text(cardio.guidance).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
                ForEach(dayRope.filter { $0.scheduledWorkoutID == schedule.id }) { entry in recordRow(entry) }
                if schedule.status == .planned || schedule.status == .skipped {
                    if localDay <= TrainingLocalDate.key(.now) {
                        Button { recordingRope = schedule } label: { EditorialPrimary(title: "记录完成", icon: "checkmark") }
                            .accessibilityIdentifier("日期菜单-记录跳绳-" + schedule.id.uuidString)
                    } else {
                        Text("按计划日期训练后记录").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
            } else if let cardio {
                Text("目标 · " + cardio.durationLabel).font(.subheadline)
                if let linked {
                    if linked.status == .inProgress {
                        TrainingActualSessionRow(session: linked, progress: progress[linked.id])
                    } else {
                        NavigationLink { CardioWorkoutSummaryView(sessionID: linked.id) } label: {
                            EditorialRow(title: "训练总结", subtitle: "实际已记录", icon: "checkmark.circle")
                        }.accessibilityIdentifier("日期菜单-有氧总结")
                    }
                } else if schedule.status == .planned && localDay <= TrainingLocalDate.key(.now) {
                    Button { recordingCardio = schedule } label: { EditorialPrimary(title: "记录完成", icon: "checkmark") }
                        .accessibilityIdentifier("日期菜单-记录有氧")
                } else if localDay > TrainingLocalDate.key(.now) {
                    Text("按计划日期训练后记录").font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            } else if let linked {
                TrainingActualSessionRow(session: linked, progress: progress[linked.id])
            } else if let date {
                NavigationLink { DailyWorkoutBuilderView(initialDate: date, initialScheduleID: schedule.id).legacyTrainingScreen() } label: {
                    EditorialRow(title: "查看与调整", subtitle: schedule.planSnapshot.isEmpty ? nil : "\(schedule.planSnapshot.count) 个动作", icon: "list.bullet")
                }
                if schedule.status == .planned && localDay == TrainingLocalDate.key(.now) {
                    Button { start(schedule) } label: { EditorialPrimary(title: starting ? "准备中…" : "开始训练", icon: "play.fill") }
                        .disabled(starting).accessibilityIdentifier("日期菜单-开始力量")
                }
            }
            Button { managing = schedule } label: {
                Text("管理安排").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("日期菜单-管理安排-" + schedule.id.uuidString)
        }.foregroundStyle(AppTheme.ink).cardSurface(padding: 16, cornerRadius: 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("日期菜单-项目-" + schedule.id.uuidString)
    }

    private func recordRow(_ entry: JumpRopeEntry) -> some View {
        NavigationLink { JumpRopeMenuRecordDetail(entry: entry) } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("跳绳 · 已记录").font(.subheadline.weight(.semibold))
                    Text(entry.displaySummary).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("日期菜单-跳绳记录-" + entry.id.uuidString)
    }

    private func reloadProgress() {
        do {
            progress = try TrainingWorkingSetProgressLoader.load(
                schedules: schedules.filter { TrainingScheduleDate.localDay($0) == localDay }, sessions: sessions,
                includingLocalDays: [localDay], in: context)
        } catch { self.error = error.localizedDescription }
    }

    private func reportManagement(_ undo: ScheduleManagementUndo, message: String) {
        managementUndo = undo
        managementMessage = message
        lastManagedID = undo.scheduleID
        reloadProgress()
    }

    private func skipSelected() {
        guard let schedule = skipping else { return }
        do {
            let undo = try ScheduleService.skipManaged(schedule, reason: skipReason, in: context)
            reportManagement(undo, message: "已跳过这次训练")
        } catch { self.error = error.localizedDescription }
        skipping = nil
        skipReason = ""
    }

    private func restoreSelected() {
        guard let schedule = restoring else { return }
        do {
            let undo = try ScheduleService.restoreManaged(schedule, in: context)
            reportManagement(undo, message: "已恢复这次训练")
        } catch { self.error = error.localizedDescription }
        restoring = nil
    }

    private func undoManagement() {
        guard let undo = managementUndo else { return }
        do {
            try ScheduleService.undoManaged(undo, in: context)
            managementUndo = nil
            managementMessage = "已撤销本次调整"
            reloadProgress()
        } catch { self.error = error.localizedDescription }
    }

    private func statusLabel(_ status: ScheduleStatus) -> String {
        switch status {
        case .planned: return "待练"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        case .skipped: return "已跳过"
        }
    }

    private func start(_ schedule: ScheduledWorkout) {
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do {
                activeID = try await WorkoutService.startUsingAvailableBodyWeight(schedule: schedule, in: context)
                showActive = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct JumpRopeMenuInput {
    var count = ""
    var activeMinutes = ""
    var elapsedMinutes = ""
    var countValue: Int? { Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var activeSeconds: Int? { seconds(activeMinutes) }
    var elapsedSeconds: Int? { seconds(elapsedMinutes) }
    var isValid: Bool {
        (count.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || countValue != nil)
            && (activeMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeSeconds != nil)
            && (elapsedMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || elapsedSeconds != nil)
            && JumpRopeDurationValidation.isValidRecord(count: countValue, active: activeSeconds, elapsed: elapsedSeconds)
    }
    private func seconds(_ text: String) -> Int? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0, value <= 1_440 else { return nil }
        let seconds = Int((value * 60).rounded())
        return seconds > 0 ? seconds : nil
    }
}

private struct JumpRopeMenuFields: View {
    @Binding var input: JumpRopeMenuInput
    let scope: String
    var setCountText: Binding<String>? = nil
    private enum Field: Hashable { case count, active, elapsed, setCount }
    @FocusState private var focused: Field?
    var body: some View {
        TextField("次数（可留空）", text: $input.count).keyboardType(.numberPad)
            .focused($focused, equals: .count)
            .accessibilityIdentifier("跳绳菜单-" + scope + "次数")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = nil }
                        .accessibilityIdentifier("跳绳菜单-收起键盘")
                }
            }
        if let setCountText {
            TextField("总组数（可留空）", text: setCountText).keyboardType(.numberPad)
                .focused($focused, equals: .setCount)
                .accessibilityIdentifier("跳绳菜单-实际总组数")
        }
        TextField("有效时长（分钟，可留空）", text: $input.activeMinutes).keyboardType(.decimalPad)
            .focused($focused, equals: .active)
            .accessibilityIdentifier("跳绳菜单-" + scope + "有效分钟")
        TextField("含休息总时长（分钟，可留空）", text: $input.elapsedMinutes).keyboardType(.decimalPad)
            .focused($focused, equals: .elapsed)
            .accessibilityIdentifier("跳绳菜单-" + scope + "总分钟")
    }
}

private struct JumpRopeMenuPlanSheet: View {
    let localDay: String
    var editing: ScheduledWorkout? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var input = JumpRopeMenuInput()
    @State private var notes = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent("训练日期", value: localDay) }
                Section("计划目标") {
                    JumpRopeMenuFields(input: $input, scope: "计划")
                    TextField("间歇或训练备注（可选）", text: $notes, axis: .vertical)
                }
                Section {
                    Text("填写次数或时长之一。这里保存训练计划，实际完成后再记录。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Button("保存安排") { save() }.buttonStyle(SprintPrimaryButtonStyle())
                        .disabled(saving || !input.isValid).accessibilityIdentifier("跳绳菜单-保存安排")
                }
            }.scrollDismissesKeyboard(.interactively)
                .sprintPage().navigationTitle(editing == nil ? "安排跳绳" : "调整跳绳")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .onAppear {
                    guard let plan = editing?.jumpRopePlan else { return }
                    input.count = plan.targetCount.map(String.init) ?? ""
                    input.activeMinutes = plan.activeSeconds.map { String(format: "%g", Double($0) / 60) } ?? ""
                    input.elapsedMinutes = plan.elapsedSeconds.map { String(format: "%g", Double($0) / 60) } ?? ""
                    notes = plan.notes
                }
                .alert("无法保存安排", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("知道了", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard !saving, input.isValid else { return }
        saving = true
        do {
            try TrainingDateMenuService.saveJumpRopePlan(.init(targetCount: input.countValue,
                activeSeconds: input.activeSeconds, elapsedSeconds: input.elapsedSeconds,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)), localDay: localDay, editing: editing, in: context)
            dismiss()
        } catch { self.error = error.localizedDescription; saving = false }
    }
}

private struct JumpRopeMenuRecordSheet: View {
    let schedule: ScheduledWorkout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var input = JumpRopeMenuInput()
    @State private var setCountText = ""
    @State private var completedAt: Date
    @State private var recordedTimeKnown: Bool
    @State private var saving = false
    @State private var error: String?
    init(schedule: ScheduledWorkout) {
        self.schedule = schedule
        let sameDay = TrainingScheduleDate.localDay(schedule) == TrainingLocalDate.key(.now)
        _completedAt = State(initialValue: sameDay ? .now : TrainingScheduleDate.displayDate(schedule))
        _recordedTimeKnown = State(initialValue: sameDay)
    }
    private var setCountValue: Int? { Int(setCountText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var setCountInputValid: Bool {
        setCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (setCountValue.map { (1...10_000).contains($0) } ?? false)
    }
    private var timeRange: ClosedRange<Date> {
        let start = TrainingScheduleDate.displayDate(schedule).startOfDay
        return start...max(start, min(start.addingDays(1).addingTimeInterval(-1), .now))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("训练日期", value: TrainingScheduleDate.localDay(schedule))
                    Toggle("记录具体完成时间", isOn: $recordedTimeKnown)
                        .accessibilityIdentifier("跳绳菜单-记录具体时间")
                    if recordedTimeKnown {
                        DatePicker("完成时间", selection: $completedAt, in: timeRange, displayedComponents: .hourAndMinute)
                    }
                }
                Section("实际完成") {
                    JumpRopeMenuFields(input: $input, scope: "实际", setCountText: $setCountText)
                    if !setCountInputValid { Text("组数需为 1 到 10000 的整数，或留空。 ").foregroundStyle(.red) }
                }
                Section {
                    Text("只填写实际完成的次数或时长；次数留空会保留为未知。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Button("保存完成记录") { save() }.buttonStyle(SprintPrimaryButtonStyle())
                        .disabled(saving || !input.isValid || !setCountInputValid).accessibilityIdentifier("跳绳菜单-保存实际")
                }
            }.scrollDismissesKeyboard(.interactively)
                .sprintPage().navigationTitle("记录跳绳").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .alert("无法保存记录", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("知道了", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard !saving, input.isValid, setCountInputValid else { return }
        saving = true
        do {
            try TrainingDateMenuService.recordJumpRope(schedule: schedule, count: input.countValue,
                active: input.activeSeconds, elapsed: input.elapsedSeconds, at: completedAt,
                totalSetCount: setCountValue, recordedTimeKnown: recordedTimeKnown, in: context)
            dismiss()
        } catch { self.error = error.localizedDescription; saving = false }
    }
}

struct JumpRopeMenuRecordDetail: View {
    let entry: JumpRopeEntry
    @Query private var schedules: [ScheduledWorkout]
    var body: some View {
        Form {
            Section("实际完成") {
                detailRow("次数", value: entry.count.map { "\($0) 次" } ?? "未知", id: "次数")
                detailRow("总组数", value: entry.totalSetCount.map { "\($0) 组" } ?? "未记录", id: "总组数")
                detailRow("有效时长", value: entry.activeDurationSeconds.map { "\($0) 秒" } ?? "未记录", id: "有效时长")
                detailRow("含休息总时长", value: entry.elapsedDurationSeconds.map { "\($0) 秒" } ?? "未记录", id: "总时长")
                if let legacy = entry.durationSeconds { detailRow("旧口径时长", value: "\(legacy) 秒", id: "旧时长") }
            }
            Section("记录信息") {
                detailRow("训练日期", value: TrainingJumpRopeDate.localDay(entry, schedules: schedules), id: "日期")
                LabeledContent("完成时间", value: entry.recordedTimeKnown == false
                    ? "未记录" : entry.date.formatted(date: .omitted, time: .shortened))
            }
        }.sprintPage().navigationTitle("跳绳记录").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
    private func detailRow(_ title: String, value: String, id: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value)
            .accessibilityIdentifier("跳绳记录-" + id)
    }
}

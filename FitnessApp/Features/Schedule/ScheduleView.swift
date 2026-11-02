import SwiftData
import SwiftUI

struct ScheduleView: View {
    var initialScheduleID: UUID? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var cardTitleSize = 16.0
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query private var programWorkoutLinks: [ProgramWorkoutLink]
    @Query private var programRevisions: [TrainingProgramRevision]
    @Query private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]
    @Query private var jumpRopeEntries: [JumpRopeEntry]

    @State private var dateSelection = TrainingDateSelection.shared
    @State private var displayedMonth = TrainingScheduleMonth.key(TrainingDateSelection.shared.selectedDate)
    @State private var locatedLocalDay = TrainingDateSelection.shared.selectedLocalDay
    @State private var calendarExpanded = false
    @State private var showMonthPicker = false
    @State private var pickerYear = Calendar.current.component(.year, from: .now)
    @State private var scrollRevision = 0
    @State private var isVisible = false
    @State private var isEditing = false
    @State private var hasLocatedSelection = false
    @State private var workingSetProgress: [UUID: TrainingWorkSetProgress] = [:]
    @State private var showAddOptions = false
    @State private var showAdd = false
    @State private var showDailyBuilder = false
    @State private var rescheduling: ScheduledWorkout?
    @State private var backfillingJumpRope: ScheduledWorkout?
    @State private var skipping: ScheduledWorkout?
    @State private var skipReason = ""
    @State private var errorMessage: String?

    private var supersededScheduleIDs: Set<UUID> {
        ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in: schedules)
    }

    private var monthContent: TrainingScheduleMonthContent {
        TrainingScheduleMonthContent(month: displayedMonth, schedules: schedules,
            sessions: sessions, jumpRopeEntries: jumpRopeEntries)
    }

    private var visibleSchedules: [ScheduledWorkout] {
        if let initialScheduleID { return schedules.filter { $0.id == initialScheduleID } }
        let days = Set(TrainingScheduleMonth.days(displayedMonth))
        return schedules.filter { days.contains(TrainingScheduleDate.localDay($0)) }
    }

    private var visibleDays: [String] {
        if initialScheduleID != nil { return Array(Set(visibleSchedules.map { TrainingScheduleDate.localDay($0) })).sorted() }
        return monthContent.days.map(\.localDay)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if initialScheduleID == nil { scheduleControls }
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if initialScheduleID != nil && visibleSchedules.isEmpty {
                            Text("这条安排已不存在").foregroundStyle(AppTheme.secondaryText)
                        }
                        if initialScheduleID == nil && visibleDays.isEmpty {
                            Text("本月暂无训练安排或记录")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 160)
                                .accessibilityIdentifier("日程-空月份")
                        }
                        if initialScheduleID == nil && locatedLocalDay.hasPrefix(displayedMonth)
                            && !visibleDays.contains(locatedLocalDay) {
                            NavigationLink { TrainingDateMenuView(localDay: locatedLocalDay) } label: {
                                Text("\(locatedLocalDay) · 暂无安排或记录")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText).frame(minHeight: 44)
                            }.accessibilityIdentifier("日程-空日期").id(locatedLocalDay)
                        }
                        ForEach(visibleDays, id: \.self) { day in
                            HStack(alignment: .top, spacing: 12) {
                                dayHeading(day)
                                    .frame(width: 44)
                                VStack(spacing: 8) {
                                    if initialScheduleID != nil {
                                        ForEach(visibleSchedules) { schedule in scheduleRow(schedule) }
                                        ForEach(sessions.filter { $0.scheduledWorkoutID == initialScheduleID && $0.status == .completed }) { session in
                                            actualSessionRow(session)
                                        }
                                        ForEach(jumpRopeEntries.filter { $0.scheduledWorkoutID == initialScheduleID }) { entry in
                                            actualRopeRow(entry)
                                        }
                                    } else {
                                        ForEach(monthContent.days.first(where: { $0.localDay == day })?.entries ?? []) { entry in
                                            entryRow(entry)
                                        }
                                    }
                                }
                            }.id(day)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 28)
                }.accessibilityIdentifier("训练日程列表")
            }
            .onAppear {
                isVisible = true
                reloadWorkingSetProgress()
                if !hasLocatedSelection {
                    hasLocatedSelection = true
                    proxy.scrollTo(visibleSchedules.first(where: { $0.id == initialScheduleID }).map { TrainingScheduleDate.localDay($0) }
                        ?? locatedLocalDay, anchor: .top)
                }
            }
            .onDisappear { isVisible = false }
            .onChange(of: displayedMonth) { _, _ in
                reloadWorkingSetProgress()
                if locatedLocalDay.isEmpty, let first = visibleDays.first { proxy.scrollTo(first, anchor: .top) }
            }
            .onChange(of: scrollRevision) { _, _ in proxy.scrollTo(locatedLocalDay, anchor: .top) }
        }
        .sprintPage()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDate(.foreground) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDate(.dayOrTimeZoneChanged) }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDate(.dayOrTimeZoneChanged) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDate(.dayOrTimeZoneChanged) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isEditing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isEditing = false }
        .navigationTitle(initialScheduleID == nil ? "训练日程" : "训练安排")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if #available(iOS 26.0, *) {
                scheduleNavigationActions.sharedBackgroundVisibility(.hidden)
            } else {
                scheduleNavigationActions
            }
        }
        .navigationDestination(isPresented: $showDailyBuilder) {
            DailyWorkoutBuilderView(initialDate: .now)
        }
        .confirmationDialog(
            "新增训练安排",
            isPresented: $showAddOptions,
            titleVisibility: .visible
        ) {
            Button("自选动作编排") {
                showDailyBuilder = true
            }
            Button("从现有模板安排") {
                showAdd = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("自选动作，或复用已有模板。")
        }
        .sheet(isPresented: $showMonthPicker) {
            NavigationStack {
                monthPicker
                .navigationTitle("选择月份").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showMonthPicker = false } }
                }
            }.sprintPage().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAdd) {
            AddScheduledWorkoutView(templates: templates)
                .sprintPage()
                .tint(AppTheme.ink)
        }
        .sheet(item: $rescheduling) { schedule in
            RescheduleWorkoutView(schedule: schedule)
                .sprintPage()
                .tint(AppTheme.ink)
        }
        .sheet(item: $backfillingJumpRope) { schedule in
            JumpRopeQuickEntrySheet(initialDate: TrainingScheduleDate.displayDate(schedule)) { input in
                do {
                    _ = try WellnessToolService.recordJumpRope(
                        count: input.count,
                        activeDurationSeconds: input.activeDurationSeconds,
                        elapsedDurationSeconds: input.elapsedDurationSeconds,
                        at: input.date,
                        scheduledWorkoutID: schedule.id,
                        totalSetCount: input.totalSetCount,
                        recordedTimeKnown: input.recordedTimeKnown,
                        in: modelContext
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("跳过这次训练？", isPresented: Binding(
            get: { skipping != nil },
            set: { if !$0 { skipping = nil } }
        )) {
            TextField("原因（可选）", text: $skipReason)
            Button("取消", role: .cancel) {
                skipping = nil
                skipReason = ""
            }
            Button("确认跳过", role: .destructive) {
                skipSelected()
            }
        } message: {
            Text("跳过会保留在日程统计中，但不会计入已完成训练。")
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

    @ToolbarContentBuilder private var scheduleNavigationActions: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                if initialScheduleID == nil {
                    Button("今天") {
                        dateSelection.refresh(reason: .explicitToday)
                        displayedMonth = TrainingScheduleMonth.key(dateSelection.today)
                        locate(dateSelection.todayLocalDay)
                    }
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("日程-回到今天")
                } else {
                    NavigationLink { ScheduleView() } label: { Label("完整日程", systemImage: "calendar") }
                        .accessibilityIdentifier("安排-完整日程")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if initialScheduleID == nil {
                    Button { showAddOptions = true } label: {
                        Label("新增训练安排", systemImage: "plus")
                            .font(.system(size: 19, weight: .regular))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("新增训练安排")
                }
            }
    }

    private var scheduleControls: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { monthLocator; Spacer(minLength: 0); monthActions }
                VStack(alignment: .leading, spacing: 0) { monthLocator; monthActions }
            }
            if calendarExpanded { calendarPanel }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
    }

    private var monthLocator: some View {
        Button {
            pickerYear = Int(displayedMonth.prefix(4)) ?? 2026
            showMonthPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(monthTitle).font(.title3.weight(.bold)).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText)
            }.foregroundStyle(AppTheme.ink).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("选择训练月份")
            .accessibilityValue(displayedMonth)
            .accessibilityIdentifier("日程-选择月份")
    }

    private var monthTitle: String {
        let parts = displayedMonth.split(separator: "-")
        return "\(parts.first ?? "")年\(Int(parts.last ?? "") ?? 1)月"
    }

    private var monthActions: some View {
        HStack(spacing: 0) {
            Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("上个月").accessibilityIdentifier("日程-上个月")
            Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("下个月").accessibilityIdentifier("日程-下个月")
            Button { calendarExpanded.toggle() } label: {
                Image(systemName: "calendar").frame(width: 44, height: 44)
                    .background(calendarExpanded ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }.accessibilityLabel(calendarExpanded ? "收起日历" : "展开日历")
                .accessibilityValue(calendarExpanded ? "展开" : "折叠").accessibilityIdentifier("日程-折叠日历")
        }.font(.system(size: 15, weight: .light)).foregroundStyle(AppTheme.ink).buttonStyle(.plain)
    }

    private var calendarPanel: some View {
        let days = TrainingScheduleMonth.days(displayedMonth)
        let first = TrainingLocalDate.date(days.first ?? "") ?? dateSelection.today
        let offset = (Calendar(identifier: .gregorian).component(.weekday, from: first) + 5) % 7
        return VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption2).foregroundStyle(AppTheme.secondaryText) }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(days, id: \.self) { day in
                    Button { locate(day) } label: {
                        VStack(spacing: 3) {
                            Text(String(Int(day.suffix(2)) ?? 1)).font(.subheadline)
                                .frame(width: 34, height: 30)
                                .background(day == locatedLocalDay ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                            Circle().fill(visibleDays.contains(day) ? AppTheme.secondaryText : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(day)，定位当天训练")
                        .accessibilityIdentifier("日程-日历日期-" + day)
                }
            }
            HStack {
                Text("点日期定位训练").font(.caption2).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button("收起", systemImage: "chevron.up") { calendarExpanded = false }.font(.caption).frame(minHeight: 44)
            }
        }.foregroundStyle(AppTheme.ink).padding(.horizontal, -10)
            .accessibilityIdentifier("日程-月历")
    }

    private var monthPicker: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Button { pickerYear = max(1, pickerYear - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一年")
                    Spacer(); Text(String(pickerYear)).font(.title2.bold()); Spacer()
                    Button { pickerYear = min(9998, pickerYear + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下一年")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(1...12, id: \.self) { month in
                        let key = String(format: "%04d-%02d", pickerYear, month)
                        Button {
                            displayedMonth = key; locatedLocalDay = ""; calendarExpanded = false; showMonthPicker = false
                        } label: {
                            Text("\(month)月").font(.subheadline).frame(maxWidth: .infinity, minHeight: 48)
                                .background(displayedMonth == key ? AppTheme.accent : AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityIdentifier("日程-月份-" + key)
                            .accessibilityAddTraits(displayedMonth == key ? .isSelected : [])
                    }
                }
            }.padding(20)
        }.foregroundStyle(AppTheme.ink).buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let next = TrainingScheduleMonth.shifted(displayedMonth, by: offset) else { return }
        displayedMonth = next; locatedLocalDay = ""; calendarExpanded = false
    }

    private func locate(_ day: String) {
        locatedLocalDay = day; calendarExpanded = false; scrollRevision += 1
    }

    private func dayHeading(_ day: String) -> some View {
        let date = TrainingLocalDate.date(day) ?? dateSelection.today
        return NavigationLink { TrainingDateMenuView(localDay: day) } label: {
            VStack(spacing: 5) {
                Text(String(Int(day.suffix(2)) ?? 1)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .frame(minWidth: 36, minHeight: 32)
                    .background(day == dateSelection.todayLocalDay ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                Text(day == dateSelection.todayLocalDay ? "今天" : date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_Hans_CN"))))
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }.foregroundStyle(AppTheme.ink).frame(minWidth: 44, minHeight: 54).contentShape(Rectangle())
                .padding(.top, 6)
        }.buttonStyle(.plain).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("日程-日期菜单-" + day)
            .accessibilityLabel("\(day)，查看当天训练菜单")
    }

    private func refreshDate(_ reason: TrainingDateSelection.RefreshReason) {
        dateSelection.refresh(reason: reason,
            isEditing: isEditing || showMonthPicker || showAdd || showAddOptions || rescheduling != nil || backfillingJumpRope != nil || skipping != nil,
            isShowingDetail: !isVisible || showDailyBuilder)
        if isVisible && !isEditing && !sessions.contains(where: { $0.status == .inProgress }) { reloadWorkingSetProgress() }
    }
    private func feedback(for schedules: [ScheduledWorkout]) -> TrainingDayFeedback {
        let retired = supersededScheduleIDs
        return TrainingDayFeedback(schedules: schedules.filter { !retired.contains($0.id) },
            sessions: sessions, progress: workingSetProgress)
    }
    private func daySummary(for day: String) -> TrainingDaySummary {
        if let initialScheduleID {
            return TrainingDaySummary(localDay: day, schedules: schedules,
                sessions: sessions.filter { $0.scheduledWorkoutID == initialScheduleID },
                progress: workingSetProgress,
                jumpRopeEntries: jumpRopeEntries.filter { $0.scheduledWorkoutID == initialScheduleID },
                excludedScheduleIDs: Set(schedules.filter { $0.id != initialScheduleID }.map(\.id)).union(supersededScheduleIDs))
        }
        return TrainingDaySummary(localDay: day, schedules: schedules, sessions: sessions,
            progress: workingSetProgress, jumpRopeEntries: jumpRopeEntries, excludedScheduleIDs: supersededScheduleIDs)
    }
    private func reloadWorkingSetProgress() {
        do {
            workingSetProgress = try TrainingWorkingSetProgressLoader.load(
                schedules: visibleSchedules, sessions: sessions, includingLocalDays: Set(visibleDays), in: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }

    private func scheduleRow(_ schedule: ScheduledWorkout) -> some View {
        let presentation = TrainingWorkoutPresentation.upcoming(schedule.templateName)
        let feedback = feedback(for: [schedule])
        let active = sessions.first { $0.scheduledWorkoutID == schedule.id && $0.status == .inProgress }
        return Group {
                if supersededScheduleIDs.contains(schedule.id) {
                    supersededScheduleRow(schedule, presentation: presentation)
                } else if let active {
                    NavigationLink { ActiveWorkoutView(sessionID: active.id) } label: {
                        scheduleLabel(schedule, presentation: presentation, feedback: feedback)
                    }.accessibilityIdentifier("日程-继续训练-\(active.id.uuidString)")
                } else if schedule.status == .completed || schedule.status == .inProgress {
                    NavigationLink { TrainingDateMenuView(localDay: TrainingScheduleDate.localDay(schedule)) } label: {
                        scheduleLabel(schedule, presentation: presentation, feedback: feedback)
                    }.accessibilityIdentifier("日程-历史安排-\(schedule.id.uuidString)")
                } else if isJumpRopeSchedule(schedule) && isPast(schedule) {
                    Button { backfillingJumpRope = schedule } label: {
                        scheduleLabel(schedule, presentation: presentation, feedback: feedback)
                    }.accessibilityIdentifier("补录完成情况-跳绳")
                } else if isJumpRopeSchedule(schedule) || CardioWorkoutPresentation.plan(schedule) != nil {
                    NavigationLink { TrainingDateMenuView(localDay: TrainingScheduleDate.localDay(schedule)) } label: {
                        scheduleLabel(schedule, presentation: presentation, feedback: feedback)
                    }.accessibilityIdentifier(isJumpRopeSchedule(schedule) ? "跳绳日程" : "日程-有氧安排-\(schedule.id.uuidString)")
                } else {
                    NavigationLink(destination: isPast(schedule)
                        ? AnyView(HistoricalWorkoutEntryView(scheduleID: schedule.id))
                        : AnyView(DailyWorkoutBuilderView(initialDate: schedule.plannedDate, initialScheduleID: schedule.id))) {
                        scheduleLabel(schedule, presentation: presentation, feedback: feedback)
                    }.accessibilityIdentifier(isPast(schedule) ? "补录完成情况-力量" : "调整当天动作")
                }
        }.buttonStyle(.plain)
            .padding(.horizontal, 15).padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .contextMenu {
                if !supersededScheduleIDs.contains(schedule.id), schedule.status == .planned || schedule.status == .skipped {
                    if schedule.status == .planned {
                        Button { rescheduling = schedule } label: { Label("调整日期", systemImage: "calendar.badge.clock") }
                        Button(role: .destructive) { skipReason = ""; skipping = schedule } label: {
                            Label("跳过训练", systemImage: "forward.end")
                        }
                    } else {
                        if !schedule.skipReason.isEmpty {
                            Section("跳过原因") { Text(schedule.skipReason) }
                        }
                        Button { restore(schedule) } label: { Label("恢复训练", systemImage: "arrow.uturn.backward") }
                        Button { rescheduling = schedule } label: { Label("改期并恢复", systemImage: "calendar.badge.clock") }
                    }
                    if schedule.isManuallyScheduled {
                        Button(role: .destructive) { deleteManual(schedule) } label: {
                            Label("删除临时安排", systemImage: "trash")
                        }
                    }
                }
            }
    }

    private func supersededScheduleRow(_ schedule: ScheduledWorkout, presentation: TrainingWorkoutPresentation.Upcoming) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("以下为原计划目标，未作为实际训练记录。").font(.caption)
                if let rope = schedule.jumpRopePlan { Text(rope.summary).font(.subheadline) }
                ForEach(schedule.planSnapshot) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.exerciseName).font(.subheadline.weight(.semibold))
                        ForEach(Array(item.plannedSets.enumerated()), id: \.offset) { index, set in
                            if item.volumeUnit.recordsSingleAmount {
                                Text("第 \(index + 1) 组计划 · \(set.reps) \(item.volumeUnit.symbol)").font(.caption)
                            } else if item.volumeUnit == .bodyweight {
                                Text("第 \(index + 1) 组计划 · 自重 × \(set.reps) 次").font(.caption)
                            } else {
                                let repetitionUnit = item.volumeUnit == .meter ? "趟" : "次"
                                Text("第 \(index + 1) 组计划 · \(TrainingFormatters.weight(set.weight)) \(item.volumeUnit.symbol) × \(set.reps) \(repetitionUnit)").font(.caption)
                            }
                            if item.volumeUnit.usesMeasurementSide {
                                Text("负重口径 · \(set.weightSide.title) · 次数口径 · \(set.repsSide.title)").font(.caption)
                            }
                            if let target = set.prescription { Text("第 \(index + 1) 组 · " + target.summary).font(.caption) }
                        }
                        if !item.exerciseNotes.isEmpty { Text(item.exerciseNotes).font(.caption) }
                    }
                }
                NavigationLink { TrainingDateMenuView(localDay: TrainingScheduleDate.localDay(schedule)) } label: {
                    Label("查看当天训练菜单", systemImage: "calendar")
                        .font(.subheadline).frame(minHeight: 44)
                }
            }.foregroundStyle(AppTheme.secondaryText).padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                Text("已被新版替代 · 原处方保留").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.frame(minHeight: 44, alignment: .leading)
        }.accessibilityIdentifier("日程-被替代安排-" + schedule.id.uuidString)
    }

    private func scheduleLabel(_ schedule: ScheduledWorkout, presentation: TrainingWorkoutPresentation.Upcoming,
                               feedback: TrainingDayFeedback) -> some View {
        let actual = sessions.filter { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }
            .max { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }
        let progress = actual.flatMap { workingSetProgress[$0.id] }
        return compactLabel(title: presentation.title,
            symbol: isJumpRopeSchedule(schedule) ? "figure.jumprope" : presentation.symbolName,
            feedback: feedback, progress: progress,
            completionVerified: actual != nil && ((progress?.total ?? 0) > 0 || CardioWorkoutPresentation.plan(schedule) != nil))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(schedule.templateName)，\(schedule.status == .completed ? completedArrangementLabel(schedule) : feedback.label)")
            .accessibilityHint("查看训练详情与具体数据；长按可调整日期、跳过或恢复")
    }

    @ViewBuilder private func entryRow(_ entry: TrainingScheduleMonthContent.Entry) -> some View {
        switch entry {
        case .arrangement(let schedule): scheduleRow(schedule)
        case .session(let session, let plan): actualSessionRow(session, linkedSchedule: plan)
        case .jumpRope(let entry, let plan): actualRopeRow(entry, linkedSchedule: plan)
        }
    }

    private func compactLabel(title: String, symbol: String, feedback: TrainingDayFeedback,
                              progress: TrainingWorkSetProgress? = nil, completionVerified: Bool = true) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol == "figure.indoor.cycle" ? "bicycle" : symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(AppTheme.secondaryText).frame(width: 22).accessibilityHidden(true)
            Text(title).font(.system(size: cardTitleSize, weight: .semibold)).foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            ScheduleStatusGraphic(feedback: feedback, progress: progress, completionVerified: completionVerified).accessibilityHidden(true)
        }.frame(minHeight: 40).contentShape(Rectangle())
    }

    private func actualSessionRow(_ session: WorkoutSession, linkedSchedule: ScheduledWorkout? = nil) -> some View {
        let presentation = TrainingWorkoutPresentation.upcoming(session.templateName)
        let progress = workingSetProgress[session.id]
        let completionVerified = (progress?.total ?? 0) > 0 || session.cardioResistanceLevel != nil
            || linkedSchedule.map { CardioWorkoutPresentation.plan($0) != nil } == true
        let feedback = session.status == .inProgress ? TrainingDayFeedback(states: [.inProgress])
            : TrainingDayFeedback(recordedEvents: [.init(state: .completed, workingSets: progress)])
        return NavigationLink {
            Group {
                if session.status == .inProgress { ActiveWorkoutView(sessionID: session.id) }
                else { WorkoutDetailView(sessionID: session.id) }
            }.toolbar {
                if let plan = linkedSchedule {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { ScheduleView(initialScheduleID: plan.id) } label: { Image(systemName: "calendar") }
                            .accessibilityLabel("查看关联安排").accessibilityIdentifier("日程-关联安排")
                    }
                }
            }
        } label: {
            compactLabel(title: presentation.title, symbol: presentation.symbolName, feedback: feedback,
                progress: progress, completionVerified: completionVerified)
                .padding(.horizontal, 15).padding(.vertical, 18)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("实际训练-\(session.id.uuidString)")
            .accessibilityLabel("\(session.templateName)，\(feedback.label)\(session.status == .completed && !completionVerified ? "，工作组进度未知" : "")")
            .accessibilityHint(session.status == .inProgress ? "继续本次训练" : "查看具体组数、重量、时长与训练记录")
    }

    private func actualRopeRow(_ entry: JumpRopeEntry, linkedSchedule: ScheduledWorkout? = nil) -> some View {
        NavigationLink {
            JumpRopeMenuRecordDetail(entry: entry).toolbar {
                if let plan = linkedSchedule {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { ScheduleView(initialScheduleID: plan.id) } label: { Image(systemName: "calendar") }
                            .accessibilityLabel("查看关联安排")
                    }
                }
            }
        } label: {
            compactLabel(title: "跳绳", symbol: "figure.jumprope", feedback: TrainingDayFeedback(states: [.completed]))
                .padding(.horizontal, 15).padding(.vertical, 18)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("跳绳实际-\(entry.id.uuidString)")
            .accessibilityLabel("已记录跳绳，\(entry.displaySummary)")
            .accessibilityHint("查看跳绳具体数据")
    }

    private func completedArrangementLabel(_ schedule: ScheduledWorkout) -> String {
        let hasActual = sessions.contains { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }
            || jumpRopeEntries.contains { $0.scheduledWorkoutID == schedule.id }
        return hasActual ? "安排已完成 · 已有训练记录" : "安排已完成 · 暂无关联记录"
    }

    private func isJumpRopeSchedule(_ schedule: ScheduledWorkout) -> Bool {
        if TrainingDateMenuService.isJumpRope(schedule, links: programWorkoutLinks,
            revisions: programRevisions, exercises: exercises) { return true }
        return programWorkoutLinks.contains {
            $0.scheduledWorkoutID == schedule.id && $0.templateCode.hasPrefix("ROPE_")
        }
    }

    private func isPast(_ schedule: ScheduledWorkout) -> Bool {
        TrainingScheduleDate.localDay(schedule) < dateSelection.todayLocalDay
    }

    private func skipSelected() {
        guard let skipping else { return }
        do {
            try ScheduleService.skip(skipping, reason: skipReason, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
        self.skipping = nil
        skipReason = ""
    }

    private func restore(_ schedule: ScheduledWorkout) {
        do {
            try ScheduleService.restore(schedule, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteManual(_ schedule: ScheduledWorkout) {
        do {
            try ScheduleService.deleteManual(schedule, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScheduleStatusGraphic: View {
    let feedback: TrainingDayFeedback
    var progress: TrainingWorkSetProgress?
    var completionVerified = true

    var body: some View {
        Group {
            if feedback.isPartial, let fraction = progress?.completionFraction {
                ZStack {
                    Circle().stroke(AppTheme.line, lineWidth: 2)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }.frame(width: 23, height: 23)
            } else if feedback.tone == .green && completionVerified {
                Circle().stroke(color, lineWidth: 1.6)
                    .overlay {
                        Path { path in
                            path.move(to: CGPoint(x: 7, y: 12))
                            path.addLine(to: CGPoint(x: 11, y: 16))
                            path.addLine(to: CGPoint(x: 18, y: 8))
                        }.stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }.frame(width: 24, height: 24)
            } else if feedback.tone == .amber && !feedback.isPartial {
                Circle().stroke(color, lineWidth: 1.5)
                    .overlay {
                        Path { path in
                            path.move(to: CGPoint(x: 12, y: 6))
                            path.addLine(to: CGPoint(x: 12, y: 12))
                            path.addLine(to: CGPoint(x: 17, y: 12))
                        }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }.frame(width: 23, height: 23)
            } else {
                Image(systemName: symbol).font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(color)
            }
        }.frame(width: 30, height: 30)
    }

    private var symbol: String {
        if feedback.tone == .green && !completionVerified { return "doc.text" }
        if feedback.isPartial { return "circle.lefthalf.filled" }
        switch feedback.tone {
        case .green: return "checkmark.circle"
        case .purple: return "play.circle"
        case .gray: return "forward.end.circle"
        case .amber: return "clock"
        case .none: return "questionmark.circle"
        }
    }

    private var color: Color {
        if feedback.isPartial { return Color(red: 0.608, green: 0.396, blue: 0.051) }
        if feedback.tone == .green && completionVerified { return Color(red: 0.031, green: 0.49, blue: 0.314) }
        if feedback.tone == .amber { return Color(red: 0.486, green: 0.537, blue: 0.51) }
        if feedback.tone == .green { return AppTheme.secondaryText }
        return feedback.color
    }
}

private struct AddScheduledWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let templates: [WorkoutTemplate]

    @State private var selectedTemplateID: UUID?
    @State private var selectedDate = Date.now.startOfDay
    @State private var errorMessage: String?

    private var availableTemplates: [WorkoutTemplate] {
        templates.filter { !$0.isOneOff }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SprintPageHeader(title: "新增安排", icon: "calendar.badge.plus")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    if availableTemplates.isEmpty {
                        Text("请先在训练页创建一个专项模板。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("选择计划", selection: $selectedTemplateID) {
                            ForEach(availableTemplates) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                    }
                } header: {
                    SprintSectionHeading(title: "训练计划", icon: "checklist")
                }

                Section {
                    DatePicker(
                        "日期",
                        selection: $selectedDate,
                        in: Date.now.addingDays(-7)...Date.now.addingDays(90),
                        displayedComponents: .date
                    )
                } header: {
                    SprintSectionHeading(title: "训练日期", icon: "calendar")
                }
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
            .navigationTitle("临时加练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addSchedule() }
                        .fontWeight(.semibold)
                        .disabled(selectedTemplateID == nil)
                }
            }
            .onAppear {
                selectedTemplateID = selectedTemplateID ?? availableTemplates.first?.id
            }
            .alert("无法添加", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func addSchedule() {
        guard let template = availableTemplates.first(where: { $0.id == selectedTemplateID }) else { return }
        do {
            _ = try ScheduleService.addManual(template: template, on: selectedDate, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RescheduleWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let schedule: ScheduledWorkout
    let validate: ((Date) throws -> Void)?
    let onSave: ((Date) throws -> Void)?
    let minimumDate: Date?
    let resultDestination: String
    @State private var selectedDate: Date
    @State private var errorMessage: String?
    @State private var showPreview = false

    init(schedule: ScheduledWorkout, minimumDate: Date? = nil, resultDestination: String = "当前训练菜单",
         validate: ((Date) throws -> Void)? = nil,
         onSave: ((Date) throws -> Void)? = nil) {
        self.schedule = schedule
        self.validate = validate
        self.onSave = onSave
        self.minimumDate = minimumDate
        self.resultDestination = resultDestination
        let originalDate = onSave == nil ? schedule.plannedDate : TrainingScheduleDate.displayDate(schedule)
        _selectedDate = State(initialValue: minimumDate.map { max(originalDate, $0) } ?? originalDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SprintPageHeader(title: "调整日期", icon: "calendar.badge.clock")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    Text(schedule.templateName)
                } header: {
                    SprintSectionHeading(title: "训练", icon: "dumbbell")
                }
                Section {
                    DatePicker(
                        "日期",
                        selection: $selectedDate,
                        in: (minimumDate ?? Date.now.addingDays(-7))...Date.now.addingDays(90),
                        displayedComponents: .date
                    ).accessibilityIdentifier("计划管理-新日期")
                } header: {
                    SprintSectionHeading(title: "新的日期", icon: "calendar.badge.clock")
                }
                if onSave != nil {
                    if let validationMessage {
                        Section { Text(validationMessage).font(.caption).foregroundStyle(AppTheme.orange) }
                            .accessibilityIdentifier("计划管理-日期冲突")
                    } else {
                        Section {
                            Text("仅调整这一场的日期，训练内容和其他安排保留。")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .sprintPage()
            .navigationTitle("调整训练日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(onSave == nil ? "保存" : "预览") {
                        if onSave == nil { save() } else { preview() }
                    }
                        .fontWeight(.semibold)
                        .disabled(onSave != nil && validationMessage != nil)
                        .accessibilityIdentifier("计划管理-预览改期")
                }
            }
            .navigationDestination(isPresented: $showPreview) { confirmation }
            .alert("无法改期", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var validationMessage: String? {
        guard let validate else { return nil }
        do { try validate(selectedDate); return nil }
        catch { return error.localizedDescription }
    }

    private var confirmation: some View {
        Form {
            Section {
                Text(schedule.templateName)
                LabeledContent("原日期") {
                    Text(TrainingScheduleDate.displayDate(schedule), format: .dateTime.month().day().weekday())
                }
                LabeledContent("新日期") {
                    Text(selectedDate, format: .dateTime.month().day().weekday())
                }
            } header: { SprintSectionHeading(title: "本次训练", icon: "dumbbell") }
            Section {
                Text("动作、组数和重量目标保留。其他计划日期保留。保存后返回\(resultDestination)，可查看改期后的计划或撤销。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden).sprintPage()
        .navigationTitle("确认改期").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("确认改期") { save() }.fontWeight(.semibold)
                    .accessibilityIdentifier("计划管理-确认改期")
            }
        }
    }

    private func preview() {
        do { try validate?(selectedDate); showPreview = true }
        catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        do {
            if let onSave { try onSave(selectedDate) }
            else { try ScheduleService.reschedule(schedule, to: selectedDate, in: modelContext) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

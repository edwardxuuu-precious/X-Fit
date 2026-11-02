import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query private var templates: [WorkoutTemplate]
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query(sort: \TrainingProgramRevision.effectiveDate, order: .reverse) private var programRevisions: [TrainingProgramRevision]
    @Query private var programWorkoutLinks: [ProgramWorkoutLink]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var jumpRopeEntries: [JumpRopeEntry]
    @State private var dateSelection = TrainingDateSelection.shared
    @State private var isVisible = false
    @State private var isEditing = false
    @State private var workingSetProgress: [UUID: TrainingWorkSetProgress] = [:]
    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var showRope = false
    @State private var jumpRopeScheduleID: UUID?
    @State private var starting = false
    @State private var errorMessage: String?

    private var selectedDate: Date { dateSelection.selectedDate }

    private var activeSession: WorkoutSession? { sessions.first { $0.status == .inProgress } }
    private var daySchedules: [ScheduledWorkout] {
        schedules.filter { TrainingScheduleDate.localDay($0) == dateSelection.selectedLocalDay && $0.status != .skipped }.sorted { left, right in
            let leftManual = templates.first { $0.id == left.templateID }?.isOneOff == true
            let rightManual = templates.first { $0.id == right.templateID }?.isOneOff == true
            if leftManual != rightManual { return leftManual }
            if left.status != right.status { return left.status == .planned }
            return left.createdAt > right.createdAt
        }
    }
    private var weekDays: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate.startOfDay
        return (0..<7).map { start.addingDays($0) }
    }
    private var activeProgram: FatLossProgram? { programs.first { $0.statusRaw == "active" } }
    private var hasPendingWeekImport: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-pending-week-import") {
            return activeProgram != nil
        }
        #endif
        guard let program = activeProgram else { return false }
        for day in weekDays {
            let localDay = TrainingLocalDate.key(day)
            guard let programDay = TrainingLocalDate.date(localDay, timeZone: FatLossCalendar.calendar.timeZone),
            let revision = TrainingPreferenceService.effectiveProgram(
                programRevisions,
                programID: program.id,
                on: programDay
            ), let snapshot = revision.snapshot else { continue }
            let weekday = FatLossCalendar.calendar.component(.weekday, from: programDay)
            var codes = snapshot.strengthWorkouts.filter { $0.weekday == weekday }.map(\.code)
            if snapshot.code == "CUT-LB3-20260914-R1" {
                codes += snapshot.cardioWorkouts.filter { $0.weekday == weekday }.map(\.code)
            }
            for code in codes {
                let linked = programWorkoutLinks.contains {
                    $0.programID == program.id && $0.trainingProgramRevisionID == revision.id
                        && $0.templateCode == code && FatLossCalendar.label($0.originalDate) == localDay
                }
                let occupied = schedules.contains {
                    TrainingScheduleDate.localDay($0) == localDay && $0.status != .skipped
                } || sessions.contains { session in
                    let sessionDay = schedules.first(where: { $0.id == session.scheduledWorkoutID })
                        .map { TrainingScheduleDate.localDay($0) } ?? TrainingLocalDate.key(session.plannedDate)
                    return sessionDay == localDay && session.status != .discarded
                }
                if !linked && !occupied { return true }
            }
        }
        return false
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    SprintPageHeader(title: "训练", icon: "figure.strengthtraining.traditional")
                    NavigationLink(destination: ScheduleView()) {
                        Image(systemName: "calendar").frame(width: 44, height: 44)
                            .background(AppTheme.elevatedSurface, in: Circle())
                    }.accessibilityLabel("训练日程")
                }
                HStack {
                    Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("训练-已选日期")
                        .accessibilityValue(dateSelection.selectedLocalDay)
                    Spacer()
                    Button("今天") { dateSelection.refresh(reason: .explicitToday) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("训练-回到今天")
                }
                HStack(spacing: 2) {
                    ForEach(weekDays, id: \.self) { day in
                        let dayKey = TrainingLocalDate.key(day)
                        let selected = dayKey == dateSelection.selectedLocalDay
                        let summary = daySummary(for: dayKey)
                        let feedback = summary.feedback
                        Button { dateSelection.select(localDay: dayKey) } label: {
                            VStack(spacing: 5) {
                                Text(day, format: .dateTime.weekday(.narrow)).font(.caption)
                                Text("\(Calendar.current.component(.day, from: day))").font(.body.bold().monospacedDigit())
                                TrainingStatusMarker(feedback: feedback)
                                    .padding(2)
                                    .background(selected && feedback.tone != .none ? AppTheme.background : .clear, in: Circle())
                                    .accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(AppTheme.ink)
                                .background(selected ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.month().day().weekday(.wide)))
                            .accessibilityIdentifier("训练日期-\(dayKey)")
                            .accessibilityValue(selected ? "已选择" : summary.accessibilityLabel)
                            .accessibilityHint(summary.accessibilityLabel)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("训练周历")
                let selectedSummary = daySummary(for: dateSelection.selectedLocalDay)
                let selectedFeedback = selectedSummary.feedback
                if selectedFeedback.tone != .none {
                    Text(selectedFeedback.label).font(.caption.bold()).foregroundStyle(selectedFeedback.color)
                        .accessibilityIdentifier("训练-当天状态")
                }
                if let pending = selectedSummary.pendingPlansLabel {
                    Text(pending).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("训练-其他安排状态")
                }
                if let activeSession {
                    VStack(alignment: .leading, spacing: 18) {
                        SprintIcon(systemName: "figure.strengthtraining.traditional", size: 64, prominent: true)
                        Label("训练进行中", systemImage: "record.circle").font(.subheadline).foregroundStyle(AppTheme.purple)
                        Text(activeSession.templateName).font(.title2.bold())
                        Button { open(activeSession.id) } label: { Label("继续训练", systemImage: "play.fill").neonButtonStyle() }
                            .accessibilityIdentifier("继续训练")
                    }.cardSurface(padding: 20, cornerRadius: 24)
                } else if selectedSummary.hasActualRecords {
                    VStack(alignment: .leading, spacing: 12) {
                        SprintSectionHeading(title: "实际训练", icon: "checkmark.circle")
                        ForEach(selectedSummary.recordedSessions) { session in
                            TrainingActualSessionRow(session: session, progress: workingSetProgress[session.id])
                        }
                        ForEach(selectedSummary.jumpRopeEntries) { entry in TrainingActualJumpRopeRow(entry: entry) }
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-当天实际")
                    let pending = daySchedules.filter { $0.status == .planned }
                    if !pending.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("其他待完成安排").font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                            ForEach(pending) { schedule in weekScheduleRow(schedule) }
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-其他待完成安排")
                    }
                } else if let schedule = daySchedules.first {
                    workoutCard(schedule)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        SprintIcon(systemName: "figure.cooldown", size: 64, prominent: true)
                        Text(selectedDate.isSameDay(as: .now) ? "按自己的节奏" : selectedDate.formatted(.dateTime.month().day()))
                            .font(.title2.bold())
                        Text("还没有训练安排").foregroundStyle(AppTheme.secondaryText)
                        NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate)) {
                            Label(selectedDate.isSameDay(as: .now) ? "安排今天训练" : "安排这天训练", systemImage: "plus").neonButtonStyle()
                        }.accessibilityIdentifier("安排今天训练")
                    }.cardSurface(padding: 20, cornerRadius: 24)
                }
                HStack {
                    SprintSectionHeading(title: "本周安排", icon: "calendar")
                    Spacer()
                    NavigationLink("查看全部", destination: ScheduleView()).frame(minHeight: 44)
                }
                let weekSchedules = schedules.filter { item in weekDays.contains { TrainingLocalDate.key($0) == TrainingScheduleDate.localDay(item) } }
                if weekSchedules.isEmpty {
                    if hasPendingWeekImport, let program = activeProgram {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("本周编排已准备好，尚未加入日程。")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            NavigationLink(destination: FatLossTrainingView(program: program)) {
                                Label("安排本周训练", systemImage: "calendar.badge.plus").neonButtonStyle()
                            }.accessibilityIdentifier("训练-安排本周")
                        }
                    } else {
                        Text("本周暂无安排。可以逐日添加，也可以导入已有计划。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(weekSchedules) { item in
                            weekScheduleRow(item)
                        }
                    }
                    if hasPendingWeekImport, let program = activeProgram {
                        NavigationLink(destination: FatLossTrainingView(program: program)) {
                            Label("继续安排本周", systemImage: "calendar.badge.plus")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("训练-继续安排本周")
                    }
                }
                VStack(spacing: 0) {
                    if let program = programs.first(where: { $0.statusRaw == "active" }) {
                        NavigationLink(destination: FatLossTrainingView(program: program)) {
                            destinationRow("减脂训练计划", "calendar.badge.plus")
                        }.accessibilityIdentifier("训练-减脂计划导入")
                        Divider()
                    }
                    NavigationLink(destination: PlanView()) { destinationRow("训练计划与动作库", "square.stack.3d.up") }
                        .accessibilityIdentifier("训练计划与动作库")
                    Divider()
                    NavigationLink(destination: HistoryView()) { destinationRow("训练历史", "clock.arrow.circlepath") }
                    Divider()
                    Button {
                        jumpRopeScheduleID = nil
                        showRope = true
                    } label: { destinationRow("记录跳绳", "figure.jumprope") }
                        .accessibilityIdentifier("训练-记录跳绳")
                }.padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.sprintPage().buttonStyle(.plain).navigationTitle("训练日历").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .onAppear { isVisible = true; reloadWorkingSetProgress() }
            .onDisappear { isVisible = false }
            .onChange(of: dateSelection.selectedLocalDay) { _, _ in reloadWorkingSetProgress() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDate(.foreground) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refreshDate(.dayOrTimeZoneChanged)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                refreshDate(.dayOrTimeZoneChanged)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshDate(.dayOrTimeZoneChanged)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isEditing = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isEditing = false }
            .navigationDestination(isPresented: $showWorkout) {
                if let workoutSessionID { ActiveWorkoutView(sessionID: workoutSessionID) }
            }
            .sheet(isPresented: $showRope, onDismiss: { jumpRopeScheduleID = nil }) {
                JumpRopeQuickEntrySheet(initialDate: min(selectedDate, .now)) { input in
                    do {
                        _ = try WellnessToolService.recordJumpRope(
                            count: input.count,
                            activeDurationSeconds: input.activeDurationSeconds,
                            elapsedDurationSeconds: input.elapsedDurationSeconds,
                            at: input.date,
                            scheduledWorkoutID: jumpRopeScheduleID,
                            totalSetCount: input.totalSetCount,
                            recordedTimeKnown: input.recordedTimeKnown,
                            in: modelContext
                        )
                    }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }
    private func refreshDate(_ reason: TrainingDateSelection.RefreshReason) {
        dateSelection.refresh(reason: reason, hasActiveSession: showWorkout && activeSession != nil,
            isEditing: isEditing || showRope, isShowingDetail: !isVisible || showWorkout)
        if isVisible && !isEditing && activeSession == nil { reloadWorkingSetProgress() }
    }
    private func feedback(for schedules: [ScheduledWorkout]) -> TrainingDayFeedback {
        TrainingDayFeedback(schedules: schedules, sessions: sessions, progress: workingSetProgress)
    }
    private func daySummary(for day: String) -> TrainingDaySummary {
        TrainingDaySummary(localDay: day, schedules: schedules, sessions: sessions,
            progress: workingSetProgress, jumpRopeEntries: jumpRopeEntries)
    }
    private func reloadWorkingSetProgress() {
        let days = Set(weekDays.map { TrainingLocalDate.key($0) })
        do {
            workingSetProgress = try TrainingWorkingSetProgressLoader.load(
                schedules: schedules.filter { days.contains(TrainingScheduleDate.localDay($0)) },
                sessions: sessions, includingLocalDays: days, in: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }

    private func workoutCard(_ schedule: ScheduledWorkout) -> some View {
        let items = templateExercises.filter { $0.templateID == schedule.templateID }.sorted { $0.order < $1.order }
        let cardio = jumpRopeDraft(for: schedule)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SprintIcon(systemName: cardio == nil ? "figure.strengthtraining.traditional" : "figure.jumprope", size: 72, prominent: true)
                HStack {
                    Text(selectedDate.isSameDay(as: .now) ? "待练" : selectedDate.formatted(.dateTime.month().day()))
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Spacer()
                    if schedule.status == .completed,
                       let session = sessions.first(where: { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }) {
                        NavigationLink(destination: HistoricalWorkoutEditView(sessionID: session.id)) {
                            Label("修改记录", systemImage: "pencil").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("修改今日记录")
                    } else if cardio != nil {
                        NavigationLink(destination: ScheduleView()) {
                            Label("管理", systemImage: "calendar").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("管理跳绳日程")
                    } else {
                        NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                            Label("调整", systemImage: "slider.horizontal.3").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("修改今日计划")
                    }
                }
                Text(schedule.templateName)
                    .font(AppTheme.pageTitle).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                workoutMetric(items: items, cardio: cardio)
                workoutAction(schedule)
            }
            .cardSurface(padding: 20, cornerRadius: 24)
            if !items.isEmpty {
                HStack {
                    SprintSectionHeading(title: "动作", icon: "dumbbell")
                    Rectangle().fill(AppTheme.line).frame(height: 1)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                        workoutItemRow(index: index, item: item, cardio: cardio)
                        Rectangle().fill(AppTheme.line).frame(height: 1)
                    }
                }
                if items.count > 4 {
                    NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                        HStack { Text("查看全部 \(items.count) 个动作"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink).frame(minHeight: 44)
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-今日安排")
    }

    @ViewBuilder private func workoutMetric(items: [TemplateExercise], cardio: ProgramCardioDraft?) -> some View {
        if let cardio {
            let rounds = TrainingPlanPresentation.requiredRoundCount(for: cardio)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(rounds)").font(AppTheme.metricValue).foregroundStyle(AppTheme.ink)
                Text("轮").font(.caption).foregroundStyle(AppTheme.ink)
                Text("/").font(.subheadline).foregroundStyle(AppTheme.ink).accessibilityHidden(true)
                Text("约 \(TrainingPlanPresentation.roundedElapsedMinutes(for: cardio)) 分钟")
                    .font(.subheadline).foregroundStyle(AppTheme.ink)
            }
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("训练-今日安排-摘要")
            .accessibilityLabel(TrainingPlanPresentation.cardioVolumeSummary(cardio))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(items.reduce(0) { $0 + $1.targetSets })")
                    .font(AppTheme.metricValue).foregroundStyle(AppTheme.ink)
                Text("组").font(.caption).foregroundStyle(AppTheme.ink)
                Text("/").font(.subheadline).foregroundStyle(AppTheme.ink).accessibilityHidden(true)
                Text("\(items.count) 个动作").font(.subheadline).foregroundStyle(AppTheme.ink)
            }.padding(.bottom, 8)
        }
    }

    @ViewBuilder private func workoutItemRow(index: Int, item: TemplateExercise, cardio: ProgramCardioDraft?) -> some View {
        let number = String(format: "%02d", index + 1)
        let name = exercises.first { $0.id == item.exerciseID }?.name ?? "已保存动作"
        if let cardio {
            let volume = "\(TrainingPlanPresentation.requiredRoundCount(for: cardio)) 轮"
            workoutItemContent(number: number, name: name, volume: volume)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("训练-今日安排-动作-跳绳")
                .accessibilityLabel("\(number), \(name), \(volume)")
        } else {
            workoutItemContent(number: number, name: name, volume: "\(item.targetSets) 组")
        }
    }

    private func workoutItemContent(number: String, name: String, volume: String) -> some View {
        HStack(spacing: 12) {
            Text(number).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
            Text(name).font(.subheadline)
            Spacer(minLength: 8)
            Text(volume).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private func workoutAction(_ schedule: ScheduledWorkout) -> some View {
        if schedule.status == .completed {
            if let session = sessions.first(where: { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }) {
                NavigationLink(destination: WorkoutDetailView(sessionID: session.id)) {
                    heroActionLabel("查看训练记录", icon: "checkmark.circle")
                }
            } else { Label("已完成", systemImage: "checkmark.circle").foregroundStyle(AppTheme.ink) }
        } else if jumpRopeDraft(for: schedule) != nil && dateSelection.selectedLocalDay <= dateSelection.todayLocalDay {
            Button {
                jumpRopeScheduleID = schedule.id
                showRope = true
            } label: {
                heroActionLabel("记录并完成跳绳", icon: "figure.jumprope")
            }
            .accessibilityIdentifier("记录并完成跳绳")
        } else if selectedDate.isSameDay(as: .now) {
            Button { start(schedule) } label: { heroActionLabel(starting ? "正在准备…" : "开始训练") }
                .disabled(starting).accessibilityIdentifier("开始记录训练")
        } else if jumpRopeDraft(for: schedule) != nil {
            heroActionLabel("按计划日期记录", icon: "calendar")
        } else {
            NavigationLink(destination: DailyWorkoutBuilderView(initialDate: selectedDate, initialScheduleID: schedule.id)) {
                heroActionLabel("查看训练安排")
            }
        }
    }
    private func heroActionLabel(_ title: String, icon: String = "arrow.right") -> some View {
        HStack { Text(title); Spacer(); Image(systemName: icon) }
            .padding(.horizontal, 16).neonButtonStyle()
    }
    private func destinationRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            SprintIcon(systemName: icon, size: 24)
            Text(title).foregroundStyle(AppTheme.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
        }.frame(minHeight: 52).contentShape(Rectangle())
    }
    @ViewBuilder private func weekScheduleRow(_ schedule: ScheduledWorkout) -> some View {
        if jumpRopeDraft(for: schedule) != nil {
            Button { dateSelection.select(localDay: TrainingScheduleDate.localDay(schedule)) } label: { weekScheduleLabel(schedule) }
                .accessibilityIdentifier("查看跳绳日程")
        } else {
            NavigationLink(destination: DailyWorkoutBuilderView(
                initialDate: schedule.plannedDate,
                initialScheduleID: schedule.id
            )) { weekScheduleLabel(schedule) }
        }
    }
    private func weekScheduleLabel(_ schedule: ScheduledWorkout) -> some View {
        let feedback = feedback(for: [schedule])
        return HStack(spacing: 14) {
            Text(TrainingScheduleDate.displayDate(schedule), format: .dateTime.weekday(.short))
                .font(.caption).foregroundStyle(AppTheme.secondaryText).frame(width: 42)
            Text(schedule.templateName).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
            Spacer()
            Text(feedback.label).font(.caption2).foregroundStyle(feedback.color)
            TrainingStatusMarker(feedback: feedback)
        }.frame(minHeight: 56).contentShape(Rectangle())
    }
    private func jumpRopeDraft(for schedule: ScheduledWorkout) -> ProgramCardioDraft? {
        if let plan = schedule.jumpRopePlan {
            return ProgramCardioDraft(code: "ROPE_MANUAL_" + schedule.id.uuidString,
                title: schedule.templateName, weekday: TrainingScheduleDate.displayDate(schedule).weekdayNumber,
                timing: "", activeSeconds: plan.activeSeconds, elapsedSeconds: plan.elapsedSeconds,
                intervals: plan.notes, guidance: plan.summary)
        }
        guard let cardio = TrainingPlanPresentation.cardioDraft(scheduleID: schedule.id,
            links: programWorkoutLinks, revisions: programRevisions),
              TrainingPlanPresentation.isJumpRope(cardio, exercises: exercises) else { return nil }
        return cardio
    }
    private func open(_ id: UUID) { workoutSessionID = id; showWorkout = true }
    private func start(_ schedule: ScheduledWorkout) {
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do { open(try await WorkoutService.startUsingAvailableBodyWeight(schedule: schedule, in: modelContext)) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

enum ConditionScorePresentation {
    static func emoji(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "😵"
        case 2: return "😣"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "💪"
        }
    }

    static func title(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差，建议休息或明显降量"
        case 2: return "状态偏差，训练时注意反馈"
        case 3: return "状态一般，按实际感觉调整"
        case 4: return "状态不错，可以正常训练"
        default: return "状态很好，准备充分"
        }
    }

    static func shortTitle(for score: Int) -> String {
        switch min(max(score, 1), 5) {
        case 1: return "状态很差"
        case 2: return "状态偏差"
        case 3: return "状态一般"
        case 4: return "状态不错"
        default: return "状态很好"
        }
    }
}

struct DailyBodyCheckInEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let checkIn: DailyBodyCheckIn?
    let date: Date

    @State private var score: Int
    @State private var notes: String
    @State private var selectedKind: BodyMarkerKind = .area
    @State private var markers: [BodyMapMarker]
    @State private var errorMessage: String?
    @State private var inferenceMessage: String?

    init(checkIn: DailyBodyCheckIn?, date: Date = .now) {
        self.checkIn = checkIn
        self.date = date
        _score = State(initialValue: checkIn?.conditionScore ?? 3)
        _notes = State(initialValue: checkIn?.discomfortNotes ?? "")
        _markers = State(initialValue: checkIn?.bodyMarkers ?? [])
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SprintPageHeader(title: "身体体感", icon: "figure.stand", subtitle: date.formatted(.dateTime.month().day()))
                scoreCard
                notesCard
                anatomyCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .dismissKeyboardWhenScrolling {
            KeyboardDismissal.dismiss()
        }
        .sprintPage()
        .navigationTitle(date.isSameDay(as: .now) ? "今日体感" : "身体体感")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier("取消今日体感")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("保存今日体感")
                    .disabled(date.startOfDay > Date.now.startOfDay)
            }
        }
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("整体状态 · 1 差 → 5 好", systemImage: "heart")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        score = value
                    } label: {
                        VStack(spacing: 5) {
                            Text(ConditionScorePresentation.emoji(for: value))
                                .font(.title2)
                            Text("\(value)")
                                .font(.caption2.bold().monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            score == value ? AppTheme.accent.opacity(0.18) : AppTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(score == value ? AppTheme.accent : AppTheme.line, lineWidth: score == value ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("体感 \(value) 分，\(ConditionScorePresentation.title(for: value))")
                    .accessibilityIdentifier("body-score-\(value)")
                    .accessibilityAddTraits(score == value ? .isSelected : [])
                }
            }

            Text(ConditionScorePresentation.title(for: score))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SprintSectionHeading(title: "不适备注", icon: "note.text")
            TextField("例如：右肩前侧抬手疼，左膝下蹲发紧", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("body-discomfort-notes")

            Button {
                let result = BodyRegionCatalog.inferMarkers(in: notes, kind: selectedKind)
                merge(result.markers)
                if result.requiresConfirmation {
                    inferenceMessage = "无法确定\(result.unresolvedTerms.joined(separator: "、"))的前后或左右位置，请在人体图上确认。"
                } else if result.markers.isEmpty, !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已忽略否定描述，没有自动添加标记。"
                } else if result.markers.isEmpty {
                    inferenceMessage = "没有识别到明确部位，请在人体图上手动点选。"
                } else if !result.ignoredNegatedTerms.isEmpty {
                    inferenceMessage = "已标记明确不适，并忽略了否定描述。"
                } else {
                    inferenceMessage = "已标记 \(result.markers.count) 个明确部位，请确认后保存。"
                }
            } label: {
                Label("按备注识别并标记部位", systemImage: "sparkles")
                    .font(.caption.bold())
            }
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("按备注标记部位")

            if let inferenceMessage {
                Text(inferenceMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("body-inference-result")
            }
        }
        .cardSurface()
    }

    private var anatomyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("不适部位", systemImage: "figure.stand")
                    .font(.headline)
                Text("先选标记类型，再点正面或背面的部位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("标记类型", selection: $selectedKind) {
                ForEach(BodyMarkerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("body-marker-kind")

            BodyMapDiagram(
                markers: markers,
                selectedKind: selectedKind,
                isInteractive: true,
                onTap: toggle
            )
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Label("红色区域：肌肉 / 部位", systemImage: "rectangle.inset.filled")
                Label("红点：关节 / 筋膜", systemImage: "circle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if markers.isEmpty {
                Text("还没有标记。没有不适时可以只保存体感分数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已标注")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(sortedMarkers) { marker in
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: marker.kind == .jointFascia ? 8 : 13, height: 8)
                            Text("\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID) · \(marker.kind.title)")
                                .font(.caption)
                            Spacer()
                            Button {
                                markers.removeAll { $0.id == marker.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除\(BodyRegionCatalog.definition(for: marker.regionID)?.name ?? marker.regionID)的\(marker.kind.title)标注")
                            .accessibilityIdentifier("remove-body-marker-\(marker.id)")
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private var sortedMarkers: [BodyMapMarker] {
        markers.sorted {
            (BodyRegionCatalog.definition(for: $0.regionID)?.name ?? $0.regionID)
                < (BodyRegionCatalog.definition(for: $1.regionID)?.name ?? $1.regionID)
        }
    }

    private func merge(_ incoming: [BodyMapMarker]) {
        guard !incoming.isEmpty else { return }
        for marker in incoming {
            markers.removeAll { $0.id == marker.id }
            markers.append(marker)
        }
    }

    private func toggle(_ regionID: String) {
        if markers.contains(where: { $0.regionID == regionID && $0.kind == selectedKind }) {
            markers.removeAll { $0.regionID == regionID && $0.kind == selectedKind }
        } else {
            markers.append(BodyMapMarker(regionID: regionID, kind: selectedKind))
        }
    }

    private func save() {
        do {
            try DailyBodyCheckInService.save(
                existing: checkIn,
                date: date,
                conditionScore: score,
                discomfortNotes: notes,
                bodyMarkers: markers,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BodyMapDiagram: View {
    let markers: [BodyMapMarker]
    let selectedKind: BodyMarkerKind
    let isInteractive: Bool
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("MuscleMapBase")
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("正面和背面肌肉图")
                    .accessibilityIdentifier("body-muscle-map")

                ForEach(BodyRegionCatalog.all) { region in
                    let placement = BodyRegionImageLayout.placement(for: region)
                    regionControl(region, placement: placement, in: proxy.size)
                        .position(
                            x: proxy.size.width * placement.x,
                            y: proxy.size.height * placement.y
                        )
                }

                viewSideLabel("正面", x: 0.28, in: proxy.size)
                viewSideLabel("背面", x: 0.735, in: proxy.size)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正面和背面肌肉不适标注图")
        .accessibilityIdentifier("body-muscle-map-container")
    }

    @ViewBuilder
    private func regionControl(
        _ region: BodyRegionDefinition,
        placement: BodyRegionImagePlacement,
        in size: CGSize
    ) -> some View {
        let hasAreaMarker = markers.contains { $0.regionID == region.id && $0.kind == .area }
        let hasJointMarker = markers.contains { $0.regionID == region.id && $0.kind == .jointFascia }
        let isSelectedForCurrentKind = markers.contains {
            $0.regionID == region.id && $0.kind == selectedKind
        }
        let markerDescription: String = {
            switch (hasAreaMarker, hasJointMarker) {
            case (true, true): return "肌肉 / 区域和关节 / 筋膜"
            case (true, false): return BodyMarkerKind.area.title
            case (false, true): return BodyMarkerKind.jointFascia.title
            case (false, false): return "未标记"
            }
        }()
        let control = ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    hasAreaMarker
                        ? Color.red.opacity(0.46)
                        : AppTheme.ink.opacity(isInteractive ? 0.018 : 0)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            hasAreaMarker
                                ? Color.red
                                : AppTheme.ink.opacity(isInteractive ? 0.10 : 0),
                            lineWidth: hasAreaMarker ? 1.5 : 0.7
                        )
                }
                .shadow(color: hasAreaMarker ? Color.red.opacity(0.65) : .clear, radius: 7)

            if hasJointMarker {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .shadow(color: Color.red.opacity(0.9), radius: 5)
            }
        }
        .frame(
            width: max(20, size.width * placement.width),
            height: max(16, size.height * placement.height)
        )

        if isInteractive {
            Button { onTap(region.id) } label: {
                control
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(region.name)，\(markerDescription)")
            .accessibilityHint("点按切换为\(selectedKind.title)标记")
            .accessibilityIdentifier("body-region-\(region.id)")
            .accessibilityAddTraits(isSelectedForCurrentKind ? .isSelected : [])
        } else {
            control
                .accessibilityHidden(true)
        }
    }

    private func viewSideLabel(_ title: String, x: CGFloat, in size: CGSize) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.background, in: Capsule())
            .position(x: size.width * x, y: 18)
            .accessibilityHidden(true)
    }
}

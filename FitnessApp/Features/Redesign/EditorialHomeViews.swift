import Charts
import SwiftData
import SwiftUI

enum EditorialTheme {
    static let paper = AppTheme.background
    static let ink = AppTheme.ink
    static let muted = AppTheme.secondaryText
    static let line = AppTheme.line
    static let sage = AppTheme.surface
    static let lime = AppTheme.accent
}

extension View {
    func editorialPage() -> some View {
        sprintPage()
    }
    func legacyTrainingScreen() -> some View {
        sprintPage()
    }
}

struct EditorialHeading: View {
    let title: String
    let eyebrow: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.replacingOccurrences(of: "。", with: ""))
                .font(.title.bold()).tracking(-0.6).accessibilityIdentifier(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditorialRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(systemName: icon).font(.system(size: 22, weight: .regular)).frame(width: 28).foregroundStyle(EditorialTheme.ink).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(EditorialTheme.muted) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
        }.frame(minHeight: 52).contentShape(Rectangle()).padding(.vertical, 4)
            .overlay(alignment: .bottom) { EditorialTheme.line.frame(height: 0.5) }
    }
}

struct EditorialPrimary: View {
    let title: String
    var icon: String? = nil
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        HStack(spacing: 13) {
            if let icon {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(EditorialTheme.ink).frame(width: 36, height: 36)
                    .background(EditorialTheme.lime, in: RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
            }
            Text(title); Spacer(minLength: 10); Image(systemName: "arrow.right").accessibilityHidden(true)
        }
        .font(.subheadline.bold()).foregroundStyle(.white)
        .padding(.horizontal, icon == nil ? 17 : 10).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 56)
        .background(EditorialTheme.ink, in: RoundedRectangle(cornerRadius: 16))
        .opacity(isEnabled ? 1 : 0.4).contentShape(RoundedRectangle(cornerRadius: 16))
    }
}


struct EditorialTabBar: View {
    @Binding var selection: Int
    private let tabs = [("训练", "dumbbell"), ("饮食", "fork.knife"), ("进展", "chart.xyaxis.line"), ("工具", "square.grid.2x2"), ("我的", "person")]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button { selection = index } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tabs[index].1).font(.system(size: 21, weight: selection == index ? .semibold : .regular))
                            .frame(height: 24)
                            .accessibilityHidden(true)
                        Text(tabs[index].0)
                            .font(.caption2.weight(selection == index ? .semibold : .regular))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 2).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(selection == index ? EditorialTheme.lime : .clear, in: Capsule())
                    .foregroundStyle(selection == index ? EditorialTheme.ink : EditorialTheme.muted)
                    .contentShape(Rectangle())
                }.accessibilityLabel(tabs[index].0).accessibilityIdentifier("主导航-" + tabs[index].0)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.buttonStyle(.plain).padding(6)
            .floatingGlassSurface(cornerRadius: 32)
            .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 6)
            .accessibilityElement(children: .contain).accessibilityIdentifier("主导航")
            .modifier(EditorialTabAccessibility())
    }
}

private struct SprintBrand: View {
    let page: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill").foregroundStyle(EditorialTheme.lime)
                .overlay { Image(systemName: "bolt").foregroundStyle(EditorialTheme.ink) }
                .accessibilityHidden(true)
            Text("XFIT").font(.title2.weight(.heavy).italic()).tracking(-1.2)
                .accessibilityLabel(page).accessibilityIdentifier(page + "。")
        }.foregroundStyle(EditorialTheme.ink)
    }
}

private struct SprintHomeBar<Trailing: View>: View {
    let page: String
    let trailing: Trailing

    init(page: String, @ViewBuilder trailing: () -> Trailing) {
        self.page = page
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            SprintBrand(page: page)
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44).padding(.horizontal, 23).padding(.vertical, 6)
        .background(EditorialTheme.paper.ignoresSafeArea(edges: .top))
    }
}

private struct SprintTrainingEmblem: View {
    var symbol = "figure.strengthtraining.traditional"
    var body: some View {
        ZStack {
            SprintIcon(systemName: symbol, size: 124, prominent: true).rotationEffect(.degrees(-8))
            VStack(spacing: 6) {
                Capsule().frame(width: 29, height: 5)
                Capsule().frame(width: 21, height: 5)
            }.rotationEffect(.degrees(-32)).offset(x: -64, y: -31)
            Capsule().frame(width: 16, height: 4).rotationEffect(.degrees(-35)).offset(x: 64, y: 46)
        }.foregroundStyle(EditorialTheme.ink).frame(width: 162, height: 148).accessibilityHidden(true)
    }
}

private struct SprintShortcut: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .regular)).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(EditorialTheme.muted)
        }.frame(maxWidth: .infinity, minHeight: 76).contentShape(Rectangle())
    }
}

private struct EditorialTabAccessibility: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.accessibilityAddTraits(.isTabBar) }
        else { content }
    }
}

struct EditorialTrainingHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query private var sets: [SetLog]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var rope: [JumpRopeEntry]
    @Query private var programLinks: [ProgramWorkoutLink]
    @Query private var programRevisions: [TrainingProgramRevision]
    @Query private var catalog: [Exercise]
    @State private var selection = TrainingDateSelection.shared
    @State private var activeID: UUID?
    @State private var showActive = false
    @State private var error: String?
    @State private var starting = false
    @State private var isVisible = false
    @State private var recordingCardio: ScheduledWorkout?
    @State private var reschedulingPastPlan: ScheduledWorkout?
    @State private var rescheduleUndo: ScheduleManagementUndo?
    @State private var rescheduleMessage: String?
    @State private var rescheduledID: UUID?
    @State private var viewingRescheduledDay: String?
    @State private var weekFrame: CGRect = .zero

    private var progress: [UUID: TrainingWorkSetProgress] {
        Dictionary(grouping: sets.filter { !$0.isWarmup }, by: \.sessionID).mapValues { rows in
            let active = rows.filter { $0.reductionOrder == nil }
            return TrainingWorkSetProgress(completed: active.filter(\.isCompleted).count, total: active.count)
        }
    }
    private var supersededScheduleIDs: Set<UUID> {
        ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in: schedules)
    }
    private var effectiveSchedules: [ScheduledWorkout] {
        let retired = supersededScheduleIDs
        return schedules.filter { !retired.contains($0.id) }
    }
    private var summary: TrainingDaySummary {
        TrainingDaySummary(localDay: selection.selectedLocalDay, schedules: schedules, sessions: sessions,
            progress: progress, jumpRopeEntries: rope, excludedScheduleIDs: supersededScheduleIDs, timeZone: selection.timeZone)
    }
    private var active: WorkoutSession? { summary.activeSessions.first }
    private var otherDayActiveSessions: [WorkoutSession] {
        sessions.filter { session in
            guard session.status == .inProgress else { return false }
            let linked = schedules.first { $0.id == session.scheduledWorkoutID }
            return TrainingHistoryDate.localDay(session, schedule: linked, timeZone: selection.timeZone) != selection.selectedLocalDay
        }
    }
    private var planned: ScheduledWorkout? {
        effectiveSchedules.first { TrainingScheduleDate.localDay($0, timeZone: selection.timeZone) == selection.selectedLocalDay && $0.status == .planned }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                    NavigationLink {
                        TrainingDateMenuView(localDay: selection.selectedLocalDay)
                    } label: { HStack(spacing: 7) {
                        Text(selection.selectedDate, format: .dateTime.month().day()).font(.subheadline.weight(.semibold))
                        Text(selection.selectedDate, format: .dateTime.weekday()).font(.caption).foregroundStyle(EditorialTheme.muted)
                        Spacer()
                    }.frame(minHeight: 44).contentShape(Rectangle()).accessibilityElement(children: .combine)
                        .accessibilityIdentifier("训练-所选日期")
                    }.accessibilityIdentifier("训练-日期菜单").accessibilityHint("打开这一天的训练菜单")
                    Button { selection.shiftWeek(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("上一周")
                    Button { selection.shiftWeek(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.accessibilityLabel("下一周")
                    }
                    weekStrip
                }
                if let active {
                    let cardio = CardioWorkoutPresentation.actual(active, exercises: sessionExercises, logs: sets)
                    hero(title: active.templateName, status: "进行中", value: "", statusIcon: "play.circle",
                         exerciseCount: cardio == nil ? sessionExercises.filter { $0.sessionID == active.id }.count : nil,
                         setCount: cardio == nil ? progress[active.id]?.total : nil, cardio: cardio)
                    if let schedule = effectiveSchedules.first(where: { $0.id == active.scheduledWorkoutID }) {
                        planActions(schedule) {
                            Button { activeID = active.id; showActive = true } label: { actionLabel("继续") }
                                .accessibilityLabel("继续训练").accessibilityIdentifier("继续训练")
                        }
                    } else {
                        Button { activeID = active.id; showActive = true } label: { EditorialPrimary(title: "继续", icon: "play.fill") }
                            .accessibilityLabel("继续训练").accessibilityIdentifier("继续训练")
                    }
                } else if summary.hasActualRecords {
                    actualCard
                    if let session = summary.recordedSessions.first,
                       let schedule = effectiveSchedules.first(where: { $0.id == session.scheduledWorkoutID }) {
                        planOnly(schedule)
                    }
                } else if let planned {
                    let cardio = CardioWorkoutPresentation.plan(planned)
                    hero(title: planned.templateName, status: "待练", value: "",
                         exerciseCount: cardio == nil && !planned.planSnapshot.isEmpty ? planned.planSnapshot.count : nil,
                         setCount: cardio == nil && !planned.planSnapshot.isEmpty ? planned.planSnapshot.reduce(0) { $0 + $1.targetSets } : nil,
                         cardio: cardio)
                    planActions(planned) {
                    if cardio != nil {
                        if selection.selectedLocalDay <= TrainingLocalDate.key(.now) {
                            Button { recordingCardio = planned } label: { actionLabel("记录完成") }
                                .accessibilityIdentifier("训练-记录有氧")
                        } else {
                            NavigationLink { TrainingDateMenuView(localDay: selection.selectedLocalDay) } label: {
                                actionLabel("打开菜单")
                            }
                        }
                    } else if TrainingDateMenuService.isJumpRope(planned, links: programLinks, revisions: programRevisions, exercises: catalog) {
                        NavigationLink { TrainingDateMenuView(localDay: selection.selectedLocalDay) } label: {
                            actionLabel("打开菜单")
                        }.accessibilityIdentifier("训练-打开跳绳菜单")
                    } else {
                        Button { start(planned) } label: { actionLabel(starting ? "准备中…" : "开始") }.disabled(starting).accessibilityLabel("开始训练")
                    }
                    }
                    if selection.selectedLocalDay < TrainingLocalDate.key(.now),
                       ScheduleService.canManage(planned, in: context) {
                        Button { reschedulingPastPlan = planned } label: {
                            Label("调整训练日期", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(EditorialTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.accessibilityIdentifier("训练-调整过去计划日期")
                    }
                } else {
                    hero(title: "准备开练", status: "暂无安排", value: "", statusIcon: "calendar")
                    NavigationLink { TrainingDateMenuView(localDay: selection.selectedLocalDay) } label: {
                        EditorialPrimary(title: "安排训练", icon: "plus")
                    }.accessibilityIdentifier("安排今天训练")
                }
                ForEach(otherDayActiveSessions) { session in
                    Button { activeID = session.id; showActive = true } label: {
                        EditorialRow(title: session.templateName, subtitle: "其他日期 · 继续训练", icon: "play.circle")
                    }.accessibilityIdentifier("训练-其他日期继续-\(session.id.uuidString)")
                }
                if summary.hasActualRecords, let pending = summary.pendingPlansLabel {
                    NavigationLink { ScheduleView().legacyTrainingScreen() } label: {
                        EditorialRow(title: "其他待完成安排", subtitle: pending, icon: "clock")
                    }.accessibilityIdentifier("训练-其他待完成安排")
                }
                let upcoming = effectiveSchedules.filter { $0.status == .planned && TrainingScheduleDate.localDay($0) > selection.selectedLocalDay }
                if !upcoming.isEmpty {
                    upcomingTimeline(Array(upcoming.prefix(2)))
                }
            }.padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 18)
        }

        #if DEBUG
        .overlay(alignment: .topLeading) {
            if CloudSyncRuntime.isUITesting, CommandLine.arguments.contains("--ui-testing-home-plan-week") {
                Text(homePlanTestDigest).font(.system(size: 1)).foregroundStyle(.clear)
                    .frame(width: 1, height: 1).allowsHitTesting(false)
                    .accessibilityLabel("只读浏览校验").accessibilityValue(homePlanTestDigest)
                    .accessibilityIdentifier("训练-只读校验")
            }
        }
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            SprintHomeBar(page: "训练") {
                if selection.selectedLocalDay != TrainingLocalDate.key(.now) {
                    Button("今天") { selection.refresh(reason: .explicitToday) }.font(.caption.bold()).frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("训练-回到今天")
                }
                NavigationLink { ScheduleView().legacyTrainingScreen() } label: {
                    Image(systemName: "calendar").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("训练日程")
            }
        }.editorialPage().buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { pastRescheduleResult }
            .navigationDestination(isPresented: $showActive) { if let activeID { ActiveWorkoutView(sessionID: activeID).legacyTrainingScreen() } }
            .navigationDestination(isPresented: Binding(
                get: { viewingRescheduledDay != nil }, set: { if !$0 { viewingRescheduledDay = nil } }
            )) {
                if let day = viewingRescheduledDay { TrainingDateMenuView(localDay: day) }
            }
            .onAppear { isVisible = true; refreshDate(.returnFromDetail) }
            .onDisappear { isVisible = false }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDate(.foreground) } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDate(.dayOrTimeZoneChanged) }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDate(.dayOrTimeZoneChanged) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDate(.dayOrTimeZoneChanged) }
            .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .sheet(item: $recordingCardio) { CardioWorkoutRecordSheet(schedule: $0) }
            .sheet(item: $reschedulingPastPlan) { schedule in
                RescheduleWorkoutView(schedule: schedule, minimumDate: Date.now.startOfDay,
                    resultDestination: "当前首页", validate: { date in
                        try validatePastReschedule(schedule, date: date)
                    }, onSave: { date in
                        try validatePastReschedule(schedule, date: date)
                        rescheduleUndo = try ScheduleService.rescheduleManaged(schedule, to: date, in: context)
                        rescheduledID = schedule.id
                        rescheduleMessage = "已改期至" + date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
                    }).tint(AppTheme.ink)
            }
    }

    #if DEBUG
    private var homePlanTestDigest: String {
        var hash = Hasher()
        for row in schedules.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hash.combine(row.id); hash.combine(row.templateID); hash.combine(row.templateName)
            hash.combine(row.plannedDate); hash.combine(row.plannedLocalDay)
            hash.combine(row.statusRaw); hash.combine(row.planSnapshotJSON)
        }
        for row in sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hash.combine(row.id); hash.combine(row.scheduledWorkoutID); hash.combine(row.statusRaw)
            hash.combine(row.startedAt); hash.combine(row.completedAt); hash.combine(row.notes)
        }
        for row in sessionExercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hash.combine(row.id); hash.combine(row.sessionID); hash.combine(row.exerciseName)
            hash.combine(row.targetWeight); hash.combine(row.targetSets); hash.combine(row.plannedSetsJSON)
        }
        for row in sets.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hash.combine(row.id); hash.combine(row.sessionID); hash.combine(row.targetWeight); hash.combine(row.targetReps)
            hash.combine(row.actualWeight); hash.combine(row.actualReps); hash.combine(row.isCompleted)
        }
        return "\(schedules.count)/\(sessions.count)/\(sessionExercises.count)/\(sets.count):\(hash.finalize())"
    }
    #endif

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: 7) { Text(title); Image(systemName: "arrow.right").accessibilityHidden(true) }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minWidth: 90, minHeight: 56).contentShape(Rectangle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func planActions<Primary: View>(_ schedule: ScheduledWorkout, @ViewBuilder primary: () -> Primary) -> some View {
        HStack(spacing: 0) {
            NavigationLink { savedPlan(schedule) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet").font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(EditorialTheme.ink).frame(width: 36, height: 36)
                        .background(EditorialTheme.lime, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    Text("查看计划").foregroundStyle(.white)
                }.font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }.accessibilityIdentifier("训练-查看计划")
            Color.white.opacity(0.3).frame(width: 1, height: 24).accessibilityHidden(true)
            primary()
        }.background(EditorialTheme.ink, in: RoundedRectangle(cornerRadius: 16))
    }

    private func planOnly(_ schedule: ScheduledWorkout) -> some View {
        NavigationLink { savedPlan(schedule) } label: { EditorialPrimary(title: "查看计划", icon: "list.bullet") }
            .accessibilityIdentifier("训练-查看计划")
    }

    private func savedPlan(_ schedule: ScheduledWorkout) -> some View {
        SavedSchedulePlanView(schedule: schedule, draft: TrainingPlanPresentation.cardioDraft(
            scheduleID: schedule.id, links: programLinks, revisions: programRevisions))
    }

    private func validatePastReschedule(_ schedule: ScheduledWorkout, date: Date) throws {
        guard TrainingLocalDate.key(date) >= TrainingLocalDate.key(.now) else {
            throw NSError(domain: "PastPlanReschedule", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请选择今天或之后的日期。"])
        }
        try ScheduleService.validateManagedReschedule(schedule, to: date, in: context)
    }

    @ViewBuilder private var pastRescheduleResult: some View {
        if let rescheduleMessage {
            VStack(alignment: .leading, spacing: 2) {
                Text(rescheduleMessage).font(.caption).accessibilityIdentifier("过去计划改期-结果")
                HStack {
                    if let schedule = schedules.first(where: { $0.id == rescheduledID }),
                       TrainingScheduleDate.localDay(schedule) != selection.selectedLocalDay {
                        Button("查看计划") {
                            let day = TrainingScheduleDate.localDay(schedule)
                            selection.select(localDay: day)
                            viewingRescheduledDay = day
                        }
                            .accessibilityIdentifier("过去计划改期-查看")
                    }
                    if rescheduleUndo != nil {
                        Button("撤销") { undoPastReschedule() }.accessibilityIdentifier("过去计划改期-撤销")
                    }
                    Spacer()
                    Button("关闭") { self.rescheduleMessage = nil; rescheduleUndo = nil }
                        .accessibilityIdentifier("过去计划改期-关闭结果")
                }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            }.padding(.horizontal, 23).padding(.top, 8)
                .background(AppTheme.surface).foregroundStyle(AppTheme.ink)
        }
    }

    private func undoPastReschedule() {
        guard let undo = rescheduleUndo else { return }
        do {
            try ScheduleService.undoManaged(undo, in: context)
            rescheduleUndo = nil
            rescheduleMessage = "已撤销本次调整"
        } catch { self.error = error.localizedDescription }
    }

    private var weekStrip: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = selection.timeZone
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: selection.selectedDate)?.start ?? selection.selectedDate
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                weekDay(day, number: calendar.component(.day, from: day))
            }
        }.padding(.horizontal, -17)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("训练周历")
            .simultaneousGesture(DragGesture(minimumDistance: 20, coordinateSpace: .global).onEnded { value in
                guard weekFrame.contains(value.startLocation) else { return }
                if let direction = TrainingDateSelection.weekSwipeDirection(horizontal: value.translation.width, vertical: value.translation.height) {
                    selection.shiftWeek(by: direction)
                }
            })
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global).insetBy(dx: -17, dy: 0)
            } action: { frame in weekFrame = frame }
    }

    private func weekDay(_ day: Date, number: Int) -> some View {
        let key = TrainingLocalDate.key(day, timeZone: selection.timeZone)
        let selected = key == selection.selectedLocalDay
        let today = key == selection.todayLocalDay
        let status = TrainingDaySummary(localDay: key, schedules: schedules, sessions: sessions,
            progress: progress, jumpRopeEntries: rope, excludedScheduleIDs: supersededScheduleIDs, timeZone: selection.timeZone).feedback
        return Button { selection.select(localDay: key) } label: {
            VStack(spacing: 6) {
                (today ? Text("今") : Text(day, format: .dateTime.weekday(.narrow)))
                    .font(.caption2.weight(today ? .bold : .regular))
                    .foregroundStyle(today ? EditorialTheme.ink : EditorialTheme.muted)
                Text(String(number)).font(.headline).monospacedDigit()
                    .frame(width: 36, height: 36)
                    .background(selected ? EditorialTheme.lime : .clear, in: Circle())
                if key > selection.todayLocalDay, status.symbolName == "clock" {
                    Circle().fill(EditorialTheme.muted).frame(width: 4, height: 4).frame(height: 11)
                        .accessibilityHidden(true)
                } else if status.tone == .none { Color.clear.frame(height: 11) }
                else { Image(systemName: status.symbolName).font(.system(size: 10)).frame(height: 11).accessibilityHidden(true) }
            }.frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.accessibilityLabel(day.formatted(.dateTime.month().day().weekday()) + "，" + status.label)
            .accessibilityValue((today ? "今天，" : "") + (selected ? "已选中" : "未选中"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("训练日期-\(key)")
    }

    private func upcomingTimeline(_ items: [ScheduledWorkout]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接下来").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink { ScheduleView(initialScheduleID: item.id).legacyTrainingScreen() } label: {
                        upcomingRow(item)
                    }.accessibilityIdentifier("训练-接下来-\(item.id.uuidString)")
                    if index < items.count - 1 {
                        HStack(spacing: 0) {
                            EditorialTheme.line.frame(width: 1, height: 10).frame(width: 48)
                            Spacer(minLength: 0)
                        }.accessibilityHidden(true)
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-接下来时间线")
    }

    private func upcomingRow(_ item: ScheduledWorkout) -> some View {
        let display = TrainingWorkoutPresentation.upcoming(item.templateName)
        let date = TrainingScheduleDate.displayDate(item)
        let sameMonth = Calendar.current.isDate(date, equalTo: selection.selectedDate, toGranularity: .month)
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        let detail = display.detail ?? (item.planSnapshot.isEmpty ? nil : "力量训练")
        return HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(sameMonth ? String(day) : "\(month)/\(day)")
                    .font(sameMonth ? .title3.weight(.heavy) : .subheadline.bold()).monospacedDigit()
                Text(date, format: .dateTime.weekday(.short)).font(.caption2)
                    .foregroundStyle(EditorialTheme.muted)
            }.frame(width: 48).frame(minHeight: 60)
                .background(EditorialTheme.sage, in: RoundedRectangle(cornerRadius: 13))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityHidden(true)
            Image(systemName: display.symbolName).font(.system(size: 24, weight: .regular))
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(display.title).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.caption).foregroundStyle(EditorialTheme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
        }.foregroundStyle(EditorialTheme.ink).padding(.vertical, 7).frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(Rectangle()).accessibilityElement(children: .ignore)
            .accessibilityLabel(([date.formatted(.dateTime.year().month().day().weekday()), display.title, detail]
                .compactMap { $0 }).joined(separator: "，"))
            .accessibilityHint("查看这条训练安排")
    }

    private func hero(title: String, status: String, value: String, statusIcon: String = "clock", exerciseCount: Int? = nil, setCount: Int? = nil, cardio: CardioWorkoutSummary? = nil) -> some View {
        let hasCount = value.contains("/")
        let presentation = TrainingWorkoutPresentation.upcoming(title)
        let displayTitle = cardio?.title ?? presentation.title
        return VStack(spacing: 18) {
            SprintTrainingEmblem(symbol: cardio?.symbolName ?? (title.contains("跳绳") ? "figure.jumprope" : title.contains("下肢") || title.contains("腿") ? "figure.strengthtraining.functional" : "figure.strengthtraining.traditional"))
            VStack(spacing: 8) {
                Text(displayTitle.isEmpty ? title : displayTitle).font(.title.bold()).tracking(-0.7).multilineTextAlignment(.center)
                    .accessibilityIdentifier("训练-训练标题")
                if cardio == nil, let detail = presentation.detail {
                    Text(detail).font(.caption).foregroundStyle(EditorialTheme.muted)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("训练-训练副标题")
                }
                HStack(spacing: 5) {
                    Image(systemName: statusIcon).accessibilityHidden(true)
                    Text(status).accessibilityIdentifier("训练-当天状态")
                }.font(.caption).foregroundStyle(EditorialTheme.muted)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(EditorialTheme.sage, in: Capsule())
            }
            if let cardio {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .center, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 24))) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "timer").font(.subheadline).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
                        Text(cardio.durationValue).font(.title.bold().italic()).monospacedDigit()
                        Text(cardio.durationUnit).font(.caption).foregroundStyle(EditorialTheme.muted)
                    }
                    if let level = cardio.level {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Level").font(.caption).foregroundStyle(EditorialTheme.muted)
                            Text(TrainingFormatters.weight(level)).font(.title.bold().italic()).monospacedDigit()
                        }
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel(cardio.label)
                    .accessibilityIdentifier("训练-有氧指标")
            } else if hasCount {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.title3).accessibilityHidden(true)
                    Text(value).font(.title.bold().italic()).monospacedDigit()
                    Text("组已记录").font(.caption).foregroundStyle(EditorialTheme.muted)
                }
            } else if exerciseCount != nil || setCount != nil {
                HStack(spacing: 24) {
                    if let exerciseCount { heroMetric(exerciseCount, unit: "动作", icon: "dumbbell") }
                    if let setCount { heroMetric(setCount, unit: "组", icon: "square.3.layers.3d") }
                }
            }
        }.frame(maxWidth: .infinity).padding(.bottom, 9)
    }

    private func heroMetric(_ value: Int, unit: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(EditorialTheme.muted).accessibilityHidden(true)
            Text(String(format: "%02d", value)).font(.title.bold().italic()).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(EditorialTheme.muted)
        }
    }

    private var actualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = summary.recordedSessions.first {
                let count = progress[session.id]
                let cardio = CardioWorkoutPresentation.actual(session, exercises: sessionExercises, logs: sets)
                NavigationLink {
                    if cardio != nil { CardioWorkoutSummaryView(sessionID: session.id) }
                    else { WorkoutDetailView(sessionID: session.id).legacyTrainingScreen() }
                } label: {
                    hero(title: session.templateName, status: cardio == nil ? summary.feedback.label : "已完成",
                        value: cardio == nil ? "\(count?.completed ?? 0) / \(count?.total ?? 0)" : "",
                        statusIcon: summary.feedback.symbolName, cardio: cardio)
                }
            }
            ForEach(summary.recordedSessions.dropFirst()) { session in
                NavigationLink { WorkoutDetailView(sessionID: session.id).legacyTrainingScreen() } label: {
                    EditorialRow(title: session.templateName, subtitle: "实际已记录", icon: "checkmark.circle")
                }
            }
            ForEach(summary.jumpRopeEntries) { entry in
                NavigationLink { JumpRopeMenuRecordDetail(entry: entry) } label: {
                    EditorialRow(title: "跳绳 · \(entry.count.map { "\($0)次" } ?? "次数未记录")", subtitle: "实际已记录", icon: "figure.jumprope")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("训练-当天实际")
    }

    private func refreshDate(_ reason: TrainingDateSelection.RefreshReason) {
        selection.refresh(reason: reason, hasActiveSession: showActive && active != nil,
            isEditing: reschedulingPastPlan != nil,
            isShowingDetail: !isVisible || showActive)
    }

    private func start(_ schedule: ScheduledWorkout) {
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do { activeID = try await WorkoutService.startUsingAvailableBodyWeight(schedule: schedule, in: context); showActive = true }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct EditorialNutritionHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @State private var date = Date.now
    @State private var showDate = false
    @State private var showMethods = false
    @State private var showPhoto = false
    @State private var showManual = false
    @State private var detail: MealEntry?
    @ScaledMetric(relativeTo: .largeTitle) private var mealCountSize = 58
    private var dayMeals: [MealEntry] { meals.filter { $0.isActiveMeal && $0.stableLocalDay == MealLocalDay.string(for: date) } }
    private var future: Bool { MealLocalDay.string(for: date) > MealLocalDay.string(for: .now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(date, format: .dateTime.month().day().weekday()).font(.subheadline)
                    Spacer(); Text(future ? "未来日期" : "已记录").font(.caption).foregroundStyle(EditorialTheme.muted)
                }
                VStack(spacing: 19) {
                    SprintIcon(systemName: "fork.knife", size: 124, prominent: true).rotationEffect(.degrees(-8))
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(String(format: "%02d", dayMeals.count)).font(.system(size: mealCountSize, weight: .heavy, design: .rounded).italic())
                        Text("餐").font(.subheadline).foregroundStyle(EditorialTheme.muted)
                    }.accessibilityElement(children: .combine).accessibilityLabel("已记录\(dayMeals.count)条餐食")
                        .accessibilityIdentifier("饮食-已记录餐数")
                }.frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 4)
                Button { showMethods = true } label: { EditorialPrimary(title: "记一餐", icon: "camera") }
                    .disabled(future).accessibilityLabel("记录一餐").accessibilityIdentifier("饮食-记录一餐")
                if let meal = dayMeals.first {
                    Button { detail = meal } label: {
                        HStack(spacing: 14) {
                            if let photo = meal.mealPhotos.first {
                                MealStoredPhoto(photo: photo).frame(width: 66, height: 66).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                            } else {
                                SprintIcon(systemName: meal.mealType.systemImage, size: 56)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(MealPhotoPresentation.title(meal)).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                Text(meal.mealType.title + " · " + meal.photoReviewStatus).font(.caption).foregroundStyle(EditorialTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 66).contentShape(Rectangle())
                    }.accessibilityIdentifier("饮食-最近一餐")
                }
                VStack(spacing: 0) {
                    ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                        let existing = dayMeals.first { $0.mealType == type }
                        Button { if let existing { detail = existing } else { showMethods = true } } label: {
                            HStack(spacing: 12) {
                                SprintIcon(systemName: type.systemImage, size: 38)
                                Text(type.title).font(.subheadline)
                                Spacer(minLength: 8)
                                Text(existing?.photoReviewStatus ?? "未记录").font(.caption).foregroundStyle(EditorialTheme.muted)
                                Image(systemName: existing == nil ? "plus" : "chevron.right").font(.caption).accessibilityHidden(true)
                            }.frame(minHeight: 65).contentShape(Rectangle())
                                .overlay(alignment: .bottom) { EditorialTheme.line.frame(height: 0.5) }
                        }.disabled(future && existing == nil)
                    }
                }
                HStack(spacing: 16) {
                    NavigationLink { MealWeekReviewView(date: date).legacyTrainingScreen() } label: { SprintShortcut(title: "周回顾", icon: "calendar.badge.checkmark") }.accessibilityIdentifier("饮食-餐食周回顾")
                    NavigationLink { NutritionHomeView().legacyTrainingScreen() } label: { SprintShortcut(title: "餐单与备餐", icon: "frying.pan") }.accessibilityLabel("餐单、备餐与全部餐食")
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SprintHomeBar(page: "饮食") {
                Button { showDate = true } label: { Image(systemName: "calendar").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("选择饮食日期")
            }
        }.editorialPage().buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("记录一餐", isPresented: $showMethods, titleVisibility: .visible) {
                Button("拍照记录新餐") { showPhoto = true }.accessibilityIdentifier("饮食-拍照记餐")
                Button("手动记录新餐") { showManual = true }
                Button("取消", role: .cancel) {}
            } message: { Text("补充已记录的餐食，请点开对应餐次。") }
            .sheet(isPresented: $showPhoto) {
                MealPhotoComposer(date: date) { photos, date, type, note in
                    _ = try MealPhotoService().createMeal(photoData: photos, date: date, mealType: type, note: note, context: context)
                }.legacyTrainingScreen()
            }
            .sheet(isPresented: $showManual) { MealEditorView(meal: nil, date: date).legacyTrainingScreen() }
            .sheet(item: $detail) { MealPhotoDetailView(meal: $0).legacyTrainingScreen() }
            .sheet(isPresented: $showDate) {
                NavigationStack {
                    DatePicker("饮食日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).padding(24)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showDate = false } } }
                }.editorialPage()
            }
    }
}

struct EditorialProgressHomeView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var snapshots: [SessionExercise]
    @Query private var sets: [SetLog]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var bodyMode = false
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize = 58
    @Query private var coachRows: [TrainingCoachRecord]
    private var completed: [WorkoutSession] { sessions.filter { $0.status == .completed } }
    private var latestSet: SetLog? {
        guard let session = completed.first else { return nil }
        return sets.filter { set in
            set.sessionID == session.id && set.isCompleted && !set.isWarmup && !set.isActualWeightBlank && set.actualWeight > 0
                && snapshots.contains { $0.id == set.sessionExerciseID && $0.volumeUnit == .kilogram }
        }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.first
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 25) {
                    ForEach([false, true], id: \.self) { value in
                        Button { bodyMode = value } label: {
                            Text(value ? "身体" : "训练").font(.subheadline.weight(bodyMode == value ? .semibold : .regular))
                                .foregroundStyle(bodyMode == value ? EditorialTheme.ink : EditorialTheme.muted)
                                .frame(minWidth: 44, minHeight: 44)
                                .overlay(alignment: .bottom) { if bodyMode == value { EditorialTheme.lime.frame(height: 2) } }
                        }.accessibilityAddTraits(bodyMode == value ? .isSelected : [])
                    }
                    Spacer()
                }.overlay(alignment: .bottom) { EditorialTheme.line.frame(height: 0.5) }
                if bodyMode { bodyProgress } else { trainingProgress }
                NavigationLink { GoalHomeView().legacyTrainingScreen() } label: { EditorialRow(title: "目标与周期", icon: "scope") }
                NavigationLink { MuscleCoverageView().legacyTrainingScreen() } label: { EditorialRow(title: "肌群分布", icon: "figure.strengthtraining.traditional") }.accessibilityLabel("训练肌群分布")
            }.padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SprintHomeBar(page: "进展") { Image(systemName: "chart.xyaxis.line").font(.title3).accessibilityHidden(true) }
        }.editorialPage().buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var trainingProgress: some View {
        if let set = latestSet, let item = snapshots.first(where: { $0.id == set.sessionExerciseID }) {
            VStack(alignment: .leading, spacing: 16) {
                SprintIcon(systemName: "chart.line.uptrend.xyaxis", size: 54, prominent: true)
                Text(item.exerciseName).font(.subheadline.weight(.medium))
                Text(set.actualWeight.formatted()).font(.system(size: metricSize, weight: .heavy, design: .rounded).italic()).tracking(-2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.volumeUnit.symbol) · \(set.actualWeightSide.title)").font(.subheadline).foregroundStyle(EditorialTheme.muted)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(set.actualReps) 次").font(.title3.bold())
                    Spacer(); Text(effortLabel(set, item: item)).font(.caption).foregroundStyle(EditorialTheme.muted)
                }
                Text("最近记录 · 同器械、同口径比较").font(.caption).foregroundStyle(EditorialTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        } else {
            SprintPageHeader(title: "记录你的进展", icon: "chart.line.uptrend.xyaxis", subtitle: "完成训练后查看")
        }
        SprintSectionHeading(title: "最近训练", icon: "clock.arrow.circlepath")
        VStack(spacing: 0) {
            ForEach(Array(completed.prefix(3))) { session in
                NavigationLink {
                    if CardioWorkoutPresentation.actual(session, exercises: snapshots, logs: sets) != nil {
                        CardioWorkoutSummaryView(sessionID: session.id)
                    } else {
                        TrainingReviewView(sessionID: session.id)
                    }
                } label: {
                    HStack(spacing: 16) {
                        VStack(spacing: 1) {
                            Text(String(TrainingHistoryDate.localDay(session).suffix(2))).font(.title2.bold().italic())
                            Text(String(TrainingHistoryDate.localDay(session).prefix(7))).font(.caption2).foregroundStyle(EditorialTheme.muted)
                        }
                        Text(session.templateName).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark").font(.subheadline).accessibilityHidden(true)
                    }.frame(minHeight: 68).contentShape(Rectangle())
                        .overlay(alignment: .bottom) { EditorialTheme.line.frame(height: 0.5) }
                }.accessibilityIdentifier("进展-最近训练-" + session.id.uuidString)
            }
        }
        NavigationLink { StatsView().legacyTrainingScreen() } label: { EditorialRow(title: "训练趋势", icon: "chart.xyaxis.line") }.accessibilityLabel("全部训练趋势与历史")
    }

    private func effortLabel(_ set: SetLog, item: SessionExercise) -> String {
        if let rir = set.rir { return "RIR \(rir)" }
        let rows = TrainingCoachService.ordered(coachRows.filter { $0.sessionID == set.sessionID })
        let last = sets.filter { $0.sessionExerciseID == item.id && $0.isCompleted && !$0.isWarmup }.max { $0.setNumber < $1.setNumber }
        if last?.id == set.id, let after = try? TrainingCoachService.latestFeedback("after", rows: rows),
           let estimate = after.lastRIR[item.id.uuidString] { return "后补末组余力 ≈\(estimate)" }
        return "余力未记录"
    }

    private var bodyProgress: some View {
        let values = BodyMeasurementService.dailyRepresentativeWeights(from: measurements)
        return VStack(alignment: .leading, spacing: 18) {
            if let last = values.last {
                SprintIcon(systemName: "scalemass", size: 54, prominent: true)
                Text("\(last.weightKg.formatted()) kg").font(.largeTitle.bold().italic())
                Text(last.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(EditorialTheme.muted)
                if values.count >= 3 {
                    Chart(values, id: \.date) { item in
                        LineMark(x: .value("日期", item.date), y: .value("体重", item.weightKg)).foregroundStyle(EditorialTheme.ink)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) {
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 180).sprintChart()
                    .accessibilityIdentifier("进展-身体趋势图")
                } else { Text("继续记录，查看趋势").font(.caption).foregroundStyle(EditorialTheme.muted) }
            } else { SprintPageHeader(title: "身体记录", icon: "scalemass", subtitle: "从一次测量开始") }
            NavigationLink { BodyMeasurementsView().legacyTrainingScreen() } label: { EditorialPrimary(title: "身体记录", icon: "plus") }.accessibilityLabel("记录与查看身体数据")
        }
    }
}

struct EditorialToolsHomeView: View {
    var body: some View {
        ToolsView(isTabRoot: true)
            .safeAreaInset(edge: .top, spacing: 0) {
                SprintHomeBar(page: "工具") { EmptyView() }
            }
            .editorialPage()
    }
}

struct EditorialProfileHomeView: View {
    @Query(sort: \TrainingPreferenceRevision.effectiveAt, order: .reverse) private var preferences: [TrainingPreferenceRevision]
    private var preference: TrainingPreferenceRevision? { preferences.first { $0.effectiveAt <= .now } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 16) {
                    SprintIcon(systemName: "person", size: 84, prominent: true)
                    Text("训练档案").font(.title2.bold()).tracking(-0.4)
                    Text(preference?.snapshot?.splitStyle.title ?? "尚待确认").font(.subheadline.weight(.semibold))
                        .foregroundStyle(EditorialTheme.muted)
                }.frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 10)
                HStack(spacing: 8) {
                    NavigationLink { TrainingCoachPreferencesView().editorialPage() } label: { SprintShortcut(title: "偏好", icon: "slider.horizontal.3") }.accessibilityLabel("偏好与编排")
                    NavigationLink { BodyMeasurementsView().legacyTrainingScreen() } label: { SprintShortcut(title: "身体", icon: "ruler") }.accessibilityLabel("身体记录")
                    NavigationLink { HistoryView().legacyTrainingScreen() } label: { SprintShortcut(title: "历史", icon: "clock.arrow.circlepath") }.accessibilityLabel("训练历史")
                    NavigationLink { PlanView().legacyTrainingScreen() } label: { SprintShortcut(title: "动作", icon: "dumbbell") }.accessibilityLabel("模板与动作")
                }
                VStack(spacing: 0) {
                    NavigationLink { CoachWeekView() } label: { EditorialRow(title: "整周训练教练", icon: "calendar.badge.clock") }
                        .accessibilityIdentifier("我的-整周训练教练")
                    NavigationLink { ScheduleView().legacyTrainingScreen() } label: { EditorialRow(title: "训练日程", icon: "calendar") }
                    NavigationLink { AppSettingsView().legacyTrainingScreen() } label: { EditorialRow(title: "设置", icon: "gearshape") }.accessibilityIdentifier("打开设置")
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SprintHomeBar(page: "我的") { Image(systemName: "person.crop.circle").font(.title3).accessibilityHidden(true) }
        }.editorialPage().buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
    }
}

struct TrainingCoachPreferencesView: View {
    @Query(sort: \TrainingPreferenceRevision.effectiveAt, order: .reverse) private var preferences: [TrainingPreferenceRevision]
    var body: some View {
        List {
            SprintPageHeader(title: "训练偏好", icon: "slider.horizontal.3").listRowBackground(EditorialTheme.paper).listRowSeparator(.hidden)
            if let current = preferences.first(where: { $0.effectiveAt <= .now }), let snapshot = current.snapshot {
                Section("生效偏好 · \(current.revisionCode)") {
                    Text(snapshot.splitStyle.title)
                    Text("每周\(snapshot.strengthDaysPerWeek)次 · 每次\(snapshot.sessionMinutesLower)–\(snapshot.sessionMinutesUpper)分钟")
                    if let cardio = snapshot.totalCardioSessionsPerWeek { Text("每周有氧\(cardio)次，模式可调整") }
                    ForEach(snapshot.constraints, id: \.self) { Text($0) }
                }
            }
            Section {
                DisclosureGroup("编排方法") {
                    Text("先核对实际重量、次数、余力和动作质量，再看近期暴露与恢复。不同动作、器械和记重口径不混算。")
                    Text("按生效偏好设置工作组；技术、自重、计时及其他特殊动作单独校准。变化需要完整确认，不自动续排。")
                    Text("热身不计工作量；新反馈形成新草案，旧确认计划与原始实际保留。")
                }.font(.subheadline)
            }
        }.navigationTitle("训练偏好").navigationBarTitleDisplayMode(.inline).sprintPage()
    }
}

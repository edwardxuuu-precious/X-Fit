import SwiftData
import SwiftUI

struct PlanView: View {
    @Query(sort: \ScheduledWorkout.plannedDate) private var schedules: [ScheduledWorkout]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var templateExercises: [TemplateExercise]

    private var progressSummary: TrainingProgressSummary {
        TrainingMetrics.progressSummary(
            period: .week,
            schedules: schedules,
            sessions: sessions,
            sessionExercises: sessionExercises,
            setLogs: setLogs
        )
    }

    private var latestCompletedSession: WorkoutSession? {
        sessions.first { $0.status == .completed }
    }

    private var nextSchedule: ScheduledWorkout? {
        schedules.first {
            $0.plannedDate >= Date.now.startOfDay && $0.status == .planned
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "TRAINING WORKSPACE",
                    title: "训练"
                )

                progressCard

                SectionHeader(title: "训练记录", actionTitle: "查看全部")
                NavigationLink(destination: HistoryView()) {
                    historyEntryCard
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("训练记录入口")

                SectionHeader(title: "接下来训练计划", actionTitle: "编排日程")
                NavigationLink(destination: ScheduleView()) {
                    upcomingPlanCard
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("训练计划入口")

                SectionHeader(title: "快捷设置")
                quickSettings
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var progressCard: some View {
        let summary = progressSummary
        let weekSchedules = schedules.filter {
            summary.interval.contains($0.plannedDate) && $0.status != .skipped
        }
        let completedSchedules = weekSchedules.filter { $0.status == .completed }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周进度")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("完成记录与工作组的简要汇总")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            }

            HStack(spacing: 0) {
                progressMetric("\(summary.completedSessions)", label: "完成训练")
                progressMetric("\(summary.workingSets)", label: "工作组")
                progressMetric("\(Int(summary.volume).formatted())", label: "容量 kg")
            }

            if !weekSchedules.isEmpty {
                ProgressView(
                    value: Double(completedSchedules) / Double(weekSchedules.count)
                )
                .tint(AppTheme.accent)
                .accessibilityLabel("本周计划完成进度")
                Text("日程完成 \(completedSchedules)/\(weekSchedules.count) · 容量包含本周全部完成记录")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text("本周暂无训练计划，可在下方快速编排。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .cardSurface(padding: 16, cornerRadius: 19)
        .accessibilityIdentifier("训练页进度摘要")
    }

    private func progressMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyEntryCard: some View {
        Group {
            if let session = latestCompletedSession {
                let logs = setLogs.filter {
                    $0.sessionID == session.id && $0.isCompleted && !$0.isWarmup
                }
                let exerciseCount = sessionExercises.filter { $0.sessionID == session.id }.count

                entryCard(
                    icon: "clock.arrow.circlepath",
                    eyebrow: briefDate(session.startedAt),
                    title: session.templateName,
                    detail: "\(exerciseCount) 个动作 · \(logs.count) 个工作组 · \(Int(TrainingMetrics.volume(for: logs, sessionExercises: sessionExercises)).formatted()) kg",
                    empty: false
                )
            } else {
                entryCard(
                    icon: "clock.arrow.circlepath",
                    eyebrow: "最近训练",
                    title: "还没有完成的训练",
                    detail: "完成训练后会自动保存在这里",
                    empty: true
                )
            }
        }
    }

    private var upcomingPlanCard: some View {
        Group {
            if let schedule = nextSchedule {
                let items = templateExercises.filter { $0.templateID == schedule.templateID }
                let totalSets = items.reduce(0) { $0 + $1.targetSets }

                entryCard(
                    icon: "calendar.badge.clock",
                    eyebrow: briefDate(schedule.plannedDate),
                    title: schedule.templateName,
                    detail: "\(items.count) 个动作 · \(totalSets) 个工作组 · 点按调整日期或计划",
                    empty: false
                )
            } else {
                entryCard(
                    icon: "calendar.badge.plus",
                    eyebrow: "接下来",
                    title: "还没有后续计划",
                    detail: "点按进入日程并安排下一次训练",
                    empty: true
                )
            }
        }
    }

    private func entryCard(
        icon: String,
        eyebrow: String,
        title: String,
        detail: String,
        empty: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.bold())
                .foregroundStyle(empty ? AppTheme.secondaryText : AppTheme.accent)
                .frame(width: 48, height: 48)
                .background(
                    (empty ? AppTheme.elevatedSurface : AppTheme.accent.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption2.bold())
                    .foregroundStyle(empty ? AppTheme.secondaryText : AppTheme.accent)
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface(padding: 14, cornerRadius: 18)
    }

    private func briefDate(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日 \(WeekdayName.short(date.weekdayNumber))"
    }

    private var quickSettings: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            NavigationLink(destination: DailyWorkoutBuilderView()) {
                quickSettingCard(
                    icon: "wand.and.stars",
                    title: "今日编排",
                    detail: "按状态选动作"
                )
            }
            .accessibilityLabel("今日编排")
            .accessibilityIdentifier("今日编排入口")
            NavigationLink(destination: TrainingSetupView(initialMode: 1)) {
                quickSettingCard(
                    icon: "list.bullet.clipboard",
                    title: "每周模板",
                    detail: "自动生成日程"
                )
            }
            .accessibilityLabel("每周模板")
            .accessibilityIdentifier("每周模板入口")
            NavigationLink(destination: TrainingSetupView(initialMode: 2)) {
                quickSettingCard(
                    icon: "dumbbell.fill",
                    title: "动作库",
                    detail: "管理动作参数"
                )
            }
            .accessibilityLabel("动作库")
            .accessibilityIdentifier("动作库入口")
        }
        .buttonStyle(.plain)
    }

    private func quickSettingCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .cardSurface(padding: 12, cornerRadius: 16)
    }
}

private struct TrainingSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [WorkoutTemplate]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query private var schedules: [ScheduledWorkout]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var workoutSessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]

    @State private var showEditor = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var pendingDelete: WorkoutTemplate?
    @State private var selectedMode = 0
    @State private var selectedMajorMuscleGroup = "全部"
    @State private var selectedMinorMuscleGroup = "全部"
    @State private var searchText = ""
    @State private var showNewExerciseEditor = false
    @State private var editingExercise: Exercise?
    @State private var pendingDeleteExercise: Exercise?
    @State private var showArchivedExercises = false

    init(initialMode: Int = 0) {
        _selectedMode = State(initialValue: min(max(initialMode, 0), 2))
    }

    private var sortedTemplates: [WorkoutTemplate] {
        templates
            .filter { !$0.isOneOff }
            .sorted {
            let left = WeekdayName.orderedCalendarValues.firstIndex(of: $0.weekday) ?? 99
            let right = WeekdayName.orderedCalendarValues.firstIndex(of: $1.weekday) ?? 99
            return left == right ? $0.createdAt < $1.createdAt : left < right
        }
    }

    private var librarySourceExercises: [Exercise] {
        exercises.filter { showArchivedExercises ? $0.isArchived : !$0.isArchived }
    }

    private var libraryCategories: [ExerciseMuscleCategory] {
        librarySourceExercises.map {
            ExerciseMuscleTaxonomy.category(name: $0.name, muscleGroup: $0.muscleGroup)
        }
    }

    private var majorMuscleGroups: [String] {
        ["全部"] + ExerciseMuscleTaxonomy.orderedMajorGroups(in: libraryCategories)
    }

    private var minorMuscleGroups: [String] {
        guard selectedMajorMuscleGroup != "全部" else { return [] }
        return ["全部"] + ExerciseMuscleTaxonomy.orderedMinorGroups(
            for: selectedMajorMuscleGroup,
            in: libraryCategories
        )
    }

    private var filteredExercises: [Exercise] {
        let muscleMatches = librarySourceExercises
            .filter { exercise in
                let category = ExerciseMuscleTaxonomy.category(
                    name: exercise.name,
                    muscleGroup: exercise.muscleGroup
                )
                let matchesMajor = selectedMajorMuscleGroup == "全部"
                    || category.majorGroup == selectedMajorMuscleGroup
                let matchesMinor = selectedMinorMuscleGroup == "全部"
                    || category.minorGroup == selectedMinorMuscleGroup
                return matchesMajor && matchesMinor
            }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return muscleMatches.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return ExerciseCatalogService.search(muscleMatches, query: searchText)
    }

    private var setupTitle: String {
        switch selectedMode {
        case 1: return "每周模板"
        case 2: return "动作库"
        default: return "今日编排"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(
                eyebrow: "QUICK SETTINGS",
                title: setupTitle,
                trailingSystemImage: selectedMode == 0 ? nil : "plus",
                trailingAccessibilityLabel: selectedMode == 1 ? "新建每周模板" : "新建动作",
                trailingAction: {
                    if selectedMode == 1 {
                        editingTemplate = nil
                        showEditor = true
                    } else if selectedMode == 2 {
                        editingExercise = nil
                        showNewExerciseEditor = true
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            modePicker
                .padding(.horizontal, 16)

            if selectedMode == 1 {
                Text("设置一次，每周自动生成训练日程")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            if selectedMode == 0 {
                DailyWorkoutBuilderView(isEmbedded: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if selectedMode == 1 {
                            if let featured = sortedTemplates.first {
                                featuredWorkout(featured)
                            }
                            weekOverview

                            SectionHeader(title: "我的每周模板", actionTitle: "\(sortedTemplates.count) 个")
                            ForEach(sortedTemplates) { template in
                                templateCard(template)
                                    .contextMenu {
                                        Button {
                                            edit(template)
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            pendingDelete = template
                                        } label: {
                                            Label("删除计划", systemImage: "trash")
                                        }
                                    }
                            }
                        } else {
                            exerciseLibrary
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showEditor) {
            TemplateEditorView(template: editingTemplate)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(isPresented: $showNewExerciseEditor) {
            ExerciseEditorView()
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditorView(exercise: exercise)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .alert("删除这个训练计划？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    delete(pendingDelete)
                }
            }
        } message: {
            Text("历史训练不会被删除，尚未开始的未来安排会同步移除。")
        }
        .alert("删除这个动作？", isPresented: Binding(
            get: { pendingDeleteExercise != nil },
            set: { if !$0 { pendingDeleteExercise = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeleteExercise = nil }
            Button("删除", role: .destructive) {
                if let exercise = pendingDeleteExercise {
                    setArchived(exercise, archived: true)
                }
                pendingDeleteExercise = nil
            }
        } message: {
            Text("动作会从搜索和新计划中移除，但历史训练记录仍会完整保留；之后可在已删除动作中恢复。")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("今日编排", value: 0)
            modeButton("每周模板", value: 1)
            modeButton("动作库", value: 2)
        }
        .padding(4)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))
    }

    private func modeButton(_ title: String, value: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedMode = value
            }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(selectedMode == value ? .black : AppTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selectedMode == value ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func featuredWorkout(_ template: WorkoutTemplate) -> some View {
        let items = templateExercises.filter { $0.templateID == template.id }
        let totalSets = items.reduce(0) { $0 + $1.targetSets }

        return ZStack(alignment: .bottomLeading) {
            HeroWorkoutImage()
                .frame(height: 225)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.96)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED WORKOUT")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.accent)
                Text(template.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("\(items.count) 个动作 · \(totalSets) 个工作组 · 约 \(max(30, totalSets * 3)) 分钟")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))

                Button {
                    edit(template)
                } label: {
                    Label("查看训练计划", systemImage: "arrow.right")
                        .neonButtonStyle()
                }
            }
            .padding(17)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 1))
    }

    private var weekOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周训练")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("\(templates.filter(\.isActive).count) 个训练日")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 7) {
                ForEach(WeekdayName.orderedCalendarValues, id: \.self) { weekday in
                    let isTrainingDay = templates.contains { $0.weekday == weekday && $0.isActive }
                    VStack(spacing: 7) {
                        Text(WeekdayName.short(weekday).replacingOccurrences(of: "周", with: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Circle()
                            .fill(isTrainingDay ? AppTheme.accent : AppTheme.elevatedSurface)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if isTrainingDay {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.black)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cardSurface()
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        let items = templateExercises
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }

        return Button {
            edit(template)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Image(systemName: templateIcon(template))
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(WeekdayName.short(template.weekday))
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.accent)
                        Text(template.name)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Divider().overlay(AppTheme.line)

                ForEach(items.prefix(4)) { item in
                    HStack {
                        Text(exerciseName(item.exerciseID))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.targetSets) × \(item.minReps)–\(item.maxReps) · \(TrainingFormatters.weight(item.targetWeight))kg")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                if items.count > 4 {
                    Text("另有 \(items.count - 4) 个动作")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("搜索动作…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("exercise-library-search")
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                muscleFilterRow(
                    title: "大肌群",
                    groups: majorMuscleGroups,
                    selectedGroup: selectedMajorMuscleGroup,
                    accessibilityPrefix: "大肌群"
                ) { group in
                    selectedMajorMuscleGroup = group
                    selectedMinorMuscleGroup = "全部"
                }

                if selectedMajorMuscleGroup != "全部" {
                    muscleFilterRow(
                        title: "小肌群",
                        groups: minorMuscleGroups,
                        selectedGroup: selectedMinorMuscleGroup,
                        accessibilityPrefix: "小肌群"
                    ) { group in
                        selectedMinorMuscleGroup = group
                    }
                }
            }

            SectionHeader(title: "动作库", actionTitle: "\(filteredExercises.count) 个动作")

            Button {
                showArchivedExercises.toggle()
                selectedMajorMuscleGroup = "全部"
                selectedMinorMuscleGroup = "全部"
            } label: {
                Label(
                    showArchivedExercises ? "返回可用动作" : "查看已归档动作",
                    systemImage: showArchivedExercises ? "arrow.uturn.backward" : "archivebox"
                )
                .font(.caption.bold())
                .foregroundStyle(showArchivedExercises ? AppTheme.accent : AppTheme.secondaryText)
            }

            LazyVStack(spacing: 10) {
                ForEach(filteredExercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
    }

    private func muscleFilterRow(
        title: String,
        groups: [String],
        selectedGroup: String,
        accessibilityPrefix: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups, id: \.self) { group in
                        Button(group) {
                            onSelect(group)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(selectedGroup == group ? .black : AppTheme.secondaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(
                            selectedGroup == group ? AppTheme.accent : AppTheme.surface,
                            in: Capsule()
                        )
                        .accessibilityIdentifier("\(accessibilityPrefix)-\(group)")
                    }
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let latest = latestPerformance(for: exercise.id)

        return HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("exercise-name-\(exercise.name)")
                Text(latest?.dateText ?? "还没有训练记录")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            if let latest {
                Text("\(Int(latest.volume).formatted()) \(latest.unit)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
                Text(latest.feelingEmoji)
                    .font(.title3)
                    .accessibilityLabel(latest.feelingTitle)
            }
            Menu {
                if exercise.isArchived {
                    Button {
                        setArchived(exercise, archived: false)
                    } label: {
                        Label("恢复动作", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        editingExercise = exercise
                    } label: {
                        Label("编辑动作", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingDeleteExercise = exercise
                    } label: {
                        Label("删除动作", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("exercise-menu-\(exercise.name)")
            }
        }
        .cardSurface(padding: 12, cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !exercise.isArchived else { return }
            editingExercise = exercise
        }
    }

    private func latestPerformance(for exerciseID: UUID) -> (
        dateText: String,
        volume: Double,
        unit: String,
        feelingEmoji: String,
        feelingTitle: String
    )? {
        let completedSessions = workoutSessions
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        for session in completedSessions {
            guard let snapshot = sessionExercises.first(where: {
                $0.sessionID == session.id && $0.exerciseID == exerciseID
            }) else { continue }
            let logs = setLogs.filter {
                $0.sessionExerciseID == snapshot.id && $0.isCompleted && !$0.isWarmup
            }
            let volume = logs.reduce(0.0) {
                $0 + snapshot.volumeUnit.volume(weight: $1.actualWeight, reps: $1.actualReps)
            }
            return (
                dateText: "上次 \((session.completedAt ?? session.startedAt).formatted(.dateTime.month().day()))",
                volume: volume,
                unit: snapshot.volumeUnit.symbol,
                feelingEmoji: snapshot.feeling?.emoji ?? "➖",
                feelingTitle: snapshot.feeling?.title ?? "未记录感受"
            )
        }
        return nil
    }

    private func templateIcon(_ template: WorkoutTemplate) -> String {
        if template.name.contains("腿") { return "figure.strengthtraining.functional" }
        if template.name.contains("拉") { return "figure.rower" }
        return "dumbbell.fill"
    }

    private func exerciseName(_ id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "未知动作"
    }

    private func edit(_ template: WorkoutTemplate) {
        editingTemplate = template
        showEditor = true
    }

    private func setArchived(_ exercise: Exercise, archived: Bool) {
        exercise.isArchived = archived
        exercise.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            assertionFailure("更新动作归档状态失败：\(error)")
        }
    }

    private func delete(_ template: WorkoutTemplate) {
        templateExercises
            .filter { $0.templateID == template.id }
            .forEach(modelContext.delete)
        schedules
            .filter { $0.templateID == template.id && $0.status == .planned }
            .forEach(modelContext.delete)
        modelContext.delete(template)

        do {
            try modelContext.save()
        } catch {
            assertionFailure("删除训练计划失败：\(error)")
        }
        pendingDelete = nil
    }
}

private struct ExerciseDraft: Identifiable {
    let id: UUID
    var storedItemID: UUID?
    var exerciseID: UUID
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int
}

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query private var storedItems: [TemplateExercise]

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var weekday: Int
    @State private var isActive: Bool
    @State private var drafts: [ExerciseDraft] = []
    @State private var errorMessage: String?

    init(template: WorkoutTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "新训练计划")
        _weekday = State(initialValue: template?.weekday ?? Date.now.weekdayNumber)
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("计划名称", text: $name)
                    Picker("训练日", selection: $weekday) {
                        ForEach(WeekdayName.orderedCalendarValues, id: \.self) { day in
                            Text(WeekdayName.short(day)).tag(day)
                        }
                    }
                    Toggle("每周自动生成日程", isOn: $isActive)
                }

                Section {
                    if drafts.isEmpty {
                        Text("还没有动作，请从动作库添加。")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($drafts) { $draft in
                        DraftExerciseEditor(
                            draft: $draft,
                            exercise: exercises.first { $0.id == draft.exerciseID }
                        )
                    }
                    .onDelete { offsets in
                        drafts.remove(atOffsets: offsets)
                    }

                    Menu {
                        ForEach(availableExercises) { exercise in
                            Button(exercise.name) {
                                add(exercise)
                            }
                        }
                    } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                    }
                    .disabled(availableExercises.isEmpty)
                } header: {
                    Text("动作与目标")
                } footer: {
                    Text("重量和次数是下次开始训练时的默认值；历史记录会保留当时的独立快照。")
                }
            }
            .navigationTitle(template == nil ? "新建计划" : "编辑计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || drafts.isEmpty)
                }
            }
            .onAppear(perform: loadDrafts)
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var availableExercises: [Exercise] {
        exercises.filter { exercise in
            !exercise.isArchived && !drafts.contains { $0.exerciseID == exercise.id }
        }
    }

    private func loadDrafts() {
        guard drafts.isEmpty, let template else { return }
        drafts = storedItems
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }
            .map {
                ExerciseDraft(
                    id: UUID(),
                    storedItemID: $0.id,
                    exerciseID: $0.exerciseID,
                    targetSets: $0.targetSets,
                    minReps: $0.minReps,
                    maxReps: $0.maxReps,
                    targetWeight: $0.targetWeight,
                    restSeconds: $0.restSeconds
                )
            }
    }

    private func add(_ exercise: Exercise) {
        drafts.append(
            ExerciseDraft(
                id: UUID(),
                storedItemID: nil,
                exerciseID: exercise.id,
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                targetWeight: 10,
                restSeconds: exercise.defaultRestSeconds
            )
        )
    }

    private func save() {
        let savedTemplate: WorkoutTemplate
        if let template {
            savedTemplate = template
            template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.weekday = weekday
            template.isActive = isActive
        } else {
            let newTemplate = WorkoutTemplate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                weekday: weekday,
                isActive: isActive
            )
            modelContext.insert(newTemplate)
            savedTemplate = newTemplate
        }

        let existing = storedItems.filter { $0.templateID == savedTemplate.id }
        let keptIDs = Set(drafts.compactMap(\.storedItemID))
        existing.filter { !keptIDs.contains($0.id) }.forEach(modelContext.delete)

        for (index, draft) in drafts.enumerated() {
            if let storedID = draft.storedItemID,
               let item = existing.first(where: { $0.id == storedID }) {
                apply(draft, order: index, to: item)
            } else {
                modelContext.insert(
                    TemplateExercise(
                        templateID: savedTemplate.id,
                        exerciseID: draft.exerciseID,
                        order: index,
                        targetSets: draft.targetSets,
                        minReps: draft.minReps,
                        maxReps: draft.maxReps,
                        targetWeight: draft.targetWeight,
                        restSeconds: draft.restSeconds
                    )
                )
            }
        }

        do {
            try ScheduleService.refreshUpcoming(in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ draft: ExerciseDraft, order: Int, to item: TemplateExercise) {
        item.exerciseID = draft.exerciseID
        item.order = order
        item.targetSets = draft.targetSets
        item.minReps = draft.minReps
        item.maxReps = max(draft.minReps, draft.maxReps)
        item.targetWeight = max(0, draft.targetWeight)
        item.restSeconds = draft.restSeconds
    }
}

private struct LegacyExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]

    let exercise: Exercise?

    @State private var name: String
    @State private var muscleGroup: String
    @State private var equipment: String
    @State private var restSeconds: Int
    @State private var notes: String
    @State private var errorMessage: String?

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? "胸部")
        _equipment = State(initialValue: exercise?.equipment ?? "哑铃")
        _restSeconds = State(initialValue: exercise?.defaultRestSeconds ?? 90)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("动作信息") {
                    TextField("动作名称", text: $name)
                    TextField("目标肌群", text: $muscleGroup)
                    TextField("器械", text: $equipment)
                    Picker("默认休息", selection: $restSeconds) {
                        ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                            Text("\(seconds) 秒").tag(seconds)
                        }
                    }
                }

                Section("备注") {
                    TextField("动作要点、器械位置等", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(exercise == nil ? "新建动作" : "编辑动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty || trimmedMuscleGroup.isEmpty || trimmedEquipment.isEmpty)
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
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMuscleGroup: String {
        muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEquipment: String {
        equipment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let editingID = exercise?.id
        let duplicate = allExercises.contains {
            $0.id != editingID
                && !$0.isArchived
                && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        guard !duplicate else {
            errorMessage = "动作库中已经存在同名动作。"
            return
        }

        if let exercise {
            exercise.name = trimmedName
            exercise.muscleGroup = trimmedMuscleGroup
            exercise.equipment = trimmedEquipment
            exercise.defaultRestSeconds = restSeconds
            exercise.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            exercise.updatedAt = .now
        } else {
            modelContext.insert(
                Exercise(
                    name: trimmedName,
                    muscleGroup: trimmedMuscleGroup,
                    equipment: trimmedEquipment,
                    defaultRestSeconds: restSeconds,
                    isBuiltIn: false,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DraftExerciseEditor: View {
    @Binding var draft: ExerciseDraft
    let exercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? "未知动作")
                        .font(.headline)
                    Text(
                        "\(exercise?.muscleGroup ?? "") · \(exercise?.equipment ?? "") · \(exercise?.volumeUnit.symbol ?? "kg")"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }

            Stepper("工作组：\(draft.targetSets)", value: $draft.targetSets, in: 1...10)

            HStack {
                Text(exercise?.volumeUnit == .count ? "数量（个）" : exercise?.volumeUnit.repetitionTitle ?? "次数")
                Spacer()
                TextField("最低", value: $draft.minReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("–")
                TextField("最高", value: $draft.maxReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
            }

            if exercise?.volumeUnit.recordsNumericLoad == true {
                HStack {
                    Text("目标\(exercise?.volumeUnit.inputTitle ?? "重量")")
                    Spacer()
                    TextField(
                        exercise?.volumeUnit.symbol ?? "kg",
                        value: $draft.targetWeight,
                        format: .number.precision(.fractionLength(0...3))
                    )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(exercise?.volumeUnit.symbol ?? "kg")
                        .foregroundStyle(.secondary)
                }
            } else if exercise?.volumeUnit == .bodyweight {
                HStack {
                    Text("目标负重")
                    Spacer()
                    Text("自重")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Picker("组间休息", selection: $draft.restSeconds) {
                ForEach([45, 60, 90, 120, 150, 180], id: \.self) { seconds in
                    Text("\(seconds) 秒").tag(seconds)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

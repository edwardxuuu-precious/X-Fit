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
            LazyVStack(alignment: .leading, spacing: 22) {
                NavigationLink(destination: ScheduleView()) {
                    upcomingPlanCard
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("训练计划入口")

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "计划与动作")
                    quickSettings
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "最近训练", actionTitle: "查看全部")
                    NavigationLink(destination: HistoryView()) {
                        historyEntryCard
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("训练记录入口")
                }

                DisclosureGroup("本周进度") {
                    progressCard
                        .padding(.top, 12)
                }
                .font(.subheadline)
                .tint(AppTheme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .screenBackground()
        .navigationTitle("训练管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
                    .frame(width: 44, height: 44)
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
                Text("本周暂无训练计划，可从“今日编排”安排训练。")
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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("下一次训练", systemImage: "calendar")
                    .font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent)
                Spacer()
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            if let schedule = nextSchedule {
                let items = templateExercises.filter { $0.templateID == schedule.templateID }
                let totalSets = items.reduce(0) { $0 + $1.targetSets }
                VStack(alignment: .leading, spacing: 7) {
                    Text(schedule.templateName)
                        .font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(briefDate(schedule.plannedDate))
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                HStack {
                    Text("\(items.count) 个动作 · \(totalSets) 个工作组")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 8)
                    Text("查看日程").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("安排下一次训练").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text("选择日期，放入你的训练计划")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                Text("打开日程").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
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
        VStack(spacing: 0) {
            NavigationLink(destination: DailyWorkoutBuilderView()) {
                quickSettingCard(
                    icon: "wand.and.stars",
                    title: "今日编排",
                    detail: "按状态选动作"
                )
            }
            .accessibilityLabel("今日编排")
            .accessibilityIdentifier("今日编排入口")
            Divider().overlay(AppTheme.line).padding(.leading, 54)
            NavigationLink(destination: TrainingSetupView(initialMode: 1)) {
                quickSettingCard(
                    icon: "list.bullet.clipboard",
                    title: "专项模板",
                    detail: "默认方案可编辑"
                )
            }
            .accessibilityLabel("专项模板")
            .accessibilityIdentifier("专项模板入口")
            Divider().overlay(AppTheme.line).padding(.leading, 54)
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
        .cardSurface(padding: 0)
        .buttonStyle(.plain)
    }

    private func quickSettingCard(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline).foregroundStyle(AppTheme.secondaryText).frame(width: 22)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint(detail)
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

    @State private var showNewTemplateEditor = false
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
            .sorted { $0.createdAt == $1.createdAt ? $0.name < $1.name : $0.createdAt < $1.createdAt }
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
            return muscleMatches.sorted { lhs, rhs in
                let lhsKey = ExerciseCatalogService.pinyinSortKey(for: lhs.name)
                let rhsKey = ExerciseCatalogService.pinyinSortKey(for: rhs.name)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        return ExerciseCatalogService.search(muscleMatches, query: searchText)
    }

    private var groupedFilteredExercises: [(id: String, equipment: String, muscleGroup: String, items: [Exercise])] {
        Dictionary(grouping: filteredExercises) { exercise in
            let equipment = exercise.equipment.isEmpty ? "未分类器械" : exercise.equipment
            let muscleGroup = exercise.muscleGroup.isEmpty ? "未分类肌群" : exercise.muscleGroup
            return "\(equipment)␟\(muscleGroup)"
        }
        .map { key, items in
            let parts = key.split(separator: "␟", omittingEmptySubsequences: false)
            return (
                id: key,
                equipment: parts.first.map(String.init) ?? "未分类器械",
                muscleGroup: parts.dropFirst().first.map(String.init) ?? "未分类肌群",
                items: items
            )
        }
        .sorted { lhs, rhs in
            let lhsEquipment = ExerciseCatalogService.pinyinSortKey(for: lhs.equipment)
            let rhsEquipment = ExerciseCatalogService.pinyinSortKey(for: rhs.equipment)
            if lhsEquipment != rhsEquipment { return lhsEquipment < rhsEquipment }
            let lhsMuscle = ExerciseCatalogService.pinyinSortKey(for: lhs.muscleGroup)
            let rhsMuscle = ExerciseCatalogService.pinyinSortKey(for: rhs.muscleGroup)
            if lhsMuscle != rhsMuscle { return lhsMuscle < rhsMuscle }
            return lhs.id < rhs.id
        }
    }

    private var setupTitle: String {
        switch selectedMode {
        case 1: return "专项模板"
        case 2: return "动作库"
        default: return "今日编排"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            modePicker
                .padding(.horizontal, 20)

            if selectedMode == 1 {
                Text("模板由你手动安排，不会自动生成日程")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            if selectedMode == 0 {
                DailyWorkoutBuilderView(isEmbedded: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if selectedMode == 1 {
                            SectionHeader(title: "我的专项模板", actionTitle: "\(sortedTemplates.count) 个")
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            }
        }
        .screenBackground()
        .navigationTitle(setupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if selectedMode != 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedMode == 1 { showNewTemplateEditor = true }
                        else { editingExercise = nil; showNewExerciseEditor = true }
                    } label: {
                        Label(selectedMode == 1 ? "新建专项模板" : "新建动作", systemImage: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewTemplateEditor) {
            TemplateEditorView(
                template: nil,
                storedItems: templateExercises
            )
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(
                template: template,
                storedItems: templateExercises
            )
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
            modeButton("专项模板", value: 1)
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
                .frame(minHeight: 44)
                .background(selectedMode == value ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
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
            HStack(spacing: 14) {
                Image(systemName: templateIcon(template))
                    .font(.title3).foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.headline).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(items.count) 个动作 · \(items.reduce(0) { $0 + $1.targetSets }) 个工作组")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16, cornerRadius: 12)
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
                ForEach(groupedFilteredExercises, id: \.id) { group in
                    SectionHeader(
                        title: "\(group.equipment) · \(group.muscleGroup)",
                        actionTitle: "\(group.items.count) 个"
                    )
                    ForEach(group.items) { exercise in
                        exerciseRow(exercise)
                    }
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
    var plannedSets: [WorkoutSetPlan]
    var restSeconds: Int
}

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var selectedMuscleGroups: Set<String>
    @State private var storedItems: [TemplateExercise]
    @State private var drafts: [ExerciseDraft]
    @State private var isLoadingStoredItems: Bool
    @State private var errorMessage: String?

    init(template: WorkoutTemplate?, storedItems: [TemplateExercise]) {
        self.template = template
        _name = State(initialValue: template?.name ?? "新训练计划")
        _selectedMuscleGroups = State(initialValue: Set(template?.focusMuscleGroups ?? []))
        let initialItems = template.map { template in
            storedItems
                .filter { $0.templateID == template.id }
                .sorted { $0.order < $1.order }
        } ?? []
        _storedItems = State(initialValue: initialItems)
        _drafts = State(initialValue: Self.makeDrafts(from: initialItems))
        _isLoadingStoredItems = State(initialValue: template != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("计划名称", text: $name)
                    Menu {
                        ForEach(availableMuscleGroups, id: \.self) { muscleGroup in
                            Button {
                                toggleMuscleGroup(muscleGroup)
                            } label: {
                                Label(
                                    muscleGroup,
                                    systemImage: selectedMuscleGroups.contains(muscleGroup) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        LabeledContent("目标肌群") {
                            Text(selectedMuscleGroups.isEmpty ? "未选择" : sortedSelectedMuscleGroups.joined(separator: "、"))
                                .lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("专项模板目标肌群")
                }

                Section {
                    if isLoadingStoredItems && drafts.isEmpty {
                        ProgressView("正在加载动作…")
                    } else if drafts.isEmpty {
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
                    .onMove { source, destination in
                        drafts.move(fromOffsets: source, toOffset: destination)
                    }

                    Menu {
                        ForEach(groupedAvailableExercises, id: \.id) { group in
                            Section("\(group.equipment) · \(group.muscleGroup)") {
                                ForEach(group.items) { exercise in
                                    Button(exercise.name) {
                                        add(exercise)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                    }
                    .disabled(availableExercises.isEmpty)
                } header: {
                    Text("动作与目标")
                } footer: {
                    Text("完成专项训练后，已有动作会沿用本次完成的工作组、次数与重量；历史记录仍保留当时的独立快照。")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { KeyboardDismissal.dismiss() }
                }
            }
            .navigationTitle(template == nil ? "新建专项模板" : "编辑专项模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    EditButton()
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || drafts.isEmpty)
                }
            }
            .task(id: template?.id) {
                loadStoredItems()
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

    private static func makeDrafts(from items: [TemplateExercise]) -> [ExerciseDraft] {
        items.map {
            ExerciseDraft(
                id: UUID(),
                storedItemID: $0.id,
                exerciseID: $0.exerciseID,
                plannedSets: $0.plannedSets,
                restSeconds: $0.restSeconds
            )
        }
    }

    private func loadStoredItems() {
        guard let template else {
            isLoadingStoredItems = false
            return
        }

        let templateID = template.id
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { $0.templateID == templateID },
            sortBy: [SortDescriptor(\.order)]
        )
        do {
            let fetchedItems = try modelContext.fetch(descriptor)
            storedItems = fetchedItems
            drafts = Self.makeDrafts(from: fetchedItems)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingStoredItems = false
    }

    private var availableExercises: [Exercise] {
        exercises
            .filter { exercise in
                !exercise.isArchived && !drafts.contains { $0.exerciseID == exercise.id }
            }
            .sorted { lhs, rhs in
                let lhsKey = ExerciseCatalogService.pinyinSortKey(for: lhs.name)
                let rhsKey = ExerciseCatalogService.pinyinSortKey(for: rhs.name)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var availableMuscleGroups: [String] {
        let groups = Set(exercises.filter { !$0.isArchived }.map(\.muscleGroup).filter { !$0.isEmpty })
            .union(selectedMuscleGroups)
        let preferred = ["胸部", "背部", "肩部", "手臂", "腿部", "臀部", "小腿", "核心"]
        let ordered = preferred.filter(groups.contains)
        let remaining = groups.subtracting(ordered).sorted {
            ExerciseCatalogService.pinyinSortKey(for: $0) < ExerciseCatalogService.pinyinSortKey(for: $1)
        }
        return ordered + remaining
    }

    private var sortedSelectedMuscleGroups: [String] {
        availableMuscleGroups.filter(selectedMuscleGroups.contains)
    }

    private func toggleMuscleGroup(_ muscleGroup: String) {
        if selectedMuscleGroups.contains(muscleGroup) {
            selectedMuscleGroups.remove(muscleGroup)
        } else {
            selectedMuscleGroups.insert(muscleGroup)
        }
    }

    private var groupedAvailableExercises: [(id: String, equipment: String, muscleGroup: String, items: [Exercise])] {
        Dictionary(grouping: availableExercises) { exercise in
            let equipment = exercise.equipment.isEmpty ? "未分类器械" : exercise.equipment
            let muscleGroup = exercise.muscleGroup.isEmpty ? "未分类肌群" : exercise.muscleGroup
            return "\(equipment)␟\(muscleGroup)"
        }
        .map { key, items in
            let parts = key.split(separator: "␟", omittingEmptySubsequences: false)
            return (
                id: key,
                equipment: parts.first.map(String.init) ?? "未分类器械",
                muscleGroup: parts.dropFirst().first.map(String.init) ?? "未分类肌群",
                items: items
            )
        }
        .sorted { lhs, rhs in
            let lhsEquipment = ExerciseCatalogService.pinyinSortKey(for: lhs.equipment)
            let rhsEquipment = ExerciseCatalogService.pinyinSortKey(for: rhs.equipment)
            if lhsEquipment != rhsEquipment { return lhsEquipment < rhsEquipment }
            let lhsMuscle = ExerciseCatalogService.pinyinSortKey(for: lhs.muscleGroup)
            let rhsMuscle = ExerciseCatalogService.pinyinSortKey(for: rhs.muscleGroup)
            if lhsMuscle != rhsMuscle { return lhsMuscle < rhsMuscle }
            return lhs.id < rhs.id
        }
    }

    private func add(_ exercise: Exercise) {
        drafts.append(
            ExerciseDraft(
                id: UUID(),
                storedItemID: nil,
                exerciseID: exercise.id,
                plannedSets: WorkoutSetPlan.preset(
                    .fixed,
                    count: 3,
                    baseWeight: exercise.volumeUnit.recordsNumericLoad ? 10 : 0,
                    baseReps: 8
                ),
                restSeconds: exercise.defaultRestSeconds
            )
        )
    }

    private func save() {
        let savedTemplate: WorkoutTemplate
        if let template {
            savedTemplate = template
            template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.isActive = false
            template.focusMuscleGroups = sortedSelectedMuscleGroups
        } else {
            let newTemplate = WorkoutTemplate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                weekday: Date.now.weekdayNumber,
                isActive: false,
                focusMuscleGroups: sortedSelectedMuscleGroups
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
                        targetSets: draft.plannedSets.count,
                        minReps: draft.plannedSets.map(\.reps).min() ?? 1,
                        maxReps: draft.plannedSets.map(\.reps).max() ?? 1,
                        targetWeight: draft.plannedSets.first?.weight ?? 0,
                        restSeconds: draft.restSeconds,
                        plannedSets: draft.plannedSets
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
        item.plannedSets = draft.plannedSets
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
            .scrollContentBackground(.hidden)
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
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

            Stepper("工作组：\(draft.plannedSets.count)", value: setCountBinding, in: 1...12)

            ForEach(draft.plannedSets.indices, id: \.self) { index in
                setRow(index)
            }

            Picker("组间休息", selection: $draft.restSeconds) {
                ForEach([45, 60, 90, 120, 150, 180], id: \.self) { seconds in
                    Text("\(seconds) 秒").tag(seconds)
                }
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func setRow(_ index: Int) -> some View {
        let plan = Binding<WorkoutSetPlan> {
            draft.plannedSets[index]
        } set: { draft.plannedSets[index] = $0 }

        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 20)

            if exercise?.volumeUnit.recordsNumericLoad == true {
                TextField(
                    exercise?.volumeUnit.symbol ?? "kg",
                    value: plan.weight,
                    format: .number.precision(.fractionLength(0...3))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            } else if exercise?.volumeUnit == .bodyweight {
                Text("自重")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
            }

            TextField(
                exercise?.volumeUnit.recordsSingleAmount == true
                    ? exercise?.volumeUnit.inputTitle ?? "数量"
                    : exercise?.volumeUnit.repetitionTitle ?? "次数",
                value: plan.reps,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
        }
    }

    private var setCountBinding: Binding<Int> {
        Binding {
            draft.plannedSets.count
        } set: { requested in
            let count = min(max(1, requested), 12)
            if count > draft.plannedSets.count {
                let seed = draft.plannedSets.last ?? WorkoutSetPlan(weight: 0, reps: 8)
                for _ in draft.plannedSets.count..<count {
                    draft.plannedSets.append(
                        WorkoutSetPlan(
                            weight: seed.weight,
                            reps: seed.reps,
                            weightSide: seed.weightSide,
                            repsSide: seed.repsSide
                        )
                    )
                }
            } else if count < draft.plannedSets.count {
                draft.plannedSets.removeLast(draft.plannedSets.count - count)
            }
        }
    }
}

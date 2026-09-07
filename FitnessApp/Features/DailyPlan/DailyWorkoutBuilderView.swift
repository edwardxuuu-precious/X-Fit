import SwiftData
import SwiftUI

private typealias DailyExerciseTarget = DailyPlanPatternTarget

private enum DailyPlanningStage: Int {
    case muscles = 1
    case exercises = 2
    case review = 3
}

private enum DailyBuilderMode: Equatable {
    case draft
    case planned
    case active
}

struct DailyWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var templates: [WorkoutTemplate]
    @Query private var schedules: [ScheduledWorkout]

    @AppStorage(TrainingGoalMode.storageKey)
    private var trainingGoalRaw = TrainingGoalMode.cuttingVolume.rawValue

    let isEmbedded: Bool

    @State private var selectedDate = Date.now.startOfDay
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var selectedExerciseIDs: [UUID] = []
    @State private var targets: [UUID: DailyExerciseTarget] = [:]
    @State private var recommendationVariant = 0
    @State private var replaceExistingPlans = true
    @State private var loadedDate: Date?
    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var draggingExerciseID: UUID?
    @State private var showExercisePicker = false
    @State private var hasPersistedPlan = false
    @State private var isEditingPlan = false
    @State private var planningStage = DailyPlanningStage.muscles
    @State private var expandedExerciseID: UUID?
    @State private var editingExerciseID: UUID?
    @State private var replacingExerciseID: UUID?
    @State private var dayPlanPattern = SetPlanPattern.fixed
    @State private var savedMessage: String?
    @State private var errorMessage: String?
    private let initialScheduleID: UUID?

    init(
        initialDate: Date = .now,
        initialScheduleID: UUID? = nil,
        isEmbedded: Bool = false
    ) {
        self.isEmbedded = isEmbedded
        self.initialScheduleID = initialScheduleID
        _selectedDate = State(initialValue: initialDate.startOfDay)
    }

    @ViewBuilder
    private var draftPlanningContent: some View {
        planningIntroCard

        planningStepHeader(
            number: 1,
            title: "训练部位",
            summary: selectedMuscleGroups.isEmpty ? "先确定今天练哪里" : selectedMuscleGroups.sorted().joined(separator: "、"),
            stage: .muscles
        )
        if planningStage == .muscles {
            DisclosureGroup {
                trainingGoalCard
                    .padding(.top, 10)
            } label: {
                Label("编排偏好 · \(trainingGoalMode.title)", systemImage: "slider.horizontal.3")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .cardSurface()

            muscleGroupPicker
            if !advice.isEmpty {
                ForEach(advice) { item in
                    adviceCard(item)
                }
            }
        }

        if planningStage.rawValue >= DailyPlanningStage.exercises.rawValue {
            planningStepHeader(
                number: 2,
                title: "动作清单",
                summary: selectedExerciseIDs.isEmpty ? "选择今天要完成的动作" : "\(selectedExerciseIDs.count) 个动作 · \(totalPlannedSets) 组",
                stage: .exercises
            )
            if planningStage == .exercises {
                menuBuilderHeader
                ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
                    if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                        exerciseSummaryCard(exercise)
                    }
                }

                if !recommendations.isEmpty {
                    HStack {
                        SectionHeader(title: "推荐动作", actionTitle: "\(recommendations.count) 个可选")
                        Spacer()
                        Button("换一组") { recommendationVariant += 1 }
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.accent)
                    }
                    ForEach(groupedRecommendations, id: \.id) { group in
                        SectionHeader(
                            title: "\(group.equipment) · \(group.muscleGroup)",
                            actionTitle: "\(group.items.count) 个动作"
                        )
                        ForEach(group.items) { recommendation in
                            recommendationCard(recommendation)
                        }
                    }
                } else {
                    emptyMenuCard
                }
            }
        }

        if planningStage == .review {
            planningStepHeader(
                number: 3,
                title: "确认今日计划",
                summary: "\(selectedExerciseIDs.count) 个动作 · \(totalPlannedSets) 组",
                stage: .review
            )
            planSummaryCard
            ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
                if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                    exerciseSummaryCard(exercise)
                }
            }
        }
    }

    @ViewBuilder
    private func plannedOverviewContent(isActive: Bool) -> some View {
        planSummaryCard

        HStack {
            SectionHeader(title: "动作清单", actionTitle: "\(selectedExerciseIDs.count) 个动作")
            Spacer()
            if isEditingPlan {
                Button {
                    replacingExerciseID = nil
                    showExercisePicker = true
                } label: {
                    Label("添加动作", systemImage: "plus")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
                .accessibilityIdentifier("当天菜单添加动作")
            }
        }

        ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
            if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                exerciseSummaryCard(exercise)
            }
        }

        if isActive {
            Text("零完成组的动作可以删除；已有完成组的动作和记录保持不变。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        } else if !isEditingPlan {
            Text("先确认今天练什么；需要时再展开动作或进入调整。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func planningStepHeader(
        number: Int,
        title: String,
        summary: String,
        stage: DailyPlanningStage
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { planningStage = stage }
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(planningStage == stage ? .black : AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(planningStage == stage ? AppTheme.accent : AppTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: planningStage == stage ? "chevron.down" : "chevron.right")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("编排步骤-\(number)")
    }

    private var planSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(builderMode == .active ? "正在进行" : "今日计划摘要")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Text(selectedMuscleGroups.isEmpty ? "当天训练" : selectedMuscleGroups.sorted().joined(separator: " + "))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: builderMode == .active ? "bolt.fill" : "checklist")
                    .foregroundStyle(AppTheme.accent)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    summaryPill("\(selectedExerciseIDs.count) 个动作")
                    summaryPill("\(totalPlannedSets) 组")
                }
                summaryPill("\(selectedExerciseIDs.count) 个动作 · \(totalPlannedSets) 组")
            }
        }
        .cardSurface()
        .accessibilityIdentifier("今日计划摘要")
    }

    private func summaryPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.elevatedSurface, in: Capsule())
    }

    private func exerciseSummaryCard(_ exercise: Exercise) -> some View {
        let index = selectedExerciseIDs.firstIndex(of: exercise.id) ?? 0
        let isExpanded = expandedExerciseID == exercise.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedExerciseID = isExpanded ? nil : exercise.id
                    }
                } label: {
                    HStack(spacing: 11) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.accent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            Text(exercisePlanSummary(exercise))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("展开动作-\(exercise.name)")

                exerciseReorderHandle(exercise)
                exerciseActionMenu(exercise, index: index)
            }
            .padding(14)

            if isExpanded {
                Divider().overlay(AppTheme.line)
                exerciseReadOnlyDetails(exercise)
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
        .accessibilityAction(named: "上移") { moveExercise(exercise.id, offset: -1) }
        .accessibilityAction(named: "下移") { moveExercise(exercise.id, offset: 1) }
        .opacity(draggingExerciseID == exercise.id ? 0.72 : 1)
    }

    private func exerciseReorderHandle(_ exercise: Exercise) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.secondaryText)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("\(exercise.name)排序把手")
            .accessibilityIdentifier("排序把手-\(exercise.name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "上移") { moveExercise(exercise.id, offset: -1) }
            .accessibilityAction(named: "下移") { moveExercise(exercise.id, offset: 1) }
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 4))
                    .onChanged { value in
                        if case .second(true, _) = value { draggingExerciseID = exercise.id }
                    }
                    .onEnded { value in
                        if case let .second(true, drag?) = value {
                            reorderExercise(exercise.id, verticalTranslation: drag.translation.height)
                        }
                        draggingExerciseID = nil
                    }
            )
    }

    private func exerciseActionMenu(_ exercise: Exercise, index: Int) -> some View {
        Menu {
            Button {
                editExercisePlan(exercise.id)
            } label: {
                Label("单独调整", systemImage: "slider.horizontal.3")
            }
            Button {
                if builderMode != .draft { isEditingPlan = true }
                replacingExerciseID = exercise.id
                showExercisePicker = true
            } label: {
                Label("替换动作", systemImage: "arrow.triangle.2.circlepath")
            }
            Button { moveExercise(exercise.id, offset: -1) } label: {
                Label("上移", systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button { moveExercise(exercise.id, offset: 1) } label: {
                Label("下移", systemImage: "arrow.down")
            }
            .disabled(index == selectedExerciseIDs.count - 1)
            Button {
                withAnimation { expandedExerciseID = exercise.id }
            } label: {
                Label("查看动作资料", systemImage: "info.circle")
            }
            Button(role: .destructive) { removeExercise(exercise.id) } label: {
                Label("删除动作", systemImage: "trash")
            }
            .disabled(!canRemoveExerciseFromCurrentMenu(exercise.id))
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.bold())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(exercise.name)更多操作")
        .accessibilityIdentifier("动作菜单-\(exercise.name)")
    }

    private func exerciseReadOnlyDetails(_ exercise: Exercise) -> some View {
        let target = targets[exercise.id]
        return VStack(alignment: .leading, spacing: 10) {
            Text("逐组详情")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("动作详情-\(exercise.name)")
            ForEach(Array((target?.plannedSets ?? []).enumerated()), id: \.element.id) { index, plan in
                HStack {
                    Text("第 \(index + 1) 组")
                        .font(.caption.bold())
                    Spacer()
                    Text(readOnlySetSummary(plan, unit: exercise.volumeUnit))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            HStack {
                Text("组间休息")
                Spacer()
                Text("\(target?.restSeconds ?? exercise.defaultRestSeconds) 秒")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .font(.caption)

            HStack {
                Text("记录口径")
                Spacer()
                Text(recordingBasis(for: exercise, target: target))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .font(.caption)

            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if let url = URL(string: exercise.referenceURL), !exercise.referenceURL.isEmpty {
                Link("打开动作资料", destination: url)
                    .font(.caption.bold())
            } else {
                Text("动作资料：暂无外部链接")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        VStack(spacing: 9) {
            switch builderMode {
            case .draft:
                if planningStage == .muscles {
                    primaryBottomButton("选好部位，继续", icon: "arrow.right") {
                        withAnimation { planningStage = .exercises }
                    }
                    .disabled(selectedMuscleGroups.isEmpty)
                    .opacity(selectedMuscleGroups.isEmpty ? 0.45 : 1)
                } else if planningStage == .exercises {
                    primaryBottomButton("选好动作，继续", icon: "arrow.right") {
                        withAnimation { planningStage = .review }
                    }
                    .disabled(selectedExerciseIDs.isEmpty)
                    .opacity(selectedExerciseIDs.isEmpty ? 0.45 : 1)
                } else {
                    primaryBottomButton("保存并开始记录", icon: "play.fill") {
                        savePlan(startAfterSaving: true)
                    }
                    Button("保存计划，稍后记录") { savePlan(startAfterSaving: false) }
                        .font(.subheadline.bold())
                    .frame(minHeight: 44)
                }
            case .planned:
                if isEditingPlan {
                    if planningStage == .muscles {
                        primaryBottomButton("选好部位，继续", icon: "arrow.right") {
                            withAnimation { planningStage = .exercises }
                        }
                        .disabled(selectedMuscleGroups.isEmpty)
                        .opacity(selectedMuscleGroups.isEmpty ? 0.45 : 1)
                    } else if planningStage == .exercises {
                        primaryBottomButton("选好动作，继续", icon: "arrow.right") {
                            withAnimation { planningStage = .review }
                        }
                        .disabled(selectedExerciseIDs.isEmpty)
                        .opacity(selectedExerciseIDs.isEmpty ? 0.45 : 1)
                    } else {
                        primaryBottomButton("保存今日计划", icon: "checkmark.circle.fill") {
                            savePlan(startAfterSaving: false)
                        }
                    }
                    Button("取消重新编排") {
                        isEditingPlan = false
                        loadExistingPlan(for: selectedDate, force: true)
                    }
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
                } else {
                    primaryBottomButton("开始训练", icon: "play.fill") {
                        savePlan(startAfterSaving: true)
                    }
                    Button("重新编排") {
                        isEditingPlan = true
                        planningStage = .muscles
                        expandedExerciseID = nil
                    }
                        .font(.subheadline.bold())
                    .frame(minHeight: 44)
                        .accessibilityIdentifier("调整计划")
                }
            case .active:
                if isEditingPlan {
                    if planningStage == .muscles {
                        primaryBottomButton("选好部位，继续", icon: "arrow.right") {
                            withAnimation { planningStage = .exercises }
                        }
                        .disabled(selectedMuscleGroups.isEmpty)
                        .opacity(selectedMuscleGroups.isEmpty ? 0.45 : 1)
                    } else if planningStage == .exercises {
                        primaryBottomButton("选好动作，继续", icon: "arrow.right") {
                            withAnimation { planningStage = .review }
                        }
                        .disabled(selectedExerciseIDs.isEmpty)
                        .opacity(selectedExerciseIDs.isEmpty ? 0.45 : 1)
                    } else {
                        primaryBottomButton("保存当前训练", icon: "checkmark.circle.fill") {
                            if syncActiveWorkoutMenu(showConfirmation: true) {
                                isEditingPlan = false
                            }
                        }
                    }
                    Button("取消重新编排") {
                        isEditingPlan = false
                        loadExistingPlan(for: selectedDate, force: true)
                    }
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
                } else {
                    primaryBottomButton("继续训练", icon: "play.fill") {
                        if let activeSessionForSelectedDate {
                            workoutSessionID = activeSessionForSelectedDate.id
                            showWorkout = true
                        }
                    }
                    Button("重新编排") {
                        isEditingPlan = true
                        planningStage = .muscles
                        expandedExerciseID = nil
                    }
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("重新编排")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.background)
    }

    private func primaryBottomButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .neonButtonStyle()
        }
        .accessibilityIdentifier(title)
    }

    private var muscleGroups: [String] {
        let groups = Set(exercises.filter { !$0.isArchived }.map(\.muscleGroup))
        let preferred = ["胸部", "背部", "肩部", "手臂", "腿部", "臀部", "小腿", "核心"]
        let ordered = preferred.filter(groups.contains)
        return ordered + groups.subtracting(ordered).sorted()
    }

    private var recommendations: [ExerciseRecommendation] {
        WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: selectedMuscleGroups,
            exercises: exercises,
            sessions: sessions,
            sessionExercises: sessionExercises,
            setLogs: setLogs,
            templateExercises: templateExercises,
            variant: recommendationVariant,
            goalMode: trainingGoalMode
        )
    }

    private var groupedRecommendations: [(id: String, equipment: String, muscleGroup: String, items: [ExerciseRecommendation])] {
        Dictionary(grouping: recommendations) { recommendation in
            let equipment = recommendation.equipment.isEmpty ? "未分类器械" : recommendation.equipment
            let muscleGroup = recommendation.muscleGroup.isEmpty ? "未分类肌群" : recommendation.muscleGroup
            return "\(equipment)␟\(muscleGroup)"
        }
            .map { entry in
                let items = entry.value.sorted { lhs, rhs in
                    let lhsKey = ExerciseCatalogService.pinyinSortKey(for: lhs.name)
                    let rhsKey = ExerciseCatalogService.pinyinSortKey(for: rhs.name)
                    if lhsKey != rhsKey { return lhsKey < rhsKey }
                    return lhs.exerciseID.uuidString < rhs.exerciseID.uuidString
                }
                let parts = entry.key.split(separator: "␟", omittingEmptySubsequences: false)
                let equipment = parts.first.map(String.init) ?? "未分类器械"
                let muscleGroup = parts.dropFirst().first.map(String.init) ?? "未分类肌群"
                return (id: entry.key, equipment: equipment, muscleGroup: muscleGroup, items: items)
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

    private var trainingGoalMode: TrainingGoalMode {
        TrainingGoalMode(rawValue: trainingGoalRaw) ?? .cuttingVolume
    }

    private var advice: [MuscleGroupAdvice] {
        WorkoutRecommendationService.muscleGroupAdvice(
            selectedMuscleGroups: selectedMuscleGroups,
            exercises: exercises,
            sessions: sessions,
            sessionExercises: sessionExercises,
            setLogs: setLogs
        )
    }

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    private var activeSessionForSelectedDate: WorkoutSession? {
        activeSession.flatMap { session in
            session.plannedDate.isSameDay(as: selectedDate) ? session : nil
        }
    }

    private var builderMode: DailyBuilderMode {
        if activeSessionForSelectedDate != nil { return .active }
        return hasPersistedPlan ? .planned : .draft
    }

    private var totalPlannedSets: Int {
        selectedExerciseIDs.reduce(0) { $0 + (targets[$1]?.plannedSets.count ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !isEmbedded {
                        dateCard
                    }

                    switch builderMode {
                    case .draft:
                        draftPlanningContent
                    case .planned:
                        if isEditingPlan {
                            draftPlanningContent
                        } else {
                            plannedOverviewContent(isActive: false)
                        }
                    case .active:
                        if let activeSessionForSelectedDate {
                            activeWorkoutCard(activeSessionForSelectedDate)
                        }
                        if isEditingPlan {
                            draftPlanningContent
                        } else {
                            plannedOverviewContent(isActive: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            bottomActionBar
        }
        .screenBackground()
        .navigationTitle("当天训练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { recommendationVariant += 1 } label: {
                        Label("换一组推荐", systemImage: "arrow.triangle.2.circlepath")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("换一组推荐")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { KeyboardDismissal.dismiss() }
            }
        }
        .onAppear {
            loadExistingPlan(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            loadExistingPlan(for: newDate, force: true)
        }
        .navigationDestination(isPresented: $showWorkout) {
            if let workoutSessionID {
                ActiveWorkoutView(sessionID: workoutSessionID)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(
                title: "添加训练动作",
                initialMuscleGroup: selectedMuscleGroups.sorted().first ?? "",
                excludedExerciseIDs: Set(selectedExerciseIDs),
                onConfiguredSelect: { exercise, draft in
                    handlePickedExercise(exercise, draft: draft)
                }
            ) { exercise in
                handlePickedExercise(exercise, draft: nil)
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
        .sheet(isPresented: Binding(
            get: { editingExerciseID != nil },
            set: { if !$0 { editingExerciseID = nil } }
        )) {
            NavigationStack {
                ScrollView {
                    if let editingExerciseID,
                       let exercise = exercises.first(where: { $0.id == editingExerciseID }) {
                        selectedExerciseCard(exercise, showsListActions: false)
                            .padding(16)
                    }
                }
                .screenBackground()
                .navigationTitle("单独调整")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { self.editingExerciseID = nil }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
        .alert("无法保存训练安排", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("训练安排已保存", isPresented: Binding(
            get: { savedMessage != nil },
            set: { if !$0 { savedMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { savedMessage = nil }
        } message: {
            Text(savedMessage ?? "")
        }
    }

    private var menuBuilderHeader: some View {
        HStack(alignment: .center) {
            SectionHeader(
                title: selectedDate.isSameDay(as: .now) ? "今天的训练安排" : "当天训练安排",
                actionTitle: "\(selectedExerciseIDs.count) 个动作"
            )
            Spacer()
            Button {
                showExercisePicker = true
            } label: {
                Label("添加动作", systemImage: "plus.circle.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("当天菜单添加动作")
        }
    }

    private var emptyMenuCard: some View {
        Button {
            showExercisePicker = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text("从全部动作中选择，找不到时可立即新建")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("新动作保存后会直接加入这一天的训练安排。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("空菜单添加动作")
    }

    private var planningIntroCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "wand.and.stars")
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text("先计划今天练什么")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("根据近期恢复和上次强度选动作；开始后仍可按身体状态增减组、临时加动作并记录感受。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var trainingGoalCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("当前训练策略", systemImage: "scope")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text(trainingGoalMode.title)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            Picker("训练策略", selection: $trainingGoalRaw) {
                Text("减脂容量").tag(TrainingGoalMode.cuttingVolume.rawValue)
                Text("均衡进阶").tag(TrainingGoalMode.balancedProgression.rawValue)
            }
            .pickerStyle(.segmented)

            Text(trainingGoalMode.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardSurface()
    }

    private func activeWorkoutCard(_ session: WorkoutSession) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "bolt.fill")
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("当前训练进行中")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(session.templateName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("调整动作后会同步到正在记录的训练")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button("继续训练") {
                workoutSessionID = session.id
                showWorkout = true
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
        }
        .cardSurface()
    }

    private var dateCard: some View {
        DatePicker(
            "训练日期",
            selection: $selectedDate,
            in: Date.now.addingDays(-28)...Date.now.addingDays(30),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .font(.subheadline)
        .tint(AppTheme.accent)
        .frame(minHeight: 44)
        .accessibilityIdentifier("编排训练日期")
    }

    private var muscleGroupPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 9)], spacing: 9) {
            ForEach(muscleGroups, id: \.self) { group in
                Button {
                    toggleMuscleGroup(group)
                } label: {
                    Text(group)
                        .font(.subheadline.bold())
                        .foregroundStyle(selectedMuscleGroups.contains(group) ? .black : AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            selectedMuscleGroups.contains(group) ? AppTheme.accent : AppTheme.surface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
                }
                .accessibilityValue(selectedMuscleGroups.contains(group) ? "已选择" : "未选择")
            }
        }
    }

    private func adviceCard(_ item: MuscleGroupAdvice) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: readinessIcon(item.readiness))
                .font(.headline.bold())
                .foregroundStyle(readinessColor(item.readiness))
                .frame(width: 44, height: 44)
                .background(readinessColor(item.readiness).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.muscleGroup)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(item.title)
                        .font(.caption2.bold())
                        .foregroundStyle(readinessColor(item.readiness))
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                if let lastWorkoutName = item.lastWorkoutName, let date = item.lastTrainedAt {
                    Text(
                        "上次 \(date.formatted(.dateTime.month().day())) · \(lastWorkoutName)"
                            + (item.lastVolumeSummaries.isEmpty ? "" : " · \(item.lastVolumeSummaries.joined(separator: " / "))")
                    )
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func recommendationCard(_ recommendation: ExerciseRecommendation) -> some View {
        let isSelected = selectedExerciseIDs.contains(recommendation.exerciseID)
        let unit = exercises.first(where: { $0.id == recommendation.exerciseID })?.volumeUnit ?? .kilogram

        let isExpanded = expandedExerciseID == recommendation.exerciseID
        return VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedExerciseID = isExpanded ? nil : recommendation.exerciseID
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text(recommendation.name)
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                if recommendation.appearedInLastMenu {
                                    Text("上次训练")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("\(recommendation.muscleGroup) · \(recommendation.equipment)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)

                            if let last = recommendation.lastPerformance {
                                Text(
                                    "最近 \(last.date.formatted(.dateTime.month().day())) · "
                                        + (unit == .bodyweight && last.bodyWeightKgSnapshot == nil
                                            ? "暂无体重"
                                            : "\(Int(last.volume)) \(unit.symbol)")
                                )
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            } else {
                                Text("暂无记录")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("推荐动作-\(recommendation.name)")

                    Button {
                        toggleExercise(recommendation)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "移出今日动作" : "加入今日动作")
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.reason)
                            .font(.caption)
                            .foregroundStyle(recommendation.appearedInLastMenu ? .orange : AppTheme.accent)
                        if let last = recommendation.lastPerformance {
                            lastPerformanceView(last, unit: unit)
                        }
                        Text(recommendation.progressionTitle)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.accent)
                        Text(recommendation.progressionDetail)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(recommendationSummary(recommendation, unit: unit))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityIdentifier("推荐详情-\(recommendation.name)")

                    Label(recommendation.attentionText, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? AppTheme.accent.opacity(0.75) : .clear, lineWidth: 1.5)
        }
    }

    private func lastPerformanceView(_ last: ExerciseLastPerformance, unit: ExerciseVolumeUnit) -> some View {
        let best = last.bestSet
        let rir = last.averageRIR.map {
            $0.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "未记"

        return VStack(alignment: .leading, spacing: 5) {
            Text("上次：\(last.date.formatted(.dateTime.month().day())) · \(last.workoutName)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
            if let best {
                Text(
                    unit == .bodyweight
                        ? "上次：\(last.sets.count) 组 · 最多 \(best.reps) 次"
                        : "上次：\(last.sets.count) 组 · 工作均重 \(TrainingFormatters.weight(last.workingWeight)) \(unit.symbol) · 最重 \(TrainingFormatters.weight(best.weight)) \(unit.symbol) × \(best.reps)"
                )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(
                    (unit == .bodyweight && last.bodyWeightKgSnapshot == nil
                        ? "容量 暂无体重"
                        : "容量 \(Int(last.volume)) \(unit.symbol)")
                        + " · 平均 RIR \(rir)"
                )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func recommendationSummary(
        _ recommendation: ExerciseRecommendation,
        unit: ExerciseVolumeUnit
    ) -> String {
        if unit == .second {
            return "建议 \(recommendation.suggestedSets) 组 × \(recommendation.minReps)–\(recommendation.maxReps) 秒"
                + " · 目标约 \(Int(recommendation.suggestedVolume)) 秒"
        }
        let base = "建议 \(recommendation.suggestedSets) 组 × \(recommendation.minReps)–\(recommendation.maxReps) 次"
        if unit == .bodyweight {
            return base + " · 自重容量按训练时体重快照计算"
        }
        if unit == .count {
            return base + " · 目标约 \(Int(recommendation.suggestedVolume)) 个"
        }
        return base
            + " · \(TrainingFormatters.weight(recommendation.suggestedWeight)) \(unit.symbol)"
            + " · 目标容量约 \(Int(recommendation.suggestedVolume)) \(unit.symbol)"
    }

    private func selectedExerciseCard(
        _ exercise: Exercise,
        showsListActions: Bool = true
    ) -> some View {
        let binding = targetBinding(for: exercise.id)
        let index = selectedExerciseIDs.firstIndex(of: exercise.id) ?? 0

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index + 1). \(exercise.name)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("\(exercise.muscleGroup) · \(exercise.equipment)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let url = URL(string: exercise.referenceURL), !exercise.referenceURL.isEmpty {
                        Link(destination: url) {
                            Label("查看动作资料", systemImage: "link")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
                Spacer()
                if showsListActions {
                    Button {
                        moveExercise(exercise.id, offset: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        moveExercise(exercise.id, offset: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == selectedExerciseIDs.count - 1)
                    Button(role: .destructive) {
                        removeExercise(exercise.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            if exercise.volumeUnit.usesMeasurementSide {
                Picker("记录口径", selection: measurementSideBinding(for: exercise.id)) {
                    ForEach(MeasurementSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plan-measurement-side-\(exercise.name)")
            }

            Stepper(
                "计划组数：\(binding.wrappedValue.plannedSets.count)",
                value: plannedSetCountBinding(for: exercise.id),
                in: 1...12
            )
            .foregroundStyle(.white)

            HStack(spacing: 8) {
                Text("组").frame(width: 26)
                if exercise.volumeUnit.recordsSingleAmount {
                    Text("计划\(exercise.volumeUnit.inputTitle) · \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                } else if exercise.volumeUnit == .bodyweight {
                    Text("负重").frame(maxWidth: .infinity)
                    Text("计划次数").frame(maxWidth: .infinity)
                } else {
                    Text("计划\(exercise.volumeUnit.inputTitle) · \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                    Text("计划\(exercise.volumeUnit.repetitionTitle)").frame(maxWidth: .infinity)
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)

            ForEach(binding.wrappedValue.plannedSets.indices, id: \.self) { setIndex in
                plannedSetRow(
                    index: setIndex,
                    binding: plannedSetBinding(for: exercise.id, index: setIndex),
                    unit: exercise.volumeUnit,
                    exerciseName: exercise.name
                )
            }

            Picker("组间休息", selection: binding.restSeconds) {
                ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                    Text("\(seconds) 秒").tag(seconds)
                }
            }
            .foregroundStyle(.white)
        }
        .cardSurface()
    }

    private func toggleMuscleGroup(_ group: String) {
        if selectedMuscleGroups.contains(group) {
            selectedMuscleGroups.remove(group)
            let removedIDs = exercises
                .filter { $0.muscleGroup == group }
                .map(\.id)
            selectedExerciseIDs.removeAll { removedIDs.contains($0) }
            removedIDs.forEach { targets.removeValue(forKey: $0) }
        } else {
            selectedMuscleGroups.insert(group)
        }
        recommendationVariant = 0
    }

    private func toggleExercise(_ recommendation: ExerciseRecommendation) {
        if selectedExerciseIDs.contains(recommendation.exerciseID) {
            removeExercise(recommendation.exerciseID)
        } else {
            selectedExerciseIDs.append(recommendation.exerciseID)
            targets[recommendation.exerciseID] = DailyExerciseTarget(
                pattern: .fixed,
                patternSource: .dayDefault,
                plannedSets: WorkoutSetPlan.preset(
                    .fixed,
                    count: recommendation.suggestedSets,
                    baseWeight: recommendation.suggestedWeight,
                    baseReps: recommendation.minReps
                ),
                restSeconds: recommendation.restSeconds
            )
        }
    }

    private func addExerciseToMenu(_ exercise: Exercise) {
        guard !selectedExerciseIDs.contains(exercise.id) else { return }
        selectedMuscleGroups.insert(exercise.muscleGroup)
        selectedExerciseIDs.append(exercise.id)

        let recommendation = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: [exercise.muscleGroup],
            exercises: exercises,
            sessions: sessions,
            sessionExercises: sessionExercises,
            setLogs: setLogs,
            templateExercises: templateExercises,
            variant: recommendationVariant,
            goalMode: trainingGoalMode
        ).first { $0.exerciseID == exercise.id }

        targets[exercise.id] = DailyExerciseTarget(
            pattern: .fixed,
            patternSource: .dayDefault,
            plannedSets: WorkoutSetPlan.preset(
                .fixed,
                count: recommendation?.suggestedSets ?? (trainingGoalMode == .cuttingVolume ? 4 : 3),
                baseWeight: recommendation?.suggestedWeight ?? 0,
                baseReps: recommendation?.minReps ?? (trainingGoalMode == .cuttingVolume ? 10 : 8)
            ),
            restSeconds: recommendation?.restSeconds ?? exercise.defaultRestSeconds
        )
    }

    private func addExerciseToMenu(_ exercise: Exercise, draft: ExerciseSetupDraft) {
        guard !selectedExerciseIDs.contains(exercise.id) else { return }
        selectedMuscleGroups.insert(exercise.muscleGroup)
        selectedExerciseIDs.append(exercise.id)
        targets[exercise.id] = DailyExerciseTarget(
            pattern: .fixed,
            patternSource: .dayDefault,
            plannedSets: draft.plannedSets,
            restSeconds: draft.restSeconds
        )
    }

    private func handlePickedExercise(_ exercise: Exercise, draft: ExerciseSetupDraft?) {
        if let replacingExerciseID,
           let index = selectedExerciseIDs.firstIndex(of: replacingExerciseID) {
            let oldTarget = targets[replacingExerciseID]
            selectedExerciseIDs[index] = exercise.id
            targets.removeValue(forKey: replacingExerciseID)
            selectedMuscleGroups.insert(exercise.muscleGroup)
            if let draft {
                targets[exercise.id] = DailyExerciseTarget(
                    pattern: .fixed,
                    patternSource: .dayDefault,
                    plannedSets: draft.plannedSets,
                    restSeconds: draft.restSeconds
                )
            } else if let oldTarget {
                targets[exercise.id] = DailyExerciseTarget(
                    pattern: .fixed,
                    patternSource: .dayDefault,
                    plannedSets: WorkoutSetPlan.preset(
                        .fixed,
                        count: oldTarget.plannedSets.count,
                        baseWeight: 0,
                        baseReps: oldTarget.plannedSets.map(\.reps).max() ?? 8
                    ),
                    restSeconds: exercise.defaultRestSeconds
                )
            } else {
                addExerciseToMenu(exercise)
            }
            self.replacingExerciseID = nil
            return
        }

        if let draft {
            addExerciseToMenu(exercise, draft: draft)
        } else {
            addExerciseToMenu(exercise)
        }
    }

    private func removeExercise(_ id: UUID) {
        guard canRemoveExerciseFromCurrentMenu(id) else { return }
        if builderMode != .draft { isEditingPlan = true }
        selectedExerciseIDs.removeAll { $0 == id }
        targets.removeValue(forKey: id)
    }

    private func canRemoveExerciseFromCurrentMenu(_ exerciseID: UUID) -> Bool {
        guard selectedExerciseIDs.count > 1 else { return false }
        guard let activeSessionForSelectedDate,
              let snapshot = sessionExercises.first(where: {
                  $0.sessionID == activeSessionForSelectedDate.id && $0.exerciseID == exerciseID
              }) else {
            return true
        }
        return !setLogs.contains {
            $0.sessionExerciseID == snapshot.id && $0.isCompleted
        }
    }

    private func editExercisePlan(_ id: UUID) {
        guard targets[id] != nil else { return }
        if builderMode != .draft { isEditingPlan = true }
        editingExerciseID = id
    }

    private func exercisePlanSummary(_ exercise: Exercise) -> String {
        guard let target = targets[exercise.id], !target.plannedSets.isEmpty else { return "尚未设置" }
        let plans = target.plannedSets
        if exercise.volumeUnit.recordsSingleAmount {
            let amount = Set(plans.map(\.reps)).count == 1
                ? "\(plans.count)×\(plans[0].reps) \(exercise.volumeUnit.symbol)"
                : "\(plans.count) 组 · \(exercise.volumeUnit.symbol)"
            return amount
        }
        let reps = Set(plans.map(\.reps)).count == 1
            ? "\(plans.count)×\(plans[0].reps)"
            : "\(plans.count) 组"
        let load: String
        if exercise.volumeUnit.recordsNumericLoad {
            let first = TrainingFormatters.weight(plans.first?.weight ?? 0)
            let last = TrainingFormatters.weight(plans.last?.weight ?? 0)
            load = first == last
                ? "\(first) \(exercise.volumeUnit.symbol)"
                : "\(first)→\(last) \(exercise.volumeUnit.symbol)"
        } else if exercise.volumeUnit == .bodyweight {
            load = "自重"
        } else {
            load = "按数量"
        }
        return "\(reps) · \(load)"
    }

    private func readOnlySetSummary(
        _ plan: WorkoutSetPlan,
        unit: ExerciseVolumeUnit
    ) -> String {
        if unit.recordsNumericLoad {
            return "\(TrainingFormatters.weight(plan.weight)) \(unit.symbol) × \(plan.reps)"
        }
        if unit == .bodyweight { return "自重 × \(plan.reps)" }
        return "\(plan.reps) \(unit.symbol)"
    }

    private func recordingBasis(
        for exercise: Exercise,
        target: DailyExerciseTarget?
    ) -> String {
        guard exercise.volumeUnit.usesMeasurementSide else {
            return exercise.volumeUnit == .bodyweight
                ? "自重次数"
                : exercise.volumeUnit.inputTitle
        }
        let side = target?.plannedSets.first?.weightSide ?? .bilateral
        return "\(exercise.volumeUnit.inputTitle) · \(side.title)"
    }

    private func moveExercise(_ id: UUID, offset: Int) {
        guard let index = selectedExerciseIDs.firstIndex(of: id) else { return }
        let target = index + offset
        guard selectedExerciseIDs.indices.contains(target) else { return }
        selectedExerciseIDs.swapAt(index, target)
        if activeSessionForSelectedDate != nil {
            syncActiveWorkoutMenu(showConfirmation: false)
        } else if hasPersistedPlan, !isEditingPlan {
            persistCurrentPlanSilently()
        }
    }

    private func reorderExercise(_ id: UUID, verticalTranslation: CGFloat) {
        guard let sourceIndex = selectedExerciseIDs.firstIndex(of: id) else { return }
        let rowStride: CGFloat = 66
        let offset = Int((verticalTranslation / rowStride).rounded())
        guard offset != 0 else { return }

        let destinationIndex = min(
            max(sourceIndex + offset, selectedExerciseIDs.startIndex),
            selectedExerciseIDs.index(before: selectedExerciseIDs.endIndex)
        )
        guard destinationIndex != sourceIndex else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedExerciseIDs.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }

        if activeSessionForSelectedDate != nil {
            syncActiveWorkoutMenu(showConfirmation: false)
        } else if hasPersistedPlan, !isEditingPlan {
            persistCurrentPlanSilently()
        }
    }

    private func targetBinding(for id: UUID) -> Binding<DailyExerciseTarget> {
        Binding {
            targets[id] ?? DailyExerciseTarget(
                pattern: .fixed,
                patternSource: .dayDefault,
                plannedSets: WorkoutSetPlan.preset(.fixed, count: 3, baseWeight: 0, baseReps: 8),
                restSeconds: 90
            )
        } set: { newValue in
            targets[id] = newValue
        }
    }

    private func plannedSetBinding(for exerciseID: UUID, index: Int) -> Binding<WorkoutSetPlan> {
        Binding {
            guard let target = targets[exerciseID], target.plannedSets.indices.contains(index) else {
                return WorkoutSetPlan(weight: 0, reps: 1)
            }
            return target.plannedSets[index]
        } set: { newValue in
            guard var target = targets[exerciseID], target.plannedSets.indices.contains(index) else { return }
            target.plannedSets[index] = newValue
            targets[exerciseID] = target
        }
    }

    private func plannedSetCountBinding(for exerciseID: UUID) -> Binding<Int> {
        Binding {
            targets[exerciseID]?.plannedSets.count ?? 1
        } set: { newCount in
            guard var target = targets[exerciseID] else { return }
            let safeCount = min(max(1, newCount), 12)
            if safeCount > target.plannedSets.count {
                let seed = target.plannedSets.last ?? WorkoutSetPlan(weight: 0, reps: 8)
                for _ in target.plannedSets.count..<safeCount {
                    target.plannedSets.append(
                        WorkoutSetPlan(
                            weight: seed.weight,
                            reps: seed.reps,
                            weightSide: seed.weightSide,
                            repsSide: seed.repsSide
                        )
                    )
                }
            } else if safeCount < target.plannedSets.count {
                target.plannedSets.removeLast(target.plannedSets.count - safeCount)
            }
            targets[exerciseID] = target
        }
    }

    private func plannedSetRow(
        index: Int,
        binding: Binding<WorkoutSetPlan>,
        unit: ExerciseVolumeUnit,
        exerciseName: String
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 26)

            if unit.recordsNumericLoad {
                StableNumericTextField(
                    unit.symbol,
                    value: binding.weight,
                    maximumFractionDigits: 3,
                    accessibilityIdentifier: "planned-weight-\(exerciseName)-\(index + 1)"
                )
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            } else if unit == .bodyweight {
                Text("自重")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
            }

            StableNumericTextField(
                unit.recordsSingleAmount ? unit.inputTitle : unit.repetitionTitle,
                value: binding.reps,
                accessibilityIdentifier: "planned-reps-\(exerciseName)-\(index + 1)"
            )
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)

        }
    }

    private func measurementSideBinding(for exerciseID: UUID) -> Binding<MeasurementSide> {
        Binding {
            targets[exerciseID]?.plannedSets.first?.weightSide ?? .bilateral
        } set: { side in
            guard var target = targets[exerciseID] else { return }
            target.plannedSets = target.plannedSets.map { plan in
                WorkoutSetPlan(
                    id: plan.id,
                    weight: plan.weight,
                    reps: plan.reps,
                    weightSide: side,
                    repsSide: side
                )
            }
            targets[exerciseID] = target
        }
    }

    private func loadExistingPlan(for date: Date, force: Bool = false) {
        let targetDate = date.startOfDay
        if !force, loadedDate?.isSameDay(as: targetDate) == true { return }
        loadedDate = targetDate
        selectedMuscleGroups = []
        selectedExerciseIDs = []
        targets = [:]
        hasPersistedPlan = false
        isEditingPlan = false
        planningStage = .muscles
        expandedExerciseID = nil
        dayPlanPattern = .fixed

        if let active = activeSession,
           active.plannedDate.isSameDay(as: targetDate) {
            let snapshots = sessionExercises
                .filter { $0.sessionID == active.id }
                .sorted { $0.order < $1.order }
            selectedExerciseIDs = snapshots.map(\.exerciseID)
            targets = Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
                (
                    snapshot.exerciseID,
                    DailyExerciseTarget(
                        pattern: snapshot.planPattern,
                        patternSource: snapshot.patternSource,
                        plannedSets: snapshot.plannedSets,
                        restSeconds: snapshot.restSeconds
                    )
                )
            })
            selectedMuscleGroups = Set(
                activeReplannedMuscleGroups(from: active.templateName)
                    ?? snapshots.map(\.muscleGroup).filter { !$0.isEmpty }
            )
            applyLoadedPatternMetadata(
                explicitPatternRaw: active.defaultPlanPatternRaw,
                itemPatterns: snapshots.map { ($0.exerciseID, $0.planPattern, $0.patternSourceRaw) }
            )
            hasPersistedPlan = true
            replaceExistingPlans = false
            return
        }

        let candidates = schedules
            .filter {
                $0.plannedDate.isSameDay(as: targetDate)
                    && ($0.status == .planned || $0.status == .skipped)
            }
            .sorted { left, right in
                let leftOneOff = templates.first(where: { $0.id == left.templateID })?.isOneOff == true
                let rightOneOff = templates.first(where: { $0.id == right.templateID })?.isOneOff == true
                if leftOneOff != rightOneOff { return leftOneOff }
                return left.createdAt > right.createdAt
            }
        let preferredSchedule = candidates.first(where: { $0.id == initialScheduleID })
            ?? candidates.first(where: { $0.status == .planned })
            ?? candidates.first
        guard let schedule = preferredSchedule,
              let template = templates.first(where: { $0.id == schedule.templateID }) else {
            return
        }

        let items = templateExercises
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }
        selectedExerciseIDs = items.map(\.exerciseID)
        targets = Dictionary(uniqueKeysWithValues: items.map { item in
            (
                item.exerciseID,
                    DailyExerciseTarget(
                        pattern: item.planPattern,
                        patternSource: item.patternSource,
                        plannedSets: item.plannedSets,
                    restSeconds: item.restSeconds
                )
            )
        })
        let derivedGroups = items.compactMap { item in
            exercises.first(where: { $0.id == item.exerciseID })?.muscleGroup
        }
        selectedMuscleGroups = Set(
            template.focusMuscleGroups.isEmpty ? derivedGroups : template.focusMuscleGroups
        )
        applyLoadedPatternMetadata(
            explicitPatternRaw: template.defaultPlanPatternRaw,
            itemPatterns: items.map { ($0.exerciseID, $0.planPattern, $0.patternSourceRaw) }
        )
        hasPersistedPlan = true
        replaceExistingPlans = true
    }

    private func applyLoadedPatternMetadata(
        explicitPatternRaw: String?,
        itemPatterns: [(UUID, SetPlanPattern, String?)]
    ) {
        let resolution = DailyPlanPatternMetadataPolicy.resolve(
            explicitPatternRaw: explicitPatternRaw,
            itemPatterns: itemPatterns
        )
        dayPlanPattern = resolution.dayPattern
        for (id, source) in resolution.sources {
            guard var target = targets[id] else { continue }
            target.patternSource = source
            targets[id] = target
        }
    }

    private func savePlan(startAfterSaving: Bool) {
        if activeSessionForSelectedDate != nil {
            syncActiveWorkoutMenu(showConfirmation: true)
            return
        }

        let inputs = currentMenuInputs

        do {
            let schedule = try DailyPlanService.create(
                on: selectedDate,
                muscleGroups: selectedMuscleGroups.sorted(),
                defaultPlanPattern: dayPlanPattern,
                exercises: inputs,
                replaceExistingPlans: replaceExistingPlans,
                in: modelContext
            )
            loadedDate = selectedDate.startOfDay
            hasPersistedPlan = true
            isEditingPlan = false
            if startAfterSaving {
                Task { @MainActor in
                    do {
                        workoutSessionID = try await WorkoutService.startUsingAvailableBodyWeight(
                            schedule: schedule,
                            in: modelContext
                        )
                        showWorkout = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } else if isEmbedded {
                savedMessage = "今天的训练安排已更新。开始训练后仍可按身体状态临时调整动作和组数。"
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentMenuInputs: [DailyPlanExerciseInput] {
        selectedExerciseIDs.compactMap { id -> DailyPlanExerciseInput? in
            guard let target = targets[id] else { return nil }
            return DailyPlanExerciseInput(
                exerciseID: id,
                plannedSets: target.plannedSets,
                planPattern: target.pattern,
                patternSource: target.patternSource,
                restSeconds: target.restSeconds
            )
        }
    }

    private func persistCurrentPlanSilently() {
        do {
            _ = try DailyPlanService.create(
                on: selectedDate,
                muscleGroups: selectedMuscleGroups.sorted(),
                defaultPlanPattern: dayPlanPattern,
                exercises: currentMenuInputs,
                replaceExistingPlans: replaceExistingPlans,
                in: modelContext
            )
            loadedDate = selectedDate.startOfDay
            hasPersistedPlan = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func syncActiveWorkoutMenu(showConfirmation: Bool) -> Bool {
        guard let activeSessionForSelectedDate else { return false }
        do {
            try WorkoutService.syncMenu(
                currentMenuInputs,
                to: activeSessionForSelectedDate,
                muscleGroups: selectedMuscleGroups.sorted(),
                defaultPlanPattern: dayPlanPattern,
                in: modelContext
            )
            loadedDate = selectedDate.startOfDay
            if showConfirmation {
                savedMessage = "进行中的训练安排已同步；返回训练页即可继续记录。"
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func activeReplannedMuscleGroups(from title: String) -> [String]? {
        let suffix = " · 当天菜单"
        guard title.hasSuffix(suffix) else { return nil }
        let prefix = String(title.dropLast(suffix.count))
        let groups = prefix.split(separator: "+").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return groups.isEmpty ? nil : groups
    }

    private func readinessColor(_ readiness: MuscleGroupAdvice.Readiness) -> Color {
        switch readiness {
        case .ready: return AppTheme.accent
        case .moderate: return .yellow
        case .recover: return AppTheme.orange
        case .noHistory: return AppTheme.purple
        }
    }

    private func readinessIcon(_ readiness: MuscleGroupAdvice.Readiness) -> String {
        switch readiness {
        case .ready: return "checkmark.circle.fill"
        case .moderate: return "gauge.with.dots.needle.50percent"
        case .recover: return "bed.double.fill"
        case .noHistory: return "sparkles"
        }
    }
}

private extension Binding where Value == DailyExerciseTarget {
    var pattern: Binding<SetPlanPattern> {
        Binding<SetPlanPattern>(
            get: { wrappedValue.pattern },
            set: {
                var value = wrappedValue
                value.pattern = $0
                wrappedValue = value
            }
        )
    }

    var restSeconds: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.restSeconds },
            set: {
                var value = wrappedValue
                value.restSeconds = $0
                wrappedValue = value
            }
        )
    }
}

private extension Binding where Value == WorkoutSetPlan {
    var weight: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.weight },
            set: {
                var value = wrappedValue
                value.weight = Swift.max(0, $0)
                wrappedValue = value
            }
        )
    }

    var reps: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.reps },
            set: {
                var value = wrappedValue
                value.reps = Swift.max(1, $0)
                wrappedValue = value
            }
        )
    }

    var weightSide: Binding<MeasurementSide> {
        Binding<MeasurementSide>(
            get: { wrappedValue.weightSide },
            set: {
                var value = wrappedValue
                value.weightSide = $0
                wrappedValue = value
            }
        )
    }

    var repsSide: Binding<MeasurementSide> {
        Binding<MeasurementSide>(
            get: { wrappedValue.repsSide },
            set: {
                var value = wrappedValue
                value.repsSide = $0
                wrappedValue = value
            }
        )
    }
}

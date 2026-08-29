import SwiftData
import SwiftUI

private struct DailyExerciseTarget {
    var pattern: SetPlanPattern
    var plannedSets: [WorkoutSetPlan]
    var restSeconds: Int
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
    @State private var isReorderingExercises = false
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

    private var existingPlansOnDate: [ScheduledWorkout] {
        schedules.filter { schedule in
            schedule.plannedDate.isSameDay(as: selectedDate)
                && schedule.status == .planned
                && templates.first(where: { $0.id == schedule.templateID })?.isOneOff != true
        }
    }

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    private var activeSessionForSelectedDate: WorkoutSession? {
        activeSession.flatMap { session in
            session.plannedDate.isSameDay(as: selectedDate) ? session : nil
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                if isEmbedded {
                    planningIntroCard
                } else {
                    ScreenHeader(
                        eyebrow: "ADAPTIVE WORKOUT",
                        title: "编排当天训练",
                        trailingSystemImage: "arrow.triangle.2.circlepath",
                        trailingAccessibilityLabel: "换一组推荐",
                        trailingAction: { recommendationVariant += 1 }
                    )

                    dateCard
                }

                if let activeSession {
                    activeWorkoutCard(activeSession)
                }

                menuBuilderHeader

                if !selectedExerciseIDs.isEmpty {
                    selectedMenuSection
                } else {
                    emptyMenuCard
                }

                trainingGoalCard

                SectionHeader(title: "今天想练哪里")
                muscleGroupPicker

                if !advice.isEmpty {
                    SectionHeader(title: "肌群建议")
                    ForEach(advice) { item in
                        adviceCard(item)
                    }
                }

                if !recommendations.isEmpty {
                    HStack {
                        SectionHeader(title: "推荐动作", actionTitle: "\(recommendations.count) 个可选")
                        Spacer()
                        Button("换一组") {
                            recommendationVariant += 1
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    }

                    ForEach(recommendations) { recommendation in
                        recommendationCard(recommendation)
                    }
                } else if !selectedMuscleGroups.isEmpty {
                    ContentUnavailableView(
                        "这个肌群还没有可用动作",
                        systemImage: "dumbbell",
                        description: Text("请先在动作库新增动作或恢复已归档动作。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .screenBackground()
        .navigationTitle("当天训练")
        .navigationBarTitleDisplayMode(.inline)
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
                title: "添加到当天菜单",
                initialMuscleGroup: selectedMuscleGroups.sorted().first ?? "",
                excludedExerciseIDs: Set(selectedExerciseIDs),
                onConfiguredSelect: { exercise, draft in
                    addExerciseToMenu(exercise, draft: draft)
                }
            ) { exercise in
                addExerciseToMenu(exercise)
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
        .alert("无法保存菜单", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("菜单已保存", isPresented: Binding(
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
                title: selectedDate.isSameDay(as: .now) ? "今天的菜单" : "当天菜单",
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
                Text("新动作保存后会直接加入这一天的菜单，不会丢失当前编排。")
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
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("当前训练进行中")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(session.templateName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("这里调整菜单后会同步到正在记录的训练")
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

    @ViewBuilder
    private var selectedMenuSection: some View {
        if loadedDate != nil {
            Text(activeSessionForSelectedDate == nil ? "修改仅作用于当天" : "正在训练 · 修改会同步到本次记录")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.accent)
        }

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isReorderingExercises.toggle()
            }
        } label: {
            Label(
                isReorderingExercises ? "完成排序" : "拖动排序",
                systemImage: isReorderingExercises ? "checkmark" : "line.3.horizontal"
            )
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.accent)
        .accessibilityIdentifier(isReorderingExercises ? "完成排序" : "拖动排序")

        if isReorderingExercises {
            Text("按住右侧把手，上下拖动动作；这里只显示名称，训练参数不会改变。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }

        if activeSessionForSelectedDate == nil, !existingPlansOnDate.isEmpty {
            Toggle(isOn: $replaceExistingPlans) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("用当天菜单替代原计划")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("原计划会标记为跳过；每周模板和已完成历史不会改变。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .tint(AppTheme.accent)
            .cardSurface()
        }

        if let activeSessionForSelectedDate {
            Button {
                savePlan(startAfterSaving: false)
            } label: {
                Label("同步到进行中的训练", systemImage: "arrow.triangle.2.circlepath")
                    .neonButtonStyle()
            }
            .accessibilityIdentifier("同步进行中训练菜单")

            Text("动作顺序、未开始动作和未完成组会立即更新；已完成组保持原记录。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("正在训练，可从外部调整菜单")
                .id(activeSessionForSelectedDate.id)
        } else if selectedDate.isSameDay(as: .now), activeSession == nil {
            Button {
                savePlan(startAfterSaving: true)
            } label: {
                Label("保存并开始记录", systemImage: "play.fill")
                    .neonButtonStyle()
            }
            .accessibilityIdentifier("保存并开始记录")

            Button {
                savePlan(startAfterSaving: false)
            } label: {
                Label("保存计划，稍后记录", systemImage: "tray.and.arrow.down")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("保存今日计划")
        } else {
            Button {
                savePlan(startAfterSaving: false)
            } label: {
                Label(
                    selectedDate.isSameDay(as: .now) ? "更新今天菜单" : "保存到所选日期",
                    systemImage: "checkmark.circle.fill"
                )
                .neonButtonStyle()
            }
            .accessibilityIdentifier("保存当天计划")
        }

        if isReorderingExercises {
            ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
                if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                    reorderExerciseCard(exercise)
                }
            }
        } else {
            ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
                if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                    selectedExerciseCard(exercise)
                }
            }
        }

        Divider()
            .overlay(AppTheme.line)

        Text("需要增减动作时，继续在下方选择肌群和推荐动作。")
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
    }

    private var dateCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("训练日期")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                Text(selectedDate.isSameDay(as: .now) ? "今天" : selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            DatePicker(
                "训练日期",
                selection: $selectedDate,
                in: Date.now.addingDays(-28)...Date.now.addingDays(30),
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(AppTheme.accent)
        }
        .cardSurface()
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
                .frame(width: 42, height: 42)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func recommendationCard(_ recommendation: ExerciseRecommendation) -> some View {
        let isSelected = selectedExerciseIDs.contains(recommendation.exerciseID)
        let unit = exercises.first(where: { $0.id == recommendation.exerciseID })?.volumeUnit ?? .kilogram

        return Button {
            toggleExercise(recommendation)
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(recommendation.name)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            if recommendation.appearedInLastMenu {
                                Text("上次菜单")
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
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                }

                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(recommendation.appearedInLastMenu ? .orange : AppTheme.accent)

                if let last = recommendation.lastPerformance {
                    lastPerformanceView(last, unit: unit)
                } else {
                    Text("没有上次强度记录 · 建议从 \(recommendation.suggestedSets) 组 × \(recommendation.minReps)–\(recommendation.maxReps) 次开始")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
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

                Label(recommendation.attentionText, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.75) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
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
                Text("\(unit == .bodyweight ? "完成" : "容量") \(Int(last.volume)) \(unit == .bodyweight ? "次" : unit.symbol) · 平均 RIR \(rir)")
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
        let base = "建议 \(recommendation.suggestedSets) 组 × \(recommendation.minReps)–\(recommendation.maxReps) 次"
        if unit == .bodyweight {
            return base + " · 自重 · 目标约 \(Int(recommendation.suggestedVolume)) 次"
        }
        if unit == .count {
            return base + " · 目标约 \(Int(recommendation.suggestedVolume)) 个"
        }
        return base
            + " · \(TrainingFormatters.weight(recommendation.suggestedWeight)) \(unit.symbol)"
            + " · 目标容量约 \(Int(recommendation.suggestedVolume)) \(unit.symbol)"
    }

    private func selectedExerciseCard(_ exercise: Exercise) -> some View {
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

            Picker("编排模式", selection: binding.pattern) {
                ForEach(SetPlanPattern.allCases) { pattern in
                    Text(pattern.title).tag(pattern)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("set-plan-pattern-\(exercise.name)")
            .onChange(of: binding.wrappedValue.pattern) { _, _ in
                applyPreset(to: exercise.id)
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

            HStack {
                Stepper(
                    "计划组数：\(binding.wrappedValue.plannedSets.count)",
                    value: plannedSetCountBinding(for: exercise.id),
                    in: 1...12
                )
                .foregroundStyle(.white)
                Spacer()
                Button("套用预设") {
                    applyPreset(to: exercise.id)
                }
                .accessibilityIdentifier("apply-set-preset-\(exercise.name)")
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }

            HStack(spacing: 8) {
                Text("组").frame(width: 26)
                if exercise.volumeUnit == .count {
                    Text("计划数量 · 个").frame(maxWidth: .infinity)
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

    private func reorderExerciseCard(_ exercise: Exercise) -> some View {
        let index = selectedExerciseIDs.firstIndex(of: exercise.id) ?? 0

        return HStack(spacing: 12) {
            Text("\(index + 1). \(exercise.name)")
                .font(.headline.bold())
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(index + 1) 个动作，\(exercise.name)，可拖动排序")
        .accessibilityIdentifier("排序动作-\(exercise.name)")
        .opacity(draggingExerciseID == exercise.id ? 0.72 : 1)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    draggingExerciseID = exercise.id
                }
                .onEnded { value in
                    reorderExercise(exercise.id, verticalTranslation: value.translation.height)
                    draggingExerciseID = nil
                }
        )
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
            pattern: draft.pattern,
            plannedSets: draft.plannedSets,
            restSeconds: draft.restSeconds
        )
    }

    private func removeExercise(_ id: UUID) {
        selectedExerciseIDs.removeAll { $0 == id }
        targets.removeValue(forKey: id)
    }

    private func moveExercise(_ id: UUID, offset: Int) {
        guard let index = selectedExerciseIDs.firstIndex(of: id) else { return }
        let target = index + offset
        guard selectedExerciseIDs.indices.contains(target) else { return }
        selectedExerciseIDs.swapAt(index, target)
        if activeSessionForSelectedDate != nil {
            syncActiveWorkoutMenu(showConfirmation: false)
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
        }
    }

    private func targetBinding(for id: UUID) -> Binding<DailyExerciseTarget> {
        Binding {
            targets[id] ?? DailyExerciseTarget(
                pattern: .fixed,
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
            applyPreset(to: exerciseID)
        }
    }

    private func applyPreset(to exerciseID: UUID) {
        guard var target = targets[exerciseID], let first = target.plannedSets.first else { return }
        target.plannedSets = WorkoutSetPlan.preset(
            target.pattern,
            count: target.plannedSets.count,
            baseWeight: target.plannedSets.map(\.weight).min() ?? first.weight,
            baseReps: target.plannedSets.map(\.reps).max() ?? first.reps,
            weightSide: first.weightSide,
            repsSide: first.repsSide
        )
        targets[exerciseID] = target
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
                unit == .count ? "个" : unit.repetitionTitle,
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
                        plannedSets: snapshot.plannedSets,
                        restSeconds: snapshot.restSeconds
                    )
                )
            })
            selectedMuscleGroups = Set(snapshots.map(\.muscleGroup).filter { !$0.isEmpty })
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
        replaceExistingPlans = true
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
                exercises: inputs,
                replaceExistingPlans: replaceExistingPlans,
                in: modelContext
            )
            loadedDate = selectedDate.startOfDay
            if startAfterSaving {
                workoutSessionID = try WorkoutService.start(schedule: schedule, in: modelContext)
                showWorkout = true
            } else if isEmbedded {
                savedMessage = "今天的菜单已更新。开始训练后仍可按身体状态临时调整动作和组数。"
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
                restSeconds: target.restSeconds
            )
        }
    }

    private func syncActiveWorkoutMenu(showConfirmation: Bool) {
        guard let activeSessionForSelectedDate else { return }
        do {
            try WorkoutService.syncMenu(
                currentMenuInputs,
                to: activeSessionForSelectedDate,
                in: modelContext
            )
            loadedDate = selectedDate.startOfDay
            if showConfirmation {
                savedMessage = "进行中的训练菜单已同步；返回训练页即可继续记录。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

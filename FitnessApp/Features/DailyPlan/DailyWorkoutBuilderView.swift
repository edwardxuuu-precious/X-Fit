import SwiftData
import SwiftUI

private struct DailyExerciseTarget {
    var sets: Int
    var minReps: Int
    var maxReps: Int
    var weight: Double
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

    var isEmbedded = false

    @State private var selectedDate = Date.now.startOfDay
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var selectedExerciseIDs: [UUID] = []
    @State private var targets: [UUID: DailyExerciseTarget] = [:]
    @State private var recommendationVariant = 0
    @State private var replaceExistingPlans = true
    @State private var loadedDate: Date?
    @State private var workoutSessionID: UUID?
    @State private var showWorkout = false
    @State private var savedMessage: String?
    @State private var errorMessage: String?

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

                if !selectedExerciseIDs.isEmpty {
                    SectionHeader(title: "今天的菜单", actionTitle: "\(selectedExerciseIDs.count) 个动作")
                    ForEach(selectedExerciseIDs, id: \.self) { exerciseID in
                        if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                            selectedExerciseCard(exercise)
                        }
                    }

                    if !existingPlansOnDate.isEmpty {
                        Toggle(isOn: $replaceExistingPlans) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("用自选菜单替代当天原计划")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("原计划会标记为跳过，历史不会删除。")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .tint(AppTheme.accent)
                        .cardSurface()
                    }

                    if selectedDate.isSameDay(as: .now), activeSession == nil {
                        Button {
                            savePlan(startAfterSaving: true)
                        } label: {
                            Label("保存并开始训练", systemImage: "play.fill")
                                .neonButtonStyle()
                        }

                        Button {
                            savePlan(startAfterSaving: false)
                        } label: {
                            Label("只保存菜单，稍后训练", systemImage: "tray.and.arrow.down")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
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
                    }
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
                    lastPerformanceView(last)
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
                    Text(
                        "建议 \(recommendation.suggestedSets) 组 × \(recommendation.minReps)–\(recommendation.maxReps) 次 · "
                            + "\(TrainingFormatters.weight(recommendation.suggestedWeight)) kg · "
                            + "目标容量约 \(Int(recommendation.suggestedVolume)) kg"
                    )
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

    private func lastPerformanceView(_ last: ExerciseLastPerformance) -> some View {
        let best = last.bestSet
        let rir = last.averageRIR.map {
            $0.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "未记"

        return VStack(alignment: .leading, spacing: 5) {
            Text("上次：\(last.date.formatted(.dateTime.month().day())) · \(last.workoutName)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
            if let best {
                Text("上次：\(last.sets.count) 组 · 工作均重 \(TrainingFormatters.weight(last.workingWeight)) kg · 最重 \(TrainingFormatters.weight(best.weight)) kg × \(best.reps)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("容量 \(Int(last.volume)) kg · 平均 RIR \(rir)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 11))
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

            Stepper("工作组：\(binding.wrappedValue.sets)", value: binding.sets, in: 1...10)
                .foregroundStyle(.white)

            HStack {
                Text("次数范围")
                    .foregroundStyle(.white)
                Spacer()
                TextField("最低", value: binding.minReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                Text("–")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("最高", value: binding.maxReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("建议重量")
                    .foregroundStyle(.white)
                Spacer()
                TextField(
                    "kg",
                    value: binding.weight,
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)
                Text("kg")
                    .foregroundStyle(AppTheme.secondaryText)
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
                sets: recommendation.suggestedSets,
                minReps: recommendation.minReps,
                maxReps: recommendation.maxReps,
                weight: recommendation.suggestedWeight,
                restSeconds: recommendation.restSeconds
            )
        }
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
    }

    private func targetBinding(for id: UUID) -> Binding<DailyExerciseTarget> {
        Binding {
            targets[id] ?? DailyExerciseTarget(sets: 3, minReps: 8, maxReps: 12, weight: 0, restSeconds: 90)
        } set: { newValue in
            targets[id] = newValue
        }
    }

    private func loadExistingPlan(for date: Date, force: Bool = false) {
        let targetDate = date.startOfDay
        if !force, loadedDate?.isSameDay(as: targetDate) == true { return }
        loadedDate = targetDate
        selectedMuscleGroups = []
        selectedExerciseIDs = []
        targets = [:]

        let candidates = schedules
            .filter { $0.plannedDate.isSameDay(as: targetDate) && $0.status == .planned }
            .sorted { left, right in
                let leftOneOff = templates.first(where: { $0.id == left.templateID })?.isOneOff == true
                let rightOneOff = templates.first(where: { $0.id == right.templateID })?.isOneOff == true
                if leftOneOff != rightOneOff { return leftOneOff }
                return left.createdAt > right.createdAt
            }
        guard let schedule = candidates.first,
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
                    sets: item.targetSets,
                    minReps: item.minReps,
                    maxReps: item.maxReps,
                    weight: item.targetWeight,
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
        let inputs = selectedExerciseIDs.compactMap { id -> DailyPlanExerciseInput? in
            guard let target = targets[id] else { return nil }
            return DailyPlanExerciseInput(
                exerciseID: id,
                targetSets: target.sets,
                minReps: target.minReps,
                maxReps: target.maxReps,
                targetWeight: target.weight,
                restSeconds: target.restSeconds
            )
        }

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
    var sets: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.sets },
            set: {
                var value = wrappedValue
                value.sets = $0
                wrappedValue = value
            }
        )
    }

    var minReps: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.minReps },
            set: {
                var value = wrappedValue
                value.minReps = $0
                wrappedValue = value
            }
        )
    }

    var maxReps: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.maxReps },
            set: {
                var value = wrappedValue
                value.maxReps = $0
                wrappedValue = value
            }
        )
    }

    var weight: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.weight },
            set: {
                var value = wrappedValue
                value.weight = $0
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

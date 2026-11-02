import SwiftUI

struct ExerciseSetupDraft: Equatable {
    var pattern: SetPlanPattern
    var plannedSets: [WorkoutSetPlan]
    var restSeconds: Int
    var previousDate: Date?
    var history: TrainingPlanHistory? = nil

    var measurementSide: MeasurementSide {
        plannedSets.first?.weightSide ?? .bilateral
    }

    func withSetCount(_ preferredCount: Int?) -> ExerciseSetupDraft {
        guard let preferredCount else { return self }
        let count = max(1, preferredCount)
        var draft = self
        draft.plannedSets = Array(plannedSets.prefix(count))
        let seed = draft.plannedSets.last ?? WorkoutSetPlan(weight: 0, reps: 8)
        while draft.plannedSets.count < count {
            draft.plannedSets.append(WorkoutSetPlan(weight: seed.weight, reps: seed.reps,
                weightSide: seed.weightSide, repsSide: seed.repsSide,
                actualDefaultPolicy: seed.actualDefaultPolicy))
        }
        return draft
    }

    static func suggested(
        for exercise: Exercise,
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        setLogs: [SetLog],
        schedules: [ScheduledWorkout] = [],
        fallbackSets: Int = 3,
        fallbackReps: Int = 8,
        fallbackWeight: Double = 0,
        defaultPattern: SetPlanPattern = .fixed
    ) -> ExerciseSetupDraft {
        let history = TrainingPlanHistory.resolve(exercise: exercise, before: .now,
            sessions: sessions, snapshots: sessionExercises, logs: setLogs, schedules: schedules)
        let reference = WorkoutHistoryResolver.latest(exerciseID: exercise.id, unit: exercise.volumeUnit,
            equipment: exercise.equipment, before: .now, sessions: sessions,
            snapshots: sessionExercises, logs: setLogs, schedules: schedules)
        if defaultPattern == .fixed, let reference, reference.equipmentVerified,
           reference.sets.indices.allSatisfy({ reference.prefillableSet(at: $0, unit: exercise.volumeUnit) != nil }) {
            return ExerciseSetupDraft(pattern: sessionExercises.first(where: {
                $0.sessionID == reference.sessionID && $0.exerciseID == exercise.id
            })?.planPattern ?? .fixed,
                plannedSets: reference.sets.map { WorkoutSetPlan(weight: exercise.volumeUnit.recordsNumericLoad ? $0.weight : 0,
                    reps: $0.reps, weightSide: $0.weightSide, repsSide: $0.repsSide, actualDefaultPolicy: .history) },
                restSeconds: reference.restSeconds, previousDate: reference.date, history: history)
        }
        let pattern = exercise.volumeUnit == .kilogram ? defaultPattern : .fixed
        var draft = ExerciseSetupDraft(pattern: pattern,
            plannedSets: history.initialPlans(pattern: pattern, count: fallbackSets,
                weight: exercise.volumeUnit.recordsNumericLoad ? fallbackWeight : 0, reps: fallbackReps),
            restSeconds: exercise.defaultRestSeconds, previousDate: nil, history: history)
        for index in draft.plannedSets.indices {
            guard let previous = reference?.prefillableSet(at: index, unit: exercise.volumeUnit) else { continue }
            draft.plannedSets[index].weight = exercise.volumeUnit.recordsNumericLoad ? previous.weight : 0
            draft.plannedSets[index].reps = previous.reps
            draft.plannedSets[index].weightSide = previous.weightSide
            draft.plannedSets[index].repsSide = previous.repsSide
            draft.plannedSets[index].actualDefaultPolicyRaw = WorkoutActualDefaultPolicy.history.rawValue
            draft.previousDate = reference?.date
        }
        return draft
    }
}

struct ExerciseSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let onConfirm: (ExerciseSetupDraft) -> Void

    @State private var draft: ExerciseSetupDraft

    init(
        exercise: Exercise,
        draft: ExerciseSetupDraft,
        onConfirm: @escaping (ExerciseSetupDraft) -> Void
    ) {
        self.exercise = exercise
        self.onConfirm = onConfirm
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SprintPageHeader(title: "本次设置", icon: "slider.horizontal.3", subtitle: "计划设置 · 可调整")
                    sourceCard
                    if let history = draft.history {
                        TrainingPlanHistoryComparison(history: history, plans: draft.plannedSets,
                            unit: exercise.volumeUnit, exerciseName: exercise.name)
                    }
                    if exercise.volumeUnit == .kilogram {
                        Picker("训练方式", selection: $draft.pattern) {
                            ForEach(SetPlanPattern.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("动作训练方式")
                        Text("请逐组设置实际可用的器械档位，组型不自动生成重量。").font(.caption)
                    }

                    if exercise.volumeUnit.usesMeasurementSide {
                        Picker("记录口径", selection: measurementSideBinding) {
                            ForEach(MeasurementSide.allCases) { side in
                                Text(side.title).tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("动作记录口径")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("组数：\(draft.plannedSets.count)", value: setCountBinding, in: 1...12)
                            .frame(minHeight: 44)
                        Picker("休息", selection: $draft.restSeconds) {
                            ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                                Text("\(seconds) 秒").tag(seconds)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        HStack {
                            Text("组").frame(width: 26)
                            if exercise.volumeUnit.recordsNumericLoad {
                                Text("\(exercise.volumeUnit.inputTitle) \(exercise.volumeUnit.symbol)")
                                    .frame(maxWidth: .infinity)
                            } else if exercise.volumeUnit == .bodyweight {
                                Text("负重").frame(maxWidth: .infinity)
                            }
                            Text(exercise.volumeUnit.recordsSingleAmount ? exercise.volumeUnit.symbol : exercise.volumeUnit.repetitionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        ForEach(draft.plannedSets.indices, id: \.self) { index in
                            setupRow(index)
                        }
                    }

                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    KeyboardDismissal.dismiss()
                    onConfirm(draft)
                    dismiss()
                } label: {
                    Label("使用设置", systemImage: "checkmark.circle.fill")
                        .neonButtonStyle()
                }
                .accessibilityIdentifier("使用上次设置")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AppTheme.background)
            }
            .background(AppTheme.background)
            .navigationTitle("本次设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { KeyboardDismissal.dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .sprintPage()
        .tint(AppTheme.ink)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.terminologyStandardNameZH ?? exercise.name)
                        .font(.headline.bold())
                    if let english = exercise.terminologyStandardNameEN, !english.isEmpty {
                        Text(english)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(draft.previousDate == nil ? (draft.history?.date == nil ? "首次设置" : "历史参考") : "上次实际默认")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
            }

            if let previousDate = draft.previousDate {
                Text("来自 \(previousDate.formatted(.dateTime.year().month().day())) 的完成记录；对应组使用上次实际默认，其余沿用默认。可逐组调整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if draft.history?.date != nil {
                Text("上次实际见逐组对比；自动建议与历史参考分开，缺项时逐组核对，不推算器械档位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无可核验的兼容记录，使用动作默认值；可调整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func setupRow(_ index: Int) -> some View {
        let binding = Binding<WorkoutSetPlan> {
            draft.plannedSets[index]
        } set: { draft.plannedSets[index] = $0 }

        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 26)

            if exercise.volumeUnit.recordsNumericLoad {
                TextField(
                    exercise.volumeUnit.symbol,
                    value: Binding(get: { draft.plannedSets[index].weight }, set: {
                        draft.plannedSets[index].weight = $0
                        draft.plannedSets[index].actualDefaultPolicyRaw = WorkoutActualDefaultPolicy.plan.rawValue
                    }),
                    format: .number.precision(.fractionLength(0...3))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            } else if exercise.volumeUnit == .bodyweight {
                Text("自重")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            TextField(
                exercise.volumeUnit.recordsSingleAmount
                    ? exercise.volumeUnit.inputTitle
                    : exercise.volumeUnit.repetitionTitle,
                value: binding.reps,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
        }
        .opacity(draft.previousDate == nil ? 0.82 : 1)
    }

    private var measurementSideBinding: Binding<MeasurementSide> {
        Binding {
            draft.measurementSide
        } set: { side in
            draft.plannedSets = draft.plannedSets.map { plan in
                WorkoutSetPlan(
                    id: plan.id,
                    weight: plan.weight,
                    reps: plan.reps,
                    weightSide: side,
                    repsSide: side,
                    actualDefaultPolicy: plan.actualDefaultPolicy
                )
            }
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
                            repsSide: seed.repsSide,
                            actualDefaultPolicy: seed.actualDefaultPolicy
                        )
                    )
                }
            } else if count < draft.plannedSets.count {
                draft.plannedSets.removeLast(draft.plannedSets.count - count)
            }
        }
    }
}

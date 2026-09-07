import SwiftUI

struct ExerciseSetupDraft: Equatable {
    var pattern: SetPlanPattern
    var plannedSets: [WorkoutSetPlan]
    var restSeconds: Int
    var previousDate: Date?

    var measurementSide: MeasurementSide {
        plannedSets.first?.weightSide ?? .bilateral
    }

    static func suggested(
        for exercise: Exercise,
        sessions: [WorkoutSession],
        sessionExercises: [SessionExercise],
        setLogs: [SetLog],
        fallbackSets: Int = 3,
        fallbackReps: Int = 8,
        fallbackWeight: Double = 0
    ) -> ExerciseSetupDraft {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let matchingSnapshots = sessionExercises
            .filter { $0.exerciseID == exercise.id }
            .sorted { left, right in
                let leftDate = sessionByID[left.sessionID]?.completedAt
                    ?? sessionByID[left.sessionID]?.startedAt
                    ?? .distantPast
                let rightDate = sessionByID[right.sessionID]?.completedAt
                    ?? sessionByID[right.sessionID]?.startedAt
                    ?? .distantPast
                return leftDate > rightDate
            }

        for snapshot in matchingSnapshots {
            let completed = setLogs
                .filter {
                    $0.sessionExerciseID == snapshot.id
                        && $0.isCompleted
                        && !$0.isWarmup
                }
                .sorted { $0.setNumber < $1.setNumber }
            guard !completed.isEmpty else { continue }
            let plans = completed.map { log in
                WorkoutSetPlan(
                    weight: exercise.volumeUnit.recordsNumericLoad ? log.actualWeight : 0,
                    reps: max(1, log.actualReps),
                    weightSide: log.actualWeightSide,
                    repsSide: log.actualWeightSide
                )
            }
            return ExerciseSetupDraft(
                pattern: snapshot.planPattern,
                plannedSets: plans,
                restSeconds: snapshot.restSeconds,
                previousDate: sessionByID[snapshot.sessionID]?.startedAt
            )
        }

        return ExerciseSetupDraft(
            pattern: .fixed,
            plannedSets: WorkoutSetPlan.preset(
                .fixed,
                count: fallbackSets,
                baseWeight: exercise.volumeUnit.recordsNumericLoad ? fallbackWeight : 0,
                baseReps: fallbackReps
            ),
            restSeconds: exercise.defaultRestSeconds,
            previousDate: nil
        )
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
                    sourceCard

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
                    Label("使用这些设置", systemImage: "checkmark.circle.fill")
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
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
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
                Text(draft.previousDate == nil ? "首次建议" : "沿用上次")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            if let previousDate = draft.previousDate {
                Text("来自 \(previousDate.formatted(.dateTime.year().month().day())) 的完成记录；可以直接使用，也可以调整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有完成记录，先用动作默认值；所有设置都可以调整。")
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
                    value: binding.weight,
                    format: .number.precision(.fractionLength(0...3))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            } else if exercise.volumeUnit == .bodyweight {
                Text("自重")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)
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
                    repsSide: side
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

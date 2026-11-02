import SwiftData
import SwiftUI

private struct HistoricalSetDraft: Identifiable {
    let id = UUID()
    var existingLogID: UUID?
    var weight: Double = 0
    var reps: Int = 10
    var rir: Int? = 2
    var weightSide: MeasurementSide = .bilateral
    var repsSide: MeasurementSide = .bilateral
    var restDurationText: String = ""

    init(
        weight: Double = 0,
        reps: Int = 10,
        rir: Int? = 2,
        existingLogID: UUID? = nil,
        weightSide: MeasurementSide = .bilateral,
        repsSide: MeasurementSide = .bilateral,
        restDurationSeconds: Int? = nil
    ) {
        self.existingLogID = existingLogID
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.weightSide = weightSide
        self.repsSide = repsSide
        restDurationText = restDurationSeconds.map(String.init) ?? ""
    }

    var restValidation: RestDurationInputValidation {
        RestDurationInput.validate(restDurationText)
    }
}

private struct HistoricalExerciseDraft: Identifiable {
    let id = UUID()
    var existingSnapshotID: UUID?
    let exerciseID: UUID
    var sets: [HistoricalSetDraft]
    var notes: String = ""
    var feeling: WorkoutFeeling?
    var isWarmup = false
    var plannedRestSeconds = 90
    var planNotes = ""
    var allowsEmpty = false
}

struct HistoricalWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let scheduleID: UUID?

    @State private var name = "补录训练"
    @State private var startedAt = Date.now.addingDays(-1)
    @State private var trainingDate = Date.now.addingDays(-1).startOfDay
    @State private var durationMinutes = 60
    @State private var hasExactStartTime = true
    @State private var hasDuration = true
    @State private var notes = ""
    @State private var drafts: [HistoricalExerciseDraft] = []
    @State private var existingSessionID: UUID?
    @State private var didLoadSchedule = false
    @State private var showExercisePicker = false
    @State private var errorMessage: String?

    init(scheduleID: UUID? = nil) {
        self.scheduleID = scheduleID
        _hasExactStartTime = State(initialValue: scheduleID == nil)
        _hasDuration = State(initialValue: scheduleID == nil)
    }

    var body: some View {
        Form {
            Section {
                SprintPageHeader(title: scheduleID == nil ? "补录训练" : "补录完成", icon: "clock.arrow.circlepath")
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                TextField("训练名称", text: $name)
                if scheduleID != nil {
                    LabeledContent("训练日期", value: trainingDate.formatted(date: .abbreviated, time: .omitted))
                    Toggle("知道具体开始时间", isOn: $hasExactStartTime)
                    if hasExactStartTime {
                        Text("具体开始时间按当前设备时区显示（\(TimeZone.current.identifier)），训练日期保持原安排。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DatePicker(
                    scheduleID == nil ? "开始时间" : "具体开始时间",
                    selection: $startedAt,
                    in: Date.now.addingDays(-3_650)...Date.now,
                    displayedComponents: scheduleID == nil ? [.date, .hourAndMinute] : [.hourAndMinute]
                )
                .opacity(hasExactStartTime ? 1 : 0)
                .frame(height: hasExactStartTime ? nil : 0)
                .disabled(!hasExactStartTime)
                if scheduleID != nil {
                    Toggle("知道训练时长", isOn: $hasDuration)
                }
                if hasDuration {
                    Stepper("训练时长：\(durationMinutes) 分钟", value: $durationMinutes, in: 1...360, step: 5)
                }
                TextField("整场训练备注", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                SprintSectionHeading(title: "训练信息", icon: "calendar")
            }

            Section {
                if drafts.isEmpty {
                    Text("添加过去训练中的动作，再按动作单位逐组填写训练量和 RIR。")
                        .foregroundStyle(.secondary)
                }

                ForEach($drafts) { $draft in
                    if let exercise = exercises.first(where: { $0.id == draft.exerciseID }) {
                    HistoricalExerciseEditor(
                            draft: $draft,
                            exercise: exercise,
                            onDelete: {
                                drafts.removeAll { $0.id == draft.id }
                            }
                        )
                    }
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("动作与完成组")
            } footer: {
                Text("训练量会按动作的单位分别计算。")
            }
        }
        .scrollContentBackground(.hidden)
        .sprintPage()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { KeyboardDismissal.dismiss() }
            }
        }
        .navigationTitle(scheduleID == nil ? "补录过去训练" : "补录完成情况")
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
        .alert("无法补录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .task {
            loadScheduledWorkoutIfNeeded()
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(
                title: "添加实际完成动作",
                excludedExerciseIDs: Set(drafts.map(\.exerciseID))
            ) { exercise in
                addExercise(exercise)
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        drafts.append(
            HistoricalExerciseDraft(
                existingSnapshotID: nil,
                exerciseID: exercise.id,
                sets: [
                    HistoricalSetDraft(),
                    HistoricalSetDraft(),
                    HistoricalSetDraft()
                ],
                plannedRestSeconds: exercise.defaultRestSeconds,
                planNotes: exercise.notes
            )
        )
    }

    private func save() {
        if let scheduleID {
            saveScheduled(scheduleID: scheduleID)
            return
        }
        let input = HistoricalWorkoutInput(
            name: name,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            notes: notes,
            exercises: drafts.map { draft in
                HistoricalExerciseInput(
                    exerciseID: draft.exerciseID,
                    sets: draft.sets.map {
                        HistoricalSetInput(
                            weight: $0.weight,
                            reps: $0.reps,
                            rir: $0.rir
                        )
                    },
                    performanceNotes: draft.notes
                )
            }
        )

        do {
            _ = try HistoricalWorkoutService.record(input, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadScheduledWorkoutIfNeeded() {
        guard let scheduleID, !didLoadSchedule else { return }
        didLoadSchedule = true
        do {
            let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(
                scheduleID: scheduleID,
                in: modelContext
            )
            existingSessionID = preparation.existingSessionID
            name = preparation.name
            trainingDate = preparation.date
            startedAt = preparation.startedAt ?? preparation.date.startOfDay
            hasExactStartTime = preparation.startedAt != nil
            if let duration = preparation.durationMinutes {
                durationMinutes = duration
                hasDuration = true
            } else {
                hasDuration = false
            }
            notes = preparation.notes
            drafts = preparation.exercises.map { item in
                HistoricalExerciseDraft(
                    existingSnapshotID: item.existingSnapshotID,
                    exerciseID: item.exerciseID,
                    sets: item.sets.map {
                        HistoricalSetDraft(
                            weight: $0.weight,
                            reps: $0.reps,
                            rir: $0.rir,
                            existingLogID: $0.existingLogID,
                            weightSide: $0.weightSide,
                            repsSide: $0.repsSide
                        )
                    },
                    notes: item.performanceNotes,
                    feeling: item.feeling,
                    isWarmup: item.isWarmup,
                    plannedRestSeconds: item.plannedRestSeconds,
                    planNotes: item.planNotes,
                    allowsEmpty: item.existingSnapshotID != nil && item.sets.isEmpty
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveScheduled(scheduleID: UUID) {
        let input = ScheduledWorkoutBackfillInput(
            scheduleID: scheduleID,
            existingSessionID: existingSessionID,
            name: name,
            date: trainingDate.startOfDay,
            startedAt: hasExactStartTime ? startedAt : nil,
            durationMinutes: hasDuration ? durationMinutes : nil,
            notes: notes,
            exercises: drafts.map { draft in
                ScheduledWorkoutBackfillExerciseInput(
                    existingSnapshotID: draft.existingSnapshotID,
                    exerciseID: draft.exerciseID,
                    sets: draft.sets.map {
                        ScheduledWorkoutBackfillSetInput(
                            existingLogID: $0.existingLogID,
                            weight: $0.weight,
                            reps: $0.reps,
                            rir: $0.rir,
                            weightSide: $0.weightSide,
                            repsSide: $0.repsSide
                        )
                    },
                    performanceNotes: draft.notes,
                    feeling: draft.feeling,
                    isWarmup: draft.isWarmup
                )
            }
        )
        do {
            _ = try HistoricalWorkoutService.recordScheduledBackfill(input, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HistoricalExerciseEditor: View {
    @Binding var draft: HistoricalExerciseDraft
    let exercise: Exercise
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.headline)
                    Text("\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.volumeUnit.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("删除动作")
            }

            HStack(alignment: .top, spacing: 8) {
                Label("原计划休息 \(draft.plannedRestSeconds) 秒", systemImage: "timer")
                if !draft.planNotes.isEmpty {
                    Text(draft.planNotes)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Stepper(
                "完成组数：\(draft.sets.count)",
                value: Binding(
                    get: { draft.sets.count },
                    set: { updateSetCount($0) }
                ),
                in: (draft.allowsEmpty ? 0 : 1)...10
            )

            HStack {
                Text("组").frame(width: 24)
                if exercise.volumeUnit.recordsSingleAmount {
                    Text("\(exercise.volumeUnit.inputTitle) \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                } else if exercise.volumeUnit == .bodyweight {
                    Text("负重").frame(maxWidth: .infinity)
                    Text("次数").frame(maxWidth: .infinity)
                } else {
                    Text("\(exercise.volumeUnit.inputTitle) \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                    Text(exercise.volumeUnit.repetitionTitle).frame(maxWidth: .infinity)
                }
                Text("RIR").frame(width: 54)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(draft.sets.indices), id: \.self) { index in
                VStack(spacing: 8) {
                    HStack {
                        Text("\(index + 1)")
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(width: 24)
                        if exercise.volumeUnit.recordsNumericLoad {
                            TextField(
                                exercise.volumeUnit.symbol,
                                value: $draft.sets[index].weight,
                                format: .number.precision(.fractionLength(0...3))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 44)
                            .frame(maxWidth: .infinity)
                        } else if exercise.volumeUnit == .bodyweight {
                            Text("自重")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity)
                        }

                        TextField(
                            exercise.volumeUnit.recordsSingleAmount
                                ? exercise.volumeUnit.inputTitle
                                : exercise.volumeUnit.repetitionTitle,
                            value: $draft.sets[index].reps,
                            format: .number
                        )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 44)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier(
                                "历史补录-\(exercise.name)-第\(index + 1)组-\(exercise.volumeUnit.inputTitle)"
                            )

                        Menu {
                            Button("不记录") { draft.sets[index].rir = nil }
                            ForEach(0...5, id: \.self) { value in
                                Button("RIR \(value)") { draft.sets[index].rir = value }
                            }
                        } label: {
                            Text(draft.sets[index].rir.map(String.init) ?? "–")
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 54, height: 44)
                        }
                        .accessibilityLabel("设置余力 RIR")
                    }

                    if exercise.volumeUnit.usesMeasurementSide {
                        HStack(spacing: 12) {
                            Menu {
                                ForEach(MeasurementSide.allCases) { side in
                                    Button(side.title) { draft.sets[index].weightSide = side }
                                }
                            } label: {
                                Label("重量：\(draft.sets[index].weightSide.title)", systemImage: "scalemass")
                            }
                            Menu {
                                ForEach(MeasurementSide.allCases) { side in
                                    Button(side.title) { draft.sets[index].repsSide = side }
                                }
                            } label: {
                                Label("次数：\(draft.sets[index].repsSide.title)", systemImage: "repeat")
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
            }

            Toggle("作为热身组", isOn: $draft.isWarmup)
            Picker("动作体感", selection: $draft.feeling) {
                Text("未记录").tag(Optional<WorkoutFeeling>.none)
                ForEach(WorkoutFeeling.allCases) { feeling in
                    Text("\(feeling.emoji) \(feeling.title)").tag(Optional(feeling))
                }
            }

            TextField("这个动作当时的状态或注意事项", text: $draft.notes, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(.vertical, 6)
    }

    private func updateSetCount(_ count: Int) {
        if count > draft.sets.count {
            let last = draft.sets.last ?? HistoricalSetDraft()
            draft.sets.append(
                contentsOf: (0..<(count - draft.sets.count)).map { _ in
                    HistoricalSetDraft(
                        weight: last.weight,
                        reps: last.reps,
                        rir: last.rir,
                        weightSide: last.weightSide,
                        repsSide: last.repsSide,
                        restDurationSeconds: nil
                    )
                }
            )
        } else if count < draft.sets.count {
            draft.sets.removeLast(draft.sets.count - count)
        }
    }

}

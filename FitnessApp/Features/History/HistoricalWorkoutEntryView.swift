import SwiftData
import SwiftUI

private struct HistoricalSetDraft: Identifiable {
    let id = UUID()
    var weight: Double = 0
    var reps: Int = 10
    var rir: Int? = 2
    var restDurationText: String = ""

    init(
        weight: Double = 0,
        reps: Int = 10,
        rir: Int? = 2,
        restDurationSeconds: Int? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.rir = rir
        restDurationText = restDurationSeconds.map(String.init) ?? ""
    }

    var restValidation: RestDurationInputValidation {
        RestDurationInput.validate(restDurationText)
    }
}

private struct HistoricalExerciseDraft: Identifiable {
    let id = UUID()
    let exerciseID: UUID
    var sets: [HistoricalSetDraft]
    var notes: String = ""
}

struct HistoricalWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var name = "补录训练"
    @State private var startedAt = Date.now.addingDays(-1)
    @State private var durationMinutes = 60
    @State private var notes = ""
    @State private var drafts: [HistoricalExerciseDraft] = []
    @State private var errorMessage: String?

    private var availableExercises: [Exercise] {
        exercises.filter { exercise in
            !exercise.isArchived && !drafts.contains { $0.exerciseID == exercise.id }
        }
    }

    var body: some View {
        Form {
            Section("训练信息") {
                TextField("训练名称", text: $name)
                DatePicker(
                    "开始时间",
                    selection: $startedAt,
                    in: Date.now.addingDays(-90)...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Stepper("训练时长：\(durationMinutes) 分钟", value: $durationMinutes, in: 5...240, step: 5)
                TextField("整场训练备注", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
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

                Menu {
                    ForEach(availableExercises) { exercise in
                        Button(exercise.name) {
                            addExercise(exercise)
                        }
                    }
                } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                }
                .disabled(availableExercises.isEmpty)
            } header: {
                Text("动作与完成组")
            } footer: {
                Text("训练量会按动作的单位计算；组后休息可按秒补录，最后一组没有后续训练时可留空。")
            }
        }
        .navigationTitle("补录过去训练")
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
    }

    private func addExercise(_ exercise: Exercise) {
        drafts.append(
            HistoricalExerciseDraft(
                exerciseID: exercise.id,
                sets: [
                    HistoricalSetDraft(),
                    HistoricalSetDraft(),
                    HistoricalSetDraft()
                ]
            )
        )
    }

    private func save() {
        if let error = drafts
            .flatMap(\.sets)
            .compactMap({ $0.restValidation.errorMessage })
            .first {
            errorMessage = error
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
                            rir: $0.rir,
                            restDurationSeconds: $0.restValidation.seconds
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
                }
            }

            Stepper(
                "完成组数：\(draft.sets.count)",
                value: Binding(
                    get: { draft.sets.count },
                    set: { updateSetCount($0) }
                ),
                in: 1...10
            )

            HStack {
                Text("组").frame(width: 24)
                if exercise.volumeUnit == .count {
                    Text("数量 个").frame(maxWidth: .infinity)
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
                            .frame(maxWidth: .infinity)
                        } else if exercise.volumeUnit == .bodyweight {
                            Text("自重")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.accent)
                                .frame(maxWidth: .infinity)
                        }

                        TextField(
                            exercise.volumeUnit == .count ? "数量" : exercise.volumeUnit.repetitionTitle,
                            value: $draft.sets[index].reps,
                            format: .number
                        )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)

                        Menu {
                            Button("不记录") { draft.sets[index].rir = nil }
                            ForEach(0...5, id: \.self) { value in
                                Button("RIR \(value)") { draft.sets[index].rir = value }
                            }
                        } label: {
                            Text(draft.sets[index].rir.map(String.init) ?? "–")
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 54)
                        }
                    }

                    HStack {
                        Label("组后休息", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("未记录", text: restDurationBinding(at: index))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)
                            .accessibilityLabel("第 \(index + 1) 组休息秒数")
                            .accessibilityIdentifier("历史补录第 \(index + 1) 组休息秒数")
                        Text("秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = draft.sets[index].restValidation.errorMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("第 \(index + 1) 组休息秒数错误")
                    }
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
                        restDurationSeconds: nil
                    )
                }
            )
        } else if count < draft.sets.count {
            draft.sets.removeLast(draft.sets.count - count)
        }
    }

    private func restDurationBinding(at index: Int) -> Binding<String> {
        $draft.sets[index].restDurationText
    }
}

import SwiftData
import SwiftUI

enum MuscleGroupCatalogService {
    static let commonChoices = [
        "胸部", "背部", "肩部", "手臂", "腿部", "臀部", "小腿", "核心"
    ]
    static let customChoice = "其他"
}

struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]

    private let exercise: Exercise?
    private let onSave: ((Exercise) -> Void)?

    @State private var name: String
    @State private var muscleGroup: String
    @State private var muscleGroupChoice: String
    @State private var equipment: String
    @State private var equipmentChoice: String
    @State private var volumeUnit: ExerciseVolumeUnit
    @State private var restSeconds: Int
    @State private var notes: String
    @State private var referenceURL: String
    @State private var errorMessage: String?

    init(
        exercise: Exercise? = nil,
        initialName: String = "",
        initialMuscleGroup: String = "",
        initialNotes: String = "",
        initialReferenceURL: String = "",
        onSave: ((Exercise) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.onSave = onSave

        _name = State(initialValue: exercise?.name ?? initialName)
        let resolvedMuscleGroup = exercise?.muscleGroup
            ?? (initialMuscleGroup.isEmpty ? MuscleGroupCatalogService.customChoice : initialMuscleGroup)
        _muscleGroup = State(initialValue: resolvedMuscleGroup)
        _muscleGroupChoice = State(
            initialValue: MuscleGroupCatalogService.commonChoices.contains(resolvedMuscleGroup)
                ? resolvedMuscleGroup
                : MuscleGroupCatalogService.customChoice
        )
        let initialEquipment = exercise?.equipment ?? "自重"
        _equipment = State(initialValue: initialEquipment)
        _equipmentChoice = State(
            initialValue: EquipmentCatalogService.commonChoices.contains(initialEquipment)
                ? initialEquipment
                : "其他"
        )
        _volumeUnit = State(initialValue: exercise?.volumeUnit ?? .kilogram)
        _restSeconds = State(initialValue: exercise?.defaultRestSeconds ?? 90)
        _notes = State(initialValue: exercise?.notes ?? initialNotes)
        _referenceURL = State(initialValue: exercise?.referenceURL ?? initialReferenceURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("动作信息") {
                    TextField("动作名称", text: $name)
                        .textInputAutocapitalization(.never)
                    Picker("目标肌群", selection: $muscleGroupChoice) {
                        ForEach(MuscleGroupCatalogService.commonChoices, id: \.self) { choice in
                            Text(choice)
                                .accessibilityIdentifier("muscle-group-option-\(choice)")
                                .tag(choice)
                        }
                        Text(MuscleGroupCatalogService.customChoice)
                            .accessibilityIdentifier("muscle-group-option-其他")
                            .tag(MuscleGroupCatalogService.customChoice)
                    }
                    .accessibilityIdentifier("muscle-group-picker")
                    .accessibilityValue(muscleGroupChoice)
                    .onChange(of: muscleGroupChoice) { _, choice in
                        if choice != MuscleGroupCatalogService.customChoice {
                            muscleGroup = choice
                        } else if MuscleGroupCatalogService.commonChoices.contains(muscleGroup) {
                            muscleGroup = MuscleGroupCatalogService.customChoice
                        }
                    }

                    if muscleGroupChoice == MuscleGroupCatalogService.customChoice {
                        TextField("输入目标肌群", text: $muscleGroup)
                            .accessibilityIdentifier("custom-muscle-group-field")
                    }
                    Picker("器械类型", selection: $equipmentChoice) {
                        ForEach(EquipmentCatalogService.commonChoices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                        Text("其他").tag("其他")
                    }
                    .accessibilityIdentifier("equipment-picker")
                    .onChange(of: equipmentChoice) { _, choice in
                        if choice != "其他" {
                            equipment = choice
                        } else if EquipmentCatalogService.commonChoices.contains(equipment) {
                            equipment = ""
                        }
                    }

                    if equipmentChoice == "其他" {
                        TextField("输入器械名称", text: $equipment)
                            .accessibilityIdentifier("custom-equipment-field")
                    }
                    if let equipmentEN = EquipmentCatalogService.englishName(for: equipment) {
                        Text("标准英文：\(equipmentEN)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("训练量单位", selection: $volumeUnit) {
                        ForEach(ExerciseVolumeUnit.allCases) { unit in
                            Text(unit.title)
                                .accessibilityIdentifier("volume-unit-\(unit.rawValue)")
                                .tag(unit)
                        }
                    }
                    .accessibilityIdentifier("volume-unit-picker")
                    Text("个：直接记录数量；米：每趟距离 × 趟数；kg：重量 × 次数；自重：只记录完成次数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("默认休息", selection: $restSeconds) {
                        ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                            Text("\(seconds) 秒").tag(seconds)
                        }
                    }
                }

                Section {
                    TextField("参考链接（可选）", text: $referenceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("最多 40 字，只写最重要的动作提醒", text: $notes, axis: .vertical)
                        .lineLimit(1...2)
                    HStack {
                        Text("训练时会放在动作名称下方。")
                        Spacer()
                        Text("\(notes.count)/40")
                            .foregroundStyle(notes.count > 40 ? .red : .secondary)
                    }
                    .font(.caption2)
                } header: {
                    Text("学习资料")
                } footer: {
                    Text("可保存你学习这个动作时使用的视频或文章链接。")
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
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || equipment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || (notes.count > 40 && notes != exercise?.notes)
                        )
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

    private func save() {
        do {
            let result = try ExerciseCatalogService.save(
                exercise: exercise,
                name: name,
                muscleGroup: muscleGroup,
                equipment: equipment,
                volumeUnit: volumeUnit,
                defaultRestSeconds: restSeconds,
                notes: notes,
                referenceURL: referenceURL,
                allExercises: allExercises,
                in: modelContext
            )
            onSave?(result.exercise)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

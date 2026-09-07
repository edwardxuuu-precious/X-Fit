import SwiftData
import SwiftUI

struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]

    private let title: String
    private let initialMuscleGroup: String
    private let excludedExerciseIDs: Set<UUID>
    private let onSelect: (Exercise) -> Void
    private let onConfiguredSelect: ((Exercise, ExerciseSetupDraft) -> Void)?

    @State private var searchText: String
    @State private var showExerciseEditor = false
    @State private var editingExercise: Exercise?
    @State private var showEquipmentRecognition = false
    @State private var pendingSelection: Exercise?
    @State private var pendingSetupExercise: Exercise?
    @State private var errorMessage: String?
    @State private var selectedGroups: Set<String> = []
    @State private var searchPresented = false

    init(
        title: String = "添加动作",
        initialName: String = "",
        initialMuscleGroup: String = "",
        excludedExerciseIDs: Set<UUID> = [],
        onConfiguredSelect: ((Exercise, ExerciseSetupDraft) -> Void)? = nil,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.title = title
        self.initialMuscleGroup = initialMuscleGroup
        self.excludedExerciseIDs = excludedExerciseIDs
        self.onConfiguredSelect = onConfiguredSelect
        self.onSelect = onSelect
        _searchText = State(initialValue: initialName)
    }

    private var availableExercises: [Exercise] {
        ExerciseCatalogService.search(
            exercises,
            query: searchText,
            excludedExerciseIDs: excludedExerciseIDs
        ).filter { exercise in
            selectedGroups.isEmpty || !MuscleCoverageService.groups(in: exercise.muscleGroup).isDisjoint(with: selectedGroups)
                || selectedGroups.contains(exercise.muscleGroup)
        }
    }

    private var proposedExerciseName: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if searchPresented {
                        Button {
                            KeyboardDismissal.dismiss()
                        } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("动作搜索-收起键盘")
                    }
                    NavigationLink {
                        ExerciseMuscleFilterScreen(selectedGroups: $selectedGroups)
                    } label: {
                        Label(selectedGroups.isEmpty ? "按肌群选择" : selectedGroups.sorted().joined(separator: " · "), systemImage: "figure.stand")
                            .font(.subheadline)
                    }.accessibilityIdentifier("打开肌群图筛选")
                    if !selectedGroups.isEmpty {
                        Button("清除肌群筛选") { selectedGroups.removeAll() }.font(.caption)
                    }
                }
                if availableExercises.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(availableExercises) { exercise in
                            exerciseButton(exercise)
                        }
                    } footer: {
                        if !searchText.isEmpty {
                            Text("支持中文、英文双向模糊搜索，也会匹配肌群、器械、备注和参考链接。")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardWhenScrolling {
                KeyboardDismissal.dismiss()
            }
            .searchable(text: $searchText, isPresented: $searchPresented, prompt: "搜索全部动作")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showEquipmentRecognition = true
                    } label: {
                        Label("拍照识别器械", systemImage: "camera.viewfinder")
                    }
                    Button {
                        showExerciseEditor = true
                    } label: {
                        Label("新建动作", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showExerciseEditor) {
            ExerciseEditorView(
                initialName: proposedExerciseName,
                initialMuscleGroup: initialMuscleGroup,
                onSave: { exercise in
                    pendingSelection = exercise
                }
            )
        }
            .sheet(item: $editingExercise) { exercise in
            ExerciseEditorView(exercise: exercise)
        }
            .sheet(isPresented: $showEquipmentRecognition) {
            EquipmentRecognitionSheet { exercise, draft in
                showEquipmentRecognition = false
                if let onConfiguredSelect {
                    onConfiguredSelect(exercise, draft)
                } else {
                    onSelect(exercise)
                }
                dismiss()
            }
        }
            .sheet(item: $pendingSetupExercise) { exercise in
            ExerciseSetupSheet(
                exercise: exercise,
                draft: ExerciseSetupDraft.suggested(
                    for: exercise,
                    sessions: sessions,
                    sessionExercises: sessionExercises,
                    setLogs: setLogs
                )
            ) { draft in
                onConfiguredSelect?(exercise, draft)
                dismiss()
            }
        }
            .onChange(of: showExerciseEditor) { _, isShowing in
            guard !isShowing, let pendingSelection else { return }
            self.pendingSelection = nil
            selectAndDismiss(pendingSelection)
        }
            .alert("无法添加动作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
            )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
            Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(proposedExerciseName.isEmpty ? "没有可添加的动作" : "没有找到“\(proposedExerciseName)”")
                    .font(.headline)
                Text(
                    proposedExerciseName.isEmpty
                        ? "可以立即创建一个自己的动作。"
                        : "可以创建这个动作，或修改搜索词。"
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showExerciseEditor = true
            } label: {
                Label(
                    proposedExerciseName.isEmpty ? "新建动作" : "新建并加入",
                    systemImage: "plus.circle.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Button("取消并返回") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 24)
    }

    private func exerciseButton(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            Button {
                if exercise.isArchived {
                    restoreAndSelect(exercise)
                } else {
                    selectAndDismiss(exercise)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: exercise.isArchived ? "arrow.uturn.backward.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(exercise.isArchived ? .orange : AppTheme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(exercise.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if exercise.isArchived {
                                Text("已归档")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }

                        Text(
                            "\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.volumeUnit.symbol) · 默认休息 \(exercise.defaultRestSeconds) 秒"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let english = exercise.terminologyStandardNameEN, !english.isEmpty {
                            Text(english)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let equipmentEN = EquipmentCatalogService.englishName(for: exercise.equipment) {
                            Text("\(exercise.equipment) / \(equipmentEN)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if exercise.isArchived {
                        Text("恢复")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    KeyboardDismissal.dismiss()
                    editingExercise = exercise
                } label: {
                    Label("编辑动作定义", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("编辑\(exercise.name)的动作定义")
            .accessibilityIdentifier("exercise-definition-menu-\(exercise.name)")
        }
    }

    private func restoreAndSelect(_ exercise: Exercise) {
        do {
            let restoredExercise = try ExerciseCatalogService.restore(exercise, in: modelContext)
            selectAndDismiss(restoredExercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectAndDismiss(_ exercise: Exercise) {
        KeyboardDismissal.dismiss()
        if onConfiguredSelect != nil {
            pendingSetupExercise = exercise
            return
        }
        onSelect(exercise)
        dismiss()
    }
}

private struct ExerciseMuscleFilterScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGroups: Set<String>

    var body: some View {
        ScrollView {
            MuscleSelectionView(selectedGroups: $selectedGroups)
                .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("选择肌群")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}

import SwiftData
import SwiftUI

struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var schedules: [ScheduledWorkout]
    @Query private var preferences: [TrainingPreferenceRevision]

    private let title: String
    private let initialMuscleGroup: String
    private let excludedExerciseIDs: Set<UUID>
    private let defaultSetCount: Int?
    private let onSelect: (Exercise) -> Void
    private let onConfiguredSelect: ((Exercise, ExerciseSetupDraft) -> Void)?

    @State private var searchText: String
    @State private var cachedSearchResults: [Exercise] = []
    @State private var showExerciseEditor = false
    @State private var editingExercise: Exercise?
    @State private var showEquipmentRecognition = false
    @State private var pendingSelection: Exercise?
    @State private var pendingSetupExercise: Exercise?
    @State private var errorMessage: String?
    @State private var selectedGroups: Set<String> = []
    @State private var searchPresented = false
    @State private var profilingOwner = "exercise-picker-\(UUID().uuidString)"

    init(
        title: String = "添加动作",
        initialName: String = "",
        initialMuscleGroup: String = "",
        excludedExerciseIDs: Set<UUID> = [],
        defaultSetCount: Int? = nil,
        onConfiguredSelect: ((Exercise, ExerciseSetupDraft) -> Void)? = nil,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.title = title
        self.initialMuscleGroup = initialMuscleGroup
        self.excludedExerciseIDs = excludedExerciseIDs
        self.defaultSetCount = defaultSetCount
        self.onConfiguredSelect = onConfiguredSelect
        self.onSelect = onSelect
        _searchText = State(initialValue: initialName)
    }

    private var availableExercises: [Exercise] {
        cachedSearchResults.filter { exercise in
            selectedGroups.isEmpty || !MuscleCoverageService.groups(in: exercise.muscleGroup).isDisjoint(with: selectedGroups)
                || selectedGroups.contains(exercise.muscleGroup)
                || ExerciseMuscleTaxonomy.filterCategories(name: exercise.name, muscleGroup: exercise.muscleGroup)
                    .contains { selectedGroups.contains($0.majorGroup) }
        }
    }

    private var proposedExerciseName: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SprintPageHeader(title: title, icon: "dumbbell")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    BufferedExerciseSearchField(text: $searchText, isEditing: $searchPresented)
                        .frame(height: 44)
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
                    NavigationLink {
                        ExternalExerciseCatalogView(initialQuery: searchText,
                            excludedExerciseIDs: excludedExerciseIDs) { exercise in
                            selectAndDismiss(exercise)
                        }
                    } label: {
                        Label("扩展动作库 · 1,324", systemImage: "books.vertical")
                    }
                    .accessibilityIdentifier("打开扩展动作库")
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
            .scrollContentBackground(.hidden)
            .sprintPage()
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardWhenScrolling {
                KeyboardDismissal.dismiss()
            }
            .onAppear {
                refreshSearchResults()
                WorkoutInputProfiler.shared.start(owner: profilingOwner)
            }
            .onDisappear { WorkoutInputProfiler.shared.stop(owner: profilingOwner) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { WorkoutInputProfiler.shared.start(owner: profilingOwner) }
                else { WorkoutInputProfiler.shared.stop(owner: profilingOwner) }
            }
            .onChange(of: searchText) { _, _ in refreshSearchResults() }
            .onChange(of: exercises.map(ExerciseSearchRevision.init)) { _, _ in refreshSearchResults() }
            .onChange(of: excludedExerciseIDs) { _, _ in refreshSearchResults() }
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
                        KeyboardDismissal.dismiss()
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
            EquipmentRecognitionSheet(defaultSetCount: defaultSetCount) { exercise, draft in
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
                draft: setupDraft(for: exercise)
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
            SprintIcon(systemName: "dumbbell", size: 56, prominent: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                KeyboardDismissal.dismiss()
                showExerciseEditor = true
            } label: {
                Label(
                    proposedExerciseName.isEmpty ? "新建动作" : "新建并加入",
                    systemImage: "plus.circle.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SprintPrimaryButtonStyle())
            .tint(AppTheme.ink)

            Button("取消并返回") {
                dismiss()
            }
            .buttonStyle(SprintSecondaryButtonStyle())
        }
        .padding(.vertical, 24)
    }

    private func refreshSearchResults() {
        cachedSearchResults = ExerciseCatalogService.search(
            exercises, query: searchText, excludedExerciseIDs: excludedExerciseIDs
        )
    }

    private func setupDraft(for exercise: Exercise) -> ExerciseSetupDraft {
        ExerciseSetupDraft.suggested(
            for: exercise, sessions: sessions, sessionExercises: sessionExercises,
            setLogs: setLogs, schedules: schedules,
            fallbackSets: defaultSetCount
                ?? TrainingPreferenceService.effective(preferences)?.snapshot?.defaultSetCount(for: exercise.muscleGroup) ?? 3,
            defaultPattern: TrainingPreferenceService.effective(preferences)?.snapshot?.defaultPattern(for: exercise) ?? .fixed
        ).withSetCount(defaultSetCount)
    }

    private func exerciseButton(_ exercise: Exercise) -> some View {
        let mergedPrimary = ExerciseCatalogService.mergedPrimary(for: exercise, among: exercises)
        return HStack(spacing: 12) {
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
                        .foregroundStyle(exercise.isArchived ? .orange : AppTheme.ink)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(exercise.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if exercise.isArchived {
                                Text(mergedPrimary == nil ? "已归档" : "已合并")
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
                        if let summary = ExerciseCatalogService.muscleSummary(for: exercise) {
                            Text(summary).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let mergedPrimary {
                            Text("已合并至\(mergedPrimary.name)，保留历史记录")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    if exercise.isArchived {
                        Text(mergedPrimary == nil ? "恢复" : "使用主动作")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercise-picker-option-\(exercise.id.uuidString)")

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

private struct ExerciseSearchRevision: Equatable {
    let id: UUID
    let values: [String]
    let archived: Bool

    init(_ exercise: Exercise) {
        id = exercise.id
        values = [exercise.name, exercise.muscleGroup, exercise.equipment, exercise.notes,
            exercise.referenceURL, exercise.terminologyCanonicalID ?? "",
            exercise.terminologyStandardNameZH ?? "", exercise.terminologyStandardNameEN ?? "",
            exercise.terminologyDecisionRaw ?? ""]
        archived = exercise.isArchived
    }
}

/// UISearchBar preserves the native search-field accessibility and Chinese IME.
/// Intermediate marked text never invalidates the SwiftUI list or catalog search.
struct BufferedExerciseSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = "搜索全部动作"
        bar.searchTextField.accessibilityLabel = "搜索全部动作"
        bar.searchTextField.accessibilityIdentifier = "exercise-search-field"
        bar.autocapitalizationType = .none
        bar.text = text
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        guard !bar.searchTextField.isFirstResponder, bar.searchTextField.markedTextRange == nil,
              bar.text != text else { return }
        bar.text = text
        context.coordinator.input = ExerciseSearchInputState(initialQuery: text)
    }

    static func dismantleUIView(_ bar: UISearchBar, coordinator: Coordinator) {
        coordinator.pending?.cancel()
        bar.delegate = nil
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: BufferedExerciseSearchField
        var input: ExerciseSearchInputState
        var pending: DispatchWorkItem?

        init(parent: BufferedExerciseSearchField) {
            self.parent = parent
            input = ExerciseSearchInputState(initialQuery: parent.text)
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            WorkoutInputProfiler.shared.inputReceived()
            pending?.cancel()
            let composing = searchBar.searchTextField.markedTextRange != nil
            input.receive(searchText, isComposing: composing, at: ProcessInfo.processInfo.systemUptime)
            guard !composing else { return }
            let work = DispatchWorkItem { [weak self] in self?.publish(force: false) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { parent.isEditing = true }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            pending?.cancel()
            input.receive(searchBar.text ?? "", isComposing: searchBar.searchTextField.markedTextRange != nil,
                at: ProcessInfo.processInfo.systemUptime)
            publish(force: true)
            parent.isEditing = false
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.searchTextField.resignFirstResponder() }

        private func publish(force: Bool) {
            if let value = input.publishIfReady(at: ProcessInfo.processInfo.systemUptime, force: force) {
                parent.text = value
            }
        }
    }
}

private struct ExerciseMuscleFilterScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGroups: Set<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SprintPageHeader(title: "选择肌群", icon: "figure.stand")
                MuscleSelectionView(selectedGroups: $selectedGroups)
            }
            .padding(20)
        }
        .sprintPage()
        .navigationTitle("选择肌群")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}

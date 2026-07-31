import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [WorkoutTemplate]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var exercises: [Exercise]
    @Query private var schedules: [ScheduledWorkout]

    @State private var showEditor = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var pendingDelete: WorkoutTemplate?
    @State private var selectedMode = 0
    @State private var selectedMuscleGroup = "全部"
    @State private var searchText = ""
    @State private var showExerciseEditor = false
    @State private var editingExercise: Exercise?
    @State private var showArchivedExercises = false

    private var sortedTemplates: [WorkoutTemplate] {
        templates
            .filter { !$0.isOneOff }
            .sorted {
            let left = WeekdayName.orderedCalendarValues.firstIndex(of: $0.weekday) ?? 99
            let right = WeekdayName.orderedCalendarValues.firstIndex(of: $1.weekday) ?? 99
            return left == right ? $0.createdAt < $1.createdAt : left < right
        }
    }

    private var muscleGroups: [String] {
        ["全部"] + Array(Set(exercises.filter { !$0.isArchived }.map(\.muscleGroup))).sorted()
    }

    private var filteredExercises: [Exercise] {
        exercises
            .filter { showArchivedExercises ? $0.isArchived : !$0.isArchived }
            .filter { selectedMuscleGroup == "全部" || $0.muscleGroup == selectedMuscleGroup }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(
                eyebrow: "WORKOUT CENTER",
                title: "训练",
                trailingSystemImage: selectedMode == 0 ? nil : "plus",
                trailingAccessibilityLabel: selectedMode == 1 ? "新建固定计划" : "新建动作",
                trailingAction: {
                    if selectedMode == 1 {
                        editingTemplate = nil
                        showEditor = true
                    } else if selectedMode == 2 {
                        editingExercise = nil
                        showExerciseEditor = true
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            modePicker
                .padding(.horizontal, 16)

            if selectedMode == 0 {
                DailyWorkoutBuilderView(isEmbedded: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if selectedMode == 1 {
                            if let featured = sortedTemplates.first {
                                featuredWorkout(featured)
                            }
                            weekOverview

                            SectionHeader(title: "我的固定计划", actionTitle: "\(sortedTemplates.count) 个")
                            ForEach(sortedTemplates) { template in
                                templateCard(template)
                                    .contextMenu {
                                        Button {
                                            edit(template)
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            pendingDelete = template
                                        } label: {
                                            Label("删除计划", systemImage: "trash")
                                        }
                                    }
                            }
                        } else {
                            exerciseLibrary
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditor) {
            TemplateEditorView(template: editingTemplate)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(isPresented: $showExerciseEditor) {
            ExerciseEditorView(exercise: editingExercise)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .alert("删除这个训练计划？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    delete(pendingDelete)
                }
            }
        } message: {
            Text("历史训练不会被删除，尚未开始的未来安排会同步移除。")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("今日编排", value: 0)
            modeButton("固定计划", value: 1)
            modeButton("动作库", value: 2)
        }
        .padding(4)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))
    }

    private func modeButton(_ title: String, value: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedMode = value
            }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(selectedMode == value ? .black : AppTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selectedMode == value ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func featuredWorkout(_ template: WorkoutTemplate) -> some View {
        let items = templateExercises.filter { $0.templateID == template.id }
        let totalSets = items.reduce(0) { $0 + $1.targetSets }

        return ZStack(alignment: .bottomLeading) {
            HeroWorkoutImage()
                .frame(height: 225)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.96)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED WORKOUT")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.accent)
                Text(template.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("\(items.count) 个动作 · \(totalSets) 个工作组 · 约 \(max(30, totalSets * 3)) 分钟")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))

                Button {
                    edit(template)
                } label: {
                    Label("查看训练计划", systemImage: "arrow.right")
                        .neonButtonStyle()
                }
            }
            .padding(17)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 1))
    }

    private var weekOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周训练")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("\(templates.filter(\.isActive).count) 个训练日")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 7) {
                ForEach(WeekdayName.orderedCalendarValues, id: \.self) { weekday in
                    let isTrainingDay = templates.contains { $0.weekday == weekday && $0.isActive }
                    VStack(spacing: 7) {
                        Text(WeekdayName.short(weekday).replacingOccurrences(of: "周", with: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Circle()
                            .fill(isTrainingDay ? AppTheme.accent : AppTheme.elevatedSurface)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if isTrainingDay {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.black)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cardSurface()
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        let items = templateExercises
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }

        return Button {
            edit(template)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Image(systemName: templateIcon(template))
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(WeekdayName.short(template.weekday))
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.accent)
                        Text(template.name)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Divider().overlay(AppTheme.line)

                ForEach(items.prefix(4)) { item in
                    HStack {
                        Text(exerciseName(item.exerciseID))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.targetSets) × \(item.minReps)–\(item.maxReps) · \(TrainingFormatters.weight(item.targetWeight))kg")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                if items.count > 4 {
                    Text("另有 \(items.count - 4) 个动作")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("搜索动作…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.line, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(muscleGroups, id: \.self) { group in
                        Button(group) {
                            selectedMuscleGroup = group
                        }
                        .font(.caption.bold())
                        .foregroundStyle(selectedMuscleGroup == group ? .black : AppTheme.secondaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(selectedMuscleGroup == group ? AppTheme.accent : AppTheme.surface, in: Capsule())
                    }
                }
            }

            SectionHeader(title: "动作库", actionTitle: "\(filteredExercises.count) 个动作")

            Button {
                showArchivedExercises.toggle()
                if showArchivedExercises {
                    selectedMuscleGroup = "全部"
                }
            } label: {
                Label(
                    showArchivedExercises ? "返回可用动作" : "查看已归档动作",
                    systemImage: showArchivedExercises ? "arrow.uturn.backward" : "archivebox"
                )
                .font(.caption.bold())
                .foregroundStyle(showArchivedExercises ? AppTheme.accent : AppTheme.secondaryText)
            }

            LazyVStack(spacing: 10) {
                ForEach(filteredExercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(AppTheme.elevatedSurface)
                Image(systemName: exerciseIcon(exercise.muscleGroup))
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("\(exercise.muscleGroup) · \(exercise.equipment) · 休息 \(exercise.defaultRestSeconds) 秒")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(exercise.isBuiltIn ? "内置" : "自定义")
                .font(.caption2.bold())
                .foregroundStyle(exercise.isBuiltIn ? AppTheme.secondaryText : AppTheme.accent)
            Image(systemName: exercise.isArchived ? "archivebox.fill" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(exercise.isArchived ? .orange : AppTheme.secondaryText)
        }
        .cardSurface(padding: 12, cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !exercise.isBuiltIn, !exercise.isArchived else { return }
            editingExercise = exercise
            showExerciseEditor = true
        }
        .contextMenu {
            if !exercise.isBuiltIn && !exercise.isArchived {
                Button {
                    editingExercise = exercise
                    showExerciseEditor = true
                } label: {
                    Label("编辑动作", systemImage: "pencil")
                }
            }
            Button {
                setArchived(exercise, archived: !exercise.isArchived)
            } label: {
                Label(
                    exercise.isArchived ? "恢复动作" : "归档动作",
                    systemImage: exercise.isArchived ? "arrow.uturn.backward" : "archivebox"
                )
            }
        }
    }

    private func exerciseIcon(_ muscleGroup: String) -> String {
        switch muscleGroup {
        case "腿部", "小腿": return "figure.strengthtraining.functional"
        case "背部": return "figure.rower"
        case "肩部": return "figure.cross.training"
        case "手臂": return "dumbbell.fill"
        default: return "figure.strengthtraining.traditional"
        }
    }

    private func templateIcon(_ template: WorkoutTemplate) -> String {
        if template.name.contains("腿") { return "figure.strengthtraining.functional" }
        if template.name.contains("拉") { return "figure.rower" }
        return "dumbbell.fill"
    }

    private func exerciseName(_ id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "未知动作"
    }

    private func edit(_ template: WorkoutTemplate) {
        editingTemplate = template
        showEditor = true
    }

    private func setArchived(_ exercise: Exercise, archived: Bool) {
        exercise.isArchived = archived
        exercise.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            assertionFailure("更新动作归档状态失败：\(error)")
        }
    }

    private func delete(_ template: WorkoutTemplate) {
        templateExercises
            .filter { $0.templateID == template.id }
            .forEach(modelContext.delete)
        schedules
            .filter { $0.templateID == template.id && $0.status == .planned }
            .forEach(modelContext.delete)
        modelContext.delete(template)

        do {
            try modelContext.save()
        } catch {
            assertionFailure("删除训练计划失败：\(error)")
        }
        pendingDelete = nil
    }
}

private struct ExerciseDraft: Identifiable {
    let id: UUID
    var storedItemID: UUID?
    var exerciseID: UUID
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int
}

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]
    @Query private var storedItems: [TemplateExercise]

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var weekday: Int
    @State private var isActive: Bool
    @State private var drafts: [ExerciseDraft] = []
    @State private var errorMessage: String?

    init(template: WorkoutTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "新训练计划")
        _weekday = State(initialValue: template?.weekday ?? Date.now.weekdayNumber)
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("计划名称", text: $name)
                    Picker("训练日", selection: $weekday) {
                        ForEach(WeekdayName.orderedCalendarValues, id: \.self) { day in
                            Text(WeekdayName.short(day)).tag(day)
                        }
                    }
                    Toggle("加入每周计划", isOn: $isActive)
                }

                Section {
                    if drafts.isEmpty {
                        Text("还没有动作，请从动作库添加。")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($drafts) { $draft in
                        DraftExerciseEditor(
                            draft: $draft,
                            exercise: exercises.first { $0.id == draft.exerciseID }
                        )
                    }
                    .onDelete { offsets in
                        drafts.remove(atOffsets: offsets)
                    }

                    Menu {
                        ForEach(availableExercises) { exercise in
                            Button(exercise.name) {
                                add(exercise)
                            }
                        }
                    } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                    }
                    .disabled(availableExercises.isEmpty)
                } header: {
                    Text("动作与目标")
                } footer: {
                    Text("重量和次数是下次开始训练时的默认值；历史记录会保留当时的独立快照。")
                }
            }
            .navigationTitle(template == nil ? "新建计划" : "编辑计划")
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
            .onAppear(perform: loadDrafts)
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

    private var availableExercises: [Exercise] {
        exercises.filter { exercise in
            !exercise.isArchived && !drafts.contains { $0.exerciseID == exercise.id }
        }
    }

    private func loadDrafts() {
        guard drafts.isEmpty, let template else { return }
        drafts = storedItems
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }
            .map {
                ExerciseDraft(
                    id: UUID(),
                    storedItemID: $0.id,
                    exerciseID: $0.exerciseID,
                    targetSets: $0.targetSets,
                    minReps: $0.minReps,
                    maxReps: $0.maxReps,
                    targetWeight: $0.targetWeight,
                    restSeconds: $0.restSeconds
                )
            }
    }

    private func add(_ exercise: Exercise) {
        drafts.append(
            ExerciseDraft(
                id: UUID(),
                storedItemID: nil,
                exerciseID: exercise.id,
                targetSets: 3,
                minReps: 8,
                maxReps: 12,
                targetWeight: 10,
                restSeconds: exercise.defaultRestSeconds
            )
        )
    }

    private func save() {
        let savedTemplate: WorkoutTemplate
        if let template {
            savedTemplate = template
            template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.weekday = weekday
            template.isActive = isActive
        } else {
            let newTemplate = WorkoutTemplate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                weekday: weekday,
                isActive: isActive
            )
            modelContext.insert(newTemplate)
            savedTemplate = newTemplate
        }

        let existing = storedItems.filter { $0.templateID == savedTemplate.id }
        let keptIDs = Set(drafts.compactMap(\.storedItemID))
        existing.filter { !keptIDs.contains($0.id) }.forEach(modelContext.delete)

        for (index, draft) in drafts.enumerated() {
            if let storedID = draft.storedItemID,
               let item = existing.first(where: { $0.id == storedID }) {
                apply(draft, order: index, to: item)
            } else {
                modelContext.insert(
                    TemplateExercise(
                        templateID: savedTemplate.id,
                        exerciseID: draft.exerciseID,
                        order: index,
                        targetSets: draft.targetSets,
                        minReps: draft.minReps,
                        maxReps: draft.maxReps,
                        targetWeight: draft.targetWeight,
                        restSeconds: draft.restSeconds
                    )
                )
            }
        }

        do {
            try ScheduleService.refreshUpcoming(in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ draft: ExerciseDraft, order: Int, to item: TemplateExercise) {
        item.exerciseID = draft.exerciseID
        item.order = order
        item.targetSets = draft.targetSets
        item.minReps = draft.minReps
        item.maxReps = max(draft.minReps, draft.maxReps)
        item.targetWeight = max(0, draft.targetWeight)
        item.restSeconds = draft.restSeconds
    }
}

private struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]

    let exercise: Exercise?

    @State private var name: String
    @State private var muscleGroup: String
    @State private var equipment: String
    @State private var restSeconds: Int
    @State private var notes: String
    @State private var errorMessage: String?

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? "胸部")
        _equipment = State(initialValue: exercise?.equipment ?? "哑铃")
        _restSeconds = State(initialValue: exercise?.defaultRestSeconds ?? 90)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("动作信息") {
                    TextField("动作名称", text: $name)
                    TextField("目标肌群", text: $muscleGroup)
                    TextField("器械", text: $equipment)
                    Picker("默认休息", selection: $restSeconds) {
                        ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                            Text("\(seconds) 秒").tag(seconds)
                        }
                    }
                }

                Section("备注") {
                    TextField("动作要点、器械位置等", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
                        .disabled(trimmedName.isEmpty || trimmedMuscleGroup.isEmpty || trimmedEquipment.isEmpty)
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMuscleGroup: String {
        muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEquipment: String {
        equipment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let editingID = exercise?.id
        let duplicate = allExercises.contains {
            $0.id != editingID
                && !$0.isArchived
                && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        guard !duplicate else {
            errorMessage = "动作库中已经存在同名动作。"
            return
        }

        if let exercise {
            exercise.name = trimmedName
            exercise.muscleGroup = trimmedMuscleGroup
            exercise.equipment = trimmedEquipment
            exercise.defaultRestSeconds = restSeconds
            exercise.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            exercise.updatedAt = .now
        } else {
            modelContext.insert(
                Exercise(
                    name: trimmedName,
                    muscleGroup: trimmedMuscleGroup,
                    equipment: trimmedEquipment,
                    defaultRestSeconds: restSeconds,
                    isBuiltIn: false,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DraftExerciseEditor: View {
    @Binding var draft: ExerciseDraft
    let exercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? "未知动作")
                        .font(.headline)
                    Text("\(exercise?.muscleGroup ?? "") · \(exercise?.equipment ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }

            Stepper("工作组：\(draft.targetSets)", value: $draft.targetSets, in: 1...10)

            HStack {
                Text("次数")
                Spacer()
                TextField("最低", value: $draft.minReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("–")
                TextField("最高", value: $draft.maxReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
            }

            HStack {
                Text("目标重量")
                Spacer()
                TextField("kg", value: $draft.targetWeight, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg")
                    .foregroundStyle(.secondary)
            }

            Picker("组间休息", selection: $draft.restSeconds) {
                ForEach([45, 60, 90, 120, 150, 180], id: \.self) { seconds in
                    Text("\(seconds) 秒").tag(seconds)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

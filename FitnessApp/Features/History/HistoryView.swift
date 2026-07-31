import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var setLogs: [SetLog]
    @Query private var sessionExercises: [SessionExercise]

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    var body: some View {
        Group {
            if completedSessions.isEmpty {
                ContentUnavailableView(
                    "还没有完成的训练",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("从“今日”开始一次训练，完成后会自动保存在这里。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(completedSessions) { session in
                            NavigationLink(destination: WorkoutDetailView(sessionID: session.id)) {
                                historyCard(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .background(AppTheme.background)
            }
        }
        .navigationTitle("训练历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: HistoricalWorkoutEntryView()) {
                    Label("补录", systemImage: "plus")
                }
                NavigationLink(destination: HistoricalWorkoutImportView()) {
                    Label("批量同步", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private func historyCard(_ session: WorkoutSession) -> some View {
        let logs = setLogs.filter { $0.sessionID == session.id && $0.isCompleted }
        let exerciseCount = sessionExercises.filter { $0.sessionID == session.id }.count
        let volume = TrainingMetrics.volume(for: logs)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt, format: .dateTime.month().day().weekday(.wide))
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Text(session.templateName)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 18) {
                Label("\(exerciseCount) 动作", systemImage: "list.bullet")
                Label("\(logs.count) 组", systemImage: "checkmark.circle")
                Label("\(Int(volume)) kg", systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let completedAt = session.completedAt {
                Text("\(session.startedAt, format: .dateTime.hour().minute()) – \(completedAt, format: .dateTime.hour().minute()) · \(TrainingFormatters.duration(from: session.startedAt, to: completedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }
}

struct WorkoutDetailView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @AppStorage(TrainingGoalMode.storageKey)
    private var trainingGoalRaw = TrainingGoalMode.cuttingVolume.rawValue
    @State private var showEditor = false

    let sessionID: UUID

    init(sessionID: UUID) {
        self.sessionID = sessionID
        let targetID = sessionID
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.id == targetID })
        _sessionExercises = Query(
            filter: #Predicate<SessionExercise> { $0.sessionID == targetID },
            sort: \.order
        )
        _setLogs = Query(filter: #Predicate<SetLog> { $0.sessionID == targetID })
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var exercises: [SessionExercise] {
        sessionExercises
    }

    private var logs: [SetLog] {
        setLogs.filter(\.isCompleted)
    }

    private var trainingGoalMode: TrainingGoalMode {
        TrainingGoalMode(rawValue: trainingGoalRaw) ?? .cuttingVolume
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        summary(session)

                        ForEach(exercises) { exercise in
                            exerciseSummary(exercise)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("训练备注")
                                .font(.headline)
                            Text(session.notes.isEmpty ? "暂无备注，点右上角“编辑”补充。" : session.notes)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle(session.templateName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditor = true
                        } label: {
                            Label("编辑历史", systemImage: "pencil")
                        }
                    }
                }
                .sheet(isPresented: $showEditor) {
                    NavigationStack {
                        HistoricalWorkoutEditView(sessionID: session.id)
                    }
                    .preferredColorScheme(.dark)
                    .tint(AppTheme.accent)
                }
            } else {
                ContentUnavailableView("找不到训练记录", systemImage: "questionmark.folder")
            }
        }
    }

    private func summary(_ session: WorkoutSession) -> some View {
        let volume = TrainingMetrics.volume(for: logs)
        let duration = session.completedAt.map {
            TrainingFormatters.duration(from: session.startedAt, to: $0)
        } ?? "进行中"

        return VStack(alignment: .leading, spacing: 16) {
            Text(session.startedAt, format: .dateTime.year().month().day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                miniMetric("\(logs.count)", label: "完成组数")
                miniMetric("\(Int(volume))", label: "训练容量 kg")
                miniMetric(duration, label: "训练时长")
            }
        }
        .cardSurface()
    }

    private func exerciseSummary(_ exercise: SessionExercise) -> some View {
        let exerciseLogs = logs
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        let assessment = TrainingMetrics.progressionAssessment(
            weights: exerciseLogs.map(\.actualWeight),
            completedReps: exerciseLogs.map(\.actualReps),
            minimumReps: exercise.minReps,
            maximumReps: exercise.maxReps,
            rirValues: exerciseLogs.map(\.rir),
            goalMode: trainingGoalMode
        )

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)
                Spacer()
                Label(
                    assessment.title,
                    systemImage: recommendationIcon(assessment.recommendation)
                )
                    .font(.caption.bold())
                    .foregroundStyle(recommendationColor(assessment.recommendation))
            }

            ForEach(exerciseLogs) { log in
                HStack {
                    Text("第 \(log.setNumber) 组")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(TrainingFormatters.weight(log.actualWeight)) kg × \(log.actualReps)")
                        .font(.subheadline.bold().monospacedDigit())
                    if let rir = log.rir {
                        Text("RIR \(rir)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }
                .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("容量 \(Int(assessment.currentVolume)) kg · \(trainingGoalMode.title)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text(assessment.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 11))

            if !exercise.performanceNotes.isEmpty {
                Label(exercise.performanceNotes, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func miniMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendationIcon(_ recommendation: ProgressionRecommendation) -> String {
        switch recommendation {
        case .increase: return "arrow.up.right"
        case .maintain: return "equal"
        case .reduce: return "arrow.down.right"
        }
    }

    private func recommendationColor(_ recommendation: ProgressionRecommendation) -> Color {
        switch recommendation {
        case .increase: return AppTheme.accent
        case .maintain: return .secondary
        case .reduce: return .orange
        }
    }
}

private struct HistoricalSetEditDraft: Identifiable {
    let id: UUID
    let originalLogID: UUID?
    var weight: Double
    var reps: Int
    var rir: Int?

    init(
        id: UUID = UUID(),
        originalLogID: UUID? = nil,
        weight: Double = 0,
        reps: Int = 10,
        rir: Int? = 2
    ) {
        self.id = id
        self.originalLogID = originalLogID
        self.weight = weight
        self.reps = reps
        self.rir = rir
    }
}

private struct HistoricalExerciseEditDraft: Identifiable {
    let id: UUID
    let originalSnapshotID: UUID?
    let exerciseID: UUID
    let exerciseName: String
    let muscleGroup: String
    let equipment: String
    var performanceNotes: String
    var sets: [HistoricalSetEditDraft]
}

struct HistoricalWorkoutEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var sessions: [WorkoutSession]
    @Query private var snapshots: [SessionExercise]
    @Query private var logs: [SetLog]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let sessionID: UUID

    @State private var name = ""
    @State private var startedAt = Date.now
    @State private var durationMinutes = 60
    @State private var workoutNotes = ""
    @State private var exerciseDrafts: [HistoricalExerciseEditDraft] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    init(sessionID: UUID) {
        self.sessionID = sessionID
        let targetID = sessionID
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.id == targetID })
        _snapshots = Query(
            filter: #Predicate<SessionExercise> { $0.sessionID == targetID },
            sort: \.order
        )
        _logs = Query(filter: #Predicate<SetLog> { $0.sessionID == targetID })
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var availableExercises: [Exercise] {
        exercises.filter { exercise in
            !exercise.isArchived
                && !exerciseDrafts.contains(where: { $0.exerciseID == exercise.id })
        }
    }

    var body: some View {
        Form {
            Section("训练信息") {
                TextField("训练名称", text: $name)
                    .accessibilityIdentifier("历史训练名称")
                DatePicker(
                    "开始时间",
                    selection: $startedAt,
                    in: Date.distantPast...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Stepper(
                    "训练时长：\(durationMinutes) 分钟",
                    value: $durationMinutes,
                    in: 5...360,
                    step: 5
                )
            }

            Section("训练备注") {
                TextField(
                    "记录整场状态、恢复、疼痛或需要下次注意的事项",
                    text: $workoutNotes,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .accessibilityIdentifier("历史训练备注")
            }

            Section {
                ForEach($exerciseDrafts) { $draft in
                    HistoricalWorkoutEditExerciseCard(
                        draft: $draft,
                        canDelete: exerciseDrafts.count > 1,
                        onDelete: {
                            exerciseDrafts.removeAll { $0.id == draft.id }
                        }
                    )
                }

                Menu {
                    ForEach(availableExercises) { exercise in
                        Button(exercise.name) {
                            addExercise(exercise)
                        }
                    }
                } label: {
                    Label("添加遗漏动作", systemImage: "plus.circle.fill")
                }
                .disabled(availableExercises.isEmpty)
            } header: {
                Text("动作、完成组与动作备注")
            } footer: {
                Text("修改后会重新计算训练容量，并用于下一次肌群恢复和动作建议。")
            }
        }
        .navigationTitle("编辑历史训练")
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
                            || exerciseDrafts.isEmpty
                    )
            }
        }
        .onAppear(perform: loadDrafts)
        .alert("无法保存历史记录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func loadDrafts() {
        guard !hasLoaded, let session else { return }
        hasLoaded = true
        name = session.templateName
        startedAt = session.startedAt
        durationMinutes = max(
            5,
            Int(((session.completedAt ?? session.startedAt).timeIntervalSince(session.startedAt) / 60).rounded())
        )
        workoutNotes = session.notes
        exerciseDrafts = snapshots.map { snapshot in
            let exercise = exercises.first { $0.id == snapshot.exerciseID }
            let setDrafts = logs
                .filter { $0.sessionExerciseID == snapshot.id && $0.isCompleted }
                .sorted { $0.setNumber < $1.setNumber }
                .map { log in
                    HistoricalSetEditDraft(
                        id: log.id,
                        originalLogID: log.id,
                        weight: log.actualWeight,
                        reps: log.actualReps,
                        rir: log.rir
                    )
                }
            return HistoricalExerciseEditDraft(
                id: snapshot.id,
                originalSnapshotID: snapshot.id,
                exerciseID: snapshot.exerciseID,
                exerciseName: snapshot.exerciseName,
                muscleGroup: snapshot.muscleGroup,
                equipment: exercise?.equipment ?? "历史动作",
                performanceNotes: snapshot.performanceNotes,
                sets: setDrafts.isEmpty ? [HistoricalSetEditDraft()] : setDrafts
            )
        }
    }

    private func addExercise(_ exercise: Exercise) {
        exerciseDrafts.append(
            HistoricalExerciseEditDraft(
                id: UUID(),
                originalSnapshotID: nil,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                performanceNotes: "",
                sets: [
                    HistoricalSetEditDraft(),
                    HistoricalSetEditDraft(),
                    HistoricalSetEditDraft()
                ]
            )
        )
    }

    private func save() {
        guard let session else {
            errorMessage = "找不到需要编辑的训练记录。"
            return
        }
        guard exerciseDrafts.allSatisfy({ !$0.sets.isEmpty }) else {
            errorMessage = "每个动作至少需要保留一个完成组。"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请填写训练名称。"
            return
        }

        session.templateName = trimmedName
        session.plannedDate = startedAt.startOfDay
        session.startedAt = startedAt
        session.completedAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        session.notes = workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let retainedSnapshotIDs = Set(exerciseDrafts.compactMap(\.originalSnapshotID))
        for snapshot in snapshots where !retainedSnapshotIDs.contains(snapshot.id) {
            logs
                .filter { $0.sessionExerciseID == snapshot.id }
                .forEach(modelContext.delete)
            modelContext.delete(snapshot)
        }

        for (order, draft) in exerciseDrafts.enumerated() {
            let snapshot: SessionExercise
            if let originalID = draft.originalSnapshotID,
               let existing = snapshots.first(where: { $0.id == originalID }) {
                snapshot = existing
            } else {
                let libraryExercise = exercises.first { $0.id == draft.exerciseID }
                snapshot = SessionExercise(
                    sessionID: session.id,
                    exerciseID: draft.exerciseID,
                    exerciseName: draft.exerciseName,
                    order: order,
                    targetSets: draft.sets.count,
                    minReps: draft.sets.map(\.reps).min() ?? 1,
                    maxReps: draft.sets.map(\.reps).max() ?? 1,
                    targetWeight: draft.sets.map(\.weight).max() ?? 0,
                    restSeconds: libraryExercise?.defaultRestSeconds ?? 90,
                    muscleGroup: draft.muscleGroup,
                    exerciseNotes: libraryExercise?.notes ?? ""
                )
                modelContext.insert(snapshot)
            }

            snapshot.order = order
            snapshot.targetSets = draft.sets.count
            snapshot.minReps = max(1, draft.sets.map(\.reps).min() ?? 1)
            snapshot.maxReps = max(snapshot.minReps, draft.sets.map(\.reps).max() ?? 1)
            snapshot.targetWeight = max(0, draft.sets.map(\.weight).max() ?? 0)
            snapshot.performanceNotes = draft.performanceNotes
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let retainedLogIDs = Set(draft.sets.compactMap(\.originalLogID))
            logs
                .filter {
                    $0.sessionExerciseID == snapshot.id
                        && !retainedLogIDs.contains($0.id)
                }
                .forEach(modelContext.delete)

            for (index, setDraft) in draft.sets.enumerated() {
                let log: SetLog
                if let originalID = setDraft.originalLogID,
                   let existing = logs.first(where: { $0.id == originalID }) {
                    log = existing
                } else {
                    log = SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: snapshot.exerciseID,
                        setNumber: index + 1,
                        targetWeight: max(0, setDraft.weight),
                        targetReps: max(1, setDraft.reps),
                        actualWeight: max(0, setDraft.weight),
                        actualReps: max(1, setDraft.reps),
                        rir: setDraft.rir,
                        isCompleted: true,
                        completedAt: startedAt.addingTimeInterval(TimeInterval((index + 1) * 60))
                    )
                    modelContext.insert(log)
                }
                log.setNumber = index + 1
                log.targetWeight = max(0, setDraft.weight)
                log.targetReps = max(1, setDraft.reps)
                log.actualWeight = max(0, setDraft.weight)
                log.actualReps = max(1, setDraft.reps)
                log.rir = setDraft.rir
                log.isCompleted = true
                log.completedAt = log.completedAt ?? startedAt.addingTimeInterval(
                    TimeInterval((index + 1) * 60)
                )
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HistoricalWorkoutEditExerciseCard: View {
    @Binding var draft: HistoricalExerciseEditDraft
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.exerciseName)
                        .font(.headline)
                    Text("\(draft.muscleGroup) · \(draft.equipment)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .disabled(!canDelete)
            }

            TextField(
                "动作备注：状态、疼痛、技术或器械差异",
                text: $draft.performanceNotes,
                axis: .vertical
            )
            .lineLimit(2...5)
            .accessibilityIdentifier("动作备注-\(draft.exerciseName)")

            Stepper(
                "完成组数：\(draft.sets.count)",
                value: Binding(
                    get: { draft.sets.count },
                    set: updateSetCount
                ),
                in: 1...12
            )

            HStack {
                Text("组").frame(width: 24)
                Text("重量 kg").frame(maxWidth: .infinity)
                Text("次数").frame(maxWidth: .infinity)
                Text("RIR").frame(width: 54)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(draft.sets.indices), id: \.self) { index in
                HStack {
                    Text("\(index + 1)")
                        .font(.subheadline.bold().monospacedDigit())
                        .frame(width: 24)
                    TextField(
                        "kg",
                        value: $draft.sets[index].weight,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "次数",
                        value: $draft.sets[index].reps,
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)

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
            }
        }
        .padding(.vertical, 6)
    }

    private func updateSetCount(_ count: Int) {
        if count > draft.sets.count {
            let last = draft.sets.last ?? HistoricalSetEditDraft()
            draft.sets.append(
                contentsOf: (0..<(count - draft.sets.count)).map { _ in
                    HistoricalSetEditDraft(
                        weight: last.weight,
                        reps: last.reps,
                        rir: last.rir
                    )
                }
            )
        } else if count < draft.sets.count {
            draft.sets.removeLast(draft.sets.count - count)
        }
    }
}

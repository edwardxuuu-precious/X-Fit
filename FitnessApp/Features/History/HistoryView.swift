import SwiftData
import SwiftUI

private func formattedVolumeTotals(
    logs: [SetLog],
    snapshots: [SessionExercise]
) -> String {
    let totals = TrainingMetrics.volumeTotals(for: logs, sessionExercises: snapshots)
    let values = ExerciseVolumeUnit.allCases.compactMap { unit -> String? in
        let value = totals[unit] ?? 0
        guard value > 0 else { return nil }
        return "\(Int(value).formatted()) \(unit.symbol)"
    }
    return values.isEmpty ? "0 kg" : values.joined(separator: " · ")
}

struct HistoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var setLogs: [SetLog]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var schedules: [ScheduledWorkout]

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    var body: some View {
        Group {
            if completedSessions.isEmpty {
                ContentUnavailableView(
                    "还没有完成的训练",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("完成训练后保存在这里，也可以补录。")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        SprintPageHeader(title: "训练历史", icon: "clock.arrow.circlepath")
                        HStack {
                            SprintSectionHeading(title: "完成记录", icon: "checkmark.circle")
                            Spacer()
                            Text("\(completedSessions.count) 次")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                        }.padding(.bottom, 18)
                        ForEach(completedSessions) { session in
                            NavigationLink(destination: WorkoutDetailView(sessionID: session.id)) {
                                historyCard(session)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(AppTheme.line)
                        }
                    }
                    .padding(20)
                }
                .background(AppTheme.background)
            }
        }
        .sprintPage()
        .navigationTitle("训练历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: HistoricalWorkoutEntryView()) {
                    Label("补录", systemImage: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                NavigationLink(destination: HistoricalWorkoutImportView()) {
                    Label("导入历史训练", systemImage: "square.and.arrow.down")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("批量同步")
            }
        }
    }

    private func historyCard(_ session: WorkoutSession) -> some View {
        let schedule = schedules.first { $0.id == session.scheduledWorkoutID }
        let displayDate = TrainingHistoryDate.displayDate(session, schedule: schedule)
        let logs = setLogs.filter {
            $0.sessionID == session.id && $0.isCompleted && !$0.isWarmup
        }
        let exerciseCount = sessionExercises.filter { $0.sessionID == session.id }.count
        let cardio = CardioWorkoutPresentation.actual(session, exercises: sessionExercises, logs: setLogs)

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayDate, format: .dateTime.day())
                    .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(displayDate, format: .dateTime.year().month())
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
            .frame(minWidth: 58, minHeight: 64)
            .padding(.horizontal, 7)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 8) {
                Text(cardio?.title ?? TrainingWorkoutPresentation.title(session.templateName))
                    .font(.headline).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if TrainingHistoryDate.knownLocalDay(session, schedule: schedule) == nil {
                    Text("旧记录归属时区未知，日期按当前时区显示")
                        .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
                if let cardio {
                    Text(cardio.label).font(.caption).foregroundStyle(AppTheme.secondaryText)
                } else if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(exerciseCount) 动作 · \(logs.count) 组已记录")
                        durationLabel(session)
                    }
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                } else {
                    HStack(spacing: 10) {
                        Text("\(exerciseCount) 动作 · \(logs.count) 组已记录")
                        Spacer(minLength: 0)
                        durationLabel(session)
                    }
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 6)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func durationLabel(_ session: WorkoutSession) -> some View {
        if let completedAt = session.completedAt {
            Text(TrainingFormatters.duration(from: session.startedAt, to: completedAt))
                .monospacedDigit()
        } else if session.status == .completed {
            Text("时长未知")
        }
    }
}

struct WorkoutDetailView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var schedules: [ScheduledWorkout]
    @Query private var bodyMeasurements: [BodyMeasurement]
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
        setLogs.filter { $0.isCompleted && !$0.isWarmup }
    }

    private func bodyWeightSourceLabel(for exercise: SessionExercise) -> String? {
        guard exercise.volumeUnit == .bodyweight, exercise.bodyWeightKgSnapshot != nil else { return nil }
        if let sourceDate = exercise.bodyWeightSnapshotSourceDate {
            return "自重体重快照 · 来源测量 \(sourceDate.formatted(date: .abbreviated, time: .omitted))"
        }
        // Legacy fallback is deliberately strict: only claim a source date when an
        // exact local measurement matches the frozen value on/before this session.
        guard let session,
              let matching = bodyMeasurements
                .filter({ $0.date <= session.startedAt && $0.weightKg == exercise.bodyWeightKgSnapshot })
                .max(by: { $0.date < $1.date }) else {
            return "自重体重快照 · 来源日期未知"
        }
        return "自重体重快照 · 来源测量 \(matching.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var trainingGoalMode: TrainingGoalMode {
        TrainingGoalMode(rawValue: trainingGoalRaw) ?? .cuttingVolume
    }

    var body: some View {
        Group {
            if let session, session.status == .completed, CardioWorkoutPresentation.actual(session, exercises: exercises, logs: setLogs) != nil {
                CardioWorkoutSummaryView(sessionID: session.id)
            } else if let session {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        summary(session)
                        if TrainingWorkoutPresentation.title(session.templateName) != session.templateName {
                            DisclosureGroup("原始训练名称") { Text(session.templateName).font(.caption) }
                        }

                        ForEach(exercises) { exercise in
                            exerciseSummary(exercise)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            SprintSectionHeading(title: "训练备注", icon: "note.text")
                            Text(session.notes.isEmpty ? "暂无备注，点右上角“编辑”补充。" : session.notes)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }
                    .padding(20)
                }
                .background(AppTheme.background)
                .navigationTitle(TrainingWorkoutPresentation.title(session.templateName))
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
                    .sprintPage()
                    .tint(AppTheme.ink)
                }
            } else {
                ContentUnavailableView("找不到训练记录", systemImage: "questionmark.folder")
            }
        }
        .sprintPage()
    }

    private func summary(_ session: WorkoutSession) -> some View {
        let volumeText = formattedVolumeTotals(logs: logs, snapshots: exercises)
        let duration = session.completedAt.map {
            TrainingFormatters.duration(from: session.startedAt, to: $0)
        } ?? (session.status == .completed ? "未知" : "进行中")
        let schedule = schedules.first { $0.id == session.scheduledWorkoutID }
        let displayDate = TrainingHistoryDate.displayDate(session, schedule: schedule)

        return VStack(alignment: .leading, spacing: 16) {
            Text(displayDate, format: .dateTime.year().month().day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if TrainingHistoryDate.knownLocalDay(session, schedule: schedule) == nil {
                Text("旧记录归属时区未知，日期按当前时区显示。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                miniMetric("\(logs.count)", label: "完成组数")
                miniMetric(volumeText, label: "训练量（按单位分开）")
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
        let exerciseVolume = TrainingMetrics.volume(for: exerciseLogs, unit: exercise.volumeUnit)

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)
                Spacer()
                if exercise.volumeUnit == .kilogram {
                    Label(
                        assessment.title,
                        systemImage: recommendationIcon(assessment.recommendation)
                    )
                    .font(.caption.bold())
                    .foregroundStyle(recommendationColor(assessment.recommendation))
                } else {
                    Text(exercise.volumeUnit.title)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink)
                }
            }

            Text(recordedLoadBasis(exercise, logs: exerciseLogs))
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("历史记重口径-\(exercise.exerciseName)")

            if let feeling = exercise.feeling {
                Label("\(feeling.emoji) \(feeling.title)", systemImage: "face.smiling")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityLabel("动作体验，\(feeling.title)")
            }

            if let sourceLabel = bodyWeightSourceLabel(for: exercise) {
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("自重来源日期-\(exercise.exerciseName)")
            }

            ForEach(exerciseLogs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("第 \(log.setNumber) 组")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(setValueText(log, unit: exercise.volumeUnit))
                            .font(.subheadline.bold().monospacedDigit())
                        if let rir = log.rir {
                            Text("RIR \(rir)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }


                }
                .font(.subheadline)
            }
            DisclosureGroup("逐组训练量") {
                ForEach(exerciseLogs) { log in
                    let volumeWeight = exercise.volumeUnit == .bodyweight ? exercise.bodyWeightKgSnapshot : log.actualWeight
                    Text("第 \(log.setNumber) 组 · " + (exercise.volumeUnit.volume(weight: volumeWeight, reps: log.actualReps)
                        .map { "\(Int($0)) \(exercise.volumeUnit.symbol)" } ?? "暂无体重"))
                        .font(.caption.monospacedDigit())
                }
            }.font(.caption).foregroundStyle(AppTheme.secondaryText)
            if !exercise.exerciseNotes.isEmpty {
                DisclosureGroup("原始动作说明") {
                    Text(exercise.exerciseNotes).font(.caption).fixedSize(horizontal: false, vertical: true)
                }.font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            if let durationSeconds = exercise.durationSeconds {
                Label("动作总时长 \(TrainingFormatters.clock(durationSeconds))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("训练量 \(Int(exerciseVolume)) \(exercise.volumeUnit.symbol)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(
                    exercise.volumeUnit == .kilogram
                        ? assessment.detail
                        : "该动作按 \(exercise.volumeUnit.symbol) 记录，不与 kg 训练容量相加。"
                )
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

    private func recordedLoadBasis(_ exercise: SessionExercise, logs: [SetLog]) -> String {
        if let guidance = TrainingWorkoutPresentation.loadGuidance(in: exercise.exerciseNotes) { return guidance }
        guard exercise.volumeUnit.usesMeasurementSide else { return exercise.volumeUnit.inputTitle }
        let sides = Set(logs.compactMap { $0.actualWeightSideRaw ?? $0.targetWeightSideRaw })
        if sides.count == 1, let raw = sides.first, let side = MeasurementSide(rawValue: raw) {
            return "\(exercise.volumeUnit.symbol) · \(side.title)"
        }
        return sides.isEmpty ? "\(exercise.volumeUnit.symbol) · 记重侧别未注明" : "\(exercise.volumeUnit.symbol) · 侧别按各组原记录"
    }

    private func setValueText(_ log: SetLog, unit: ExerciseVolumeUnit) -> String {
        switch unit {
        case .count:
            return "\(log.actualReps) 个"
        case .second:
            return "\(log.actualReps) 秒"
        case .meter:
            return "\(TrainingFormatters.weight(log.actualWeight)) 米 × \(log.actualReps) 趟"
        case .kilogram:
            return "\(TrainingFormatters.weight(log.actualWeight)) kg × \(log.actualReps) 次"
        case .bodyweight:
            return log.actualWeight > 0
                ? "\(TrainingFormatters.weight(log.actualWeight)) kg × \(log.actualReps) 次"
                : "暂无体重 × \(log.actualReps) 次"
        }
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
        case .increase: return AppTheme.ink
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
    var restDurationText: String

    init(
        id: UUID = UUID(),
        originalLogID: UUID? = nil,
        weight: Double = 0,
        reps: Int = 10,
        rir: Int? = 2,
        restDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.originalLogID = originalLogID
        self.weight = weight
        self.reps = reps
        self.rir = rir
        restDurationText = restDurationSeconds.map(String.init) ?? ""
    }

    var restValidation: RestDurationInputValidation {
        RestDurationInput.validate(restDurationText)
    }
}

private struct HistoricalExerciseEditDraft: Identifiable {
    let id: UUID
    let originalSnapshotID: UUID?
    let exerciseID: UUID
    let exerciseName: String
    let muscleGroup: String
    let equipment: String
    let volumeUnit: ExerciseVolumeUnit
    var performanceNotes: String
    var sets: [HistoricalSetEditDraft]
    var allowsEmpty: Bool = false
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
    @State private var loadedStartedAt: Date?
    @State private var durationMinutes = 60
    @State private var hasExactStartTime = true
    @State private var hasDuration = true
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
            Section {
                SprintPageHeader(title: "编辑记录", icon: "square.and.pencil")
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                TextField("训练名称", text: $name)
                    .accessibilityIdentifier("历史训练名称")
                DatePicker(
                    "开始时间",
                    selection: $startedAt,
                    in: Date.distantPast...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Text("开始时间按当前时区（\(TimeZone.current.identifier)）显示；只修改时间或备注不会改变训练归属日期。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("知道具体开始时间", isOn: $hasExactStartTime)
                Toggle("知道训练时长", isOn: $hasDuration)
                if hasDuration {
                    Stepper(
                        "训练时长：\(durationMinutes) 分钟",
                        value: $durationMinutes,
                        in: 1...360,
                        step: 5
                    )
                }
            } header: {
                SprintSectionHeading(title: "训练信息", icon: "calendar")
            }

            Section {
                TextField(
                    "记录整场状态、恢复、疼痛或需要下次注意的事项",
                    text: $workoutNotes,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .accessibilityIdentifier("历史训练备注")
            } header: {
                SprintSectionHeading(title: "训练备注", icon: "note.text")
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
                Text("修改训练量后会按动作单位自动重算。")
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
        loadedStartedAt = session.startedAt
        hasExactStartTime = session.isStartTimeKnown
        hasDuration = session.completedAt != nil
        durationMinutes = session.completedAt.map {
            max(1, Int(($0.timeIntervalSince(session.startedAt) / 60).rounded()))
        } ?? 60
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
                        rir: log.rir,
                        restDurationSeconds: log.restDurationSeconds
                    )
                }
            return HistoricalExerciseEditDraft(
                id: snapshot.id,
                originalSnapshotID: snapshot.id,
                exerciseID: snapshot.exerciseID,
                exerciseName: snapshot.exerciseName,
                muscleGroup: snapshot.muscleGroup,
                equipment: exercise?.equipment ?? "历史动作",
                volumeUnit: snapshot.volumeUnit,
                performanceNotes: snapshot.performanceNotes,
                sets: setDrafts,
                allowsEmpty: setDrafts.isEmpty
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
                volumeUnit: exercise.volumeUnit,
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
        guard exerciseDrafts.allSatisfy({ !$0.sets.isEmpty || $0.allowsEmpty }) else {
            errorMessage = "每个动作至少需要保留一个完成组。"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请填写训练名称。"
            return
        }

        session.templateName = trimmedName
        TrainingHistoricalDateEditing.apply(
            to: session,
            originalStartedAt: loadedStartedAt ?? session.startedAt,
            editedStartedAt: startedAt
        )
        session.startedAt = startedAt
        session.isStartTimeKnown = hasExactStartTime
        session.completedAt = hasDuration
            ? startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
            : nil
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
                    exerciseNotes: libraryExercise?.notes ?? "",
                    volumeUnit: draft.volumeUnit
                )
                modelContext.insert(snapshot)
            }

            snapshot.order = order
            let pendingCount = logs.filter {
                $0.sessionExerciseID == snapshot.id && $0.reductionOrder == nil && !$0.isCompleted
            }.count
            snapshot.targetSets = draft.sets.count + pendingCount
            if !draft.sets.isEmpty {
                snapshot.minReps = max(1, draft.sets.map(\.reps).min() ?? 1)
                snapshot.maxReps = max(snapshot.minReps, draft.sets.map(\.reps).max() ?? 1)
                snapshot.targetWeight = max(0, draft.sets.map(\.weight).max() ?? 0)
            }
            snapshot.performanceNotes = draft.performanceNotes
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let retainedLogIDs = Set(draft.sets.compactMap(\.originalLogID))
            logs
                .filter {
                    $0.sessionExerciseID == snapshot.id
                        && $0.reductionOrder == nil
                        && $0.isCompleted
                        && !retainedLogIDs.contains($0.id)
                }
                .forEach(modelContext.delete)

            let preservesReducedNumbers = snapshot.hasManuallyReducedSets == true || pendingCount > 0
            var nextSetNumber = (logs.filter { $0.sessionExerciseID == snapshot.id }.map(\.setNumber).max() ?? 0) + 1
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
                        setNumber: preservesReducedNumbers ? nextSetNumber : index + 1,
                        targetWeight: max(0, setDraft.weight),
                        targetReps: max(1, setDraft.reps),
                        actualWeight: max(0, setDraft.weight),
                        actualReps: max(1, setDraft.reps),
                        rir: setDraft.rir,
                        isCompleted: true,
                        completedAt: hasExactStartTime
                            ? startedAt.addingTimeInterval(TimeInterval((index + 1) * 60))
                            : nil
                    )
                    modelContext.insert(log)
                    nextSetNumber += 1
                }
                if !preservesReducedNumbers { log.setNumber = index + 1 }
                log.targetWeight = max(0, setDraft.weight)
                log.targetReps = max(1, setDraft.reps)
                log.actualWeight = max(0, setDraft.weight)
                log.actualReps = max(1, setDraft.reps)
                log.rir = setDraft.rir
                log.isCompleted = true
                if !hasExactStartTime {
                    log.startedAt = nil
                    log.completedAt = nil
                } else if log.completedAt == nil {
                    log.completedAt = startedAt.addingTimeInterval(TimeInterval((index + 1) * 60))
                }
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
                    Text("\(draft.muscleGroup) · \(draft.equipment) · \(draft.volumeUnit.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("删除动作")
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
                in: (draft.allowsEmpty ? 0 : 1)...12
            )
            .accessibilityIdentifier("history-edit-set-count-\(draft.exerciseName)")

            HStack {
                Text("组").frame(width: 24)
                if draft.volumeUnit.recordsSingleAmount {
                    Text("\(draft.volumeUnit.inputTitle) \(draft.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                } else if draft.volumeUnit == .bodyweight {
                    Text("负重").frame(maxWidth: .infinity)
                    Text("次数").frame(maxWidth: .infinity)
                } else {
                    Text("\(draft.volumeUnit.inputTitle) \(draft.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                    Text(draft.volumeUnit.repetitionTitle).frame(maxWidth: .infinity)
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
                        if draft.volumeUnit.recordsNumericLoad {
                            TextField(
                                draft.volumeUnit.symbol,
                                value: $draft.sets[index].weight,
                                format: .number.precision(.fractionLength(0...3))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 44)
                        } else if draft.volumeUnit == .bodyweight {
                            Text("自重")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity)
                        }

                        TextField(
                            draft.volumeUnit.recordsSingleAmount
                                ? draft.volumeUnit.inputTitle
                                : draft.volumeUnit.repetitionTitle,
                            value: $draft.sets[index].reps,
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(
                            "历史编辑-\(draft.exerciseName)-第\(index + 1)组-\(draft.volumeUnit.inputTitle)"
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
                        rir: last.rir,
                        restDurationSeconds: nil
                    )
                }
            )
        } else if count < draft.sets.count {
            draft.sets.removeLast(draft.sets.count - count)
        }
    }

}

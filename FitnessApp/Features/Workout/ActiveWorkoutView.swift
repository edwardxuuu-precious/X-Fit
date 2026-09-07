import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var schedules: [ScheduledWorkout]

    let sessionID: UUID

    @State private var showFinishConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showExercisePicker = false
    @State private var showRIRHelp = false
    // Legacy rest helpers remain decode-compatible but are no longer reachable from the workout UI.
    @State private var showRestEndedAlert = false
    @State private var restPromptedForEndDate: Date?
    @State private var selectedExerciseID: UUID?
    @State private var detailedExerciseIDs: Set<UUID> = []
    @AppStorage("xfit.active.expandedExercise") private var storedExpandedExercise = ""
    @State private var showsSessionNotes = false
    @State private var pendingFeelingExerciseIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var orderedExercises: [SessionExercise] {
        MuscleCoverageService.stableOrder(sessionExercises, sessionID: sessionID)
    }

    private var logs: [SetLog] {
        setLogs.filter { $0.sessionID == sessionID }
    }

    private var completedCount: Int {
        logs.filter(\.isCompleted).count
    }

    // Read-only legacy helpers keep old persisted rest state recoverable while the
    // active workout flow no longer exposes or starts rest tracking.
    private var activeRestLog: SetLog? {
        WorkoutRestTracking.activeLog(in: logs)
    }

    private var hasActiveRest: Bool {
        activeRestLog != nil || session?.restEndDate != nil
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(spacing: 12) {
                        workoutHeader(session)

                        ForEach(orderedExercises) { exercise in
                            exerciseCard(exercise, session: session)
                        }

                        DisclosureGroup("训练备注", isExpanded: $showsSessionNotes) {
                            notesCard(session)
                        }.font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        finishButton
                        discardButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .accessibilityIdentifier("active-workout-scroll")
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardWhenScrolling {
                    dismissKeyboard()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in dismissKeyboard() }
                )
                .background(AppTheme.background)
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
                .navigationTitle(session.templateName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink {
                            DailyWorkoutBuilderView(initialDate: session.plannedDate)
                        } label: {
                            Label("调整今日菜单", systemImage: "list.bullet")
                        }
                        .accessibilityIdentifier("调整今日菜单")

                        Button {
                            showExercisePicker = true
                        } label: {
                            Label("临时加动作", systemImage: "plus")
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { dismissKeyboard() }
                    }
                }
                .interactiveDismissDisabled()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    if selectedExerciseID == nil {
                        let parts = storedExpandedExercise.split(separator: ":")
                        let restored = parts.count == 2 && parts[0] == sessionID.uuidString
                            ? UUID(uuidString: String(parts[1])) : nil
                        selectedExerciseID = orderedExercises.contains { $0.id == restored }
                            ? restored : MuscleCoverageService.initialExpandedID(orderedExercises, logs: logs)
                    }
                    WorkoutExerciseTracking.startFirstExercise(in: orderedExercises, at: session.startedAt)
                    saveQuietly()
                }
                .onChange(of: selectedExerciseID) { _, id in
                    storedExpandedExercise = id.map { "\(sessionID.uuidString):\($0.uuidString)" } ?? ""
                }
                .onChange(of: orderedExercises.map(\.id)) { _, ids in
                    if let selectedExerciseID, !ids.contains(selectedExerciseID) {
                        self.selectedExerciseID = MuscleCoverageService.initialExpandedID(orderedExercises, logs: logs)
                    }
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } else {
                ContentUnavailableView("训练记录不存在", systemImage: "questionmark.folder")
            }
        }
        .confirmationDialog(
            "结束本次训练？",
            isPresented: $showFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("完成训练") { finishWorkout() }
            Button("继续记录", role: .cancel) {}
        } message: {
            Text(completedCount < logs.count ? "还有 \(logs.count - completedCount) 组未完成，未勾选的组不会计入训练容量。" : "所有工作组都已完成。")
        }
        .confirmationDialog(
            "放弃本次训练？",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃并退出", role: .destructive) { discardWorkout() }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("本次训练不会计入历史和统计，原训练日程会恢复为等待开始。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("RIR 是什么？", isPresented: $showRIRHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("RIR 表示一组结束后，在动作标准不变的情况下，你估计还能再完成几次。\n\n0 = 已经无法再做\n1 = 还能做 1 次\n2 = 还能做 2 次\n3 = 还能做 3 次\n\n不确定时可以选择不记录。它用于判断本组强度和后续训练建议。")
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(
                title: "添加临时动作",
                excludedExerciseIDs: Set(orderedExercises.map(\.exerciseID)),
                onConfiguredSelect: { exercise, draft in
                    addExercise(exercise, configuration: draft)
                }
            ) { exercise in
                addExercise(exercise)
            }
            .preferredColorScheme(.dark)
            .tint(AppTheme.accent)
        }
    }

    private func workoutHeader(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("训练进行中", systemImage: "record.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("开始于 \(session.startedAt, format: .dateTime.hour().minute())")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(completedCount)")
                        .font(.title2.weight(.black).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(AppTheme.accent)
                    Text("/ \(logs.count) 组")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(completedCount)/\(logs.count) 组")
                .accessibilityAddTraits(.isStaticText)
            }
            ProgressView(value: Double(completedCount), total: Double(max(1, logs.count)))
                .tint(AppTheme.accent)
        }
        .padding(.bottom, 4)
    }

    private func restModeCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("组间休息模式", systemImage: "stopwatch")
                    .font(.headline)
                Spacer()
                if hasActiveRest {
                    Text("本段结束后可切换")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker(
                "组间休息模式",
                selection: Binding(
                    get: { session.restMode.rawValue },
                    set: { rawValue in
                        session.restModeRaw = rawValue
                        session.restEndDate = nil
                        NotificationService.cancelRestEnd(sessionID: session.id)
                        saveQuietly()
                    }
                )
            ) {
                ForEach(WorkoutRestMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(hasActiveRest)
            .accessibilityIdentifier("组间休息模式")

            Text(
                session.restMode == .countdown
                    ? "完成一组后按计划倒计时，仍可临时增减 30 秒。"
                    : "每组开始前点“开始本组”；完成后正向记录休息，下一组开始时自动保存真实间歇。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var adjustmentCard: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "slider.horizontal.3")
                .font(.headline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("按今天状态调整训练量")
                    .font(.subheadline.bold())
                Text("可增减未完成组、修改重量与次数；需要时也可临时增加动作。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button("临时加动作") {
                showExercisePicker = true
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
        }
        .cardSurface()
    }

    @ViewBuilder
    private func restTimer(_ session: WorkoutSession, plannedRestSeconds: Int?) -> some View {
        if session.restMode == .freestyle, let startedAt = activeRestLog?.restStartedAt {
            freestyleRestTimer(session, startedAt: startedAt)
        } else {
            countdownRestTimer(session, plannedRestSeconds: plannedRestSeconds)
        }
    }

    private func countdownRestTimer(_ session: WorkoutSession, plannedRestSeconds: Int?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, Int((session.restEndDate ?? timeline.date).timeIntervalSince(timeline.date).rounded(.up)))

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.14))
                        Image(systemName: "timer")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(remaining > 0 ? "组间休息" : "休息结束")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(TrainingFormatters.clock(remaining))
                            .font(.title.bold().monospacedDigit())
                            .accessibilityIdentifier("rest-timer-value")
                        if let plannedRestSeconds {
                            Text("计划默认休息 \(plannedRestSeconds) 秒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        endRest(session)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("结束休息")
                }

                HStack(spacing: 12) {
                    Button {
                        adjustRest(session, by: -30)
                    } label: {
                        Label("−30 秒", systemImage: "minus")
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("减少 30 秒休息")

                    Button {
                        adjustRest(session, by: 30)
                    } label: {
                        Label("+30 秒", systemImage: "plus")
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
                    .accessibilityLabel("增加 30 秒休息")
                }
            }
            .cardSurface()
            .onChange(of: remaining) { _, value in
                // A newly backgrounded app can continue receiving timeline ticks
                // during iOS's short suspension grace period. Cancelling the
                // request there races notificationd and can suppress the alert
                // exactly when the user locks the phone. Let the system deliver
                // in the background; scene activation reconciles the expired rest.
                if value == 0, session.restEndDate != nil, scenePhase == .active {
                    presentRestEndedAlert(session)
                }
            }
        }
    }

    private func freestyleRestTimer(_ session: WorkoutSession, startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = max(0, Int(timeline.date.timeIntervalSince(startedAt).rounded(.down)))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.14))
                        Image(systemName: "stopwatch.fill")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("自由组间计时")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(TrainingFormatters.clock(elapsed))
                            .font(.title.bold().monospacedDigit())
                            .accessibilityIdentifier("freestyle-rest-timer-value")
                        Text("下一组开始前点对应的“开始本组”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        finishRest(session)
                    } label: {
                        Label("仅结束休息", systemImage: "stop.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)
                    .accessibilityLabel("结束自由休息")

                    Button {
                        abandonRest(session)
                    } label: {
                        Text("漏点了，稍后补录")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("取消本段休息并稍后补录")
                }
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private func exerciseCard(_ exercise: SessionExercise, session: WorkoutSession) -> some View {
        let exerciseLogs = logs
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        let isExerciseComplete = !exerciseLogs.isEmpty && exerciseLogs.allSatisfy(\.isCompleted)

        if selectedExerciseID != exercise.id {
            completedExerciseCard(exercise, logs: exerciseLogs)
        } else {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d", (orderedExercises.firstIndex { $0.id == exercise.id } ?? 0) + 1))
                    .font(.title2.weight(.black).monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("展开动作标题-\(exercise.exerciseName)")
                    if !exercise.exerciseNotes.isEmpty {
                        Label(exercise.exerciseNotes, systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.orange)
                            .lineLimit(2)
                            .accessibilityLabel("动作注意事项：\(exercise.exerciseNotes)")
                    }
                }
                Spacer()
                if !pendingFeelingExerciseIDs.contains(exercise.id) {
                    Button {
                        selectedExerciseID = nil
                    } label: {
                        Label("折叠", systemImage: "chevron.up")
                            .font(.caption.bold())
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                }
            }

            if exercise.volumeUnit.usesMeasurementSide {
                Picker("记录口径", selection: measurementSideBinding(for: exercise)) {
                    ForEach(MeasurementSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(exerciseLogs.allSatisfy(\.isCompleted))
                .accessibilityIdentifier("active-measurement-side-\(exercise.exerciseName)")
            }

            HStack {
                Text("组")
                    .frame(width: 30)
                if exercise.volumeUnit.recordsSingleAmount {
                    Text("\(exercise.volumeUnit.inputTitle) \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                } else if exercise.volumeUnit == .bodyweight {
                    Text("负重")
                        .frame(maxWidth: .infinity)
                    Text("次数")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("\(exercise.volumeUnit.inputTitle) \(exercise.volumeUnit.symbol)")
                        .frame(maxWidth: .infinity)
                    Text(exercise.volumeUnit.repetitionTitle)
                        .frame(maxWidth: .infinity)
                }
                if detailedExerciseIDs.contains(exercise.id) {
                    Button("RIR ?") { showRIRHelp = true }
                        .font(.caption).frame(width: 66, height: 44).contentShape(Rectangle()).accessibilityLabel("了解 RIR")
                }
                Color.clear
                    .frame(width: 44)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let reference = MuscleCoverageService.lastReference(for: exercise, sessions: sessions, snapshots: sessionExercises, logs: setLogs) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("上次实际 · \(reference.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(reference.rows.joined(separator: "  /  "))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.accessibilityIdentifier("上次实际-\(exercise.exerciseName)")
            }
            ForEach(exerciseLogs) { log in
                SetLogRow(
                    log: log,
                    exerciseName: exercise.exerciseName,
                    volumeUnit: exercise.volumeUnit,
                    bodyWeightKgSnapshot: exercise.bodyWeightKgSnapshot,
                    showsRIR: detailedExerciseIDs.contains(exercise.id),
                    onEdit: {
                        WorkoutExerciseTracking.recordInteraction(with: exercise)
                        saveQuietly()
                    },
                    onToggle: { toggle(log, exercise: exercise) }
                )
            }

            if isExerciseComplete {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("动作完成后的难度 / 体验", systemImage: "face.smiling")
                            .font(.caption.bold())
                        Spacer()
                        Text(exercise.feeling?.title ?? "选一个")
                            .font(.caption2)
                            .foregroundStyle(exercise.feeling == nil ? .secondary : AppTheme.accent)
                    }

                    HStack(spacing: 8) {
                        ForEach(WorkoutFeeling.allCases) { feeling in
                            Button {
                                completeFeeling(feeling, for: exercise)
                            } label: {
                                Text(feeling.emoji)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        exercise.feeling == feeling
                                            ? AppTheme.accent.opacity(0.18)
                                            : AppTheme.elevatedSurface,
                                        in: RoundedRectangle(cornerRadius: 11)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11)
                                            .stroke(
                                                exercise.feeling == feeling ? AppTheme.accent : AppTheme.line,
                                                lineWidth: exercise.feeling == feeling ? 1.5 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(feeling.emoji)，\(feeling.title)")
                            .accessibilityIdentifier("动作感受-\(feeling.rawValue)")
                            .accessibilityAddTraits(exercise.feeling == feeling ? .isSelected : [])
                        }
                    }

                    Text("😣 不适 · 😥 太难 · 😮 有挑战 · 🙂 正合适 · 😄 轻松顺畅")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("跳过感受并收起") {
                        skipFeeling(for: exercise)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("跳过感受并收起")
                }
                .padding(12)
                .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            DisclosureGroup("RIR、动作资料与备注", isExpanded: Binding(
                get: { detailedExerciseIDs.contains(exercise.id) },
                set: { if $0 { detailedExerciseIDs.insert(exercise.id) } else { detailedExerciseIDs.remove(exercise.id) } }
            )) {
            if let url = URL(string: exercise.referenceURL), !exercise.referenceURL.isEmpty {
                Link(destination: url) {
                    Label("查看动作资料", systemImage: "link")
                        .font(.caption.bold())
                }
                .foregroundStyle(AppTheme.accent)
            }

            TextField(
                "记录这个动作的状态、疼痛或技术提醒",
                text: Binding(
                    get: { exercise.performanceNotes },
                    set: {
                        exercise.performanceNotes = $0
                        saveQuietly()
                    }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.caption)
            .padding(10)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
            }.font(.caption).foregroundStyle(AppTheme.secondaryText)

        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topLeading) {
            Capsule().fill(AppTheme.accent).frame(width: 30, height: 3)
                .padding(.leading, 16)
                .accessibilityHidden(true)
        }
        }
    }

    private func completedExerciseCard(
        _ exercise: SessionExercise,
        logs exerciseLogs: [SetLog]
    ) -> some View {
        let completed = exerciseLogs.filter(\.isCompleted).count
        let complete = !exerciseLogs.isEmpty && completed == exerciseLogs.count
        return Button {
            selectedExerciseID = exercise.id
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    if complete {
                        Image(systemName: "checkmark").font(.headline.bold())
                    } else {
                        Text(String(format: "%02d", (orderedExercises.firstIndex { $0.id == exercise.id } ?? 0) + 1))
                            .font(.title2.weight(.black).monospacedDigit()).fontWidth(.condensed)
                    }
                }
                .foregroundStyle(complete ? AppTheme.accent : AppTheme.secondaryText)
                .frame(width: 36, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(
                        "\(completed)/\(exerciseLogs.count) 组"
                            + (exercise.durationSeconds.map { " · 用时 \(TrainingFormatters.clock($0))" } ?? "")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let feeling = exercise.feeling {
                    Text(feeling.emoji)
                        .font(.title3)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("切换动作-\(exercise.exerciseName)")
        .accessibilityLabel(
            "\(exercise.exerciseName)，" + (complete ? "已完成 \(completed) 组" : "已完成 \(completed)/\(exerciseLogs.count) 组")
                + (exercise.feeling.map { "，感受 \($0.emoji) \($0.title)" } ?? "")
                + "，点按展开记录"
        )
    }

    private func isExerciseCompleted(_ exercise: SessionExercise) -> Bool {
        let exerciseLogs = logs.filter { $0.sessionExerciseID == exercise.id }
        return !exerciseLogs.isEmpty && exerciseLogs.allSatisfy(\.isCompleted)
    }

    private func completeFeeling(_ feeling: WorkoutFeeling, for exercise: SessionExercise) {
        exercise.feeling = feeling
        pendingFeelingExerciseIDs.remove(exercise.id)
        selectedExerciseID = MuscleCoverageService.initialExpandedID(orderedExercises.filter { $0.id != exercise.id }, logs: logs)
        saveQuietly()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func skipFeeling(for exercise: SessionExercise) {
        pendingFeelingExerciseIDs.remove(exercise.id)
        selectedExerciseID = MuscleCoverageService.initialExpandedID(orderedExercises.filter { $0.id != exercise.id }, logs: logs)
        saveQuietly()
    }

    private func addExercise(_ exercise: Exercise, configuration: ExerciseSetupDraft? = nil) {
        guard let session else { return }
        do {
            try WorkoutService.addExercise(
                exercise,
                to: session,
                configuration: configuration,
                in: modelContext
            )
            showExercisePicker = false
            let activeSessionID = session.id
            let addedExerciseID = exercise.id
            let descriptor = FetchDescriptor<SessionExercise>(predicate: #Predicate {
                $0.sessionID == activeSessionID && $0.exerciseID == addedExerciseID
            }, sortBy: [SortDescriptor(\SessionExercise.order, order: .reverse)])
            selectedExerciseID = try modelContext.fetch(descriptor).first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func measurementSideBinding(for exercise: SessionExercise) -> Binding<MeasurementSide> {
        Binding {
            WorkoutMeasurementSideEditing.selected(in: logs.filter { $0.sessionExerciseID == exercise.id })
        } set: { side in
            WorkoutMeasurementSideEditing.apply(side, to: exercise, logs: logs)
            saveQuietly()
        }
    }

    private func addSet(to exercise: SessionExercise) {
        do {
            try WorkoutService.addSet(to: exercise, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeLastSet(from exercise: SessionExercise) {
        do {
            try WorkoutService.removeLastIncompleteSet(from: exercise, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeExercise(_ exercise: SessionExercise, from session: WorkoutSession) {
        do {
            try WorkoutService.removeExercise(exercise, from: session, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var finishButton: some View {
        Button {
            showFinishConfirmation = true
        } label: {
            Label("完成本次训练", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .foregroundStyle(.black)
        .disabled(completedCount == 0)
        .padding(.vertical, 6)
    }

    private var discardButton: some View {
        Button(role: .destructive) {
            showDiscardConfirmation = true
        } label: {
            Label("放弃本次训练", systemImage: "xmark.circle")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func notesCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("训练备注", systemImage: "note.text")
                .font(.headline)
            TextField("记录状态、疼痛、器械调整等", text: Binding(
                get: { session.notes },
                set: {
                    session.notes = $0
                    saveQuietly()
                }
            ), axis: .vertical)
            .lineLimit(3...6)
            .padding(12)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .cardSurface()
    }

    private func toggle(_ log: SetLog, exercise: SessionExercise) {
        let now = Date.now
        let isCompletingExercise = !log.isCompleted && logs
            .filter { $0.sessionExerciseID == log.sessionExerciseID }
            .allSatisfy { $0.id == log.id || $0.isCompleted }
        log.isCompleted.toggle()
        log.completedAt = log.isCompleted ? now : nil

        if isCompletingExercise {
            pendingFeelingExerciseIDs.insert(log.sessionExerciseID)
            selectedExerciseID = log.sessionExerciseID
        } else if !log.isCompleted {
            pendingFeelingExerciseIDs.remove(log.sessionExerciseID)
            selectedExerciseID = log.sessionExerciseID
        }

        let exerciseLogs = logs.filter { $0.sessionExerciseID == exercise.id }
        let following = sessionExercises
            .filter { $0.sessionID == sessionID && $0.order > exercise.order }
            .min { $0.order < $1.order }
        WorkoutExerciseTracking.updateAfterSetChange(
            exercise: exercise,
            logs: exerciseLogs,
            followingExercise: following,
            at: now
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        saveQuietly()
    }

    private func startSet(_ log: SetLog, session: WorkoutSession) {
        guard session.restMode == .freestyle, !log.isCompleted, log.startedAt == nil else { return }
        NotificationService.cancelRestEnd(sessionID: session.id)
        _ = WorkoutRestTracking.startSet(log, session: session, logs: logs)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        saveQuietly()
    }

    private func adjustRest(_ session: WorkoutSession, by seconds: Int) {
        let now = Date.now
        let currentEndDate = max(session.restEndDate ?? now, now)
        let adjustedEndDate = currentEndDate.addingTimeInterval(TimeInterval(seconds))

        guard adjustedEndDate > now else {
            finishRest(session, at: now)
            return
        }

        session.restEndDate = adjustedEndDate
        saveQuietly()
        NotificationService.scheduleRestEnd(sessionID: session.id, at: adjustedEndDate)
    }

    private func endRest(_ session: WorkoutSession) {
        finishRest(session)
    }

    private func finishRest(_ session: WorkoutSession, at date: Date = .now) {
        _ = WorkoutRestTracking.finish(session: session, logs: logs, at: date)
        NotificationService.cancelRestEnd(sessionID: session.id)
        saveQuietly()
    }

    private func abandonRest(_ session: WorkoutSession, save: Bool = true) {
        WorkoutRestTracking.abandon(session: session, logs: logs)
        NotificationService.cancelRestEnd(sessionID: session.id)
        if save { saveQuietly() }
    }

    private func finishExpiredCountdownIfNeeded(_ session: WorkoutSession) {
        guard session.restMode == .countdown,
              let endDate = session.restEndDate,
              endDate <= .now else { return }
        presentRestEndedAlert(session)
    }

    private func presentRestEndedAlert(_ session: WorkoutSession) {
        guard let endDate = session.restEndDate,
              restPromptedForEndDate != endDate else { return }
        restPromptedForEndDate = endDate
        showRestEndedAlert = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func recoverRestState(_ session: WorkoutSession) {
        let repaired = WorkoutRestTracking.reconcile(session: session, logs: logs)
        finishExpiredCountdownIfNeeded(session)
        if repaired { saveQuietly() }
    }

    private func finishWorkout() {
        guard let session else { return }
        do {
            try WorkoutService.finish(session: session, schedules: schedules, in: modelContext)
            NotificationService.cancelRestEnd(sessionID: session.id)
            if UserDefaults.standard.bool(forKey: HealthKitService.enabledKey),
               let completedAt = session.completedAt {
                let startedAt = session.startedAt
                Task {
                    try? await HealthKitService.shared.saveWorkout(start: startedAt, end: completedAt)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout() {
        guard let session else { return }
        do {
            try WorkoutService.discard(session: session, schedules: schedules, in: modelContext)
            NotificationService.cancelRestEnd(sessionID: session.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveQuietly() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        KeyboardDismissal.dismiss()
    }
}

private struct LegacyWorkoutExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let excludedExerciseIDs: Set<UUID>
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""

    private var availableExercises: [Exercise] {
        exercises.filter {
            !$0.isArchived
                && !excludedExerciseIDs.contains($0.id)
                && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableExercises.isEmpty {
                    ContentUnavailableView(
                        "没有可添加的动作",
                        systemImage: "dumbbell",
                        description: Text("可先在动作库新增动作，或尝试其他搜索词。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(availableExercises) { exercise in
                        Button {
                            onSelect(exercise)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name)
                                        .foregroundStyle(.primary)
                                    Text("\(exercise.muscleGroup) · \(exercise.equipment) · 默认休息 \(exercise.defaultRestSeconds) 秒")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索动作")
            .navigationTitle("添加临时动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct SetLogRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var log: SetLog
    @State private var showRIRPicker = false
    let exerciseName: String
    let volumeUnit: ExerciseVolumeUnit
    let bodyWeightKgSnapshot: Double?
    let showsRIR: Bool
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        Group {
            if log.isCompleted {
                completedRow
            } else {
                editableRow
            }
        }
        .onChange(of: log.actualWeight) { _, _ in onEdit() }
        .onChange(of: log.actualReps) { _, _ in onEdit() }
        .onChange(of: log.rir) { _, _ in onEdit() }
        .confirmationDialog("本组还剩多少余力？", isPresented: $showRIRPicker, titleVisibility: .visible) {
            Button("不记录 RIR") { log.rir = nil }
            ForEach(0...5, id: \.self) { value in
                Button(rirOptionTitle(value)) { log.rir = value }
            }
        } message: {
            Text("RIR 0 表示已无余力；RIR 3 表示大约还能完成 3 次。")
        }
    }

    private var completedRow: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Text("第 \(log.setNumber) 组")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text(completedSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(AppTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(log.setNumber) 组已完成，\(completedSummary)，点按撤销完成")
        .accessibilityIdentifier("第 \(log.setNumber) 组已完成")
        .accessibilityValue("已完成")
    }

    private var editableRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text("第 \(log.setNumber) 组").font(.subheadline.bold())
                    Spacer()
                    completionButton
                }
                amountInputs
                if showsRIR { rirButton }
            } else {
                HStack(spacing: 8) {
                    Text("\(log.setNumber)").font(.subheadline.bold().monospacedDigit()).frame(width: 30)
                    amountInputs
                    completionButton
                }
                if showsRIR {
                    HStack { Spacer(); rirButton }
                }
            }
        }
    }

    private var amountInputs: some View {
        HStack(spacing: 8) {
            if volumeUnit.recordsNumericLoad {
                StableNumericTextField(volumeUnit.inputTitle, value: $log.actualWeight,
                    maximumFractionDigits: 3,
                    accessibilityIdentifier: "actual-weight-\(exerciseName)-\(log.setNumber)")
                    .padding(.horizontal, 8).frame(minHeight: 44)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
            } else if volumeUnit == .bodyweight {
                Text(bodyWeightKgSnapshot.map { "\(TrainingFormatters.weight($0)) kg" } ?? "暂无体重")
                    .font(.subheadline.bold())
                    .foregroundStyle(bodyWeightKgSnapshot == nil ? AppTheme.orange : AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
            }
            StableNumericTextField(volumeUnit.recordsSingleAmount ? volumeUnit.inputTitle : volumeUnit.repetitionTitle,
                value: $log.actualReps, accessibilityIdentifier: "actual-reps-\(exerciseName)-\(log.setNumber)")
                .padding(.horizontal, 8).frame(minHeight: 44)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)
        }
    }

    private var completionButton: some View {
        Button(action: onToggle) {
            Image(systemName: "circle").font(.title2.weight(.regular)).foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("完成第 \(log.setNumber) 组")
            .accessibilityIdentifier("完成第 \(log.setNumber) 组")
            .accessibilityValue("未完成")
    }

    private var rirButton: some View {
        Button { showRIRPicker = true } label: {
            Text(log.rir.map { "RIR \($0)" } ?? "RIR 可选")
                .font(.caption.bold().monospacedDigit()).padding(.horizontal, 12).frame(minHeight: 44)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
        }.foregroundStyle(AppTheme.secondaryText).contentShape(Rectangle())
            .accessibilityLabel(rirAccessibilityLabel)
            .accessibilityIdentifier("rir-\(exerciseName)-\(log.setNumber)")
    }

    private var completedSummary: String {
        var parts: [String] = []
        if volumeUnit.recordsSingleAmount {
            parts.append("\(log.actualReps) \(volumeUnit.symbol)")
        } else if volumeUnit == .bodyweight {
            if let bodyWeightKgSnapshot {
                parts.append("\(TrainingFormatters.weight(bodyWeightKgSnapshot)) kg × \(log.actualReps)")
            } else {
                parts.append("暂无体重 × \(log.actualReps)")
            }
        } else {
            if volumeUnit.usesMeasurementSide {
                parts.append("\(TrainingFormatters.weight(log.actualWeight)) \(volumeUnit.symbol)（\(log.actualWeightSide.title)） × \(log.actualReps)（\(log.actualRepsSide.title)）")
            } else {
                parts.append("\(TrainingFormatters.weight(log.actualWeight)) \(volumeUnit.symbol) × \(log.actualReps)")
            }
        }
        if let rir = log.rir { parts.append("RIR \(rir)") }
        return parts.joined(separator: " · ")
    }

    private func rirOptionTitle(_ value: Int) -> String {
        if value == 0 {
            return "RIR 0 · 已无余力"
        }
        return "RIR \(value) · 还能做 \(value) 次"
    }

    private var rirAccessibilityLabel: String {
        guard let rir = log.rir else {
            return "第 \(log.setNumber) 组 RIR，未记录"
        }
        if rir == 0 {
            return "第 \(log.setNumber) 组 RIR 0，已无余力"
        }
        return "第 \(log.setNumber) 组 RIR \(rir)，还能做 \(rir) 次"
    }
}

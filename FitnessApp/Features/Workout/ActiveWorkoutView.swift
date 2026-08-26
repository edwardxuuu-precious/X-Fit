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
    @State private var showRestEndedAlert = false
    @State private var restPromptedForEndDate: Date?
    @State private var expandedCompletedExerciseIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var orderedExercises: [SessionExercise] {
        sessionExercises
            .filter { $0.sessionID == sessionID }
            .sorted { left, right in
                let leftComplete = isExerciseCompleted(left)
                let rightComplete = isExerciseCompleted(right)
                if leftComplete != rightComplete { return !leftComplete }
                return left.order < right.order
            }
    }

    private var logs: [SetLog] {
        setLogs.filter { $0.sessionID == sessionID }
    }

    private var completedCount: Int {
        logs.filter(\.isCompleted).count
    }

    private var activeRestLog: SetLog? {
        WorkoutRestTracking.activeLog(in: logs)
    }

    private var hasActiveRest: Bool {
        activeRestLog != nil || session?.restEndDate != nil
    }

    private var activeRestExercise: SessionExercise? {
        if let activeRestLog {
            return orderedExercises.first { $0.id == activeRestLog.sessionExerciseID }
        }
        let completedLogs = logs.filter { $0.isCompleted && $0.completedAt != nil }
        guard let latestCompletedLog = completedLogs.max(by: {
            ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
        }) else {
            return nil
        }
        return orderedExercises.first { $0.id == latestCompletedLog.sessionExerciseID }
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(spacing: 16) {
                        workoutHeader(session)

                        restModeCard(session)

                        if hasActiveRest {
                            restTimer(session, plannedRestSeconds: activeRestExercise?.restSeconds)
                        }

                        adjustmentCard

                        ForEach(orderedExercises) { exercise in
                            exerciseCard(exercise, session: session)
                        }

                        notesCard(session)
                        finishButton
                        discardButton
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppTheme.background)
                .navigationTitle(session.templateName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showExercisePicker = true
                        } label: {
                            Label("临时加动作", systemImage: "plus")
                        }
                    }
                }
                .interactiveDismissDisabled()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    recoverRestState(session)
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    recoverRestState(session)
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
        .alert("休息结束", isPresented: $showRestEndedAlert) {
            Button("开始下一组") {
                if let session { finishRest(session) }
            }
            Button("+30 秒") {
                if let session { adjustRest(session, by: 30) }
            }
        } message: {
            Text("可以开始下一组；如果还没准备好，可以再休息 30 秒。")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("训练进行中")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Text("开始于 \(session.startedAt, format: .dateTime.hour().minute())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(completedCount)/\(logs.count) 组")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: Double(completedCount), total: Double(max(1, logs.count)))
                .tint(AppTheme.accent)

            Text("每一组都会立即保存在本机，退出后可以继续。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
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
            .sorted { left, right in
                if left.isCompleted != right.isCompleted { return !left.isCompleted }
                return left.setNumber < right.setNumber
            }
        let isExerciseComplete = !exerciseLogs.isEmpty && exerciseLogs.allSatisfy(\.isCompleted)

        if isExerciseComplete && !expandedCompletedExerciseIDs.contains(exercise.id) {
            completedExerciseCard(exercise, logs: exerciseLogs)
        } else {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.title3.bold())
                    if !exercise.exerciseNotes.isEmpty {
                        Label(exercise.exerciseNotes, systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.orange)
                            .lineLimit(2)
                            .accessibilityLabel("动作注意事项：\(exercise.exerciseNotes)")
                    }
                    Text("计划 \(exercise.plannedSets.count) 组 · \(exercise.planPattern.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("训练量单位：\(exercise.volumeUnit.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("计划默认组间休息 \(exercise.restSeconds) 秒", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("实际 \(exerciseLogs.filter(\.isCompleted).count)/\(exerciseLogs.count) 组")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    if exerciseLogs.count != exercise.plannedSets.count {
                        Text("组数差 \(exerciseLogs.count > exercise.plannedSets.count ? "+" : "")\(exerciseLogs.count - exercise.plannedSets.count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.orange)
                    }
                    Menu {
                        Button {
                            addSet(to: exercise)
                        } label: {
                            Label("增加一组", systemImage: "plus.circle")
                        }
                        Button {
                            removeLastSet(from: exercise)
                        } label: {
                            Label("减少最后未完成组", systemImage: "minus.circle")
                        }
                        .disabled(exerciseLogs.count <= 1 || exerciseLogs.last?.isCompleted != false)
                        Divider()
                        Button(role: .destructive) {
                            removeExercise(exercise, from: session)
                        } label: {
                            Label("移除未开始动作", systemImage: "trash")
                        }
                        .disabled(exerciseLogs.contains(where: \.isCompleted) || orderedExercises.count <= 1)
                    } label: {
                        Label("调整训练量", systemImage: "ellipsis")
                            .font(.caption.bold())
                    }
                    .accessibilityIdentifier("adjust-volume-\(exercise.exerciseName)")
                    .foregroundStyle(.secondary)

                    if isExerciseComplete {
                        Button {
                            expandedCompletedExerciseIDs.remove(exercise.id)
                        } label: {
                            Label("折叠", systemImage: "chevron.up")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            if exercise.volumeUnit.usesMeasurementSide {
                Picker("记录口径", selection: measurementSideBinding(for: exercise)) {
                    ForEach(MeasurementSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("active-measurement-side-\(exercise.exerciseName)")
            }

            HStack {
                Text("组")
                    .frame(width: 30)
                if exercise.volumeUnit == .count {
                    Text("数量 个")
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
                Button {
                    showRIRHelp = true
                } label: {
                    HStack(spacing: 3) {
                        Text("RIR")
                        Image(systemName: "questionmark.circle")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 66)
                .accessibilityLabel("了解 RIR")
                Color.clear
                    .frame(width: 38)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(exerciseLogs) { log in
                SetLogRow(
                    log: log,
                    exerciseName: exercise.exerciseName,
                    volumeUnit: exercise.volumeUnit,
                    restMode: session.restMode,
                    isActiveRest: activeRestLog?.id == log.id,
                    isExtraSet: log.setNumber > exercise.plannedSets.count,
                    onEdit: saveQuietly,
                    onStart: { startSet(log, session: session) },
                    onToggle: { toggle(log, restSeconds: exercise.restSeconds, session: session) }
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
                                exercise.feeling = feeling
                                saveQuietly()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                }
                .padding(12)
                .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

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
        }
        .cardSurface()
        .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
        }
    }

    private func completedExerciseCard(
        _ exercise: SessionExercise,
        logs exerciseLogs: [SetLog]
    ) -> some View {
        Button {
            expandedCompletedExerciseIDs.insert(exercise.id)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("已完成 \(exerciseLogs.count) 组 · 已移到下方")
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
            .cardSurface()
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.30), radius: 14, y: 8)
        .accessibilityLabel("\(exercise.exerciseName)，已完成 \(exerciseLogs.count) 组，点按展开记录")
    }

    private func isExerciseCompleted(_ exercise: SessionExercise) -> Bool {
        let exerciseLogs = logs.filter { $0.sessionExerciseID == exercise.id }
        return !exerciseLogs.isEmpty && exerciseLogs.allSatisfy(\.isCompleted)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func measurementSideBinding(for exercise: SessionExercise) -> Binding<MeasurementSide> {
        Binding {
            logs
                .filter { $0.sessionExerciseID == exercise.id }
                .sorted { $0.setNumber < $1.setNumber }
                .first?.actualWeightSide ?? .bilateral
        } set: { side in
            var plans = exercise.plannedSets
            plans = plans.map { plan in
                WorkoutSetPlan(
                    id: plan.id,
                    weight: plan.weight,
                    reps: plan.reps,
                    weightSide: side,
                    repsSide: side
                )
            }
            exercise.plannedSets = plans
            logs
                .filter { $0.sessionExerciseID == exercise.id && !$0.isCompleted }
                .forEach { log in
                    log.targetWeightSide = side
                    log.targetRepsSide = side
                    log.actualWeightSide = side
                    log.actualRepsSide = side
                }
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

    private func toggle(_ log: SetLog, restSeconds: Int, session: WorkoutSession) {
        log.isCompleted.toggle()
        log.completedAt = log.isCompleted ? .now : nil

        if WorkoutRestTracking.shouldBeginRest(after: log, logs: logs) {
            WorkoutRestTracking.begin(
                after: log,
                session: session,
                logs: logs,
                plannedRestSeconds: restSeconds
            )
            if session.restMode == .countdown, let endDate = session.restEndDate {
                // Adding with the same identifier atomically replaces an older
                // timer. A separate asynchronous remove can arrive after this
                // add on a physical device and delete the new request.
                NotificationService.scheduleRestEnd(sessionID: session.id, at: endDate)
            } else {
                NotificationService.cancelRestEnd(sessionID: session.id)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if !log.isCompleted {
            if activeRestLog?.id == log.id {
                abandonRest(session, save: false)
            }
            WorkoutRestTracking.clearRest(on: log)
        }
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
            WorkoutRestTracking.abandon(session: session, logs: logs)
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
            WorkoutRestTracking.abandon(session: session, logs: logs)
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
    @Bindable var log: SetLog
    @State private var showRIRPicker = false
    let exerciseName: String
    let volumeUnit: ExerciseVolumeUnit
    let restMode: WorkoutRestMode
    let isActiveRest: Bool
    let isExtraSet: Bool
    let onEdit: () -> Void
    let onStart: () -> Void
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
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.accent.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
        .accessibilityLabel("第 \(log.setNumber) 组已完成，\(completedSummary)，点按撤销完成")
        .accessibilityIdentifier("第 \(log.setNumber) 组已完成")
    }

    private var editableRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isExtraSet {
                    Text("加练")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                if volumeUnit == .count {
                    Text("\(log.targetReps) 个 · \(log.targetRepsSide.title)")
                } else if volumeUnit == .bodyweight {
                    Text("自重 × \(log.targetReps) 次")
                } else {
                    Text(
                        "\(TrainingFormatters.weight(log.targetWeight)) \(volumeUnit.symbol)（\(log.targetWeightSide.title)） × "
                            + "\(log.targetReps)（\(log.targetRepsSide.title)）"
                    )
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("\(log.setNumber)")
                    .font(.subheadline.bold().monospacedDigit())
                    .frame(width: 30)

                if volumeUnit.recordsNumericLoad {
                    StableNumericTextField(
                        volumeUnit.inputTitle,
                        value: $log.actualWeight,
                        maximumFractionDigits: 3,
                        accessibilityIdentifier: "actual-weight-\(exerciseName)-\(log.setNumber)"
                    )
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
                } else if volumeUnit == .bodyweight {
                    Text("自重")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                StableNumericTextField(
                    volumeUnit == .count ? "数量" : volumeUnit.repetitionTitle,
                    value: $log.actualReps,
                    accessibilityIdentifier: "actual-reps-\(exerciseName)-\(log.setNumber)"
                )
                .padding(.vertical, 9)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)

                Button {
                    showRIRPicker = true
                } label: {
                    Text(log.rir.map { "RIR \($0)" } ?? "RIR 可选")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 66)
                        .padding(.vertical, 9)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(rirAccessibilityLabel)

                Button(action: onToggle) {
                    Image(systemName: log.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(log.isCompleted ? AppTheme.accent : Color.secondary)
                }
                .frame(width: 38)
                .accessibilityLabel(log.isCompleted ? "标记为未完成" : "完成第 \(log.setNumber) 组")
                .accessibilityIdentifier(
                    log.isCompleted ? "第 \(log.setNumber) 组已完成" : "完成第 \(log.setNumber) 组"
                )
            }

            if let differenceText {
                Text(differenceText)
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            if restMode == .freestyle, !log.isCompleted {
                Button(action: onStart) {
                    Label(
                        log.startedAt == nil ? "开始本组" : "本组进行中",
                        systemImage: log.startedAt == nil ? "play.fill" : "figure.strengthtraining.traditional"
                    )
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
                .disabled(log.startedAt != nil)
                .accessibilityLabel(log.startedAt == nil ? "开始第 \(log.setNumber) 组" : "第 \(log.setNumber) 组进行中")
                .accessibilityIdentifier(
                    log.startedAt == nil ? "开始第 \(log.setNumber) 组" : "第 \(log.setNumber) 组进行中"
                )
            }

            if isActiveRest {
                Label("组后休息计时中", systemImage: "stopwatch")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            } else if let restDurationSeconds = log.restDurationSeconds {
                Label(
                    "组后休息 \(TrainingFormatters.clock(restDurationSeconds))",
                    systemImage: "timer"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var completedSummary: String {
        var parts: [String] = []
        if volumeUnit == .count {
            parts.append("\(log.actualReps) 个")
        } else if volumeUnit == .bodyweight {
            parts.append("自重 × \(log.actualReps)")
        } else {
            parts.append("\(TrainingFormatters.weight(log.actualWeight)) \(volumeUnit.symbol) × \(log.actualReps)")
        }
        if let rir = log.rir { parts.append("RIR \(rir)") }
        if let restDurationSeconds = log.restDurationSeconds {
            parts.append("组后休息 \(TrainingFormatters.clock(restDurationSeconds))")
        }
        return parts.joined(separator: " · ")
    }

    private var differenceText: String? {
        var differences: [String] = []
        if volumeUnit.recordsNumericLoad {
            let weightDelta = log.actualWeight - log.targetWeight
            if abs(weightDelta) > 0.001 || log.actualWeightSide != log.targetWeightSide {
                let sign = weightDelta > 0 ? "+" : ""
                differences.append(
                    "重量 \(sign)\(TrainingFormatters.weight(weightDelta)) \(volumeUnit.symbol)（\(log.actualWeightSide.title)）"
                )
            }
        }
        let repsDelta = log.actualReps - log.targetReps
        if repsDelta != 0 || log.actualRepsSide != log.targetRepsSide {
            let sign = repsDelta > 0 ? "+" : ""
            differences.append("次数 \(sign)\(repsDelta)（\(log.actualRepsSide.title)）")
        }
        if isExtraSet {
            differences.insert("比计划多 1 组", at: 0)
        }
        return differences.isEmpty ? nil : "与计划：" + differences.joined(separator: " · ")
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

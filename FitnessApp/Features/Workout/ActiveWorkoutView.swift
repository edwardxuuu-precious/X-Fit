import SwiftData
import SwiftUI
import UIKit
import Observation

/// Stable, explicitly refreshed membership for one workout. The model instances
/// remain observed by SwiftUI/@Bindable; ordinary field edits require no refetch.
@MainActor @Observable
final class ActiveWorkoutData {
    let sessionID: UUID
    private(set) var session: WorkoutSession?
    private(set) var exercises: [SessionExercise] = []
    private(set) var logs: [SetLog] = []
    private(set) var schedules: [ScheduledWorkout] = []
    private(set) var hasLoaded = false

    init(sessionID: UUID) { self.sessionID = sessionID }

    func reload(in context: ModelContext) throws {
        let currentID = sessionID
        var sessionRequest = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == currentID })
        sessionRequest.fetchLimit = 1
        let loadedSession = try context.fetch(sessionRequest).first
        let loadedExercises = try context.fetch(FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.sessionID == currentID },
            sortBy: [SortDescriptor(\SessionExercise.order), SortDescriptor(\SessionExercise.id)]
        ))
        let loadedLogs = try context.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.sessionID == currentID },
            sortBy: [SortDescriptor(\SetLog.setNumber), SortDescriptor(\SetLog.id)]
        ))
        let loadedSchedules: [ScheduledWorkout]
        if let scheduleID = loadedSession?.scheduledWorkoutID {
            loadedSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>(predicate: #Predicate { $0.id == scheduleID }))
        } else {
            loadedSchedules = []
        }
        // Publish only after every fetch succeeds; never reseed or save actual values.
        session = loadedSession
        exercises = loadedSession == nil ? [] : loadedExercises
        logs = loadedSession == nil ? [] : loadedLogs
        schedules = loadedSchedules
        hasLoaded = true
    }
}

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(WorkoutSaveIssueState.self) private var saveIssues
    @State private var workoutData: ActiveWorkoutData

    let sessionID: UUID
    init(sessionID: UUID) {
        self.sessionID = sessionID
        _workoutData = State(initialValue: ActiveWorkoutData(sessionID: sessionID))
    }

    @State private var pendingReduction: (exercise: SessionExercise, candidateID: UUID)?
    @State private var showReductionConfirmation = false
    @State private var showFinishConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showExercisePicker = false
    @State private var replacementPresentation: WorkoutExerciseReplacementPresentation?
    @State private var showExerciseOrder = false
    @State private var inputBeforeSorting: WorkoutOrderInputFocus?
    @State private var showRIRHelp = false
    // Legacy rest helpers remain decode-compatible but are no longer reachable from the workout UI.
    @State private var showRestEndedAlert = false
    @State private var restPromptedForEndDate: Date?
    @State private var selectedExerciseID: UUID?
    @State private var detailedExerciseIDs: Set<UUID> = []
    @State private var editingNotesExerciseIDs: Set<UUID> = []
    @AppStorage("xfit.active.expandedExercise") private var storedExpandedExercise = ""
    @State private var showsSessionNotes = false
    @State private var pendingFeelingExerciseIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var historyReferences: [UUID: WorkoutHistoryReference] = [:]
    @State private var completionSummary: WorkoutCompletionSummary?

    private var session: WorkoutSession? { workoutData.session }
    private var sessionExercises: [SessionExercise] { workoutData.exercises }
    private var schedules: [ScheduledWorkout] { workoutData.schedules }

    private var orderedExercises: [SessionExercise] {
        MuscleCoverageService.stableOrder(sessionExercises, sessionID: sessionID)
    }

    private var logs: [SetLog] { workoutData.logs.filter { $0.reductionOrder == nil } }

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
        workoutContent
        .alert("剩余组已有输入", isPresented: replacementConfirmationPresented) {
            if case let .confirming(review)? = replacementPresentation {
                Button("继续选择替换动作") {
                    replacementPresentation = .choosing(review, confirmingEnteredData: true)
                }
            }
            Button("取消", role: .cancel) { replacementPresentation = nil }
        } message: {
            if case let .confirming(review)? = replacementPresentation {
                Text(review.sets.contains(where: \.isCompleted)
                    ? "已完成组保持原样。替换后，剩余组输入会保留为已减组记录，不会带给新动作。使用新动作设置后才会替换，取消保持原记录。"
                    : "使用新动作设置后，原动作及未完成输入会移除，不会带给新动作。选择或取消不会立即替换。")
            }
        }
        .sheet(item: replacementPickerPresented) { presentation in
            if case let .choosing(review, confirmingEnteredData) = presentation {
                ExercisePickerSheet(
                    title: "替换剩余动作",
                    excludedExerciseIDs: Set(orderedExercises.map(\.exerciseID)),
                    defaultSetCount: review.defaultSetCount,
                    onConfiguredSelect: { exercise, draft in
                        replaceExercise(exercise, configuration: draft, review: review,
                            confirmingEnteredData: confirmingEnteredData)
                    }
                ) { _ in }
                .sprintPage()
                .tint(AppTheme.ink)
            }
        }
    }

    private var workoutContent: some View {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                .navigationTitle(TrainingWorkoutPresentation.title(session.templateName))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { workoutToolbar }
                .interactiveDismissDisabled()
                .onChange(of: selectedExerciseID) { _, id in
                    storedExpandedExercise = id.map { "\(sessionID.uuidString):\($0.uuidString)" } ?? ""
                }
            } else if !workoutData.hasLoaded {
                ProgressView("读取本次训练…")
            } else {
                ContentUnavailableView("训练记录不存在", systemImage: "questionmark.folder")
            }
        }
        .sprintPage()
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { prepareWorkoutView() }
        .onDisappear {
            _ = flushPendingInput()
            WorkoutInputProfiler.shared.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .disabled(completionSummary != nil)
        .accessibilityHidden(completionSummary != nil)
        .fullScreenCover(item: $completionSummary, onDismiss: { dismiss() }) { summary in
            WorkoutCompletionCelebration(summary: summary) { setCompletionPresentation(nil) }
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { prepareWorkoutView() }
            else { _ = flushPendingInput(); WorkoutInputProfiler.shared.stop() }
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
        .alert("这组已有输入", isPresented: $showReductionConfirmation) {
            Button("确认减组", role: .destructive) {
                if let pending = pendingReduction { reduceSet(pending.exercise, candidateID: pending.candidateID, confirmed: true) }
                pendingReduction = nil
            }
            Button("取消", role: .cancel) { pendingReduction = nil }
        } message: {
            Text("减组后内容会保留，结束训练前可撤销减组恢复。")
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
        .sheet(isPresented: $showExerciseOrder, onDismiss: {
            do { try reloadWorkoutData() }
            catch { errorMessage = "本次训练读取失败：\(error.localizedDescription)" }
            let inputFocus = inputBeforeSorting
            inputBeforeSorting = nil
            DispatchQueue.main.async { inputFocus?.restore() }
        }) {
            if let session {
                WorkoutExerciseOrderSheet(sessionID: sessionID, plannedDate: session.plannedDate) { ids in
                    guard flushPendingInput() else { throw WorkoutExerciseOrderSheetError.inputSaveFailed }
                    try WorkoutService.reorderExercises(
                        sessionID: sessionID, orderedSessionExerciseIDs: ids, in: modelContext
                    )
                }
                .sprintPage()
                .tint(AppTheme.ink)
            }
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
            .sprintPage()
            .tint(AppTheme.ink)
        }

    }

    private var replacementConfirmationPresented: Binding<Bool> {
        Binding {
            if case .confirming? = replacementPresentation { return true }
            return false
        } set: { presented in
            if !presented, case .confirming? = replacementPresentation { replacementPresentation = nil }
        }
    }

    private var replacementPickerPresented: Binding<WorkoutExerciseReplacementPresentation?> {
        Binding {
            if case .choosing? = replacementPresentation { return replacementPresentation }
            return nil
        } set: { replacementPresentation = $0 }
    }

    @ToolbarContentBuilder
    private var workoutToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    let inputFocus = inputBeforeSorting ?? WorkoutOrderInputFocus.capture()
                    guard flushPendingInput() else { return }
                    inputBeforeSorting = inputFocus
                    dismissKeyboard()
                    showExerciseOrder = true
                } label: {
                    Label("动作列表与排序", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("调整今日菜单")

                Button {
                    showExercisePicker = true
                } label: {
                    Label("临时加动作", systemImage: "plus")
                }
            } label: {
                Label("更多训练操作", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("训练更多操作")
            .simultaneousGesture(TapGesture().onEnded {
                inputBeforeSorting = WorkoutOrderInputFocus.capture()
            })
            Button("结束") {
                guard flushPendingInput() else { return }
                showFinishConfirmation = true
            }.font(.subheadline.bold()).tint(AppTheme.ink)
                .disabled(completedCount == 0)
                .accessibilityLabel("结束本次训练")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { dismissKeyboard() }
        }
    }

    private func workoutHeader(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let overviewLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            let metadataLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                : AnyLayout(HStackLayout(spacing: 5))
            overviewLayout {
                metadataLayout {
                    Label(session.status == .completed ? "已记录" : "进行中", systemImage: "record.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("开始于 \(session.startedAt, format: .dateTime.hour().minute())")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(completedCount)")
                        .font(.title2.weight(.black).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(AppTheme.ink)
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
        .padding(.top, 3).padding(.bottom, 12)
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
                .foregroundStyle(AppTheme.ink)
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
            .buttonStyle(SprintSecondaryButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .tint(AppTheme.ink)
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
                            .foregroundStyle(AppTheme.ink)
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
                    .buttonStyle(SprintSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
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
                    .buttonStyle(SprintSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("减少 30 秒休息")

                    Button {
                        adjustRest(session, by: 30)
                    } label: {
                        Label("+30 秒", systemImage: "plus")
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SprintPrimaryButtonStyle())
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
                            .foregroundStyle(AppTheme.ink)
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
                    .buttonStyle(SprintPrimaryButtonStyle())
                    .accessibilityLabel("结束自由休息")

                    Button {
                        abandonRest(session)
                    } label: {
                        Text("漏点了，稍后补录")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SprintSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
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
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    ExerciseArtworkView(exerciseID: exercise.exerciseID, name: exercise.exerciseName,
                        size: isExerciseComplete ? 52 : 58)
                        .overlay(alignment: .bottomTrailing) {
                            if isExerciseComplete { exerciseCompletionBadge }
                        }
                    ExerciseExplanationButton(exerciseID: exercise.exerciseID, name: exercise.exerciseName,
                        equipment: exercise.equipmentSnapshot ?? "", referenceURL: exercise.referenceURL,
                        showsName: true, titleAccessibilityID: "展开动作标题-\(exercise.exerciseName)",
                        beforeOpen: { flushPendingInput() })
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    replacementButton(for: exercise)
                    Spacer(minLength: 0)
                    if !pendingFeelingExerciseIDs.contains(exercise.id) {
                        Button {
                            selectedExerciseID = nil
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption.bold())
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityLabel("折叠")
                    }
                }
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : (isExerciseComplete ? 62 : 68))
            }

            if exercise.volumeUnit.usesMeasurementSide && !exerciseLogs.isEmpty {
                Text(actualMeasurementBasis(exerciseLogs))
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("实际口径-\(exercise.exerciseName)")
            }

            if !dynamicTypeSize.isAccessibilitySize {
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
                Text("余力").frame(width: 48)
                Image(systemName: "checkmark").frame(width: 44).accessibilityHidden(true)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            }
            ForEach(exerciseLogs) { log in
                let plan = exercise.plannedSets.indices.contains(log.setNumber - 1)
                    ? exercise.plannedSets[log.setNumber - 1] : nil
                SetLogRow(
                    log: log,
                    exerciseName: exercise.exerciseName,
                    volumeUnit: exercise.volumeUnit,
                    bodyWeightKgSnapshot: exercise.bodyWeightKgSnapshot,
                    bodyWeightSnapshotSourceDate: exercise.bodyWeightSnapshotSourceDate,
                    beforeOpenRIR: { flushPendingInput() },
                    plannedValue: plan.map { TrainingWorkoutPresentation.planValue($0, unit: exercise.volumeUnit) } ?? "额外组",
                    plannedTarget: plan?.prescription.map { TrainingWorkoutPresentation.target($0) },
                    onEdit: {
                        WorkoutExerciseTracking.recordInteraction(with: exercise)
                        saveQuietly(isInputCommit: true)
                    },
                    onToggle: { toggle(log, exercise: exercise) }
                )
            }

            if exerciseLogs.isEmpty {
                Text("本次不做")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("active-skipped-\(exercise.exerciseName)")
            }

            HStack(spacing: 10) {
                Button { addSet(to: exercise) } label: {
                    Label("加一组", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(WorkoutSetCountButtonStyle(isPrimary: true)).accessibilityIdentifier("active-add-set-\(exercise.exerciseName)")
                Button { requestReduction(for: exercise) } label: {
                    Label("减一组", systemImage: "minus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(WorkoutSetCountButtonStyle(isPrimary: false))
                .disabled(!exerciseLogs.contains { !$0.isCompleted })
                .accessibilityIdentifier("active-reduce-set-\(exercise.exerciseName)")
                if workoutData.logs.contains(where: { $0.sessionExerciseID == exercise.id && $0.reductionOrder != nil }) {
                    Button("撤销减组") { restoreReducedSet(for: exercise) }
                        .font(.caption).frame(minHeight: 44)
                        .accessibilityIdentifier("active-restore-reduced-set-\(exercise.exerciseName)")
                }
            }

            if isExerciseComplete {
                exerciseFeeling(exercise)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if editingNotesExerciseIDs.contains(exercise.id) {
                        guard flushPendingInput() else { return }
                        editingNotesExerciseIDs.remove(exercise.id)
                    } else {
                        editingNotesExerciseIDs.insert(exercise.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("本次备注", systemImage: "note.text").fixedSize()
                        Spacer(minLength: 8)
                        Text(exercise.performanceNotes.isEmpty ? "添加备注" : exercise.performanceNotes)
                            .lineLimit(1).truncationMode(.tail)
                        Image(systemName: editingNotesExerciseIDs.contains(exercise.id) ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption).frame(minHeight: 48)
                    .contentShape(Rectangle())
                    .foregroundStyle(AppTheme.secondaryText)
                }.buttonStyle(.plain).accessibilityIdentifier("动作备注入口-\(exercise.exerciseName)")
                if editingNotesExerciseIDs.contains(exercise.id) {
                    BufferedWorkoutTextEditor(
                        placeholder: "记录这个动作的状态、疼痛或技术提醒",
                        text: Binding(
                            get: { exercise.performanceNotes },
                            set: {
                                exercise.performanceNotes = $0
                                saveQuietly(isInputCommit: true)
                            }
                        ), accessibilityIdentifier: "动作备注-\(exercise.exerciseName)"
                    )
                    .frame(height: 88)
                    .font(.caption)
                    .padding(10)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            DisclosureGroup(isExpanded: Binding(
                get: { detailedExerciseIDs.contains(exercise.id) },
                set: { if $0 { detailedExerciseIDs.insert(exercise.id) } else { detailedExerciseIDs.remove(exercise.id) } }
            )) {
            if let notice = TrainingWorkoutPresentation.conditionNotice(in: exercise.exerciseNotes) {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("训练条件-\(exercise.exerciseName)")
            }
            Text(TrainingWorkoutPresentation.loadGuidance(in: exercise.exerciseNotes)
                 ?? recordingBasis(exercise, logs: exerciseLogs))
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("训练口径-\(exercise.exerciseName)")

            if let target = exercise.plannedSets.first?.prescription {
                Text(TrainingWorkoutPresentation.target(target))
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
            if exerciseLogs.contains(where: { $0.actualEntrySource == .history }) {
                Text("历史预填，非本次负重建议 · 可修改")
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }

            if exercise.volumeUnit.usesMeasurementSide {
                Picker("记录口径", selection: measurementSideBinding(for: exercise)) {
                    ForEach(MeasurementSide.allCases) { side in Text(side.title).tag(side) }
                }.pickerStyle(.segmented)
                    .disabled(exerciseLogs.allSatisfy(\.isCompleted))
                    .accessibilityIdentifier("active-measurement-side-\(exercise.exerciseName)")
            }
            Button("RIR ?") { showRIRHelp = true }
                .frame(minHeight: 44).accessibilityLabel("了解 RIR")
            if let history = historyReferences[exercise.id] {
                let reference = WorkoutHistoryResolver.display(history, unit: exercise.volumeUnit)
                VStack(alignment: .leading, spacing: 4) {
                    Text("上次实际 · \(reference.date.formatted(date: .abbreviated, time: .omitted))")
                    Text(reference.rows.joined(separator: "  /  ")).font(.caption.monospacedDigit())
                    if !history.equipmentVerified { Text("历史器械未确认，仅供参考，不自动填入").foregroundStyle(AppTheme.orange) }
                }.accessibilityIdentifier("上次实际-\(exercise.exerciseName)")
            }
            if !exerciseLogs.contains(where: { $0.actualEntrySource == .history }) {
                Text("实际记录与原计划分别保留")
            }
            Button("恢复计划值") {
                guard flushPendingInput() else { return }
                do { try WorkoutService.restorePlanDefaults(for: exercise, in: modelContext) }
                catch { errorMessage = error.localizedDescription }
            }.frame(minHeight: 44).disabled(exerciseLogs.allSatisfy { $0.isCompleted || $0.startedAt != nil })
                .accessibilityLabel("恢复计划默认值")
            ForEach(Array(exercise.plannedSets.enumerated()), id: \.element.id) { index, plan in
                if let target = plan.prescription {
                    Text("第 \(index + 1) 组 · \(target.summary)")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("完整训练目标-\(exercise.exerciseName)-\(index + 1)")
                }
            }
            if !exercise.exerciseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("训练说明 · 只读").font(.caption.bold())
                    Text(exercise.exerciseNotes)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("训练说明全文-\(exercise.exerciseName)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            if let url = URL(string: exercise.referenceURL), !exercise.referenceURL.isEmpty {
                Link(destination: url) {
                    Label("查看动作资料", systemImage: "link")
                        .font(.caption.bold())
                }
                .foregroundStyle(AppTheme.ink)
            }

            } label: {
                Text("动作资料与原计划")
                    .accessibilityIdentifier("RIR、动作资料与备注")
            }
            .font(.caption).foregroundStyle(AppTheme.secondaryText)

        }
        .padding(.horizontal, isExerciseComplete ? 0 : 14)
        .padding(.vertical, isExerciseComplete ? 8 : 14)
        .background(isExerciseComplete ? AppTheme.background : AppTheme.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
            if isExerciseComplete { Rectangle().fill(AppTheme.line).frame(height: 0.5) }
        }
        }
    }

    @ViewBuilder
    private func exerciseFeeling(_ exercise: SessionExercise) -> some View {
        if pendingFeelingExerciseIDs.contains(exercise.id) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("动作感受").font(.caption.weight(.semibold))
                    Spacer()
                    Text("选一个").font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
                feelingChoices(for: exercise)
            }
            .padding(.top, 6)
        } else {
            DisclosureGroup {
                feelingChoices(for: exercise)
            } label: {
                HStack {
                    Text("动作感受")
                    Spacer(minLength: 8)
                    Text(exercise.feeling?.title ?? "未记录")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("动作感受入口-\(exercise.exerciseName)")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .tint(AppTheme.secondaryText)
        }
    }

    private func feelingChoices(for exercise: SessionExercise) -> some View {
        let choices = ForEach(WorkoutFeeling.allCases) { feeling in
            Button {
                completeFeeling(feeling, for: exercise)
            } label: {
                HStack(spacing: 4) {
                    if exercise.feeling == feeling {
                        Circle().fill(AppTheme.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Text(feeling.title)
                        .font(.caption.weight(exercise.feeling == feeling ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(exercise.feeling == feeling ? AppTheme.ink : AppTheme.secondaryText)
            .accessibilityLabel("\(feeling.emoji)，\(feeling.title)")
            .accessibilityIdentifier("动作感受-\(feeling.rawValue)")
            .accessibilityAddTraits(exercise.feeling == feeling ? .isSelected : [])
        }

        return VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { choices }
                    .fixedSize(horizontal: true, vertical: false)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                    alignment: .leading, spacing: 0) {
                    choices
                }
            }
            Button("跳过感受并收起") {
                skipFeeling(for: exercise)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
            .accessibilityIdentifier("跳过感受并收起")
        }
    }

    private func actualMeasurementBasis(_ logs: [SetLog]) -> String {
        let sides = logs.map { log in
            (log.actualWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .unknown,
             log.actualRepsSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .unknown)
        }
        guard let first = sides.first else { return "重量未注明 · 次数未注明" }
        guard sides.allSatisfy({ $0.0 == first.0 && $0.1 == first.1 }) else { return "口径按各组记录" }
        return "重量\(first.0.title) · 次数\(first.1.title)"
    }

    private func completedExerciseCard(
        _ exercise: SessionExercise,
        logs exerciseLogs: [SetLog]
    ) -> some View {
        let completed = exerciseLogs.filter(\.isCompleted).count
        let complete = !exerciseLogs.isEmpty && completed == exerciseLogs.count
        return exerciseHeaderLayout {
        Button {
            selectedExerciseID = exercise.id
        } label: {
            HStack(spacing: 13) {
                ExerciseArtworkView(exerciseID: exercise.exerciseID, name: exercise.exerciseName)
                    .overlay(alignment: .bottomTrailing) {
                        if complete { exerciseCompletionBadge }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(
                        (exerciseLogs.isEmpty ? "本次不做" : "\(completed)/\(exerciseLogs.count) 组")
                            + (exercise.durationSeconds.map { " · 用时 \(TrainingFormatters.clock($0))" } ?? "")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let feeling = exercise.feeling {
                    Text(feeling.title)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("切换动作-\(exercise.exerciseName)")
        .accessibilityLabel(
            "\(exercise.exerciseName)，" + (exerciseLogs.isEmpty ? "本次不做" : (complete ? "已完成 \(completed) 组" : "已完成 \(completed)/\(exerciseLogs.count) 组"))
                + (exercise.feeling.map { "，感受 \($0.emoji) \($0.title)" } ?? "")
                + "，点按展开记录"
        )
        HStack(spacing: 6) {
            replacementButton(for: exercise)
            if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            ExerciseExplanationButton(exerciseID: exercise.exerciseID, name: exercise.exerciseName,
                equipment: exercise.equipmentSnapshot ?? "", referenceURL: exercise.referenceURL,
                beforeOpen: { flushPendingInput() })
                .foregroundStyle(AppTheme.secondaryText)
        }
        }
    }

    private var exerciseHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
    }

    private func replacementButton(for exercise: SessionExercise) -> some View {
        Button("替换动作") { requestReplacement(for: exercise) }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(session?.status != .inProgress || !logs.contains {
                $0.sessionExerciseID == exercise.id && !$0.isCompleted
            })
            .accessibilityIdentifier("active-replace-exercise-\(exercise.exerciseName)")
            .accessibilityLabel("替换\(exercise.exerciseName)剩余动作")
    }

    private var exerciseCompletionBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 19, height: 19)
            .background(AppTheme.accent, in: Circle())
            .overlay { Circle().stroke(AppTheme.background, lineWidth: 2) }
            .accessibilityHidden(true)
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
        guard let session, flushPendingInput() else { return }
        do {
            try WorkoutService.addExercise(
                exercise,
                to: session,
                configuration: configuration,
                in: modelContext
            )
            try reloadWorkoutData(refreshHistory: true)
            showExercisePicker = false
            selectedExerciseID = orderedExercises.last { $0.exerciseID == exercise.id }?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestReplacement(for exercise: SessionExercise) {
        guard replacementPresentation == nil, flushPendingInput() else { return }
        do {
            let review = try WorkoutService.replacementReview(sessionID: sessionID,
                sourceSessionExerciseID: exercise.id, in: modelContext)
            dismissKeyboard()
            replacementPresentation = review.requiresEnteredDataConfirmation
                ? .confirming(review) : .choosing(review, confirmingEnteredData: false)
        } catch { errorMessage = error.localizedDescription }
    }

    private func replaceExercise(
        _ exercise: Exercise,
        configuration: ExerciseSetupDraft,
        review: WorkoutExerciseReplacementReview,
        confirmingEnteredData: Bool
    ) {
        guard flushPendingInput() else { return }
        do {
            let replacement = try WorkoutService.replaceRemainingExercise(review: review,
                with: exercise, configuration: configuration, confirmingEnteredData: confirmingEnteredData,
                in: modelContext)
            replacementPresentation = nil
            pendingFeelingExerciseIDs.remove(review.sourceSessionExerciseID)
            try reloadWorkoutData(refreshHistory: true)
            selectedExerciseID = replacement.id
        } catch {
            replacementPresentation = nil
            errorMessage = error.localizedDescription
        }
    }

    private func measurementSideBinding(for exercise: SessionExercise) -> Binding<MeasurementSide> {
        Binding {
            WorkoutMeasurementSideEditing.selected(in: logs.filter { $0.sessionExerciseID == exercise.id })
        } set: { side in
            guard flushPendingInput() else { return }
            WorkoutMeasurementSideEditing.apply(side, to: exercise, logs: logs)
            saveQuietly()
        }
    }

    private func recordingBasis(_ exercise: SessionExercise, logs: [SetLog]) -> String {
        let side = WorkoutMeasurementSideEditing.selected(in: logs)
        let unchangedSide = logs.allSatisfy { $0.actualWeightSide == $0.targetWeightSide }
        let firstLine = exercise.exerciseNotes.components(separatedBy: .newlines).first ?? ""
        if unchangedSide && !firstLine.isEmpty && firstLine.count < 100
            && ["kg", "公斤", "片重", "每只", "每侧"].contains(where: firstLine.contains) {
            return firstLine
        }
        return exercise.volumeUnit.usesMeasurementSide
            ? "\(exercise.volumeUnit.symbol) · \(side.title)"
            : exercise.volumeUnit == .bodyweight ? "自重次数" : exercise.volumeUnit.inputTitle
    }

    private func addSet(to exercise: SessionExercise) {
        guard flushPendingInput() else { return }
        do {
            try WorkoutService.addSet(to: exercise, in: modelContext)
            try reloadWorkoutData()
            pendingFeelingExerciseIDs.remove(exercise.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestReduction(for exercise: SessionExercise) {
        guard flushPendingInput() else { return }
        do {
            guard let candidate = try WorkoutService.reductionCandidate(for: exercise, in: modelContext) else { return }
            if WorkoutService.reductionNeedsConfirmation(candidate) {
                pendingReduction = (exercise, candidate.id)
                showReductionConfirmation = true
            } else {
                reduceSet(exercise, candidateID: candidate.id, confirmed: false)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func reduceSet(_ exercise: SessionExercise, candidateID: UUID, confirmed: Bool) {
        guard flushPendingInput() else { return }
        do {
            let wasComplete = isExerciseCompleted(exercise)
            try WorkoutService.reduceSet(from: exercise, candidateID: candidateID, confirmingEnteredData: confirmed, in: modelContext)
            try reloadWorkoutData()
            if !wasComplete && isExerciseCompleted(exercise) {
                pendingFeelingExerciseIDs.insert(exercise.id)
                selectedExerciseID = exercise.id
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func restoreReducedSet(for exercise: SessionExercise) {
        guard flushPendingInput() else { return }
        do {
            try WorkoutService.restoreReducedSet(for: exercise, in: modelContext)
            try reloadWorkoutData()
            pendingFeelingExerciseIDs.remove(exercise.id)
        } catch { errorMessage = error.localizedDescription }
    }

    private func removeExercise(_ exercise: SessionExercise, from session: WorkoutSession) {
        guard flushPendingInput() else { return }
        do {
            try WorkoutService.removeExercise(exercise, from: session, in: modelContext)
            try reloadWorkoutData(refreshHistory: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var finishButton: some View {
        Button {
            showFinishConfirmation = true
        } label: {
            Label("完成本次训练", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(SprintPrimaryButtonStyle())
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
        .buttonStyle(SprintSecondaryButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .tint(.red)
    }

    private func notesCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("训练备注", systemImage: "note.text")
                .font(.headline)
            BufferedWorkoutTextEditor(placeholder: "记录状态、疼痛、器械调整等", text: Binding(
                get: { session.notes },
                set: {
                    session.notes = $0
                    saveQuietly(isInputCommit: true)
                }
            ), accessibilityIdentifier: "训练备注输入")
            .frame(height: 110)
            .padding(12)
            .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .cardSurface()
    }

    private func toggle(_ log: SetLog, exercise: SessionExercise) {
        guard flushPendingInput() else { return }
        if !log.isCompleted, exercise.volumeUnit.recordsNumericLoad, log.isActualWeightBlank {
            errorMessage = "这组计划要求重量留空，请先填写今天实际使用的重量，再勾选完成。"
            return
        }
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
        guard completionSummary == nil, let session, flushPendingInput() else { return }
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
            let summary = WorkoutCompletionFeedback.shared.receiveSavedCompletion(
                session: session, logs: logs, allDaySchedulesCompleted: allTodaySchedulesCompleted(for: session)
            )
            if let summary { setCompletionPresentation(summary) }
            else { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setCompletionPresentation(_ summary: WorkoutCompletionSummary?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { completionSummary = summary }
    }

    private func discardWorkout() {
        guard let session else { return }
        guard flushPendingInput() else { return }
        do {
            try WorkoutService.discard(session: session, schedules: schedules, in: modelContext)
            NotificationService.cancelRestEnd(sessionID: session.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult private func saveQuietly(isInputCommit: Bool = false) -> Bool {
        saveIssues.save(sessionID: sessionID, in: modelContext, isInputCommit: isInputCommit)
    }

    private func flushPendingInput() -> Bool {
        WorkoutInputDraft.flushAll()
        return saveQuietly()
    }

    private func prepareWorkoutView() {
        UIApplication.shared.isIdleTimerDisabled = true
        WorkoutInputProfiler.shared.start()
        do {
            // This outer lifecycle also runs when returning from the menu editor.
            // It must not be attached only to the initially absent session branch.
            try reloadWorkoutData(refreshHistory: true)
            guard let session, session.status == .inProgress else { return }
            // Returning from sorting must not retroactively start the newly first
            // exercise at the session's original start time.
            if orderedExercises.allSatisfy({ $0.exerciseStartedAt == nil && $0.exerciseCompletedAt == nil }) {
                WorkoutExerciseTracking.startFirstExercise(in: orderedExercises, at: session.startedAt)
            }
            saveQuietly()
        } catch { errorMessage = "本次训练读取失败：\(error.localizedDescription)" }
    }

    private func reloadWorkoutData(refreshHistory: Bool = false) throws {
        try workoutData.reload(in: modelContext)
        if refreshHistory { refreshHistoryReferences() }
        if let selectedExerciseID, orderedExercises.contains(where: { $0.id == selectedExerciseID }) { return }
        let parts = storedExpandedExercise.split(separator: ":")
        let restored = parts.count == 2 && parts[0] == sessionID.uuidString
            ? UUID(uuidString: String(parts[1])) : nil
        selectedExerciseID = orderedExercises.contains { $0.id == restored }
            ? restored : MuscleCoverageService.initialExpandedID(orderedExercises, logs: logs)
    }

    private func refreshHistoryReferences() {
        do {
            let exerciseIDs = orderedExercises.map(\.exerciseID)
            guard !exerciseIDs.isEmpty else { historyReferences = [:]; return }
            let currentID = sessionID
            let snapshots = try modelContext.fetch(FetchDescriptor<SessionExercise>(predicate: #Predicate {
                exerciseIDs.contains($0.exerciseID) && $0.sessionID != currentID
            }))
            let sessionIDs = snapshots.map(\.sessionID)
            let completedStatus = WorkoutSessionStatus.completed.rawValue
            let historySessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
                sessionIDs.contains($0.id) && $0.statusRaw == completedStatus
            }))
            let snapshotIDs = snapshots.map(\.id)
            let historicalLogs = try modelContext.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
                snapshotIDs.contains($0.sessionExerciseID) && $0.isCompleted && !$0.isWarmup
            }))
            let scheduleIDs = historySessions.compactMap(\.scheduledWorkoutID)
            let historySchedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>(predicate: #Predicate {
                scheduleIDs.contains($0.id)
            }))
            let referenceSessions = historySessions + [session].compactMap { $0 }
            let referenceSchedules = historySchedules + schedules
            var result: [UUID: WorkoutHistoryReference] = [:]
            for exercise in orderedExercises {
                let equipment = WorkoutHistoryResolver.equipment(for: exercise, sessions: referenceSessions, schedules: referenceSchedules) ?? ""
                if let reference = WorkoutHistoryResolver.latest(
                    exerciseID: exercise.exerciseID, unit: exercise.volumeUnit, equipment: equipment,
                    before: session?.startedAt ?? .now, excludingSessionID: sessionID,
                    sessions: historySessions, snapshots: snapshots, logs: historicalLogs, schedules: historySchedules
                ) { result[exercise.id] = reference }
            }
            historyReferences = result
        } catch { errorMessage = "上次记录读取失败：\(error.localizedDescription)" }
    }

    private func allTodaySchedulesCompleted(for session: WorkoutSession) -> Bool? {
        guard let schedule = schedules.first(where: { $0.id == session.scheduledWorkoutID }),
              TrainingScheduleDate.localDay(schedule) == TrainingLocalDate.key(.now) else { return nil }
        let day = TrainingScheduleDate.localDay(schedule)
        do {
            // Read day membership once after completion, never while typing or rendering.
            let daySchedules = try modelContext.fetch(FetchDescriptor<ScheduledWorkout>()).filter { TrainingScheduleDate.localDay($0) == day }
            let dayScheduleIDs = daySchedules.map(\.id)
            let completedStatus = WorkoutSessionStatus.completed.rawValue
            let completed = try modelContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
                $0.statusRaw == completedStatus
            })).filter { $0.scheduledWorkoutID.map(dayScheduleIDs.contains) ?? false }
            let progress = try TrainingWorkingSetProgressLoader.load(schedules: daySchedules, sessions: completed, in: modelContext)
            return TrainingDayFeedback(schedules: daySchedules, sessions: completed, progress: progress).tone == .green
        } catch { return nil }
    }

    private func dismissKeyboard() {
        KeyboardDismissal.dismiss()
    }
}

private enum WorkoutExerciseReplacementPresentation: Identifiable {
    case confirming(WorkoutExerciseReplacementReview)
    case choosing(WorkoutExerciseReplacementReview, confirmingEnteredData: Bool)

    var id: UUID {
        switch self {
        case let .confirming(review), let .choosing(review, _): return review.sourceSessionExerciseID
        }
    }
}

/// Keep the same unfinished input and selection across the ordering sheet.
/// A weak view reference does not keep removed/completed input controls alive.
@MainActor
private final class WorkoutOrderInputFocus {
    private weak var field: UITextField?
    private let identifier: String
    private let selection: Range<Int>?

    private init(_ field: UITextField, identifier: String) {
        self.field = field
        self.identifier = identifier
        if let range = field.selectedTextRange {
            selection = field.offset(from: field.beginningOfDocument, to: range.start)..<field.offset(from: field.beginningOfDocument, to: range.end)
        } else { selection = nil }
    }

    static func capture() -> WorkoutOrderInputFocus? {
        guard let field = fields().first(where: \.isFirstResponder),
              let id = field.accessibilityIdentifier, id.hasPrefix("actual-") else { return nil }
        return WorkoutOrderInputFocus(field, identifier: id)
    }

    func restore() {
        let candidate = field?.window != nil ? field : Self.fields().first { $0.accessibilityIdentifier == identifier }
        guard let candidate, candidate.isEnabled, candidate.window != nil,
              candidate.accessibilityIdentifier == identifier else { return }
        candidate.becomeFirstResponder()
        if let selection {
            // Numeric fields select all on the next main-queue turn when
            // editing begins. Restore afterwards so resuming does not replace
            // the entire value with the next typed digit.
            DispatchQueue.main.async { [weak candidate] in
                guard let candidate, candidate.isFirstResponder else { return }
                let length = (candidate.text ?? "").utf16.count
                if let start = candidate.position(from: candidate.beginningOfDocument, offset: min(selection.lowerBound, length)),
                   let end = candidate.position(from: candidate.beginningOfDocument, offset: min(selection.upperBound, length)) {
                    candidate.selectedTextRange = candidate.textRange(from: start, to: end)
                }
            }
        }
    }

    private static func fields() -> [UITextField] {
        func collect(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).flatMap(collect)
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
                                    .foregroundStyle(AppTheme.ink)
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
            .sprintPage()
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

private enum WorkoutExerciseOrderSheetError: LocalizedError {
    case inputSaveFailed
    var errorDescription: String? { "训练输入尚未保存，请先解决保存提示后重试。" }
}

private struct WorkoutExerciseOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [SessionExercise]
    @State private var errorMessage: String?
    @State private var showsDailyMenu = false
    let sessionID: UUID
    let plannedDate: Date
    let onReorder: ([UUID]) throws -> Void

    init(sessionID: UUID, plannedDate: Date, onReorder: @escaping ([UUID]) throws -> Void) {
        self.sessionID = sessionID
        self.plannedDate = plannedDate
        self.onReorder = onReorder
        _exercises = Query(filter: #Predicate<SessionExercise> { $0.sessionID == sessionID },
                           sort: [SortDescriptor(\SessionExercise.order), SortDescriptor(\SessionExercise.id)])
    }

    private var orderedExercises: [SessionExercise] {
        MuscleCoverageService.stableOrder(exercises, sessionID: sessionID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(minWidth: 20)
                                .accessibilityLabel("第 \(index + 1) 个动作")
                                .accessibilityIdentifier("排序位置-\(exercise.exerciseName)")
                            Text(exercise.exerciseName)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { move(exercise.id, by: -1) } label: {
                                Image(systemName: "arrow.up")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .accessibilityLabel("上移\(exercise.exerciseName)")
                            .accessibilityIdentifier("上移动作-\(exercise.exerciseName)")
                            Button { move(exercise.id, by: 1) } label: {
                                Image(systemName: "arrow.down")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(index == orderedExercises.count - 1)
                            .accessibilityLabel("下移\(exercise.exerciseName)")
                            .accessibilityIdentifier("下移动作-\(exercise.exerciseName)")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: "上移") { move(exercise.id, by: -1) }
                        .accessibilityAction(named: "下移") { move(exercise.id, by: 1) }
                    }
                    .onMove { source, destination in
                        var ids = orderedExercises.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        save(ids)
                    }
                } header: {
                    Text("本次动作顺序")
                } footer: {
                    Text("拖动右侧手柄或点按箭头，调整后立即保存。")
                }
                Section {
                    Button {
                        showsDailyMenu = true
                    } label: {
                        Label("调整今日菜单", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("排序页-调整今日菜单")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .sprintPage()
            .navigationTitle("动作顺序")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsDailyMenu) {
                DailyWorkoutBuilderView(initialDate: plannedDate)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("完成动作排序")
                }
            }
            .alert("顺序未保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请重试。")
            }
        }
        .accessibilityIdentifier("本次动作排序")
    }

    private func move(_ id: UUID, by offset: Int) {
        var ids = orderedExercises.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        save(ids)
    }

    private func save(_ ids: [UUID]) {
        do { try onReorder(ids) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SetLogRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var log: SetLog
    @State private var showRIRPicker = false
    let exerciseName: String
    let volumeUnit: ExerciseVolumeUnit
    let bodyWeightKgSnapshot: Double?
    let bodyWeightSnapshotSourceDate: Date?
    let beforeOpenRIR: () -> Bool
    let plannedValue: String
    let plannedTarget: String?
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
        .onChange(of: log.rir) { _, _ in log.markActualEntryEdited(); onEdit() }
        .sheet(isPresented: $showRIRPicker) { rirSheet }
    }

    private var rirSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("第 \(log.setNumber) 组 · \(exerciseName)")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    Text("动作标准不变，你估计还能再完成几次？0 表示已无余力，5 表示大约还能做 5 次。不确定时可以不记录。")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        rirGrid
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ForEach(0...5, id: \.self) { value in rirChoice(value).frame(width: 44) }
                            }
                            rirGrid
                        }.frame(maxWidth: .infinity)
                    }
                    Button { selectRIR(nil) } label: {
                        Text("不记录 RIR").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(WorkoutSetCountButtonStyle(isPrimary: false))
                }.padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("记录余力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showRIRPicker = false } } }
        }
        .tint(AppTheme.ink)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("workout-rir-sheet")
    }

    private var rirGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(0...5, id: \.self) { value in rirChoice(value) }
        }
    }

    private func rirChoice(_ value: Int) -> some View {
        Button { selectRIR(value) } label: {
            Text("\(value)").font(.title2.bold().monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(log.rir == value ? AppTheme.background : AppTheme.ink)
                .background(log.rir == value ? AppTheme.ink : AppTheme.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(rirOptionTitle(value))
            .accessibilityAddTraits(log.rir == value ? .isSelected : [])
    }

    private var completedRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text("第 \(log.setNumber) 组已完成").font(.subheadline.bold())
                    Spacer()
                    completedButton
                }
                Text(completedSummary).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                planCell
                HStack { Text("余力").font(.caption); Spacer(); rirButton }
            } else {
                HStack(spacing: 8) {
                    Text("\(log.setNumber)").font(.subheadline.bold().monospacedDigit()).frame(width: 30)
                    HStack(spacing: 8) {
                        if volumeUnit.recordsNumericLoad {
                            Text(TrainingFormatters.weight(log.actualWeight)).frame(maxWidth: .infinity)
                        } else if volumeUnit == .bodyweight {
                            Text(bodyWeightKgSnapshot.map { TrainingFormatters.weight($0) } ?? "—")
                                .frame(maxWidth: .infinity)
                        }
                        Text("\(log.actualReps)").frame(maxWidth: .infinity)
                    }.font(.subheadline.monospacedDigit())
                    rirButton
                    completedButton
                }
                planCell.padding(.leading, 38)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 0.5) }
    }

    private var completedButton: some View {
        Button(action: onToggle) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
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
                planCell
                HStack {
                    if volumeUnit.recordsNumericLoad || volumeUnit == .bodyweight {
                        Text("\(volumeUnit.inputTitle) \(volumeUnit.symbol)").frame(maxWidth: .infinity)
                    }
                    Text(volumeUnit.recordsSingleAmount ? volumeUnit.inputTitle : volumeUnit.repetitionTitle)
                        .frame(maxWidth: .infinity)
                }.font(.caption).foregroundStyle(AppTheme.secondaryText)
                amountInputs
                HStack { Text("余力").font(.caption); Spacer(); rirButton }
            } else {
                HStack(spacing: 8) {
                    Text("\(log.setNumber)").font(.subheadline.bold().monospacedDigit()).frame(width: 30)
                    amountInputs
                    rirButton
                    completionButton
                }
                planCell.padding(.leading, 38)
            }
        }
    }

    private var planCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("原计划 · \(plannedValue)")
            if let plannedTarget { Text(plannedTarget) }
        }
            .font(dynamicTypeSize.isAccessibilitySize ? .subheadline : .caption2)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plannedTarget ?? "原计划 · \(plannedValue)")
            .accessibilityIdentifier("训练目标-\(exerciseName)-\(log.setNumber)")
    }

    private var amountInputs: some View {
        HStack(spacing: 8) {
            if volumeUnit.recordsNumericLoad {
                StableNumericTextField(volumeUnit.inputTitle, value: $log.actualWeight,
                    maximumFractionDigits: 3,
                    accessibilityIdentifier: "actual-weight-\(exerciseName)-\(log.setNumber)",
                    commitDelay: 0.3, showsEmptyValue: log.isActualWeightBlank,
                    onCommit: { log.actualWeightIsBlank = false; log.markActualEntryEdited(); onEdit() })
                    .padding(.horizontal, 8).frame(minHeight: 44)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            } else if volumeUnit == .bodyweight {
                VStack(spacing: 2) {
                    Text(bodyWeightKgSnapshot.map { "\(TrainingFormatters.weight($0)) kg" } ?? "暂无体重")
                        .font(.subheadline.bold())
                        .foregroundStyle(bodyWeightKgSnapshot == nil ? AppTheme.orange : AppTheme.secondaryText)
                    if bodyWeightKgSnapshot != nil {
                        Text(bodyWeightSnapshotSourceDate.map {
                            "来源 \($0.formatted(date: .abbreviated, time: .omitted))"
                        } ?? "来源日期未知")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
            }
            StableNumericTextField(volumeUnit.recordsSingleAmount ? volumeUnit.inputTitle : volumeUnit.repetitionTitle,
                value: $log.actualReps, accessibilityIdentifier: "actual-reps-\(exerciseName)-\(log.setNumber)",
                commitDelay: 0.3, onCommit: { log.markActualEntryEdited(); onEdit() })
                .padding(.horizontal, 8).frame(minHeight: 44)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
        }
    }

    private var completionButton: some View {
        Button(action: onToggle) {
            Image(systemName: "circle").font(.title2.weight(.regular)).foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("完成第 \(log.setNumber) 组")
            .accessibilityIdentifier("完成第 \(log.setNumber) 组")
            .accessibilityValue("未完成")
    }

    private var rirButton: some View {
        Button {
            guard beforeOpenRIR() else { return }
            showRIRPicker = true
        } label: {
            Text(log.rir.map(String.init) ?? "—")
                .font(.subheadline.weight(log.isCompleted ? .regular : .bold).monospacedDigit())
                .frame(width: 48, height: 48)
                .background(log.isCompleted ? Color.clear : AppTheme.background,
                    in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if !log.isCompleted { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1) }
                }
        }.buttonStyle(.plain).foregroundStyle(AppTheme.ink).contentShape(Rectangle())
            .accessibilityLabel(rirAccessibilityLabel)
            .accessibilityValue(log.rir.map(String.init) ?? "—")
            .accessibilityIdentifier("rir-\(exerciseName)-\(log.setNumber)")
    }

    private func selectRIR(_ value: Int?) {
        log.rir = value
        showRIRPicker = false
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

private struct WorkoutSetCountButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? AppTheme.background : AppTheme.ink)
            .background(isPrimary ? AppTheme.ink : AppTheme.background,
                in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppTheme.ink.opacity(isPrimary ? 0 : 0.18), lineWidth: 1) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

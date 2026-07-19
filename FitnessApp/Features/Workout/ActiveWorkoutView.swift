import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]
    @Query private var schedules: [ScheduledWorkout]

    let sessionID: UUID

    @State private var showFinishConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var errorMessage: String?

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var orderedExercises: [SessionExercise] {
        sessionExercises
            .filter { $0.sessionID == sessionID }
            .sorted { $0.order < $1.order }
    }

    private var logs: [SetLog] {
        setLogs.filter { $0.sessionID == sessionID }
    }

    private var completedCount: Int {
        logs.filter(\.isCompleted).count
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        workoutHeader(session)

                        if session.restEndDate != nil {
                            restTimer(session)
                        }

                        ForEach(orderedExercises) { exercise in
                            exerciseCard(exercise, session: session)
                        }

                        notesCard(session)
                        finishButton
                        discardButton
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle(session.templateName)
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
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

    private func restTimer(_ session: WorkoutSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, Int((session.restEndDate ?? timeline.date).timeIntervalSince(timeline.date).rounded(.up)))

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
                }

                Spacer()

                Button("+30秒") {
                    session.restEndDate = max(session.restEndDate ?? .now, .now).addingTimeInterval(30)
                    saveQuietly()
                    if let endDate = session.restEndDate {
                        NotificationService.scheduleRestEnd(sessionID: session.id, at: endDate)
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    session.restEndDate = nil
                    NotificationService.cancelRestEnd(sessionID: session.id)
                    saveQuietly()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("结束休息")
            }
            .cardSurface()
            .onChange(of: remaining) { _, value in
                if value == 0, session.restEndDate != nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    session.restEndDate = nil
                    NotificationService.cancelRestEnd(sessionID: session.id)
                    saveQuietly()
                }
            }
        }
    }

    private func exerciseCard(_ exercise: SessionExercise, session: WorkoutSession) -> some View {
        let exerciseLogs = logs
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.title3.bold())
                    Text("目标 \(exercise.targetSets) 组 × \(exercise.minReps)–\(exercise.maxReps) 次 · 休息 \(exercise.restSeconds) 秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(exerciseLogs.filter(\.isCompleted).count)/\(exerciseLogs.count)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
            }

            HStack {
                Text("组")
                    .frame(width: 30)
                Text("重量 kg")
                    .frame(maxWidth: .infinity)
                Text("次数")
                    .frame(maxWidth: .infinity)
                Text("RIR")
                    .frame(width: 48)
                Color.clear
                    .frame(width: 38)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(exerciseLogs) { log in
                SetLogRow(
                    log: log,
                    onEdit: saveQuietly,
                    onToggle: { toggle(log, restSeconds: exercise.restSeconds, session: session) }
                )
            }
        }
        .cardSurface()
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

        if log.isCompleted, completedCount < logs.count {
            session.restEndDate = Date.now.addingTimeInterval(TimeInterval(restSeconds))
            if let endDate = session.restEndDate {
                NotificationService.scheduleRestEnd(sessionID: session.id, at: endDate)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if !log.isCompleted {
            session.restEndDate = nil
            NotificationService.cancelRestEnd(sessionID: session.id)
        }
        saveQuietly()
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
}

private struct SetLogRow: View {
    @Bindable var log: SetLog
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(log.setNumber)")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 30)

            TextField(
                "重量",
                value: $log.actualWeight,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            TextField("次数", value: $log.actualReps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

            Menu {
                Button("不记录") { log.rir = nil }
                ForEach(0...5, id: \.self) { value in
                    Button("RIR \(value)") { log.rir = value }
                }
            } label: {
                Text(log.rir.map(String.init) ?? "–")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 48)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(.primary)

            Button(action: onToggle) {
                Image(systemName: log.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(log.isCompleted ? AppTheme.accent : Color.secondary)
            }
            .frame(width: 38)
            .accessibilityLabel(log.isCompleted ? "标记为未完成" : "完成第 \(log.setNumber) 组")
        }
        .opacity(log.isCompleted ? 0.72 : 1)
        .onChange(of: log.actualWeight) { _, _ in onEdit() }
        .onChange(of: log.actualReps) { _, _ in onEdit() }
        .onChange(of: log.rir) { _, _ in onEdit() }
    }
}

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

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        summary(session)

                        ForEach(exercises) { exercise in
                            exerciseSummary(exercise)
                        }

                        if !session.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("训练备注")
                                    .font(.headline)
                                Text(session.notes)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle(session.templateName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
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
        let recommendation = TrainingMetrics.progression(
            completedReps: exerciseLogs.map(\.actualReps),
            minimumReps: exercise.minReps,
            maximumReps: exercise.maxReps,
            rirValues: exerciseLogs.compactMap(\.rir)
        )

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)
                Spacer()
                Label(recommendation.title, systemImage: recommendationIcon(recommendation))
                    .font(.caption.bold())
                    .foregroundStyle(recommendationColor(recommendation))
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

import SwiftData
import SwiftUI

struct CardioWorkoutRecordSheet: View {
    let schedule: ScheduledWorkout
    var editingSessionID: UUID? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var level = ""
    @State private var error: String?
    private enum Field: Hashable { case minutes, level }
    @FocusState private var focused: Field?

    private var seconds: Int? {
        guard let value = number(minutes), value > 0, value <= 1_440 else { return nil }
        let seconds = Int((value * 60).rounded())
        return seconds > 0 ? seconds : nil
    }
    private var parsedLevel: Double? { number(level) }
    private var valid: Bool {
        seconds != nil && (level.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedLevel.map { $0 >= 0 } == true)
    }
    private func number(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(TrainingWorkoutPresentation.upcoming(schedule.templateName).title).font(.headline)
                    Text(TrainingScheduleDate.displayDate(schedule), format: .dateTime.year().month().day())
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                Section("实际完成") {
                    TextField("实际时长（分钟）", text: $minutes).keyboardType(.decimalPad)
                        .focused($focused, equals: .minutes).accessibilityIdentifier("有氧-实际分钟")
                    TextField("Level（选填）", text: $level).keyboardType(.decimalPad)
                        .focused($focused, equals: .level).accessibilityIdentifier("有氧-Level")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("有氧-错误") }
                Section {
                    Button { save() } label: { EditorialPrimary(title: "保存记录", icon: "checkmark") }
                        .disabled(!valid).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("有氧-保存实际")
                }
            }.scrollContentBackground(.hidden).sprintPage()
                .navigationTitle(editingSessionID == nil ? "记录有氧" : "修改有氧记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("完成") { focused = nil }.accessibilityIdentifier("有氧-收起键盘")
                    }
                }
                .onAppear { loadActual() }
        }.tint(AppTheme.ink)
    }
    private func loadActual() {
        guard let id = editingSessionID else { return }
        do {
            guard let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first(where: { $0.id == id }),
                  let summary = CardioWorkoutPresentation.actual(session,
                    exercises: try context.fetch(FetchDescriptor<SessionExercise>()), logs: try context.fetch(FetchDescriptor<SetLog>())) else { return }
            if let seconds = summary.durationSeconds { minutes = TrainingFormatters.weight(Double(seconds) / 60) }
            level = summary.level.map { TrainingFormatters.weight($0) } ?? ""
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard valid, let seconds else { return }
        do {
            try CardioWorkoutService.record(schedule: schedule, seconds: seconds, level: parsedLevel,
                editingSessionID: editingSessionID, in: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CardioWorkoutSummaryView: View {
    let sessionID: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [SessionExercise]
    @Query private var logs: [SetLog]
    @Query private var schedules: [ScheduledWorkout]
    @State private var editing = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
        let id = sessionID
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.id == id })
        _exercises = Query(filter: #Predicate<SessionExercise> { $0.sessionID == id })
        _logs = Query(filter: #Predicate<SetLog> { $0.sessionID == id })
    }
    var body: some View {
        Group {
            if let session = sessions.first, session.status == .completed,
               let summary = CardioWorkoutPresentation.actual(session, exercises: exercises, logs: logs) {
                let schedule = schedules.first { $0.id == session.scheduledWorkoutID }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SprintPageHeader(title: summary.title, icon: summary.symbolName, subtitle: "已完成")
                        Text(TrainingHistoryDate.displayDate(session, schedule: schedule), format: .dateTime.year().month().day().weekday(.wide))
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        (dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                            Text(summary.durationValue).font(.title.bold().italic()).monospacedDigit()
                            Text(summary.durationUnit).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            if let level = summary.level {
                                Text("Level").font(.caption).foregroundStyle(AppTheme.secondaryText)
                                Text(TrainingFormatters.weight(level)).font(.title.bold().italic()).monospacedDigit()
                            }
                        }.accessibilityElement(children: .ignore).accessibilityLabel(summary.label)
                            .accessibilityIdentifier("有氧-实际摘要")
                        if !session.notes.isEmpty { Text(session.notes).font(.subheadline) }
                        if let schedule {
                            Button { editing = true } label: { EditorialRow(title: "修改记录", icon: "pencil") }
                                .accessibilityIdentifier("有氧-修改记录")
                                .sheet(isPresented: $editing) { CardioWorkoutRecordSheet(schedule: schedule, editingSessionID: session.id) }
                        }
                    }.padding(23)
                }.sprintPage().buttonStyle(.plain)
            } else { ContentUnavailableView("未找到有氧记录", systemImage: "figure.indoor.cycle") }
        }.navigationTitle("训练总结").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

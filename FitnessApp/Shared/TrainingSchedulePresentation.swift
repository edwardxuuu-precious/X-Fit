import SwiftUI
import SwiftData

/// Display-only formatting. Original names and prescription evidence stay untouched.
enum TrainingWorkoutPresentation {
    struct Upcoming: Equatable {
        let title: String
        let detail: String?
        let symbolName: String
    }

    static func upcoming(_ original: String) -> Upcoming {
        let parts = title(original).components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "R1" && $0 != "R2" }
        let name = parts.first ?? original
        let details = parts.dropFirst().flatMap { part -> [String] in
            guard let duration = part.range(of: #"\d+\s*分钟$"#, options: .regularExpression) else { return [part] }
            let activity = String(part[..<duration.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = part[duration].replacingOccurrences(of: "分钟", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return [activity, "\(minutes) 分钟"].filter { !$0.isEmpty }
        }
        let symbol: String
        if name.contains("单车") || name.contains("骑行") { symbol = "figure.indoor.cycle" }
        else if name.contains("椭圆机") { symbol = "figure.elliptical" }
        else if name.contains("跳绳") { symbol = "figure.jumprope" }
        else if name.contains("跑步") { symbol = "figure.run" }
        else if name.contains("步行") { symbol = "figure.walk" }
        else { symbol = "dumbbell" }
        return Upcoming(title: name, detail: details.isEmpty ? nil : details.joined(separator: " · "), symbolName: symbol)
    }

    static func title(_ original: String) -> String {
        let parts = original.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let result = parts.filter {
            let compact = $0.replacingOccurrences(of: " ", with: "")
            return compact.range(of: #"^(?:R\d+(?:建议预填)?|已确认P\d+|\d+组)$"#,
                                 options: .regularExpression) == nil
        }.joined(separator: " · ")
        return result.isEmpty ? original : result
    }

    /// Only explicit, exercise-local evidence is promoted out of the full notes.
    static func loadGuidance(in notes: String) -> String? {
        guard let first = notes.split(separator: "\n").first.map(String.init) else { return nil }
        guard !["热身", "准备", "依据"].contains(where: first.hasPrefix) else { return nil }
        let markers = ["片重", "杠铃片kg", "不含杆", "不含史密斯杆重", "双侧合计", "两侧合计",
                       "单侧kg", "每只哑铃kg", "每侧配重栈", "单个配重栈", "原机配重区",
                       "记重口径", "重量口径", "kg per side", "kg/side"]
        return markers.contains(where: first.lowercased().contains) ? first : nil
    }

    static func conditionNotice(in notes: String) -> String? {
        let condition = notes.split(separator: "\n").map(String.init).first {
            $0.hasPrefix("条件动作/试重：") || $0.hasPrefix("条件动作：")
        }
        guard let condition, condition.contains("恢复"),
              condition.contains("未知"), condition.contains("不适"),
              condition.contains("省去") || condition.contains("跳过") else { return nil }
        return "条件动作 · 恢复不明或不适时跳过"
    }

    static func compactTarget(_ prescription: WorkoutSetPrescription) -> String {
        var parts = [prescription.repsLower == prescription.repsUpper
            ? "\(prescription.repsLower)次" : "\(prescription.repsLower)–\(prescription.repsUpper)次"]
        if let lower = prescription.rirLower, let upper = prescription.rirUpper {
            parts.append(lower == upper ? "RIR \(lower)" : "RIR \(lower)–\(upper)")
        }
        return parts.joined(separator: " · ")
    }

    static func rest(_ prescription: WorkoutSetPrescription) -> String {
        let lower = prescription.restLowerSeconds, upper = prescription.restUpperSeconds
        return lower == upper ? "休息\(lower)秒" : "休息\(lower)–\(upper)秒"
    }

    static func target(_ prescription: WorkoutSetPrescription) -> String {
        var parts = [prescription.label,
            prescription.repsLower == prescription.repsUpper ? "\(prescription.repsLower)" : "\(prescription.repsLower)–\(prescription.repsUpper)"]
        if let lower = prescription.rirLower, let upper = prescription.rirUpper {
            parts.append(lower == upper ? "RIR \(lower)" : "RIR \(lower)–\(upper)")
        }
        let lower = prescription.restLowerSeconds, upper = prescription.restUpperSeconds
        parts.append(lower == upper ? "休息 \(lower) 秒" : "休息 \(lower)–\(upper) 秒")
        return parts.joined(separator: " · ")
    }

    static func planValue(_ plan: WorkoutSetPlan, unit: ExerciseVolumeUnit) -> String {
        if plan.actualDefaultPolicy == .blank { return "待校准" }
        if unit.recordsNumericLoad { return "\(TrainingFormatters.weight(plan.weight)) × \(plan.reps)" }
        if unit == .bodyweight { return "自重 × \(plan.reps)" }
        return "\(plan.reps) \(unit.symbol)"
    }
}

enum TrainingScheduleDate {
    /// New rows carry their original civil day. Legacy rows retain the old display interpretation;
    /// their unknown source timezone is surfaced, never guessed or backfilled.
    static func localDay(_ schedule: ScheduledWorkout, timeZone: TimeZone = .current) -> String {
        if let day = schedule.plannedLocalDay, TrainingLocalDate.date(day, timeZone: timeZone) != nil { return day }
        return TrainingLocalDate.key(schedule.plannedDate, timeZone: timeZone)
    }

    static func displayDate(_ schedule: ScheduledWorkout, timeZone: TimeZone = .current) -> Date {
        TrainingLocalDate.date(localDay(schedule, timeZone: timeZone), timeZone: timeZone) ?? schedule.plannedDate
    }
}

enum TrainingHistoryDate {
    /// Date ownership is separate from the absolute start instant. Unknown old records keep
    /// their existing display fallback, rather than having a source timezone invented.
    static func knownLocalDay(_ session: WorkoutSession, schedule: ScheduledWorkout? = nil) -> String? {
        if let day = session.trainingLocalDay, TrainingLocalDate.date(day) != nil { return day }
        if let schedule, schedule.id == session.scheduledWorkoutID,
           let day = schedule.plannedLocalDay, TrainingLocalDate.date(day) != nil { return day }
        return nil
    }

    static func localDay(_ session: WorkoutSession, schedule: ScheduledWorkout? = nil,
                         timeZone: TimeZone = .current) -> String {
        knownLocalDay(session, schedule: schedule)
            ?? TrainingLocalDate.key(session.isStartTimeKnown ? session.startedAt : session.plannedDate, timeZone: timeZone)
    }

    /// Noon is only a date-label formatting value; never use it as the workout's clock time.
    static func displayDate(_ session: WorkoutSession, schedule: ScheduledWorkout? = nil,
                            timeZone: TimeZone = .current) -> Date {
        TrainingLocalDate.date(localDay(session, schedule: schedule, timeZone: timeZone), timeZone: timeZone)
            ?? session.plannedDate
    }

    static func capture(_ session: WorkoutSession, date: Date, schedule: ScheduledWorkout? = nil,
                        timeZone: TimeZone = .current) {
        if let schedule, schedule.id == session.scheduledWorkoutID,
           let day = schedule.plannedLocalDay, TrainingLocalDate.date(day) != nil {
            session.trainingLocalDay = day
            session.trainingTimeZoneIdentifier = schedule.plannedTimeZoneIdentifier
        } else {
            session.trainingLocalDay = TrainingLocalDate.key(date, timeZone: timeZone)
            session.trainingTimeZoneIdentifier = timeZone.identifier
        }
    }
}

enum TrainingJumpRopeDate {
    static func localDay(_ entry: JumpRopeEntry, schedules: [ScheduledWorkout], timeZone: TimeZone = .current) -> String {
        if let day = entry.trainingLocalDay { return day }
        if let id = entry.scheduledWorkoutID, let schedule = schedules.first(where: { $0.id == id }) {
            return TrainingScheduleDate.localDay(schedule, timeZone: timeZone)
        }
        return TrainingLocalDate.key(entry.date, timeZone: timeZone)
    }
}

extension TrainingDayFeedback {
    init(schedules: [ScheduledWorkout], sessions: [WorkoutSession] = [], progress: [UUID: TrainingWorkSetProgress] = [:]) {
        self.init(events: schedules.map { schedule in
            let session = sessions.filter { $0.scheduledWorkoutID == schedule.id && $0.status == .completed }
                .max { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }
            return Event(state: State(rawValue: schedule.status.rawValue) ?? .planned,
                workingSets: session.flatMap { progress[$0.id] })
        })
    }

    var color: Color {
        switch tone {
        case .none: return .clear
        case .amber: return Color(red: 0.60, green: 0.36, blue: 0.04)
        case .purple: return AppTheme.purple
        case .green: return Color(red: 0.14, green: 0.43, blue: 0.28)
        case .gray: return AppTheme.secondaryText
        }
    }
}

/// Read-only day facts. Schedule-row feedback retains its original, separate contract.
struct TrainingDaySummary {
    let recordedSessions: [WorkoutSession]
    let activeSessions: [WorkoutSession]
    let jumpRopeEntries: [JumpRopeEntry]
    let pendingScheduleCount: Int
    let feedback: TrainingDayFeedback

    var hasActualRecords: Bool { !recordedSessions.isEmpty || !jumpRopeEntries.isEmpty }
    var pendingPlansLabel: String? {
        guard pendingScheduleCount > 0, hasActualRecords || !activeSessions.isEmpty else { return nil }
        return "另有 \(pendingScheduleCount) 项安排待完成"
    }
    var accessibilityLabel: String {
        [feedback.label, pendingPlansLabel].compactMap { $0 }.joined(separator: "，")
    }

    init(localDay: String, schedules: [ScheduledWorkout], sessions: [WorkoutSession],
         progress: [UUID: TrainingWorkSetProgress] = [:], jumpRopeEntries: [JumpRopeEntry] = [],
         excludedScheduleIDs: Set<UUID> = [], timeZone: TimeZone = .current) {
        var scheduleIDs = Set<UUID>()
        let uniqueSchedules = schedules.filter { scheduleIDs.insert($0.id).inserted }
        let daySchedules = uniqueSchedules.filter {
            !excludedScheduleIDs.contains($0.id) && TrainingScheduleDate.localDay($0, timeZone: timeZone) == localDay
        }
        var sessionIDs = Set<UUID>()
        let daySessions = sessions.filter { session in
            guard session.status != .discarded, sessionIDs.insert(session.id).inserted else { return false }
            let linked = uniqueSchedules.first { $0.id == session.scheduledWorkoutID }
            return TrainingHistoryDate.localDay(session, schedule: linked, timeZone: timeZone) == localDay
        }.sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
        recordedSessions = daySessions.filter { $0.status == .completed }
        activeSessions = daySessions.filter { $0.status == .inProgress }
        var ropeIDs = Set<UUID>()
        self.jumpRopeEntries = jumpRopeEntries.filter {
            TrainingJumpRopeDate.localDay($0, schedules: uniqueSchedules, timeZone: timeZone) == localDay && ropeIDs.insert($0.id).inserted
        }.sorted { $0.date > $1.date }
        pendingScheduleCount = daySchedules.filter { $0.status == .planned }.count
        let actualEvents = recordedSessions.map {
            TrainingDayFeedback.Event(state: .completed, workingSets: progress[$0.id])
        } + self.jumpRopeEntries.map { _ in TrainingDayFeedback.Event(state: .completed) }
        if !activeSessions.isEmpty {
            feedback = TrainingDayFeedback(states: [.inProgress])
        } else if !actualEvents.isEmpty {
            feedback = TrainingDayFeedback(recordedEvents: actualEvents)
        } else {
            feedback = TrainingDayFeedback(schedules: daySchedules, sessions: sessions, progress: progress)
        }
    }
}

/// Classification only: a completed arrangement is not itself an actual record.
/// Keep legacy completed arrangements visible when their actual entity is unavailable.
struct TrainingScheduleDayContent {
    let arrangements: [ScheduledWorkout]
    let independentActiveSessions: [WorkoutSession]
    let recordedSessions: [WorkoutSession]
    let jumpRopeEntries: [JumpRopeEntry]

    var hasArrangements: Bool { !arrangements.isEmpty || !independentActiveSessions.isEmpty }
    var hasRecords: Bool { !recordedSessions.isEmpty || !jumpRopeEntries.isEmpty }

    init(localDay: String, schedules: [ScheduledWorkout], sessions: [WorkoutSession],
         jumpRopeEntries: [JumpRopeEntry], timeZone: TimeZone = .current) {
        let summary = TrainingDaySummary(localDay: localDay, schedules: schedules,
            sessions: sessions, jumpRopeEntries: jumpRopeEntries, timeZone: timeZone)
        let actualScheduleIDs = Set(sessions.filter { $0.status == .completed }.compactMap(\.scheduledWorkoutID)
            + jumpRopeEntries.compactMap(\.scheduledWorkoutID))
        var seen = Set<UUID>()
        arrangements = schedules.filter {
            seen.insert($0.id).inserted && TrainingScheduleDate.localDay($0, timeZone: timeZone) == localDay
                && ($0.status != .completed || !actualScheduleIDs.contains($0.id))
        }.sorted { $0.plannedDate == $1.plannedDate
            ? $0.id.uuidString < $1.id.uuidString : $0.plannedDate < $1.plannedDate }
        let arrangementIDs = Set(arrangements.map(\.id))
        independentActiveSessions = summary.activeSessions.filter {
            $0.scheduledWorkoutID.map { !arrangementIDs.contains($0) } ?? true
        }
        recordedSessions = summary.recordedSessions
        self.jumpRopeEntries = summary.jumpRopeEntries
    }
}

/// Natural-month navigation is local presentation state, independent of the home selected day.
enum TrainingScheduleMonth {
    static func key(_ date: Date, timeZone: TimeZone = .current) -> String {
        String(TrainingLocalDate.key(date, timeZone: timeZone).prefix(7))
    }

    static func days(_ month: String, timeZone: TimeZone = .current) -> [String] {
        guard month.count == 7, let first = TrainingLocalDate.date(month + "-01", timeZone: timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        return range.map { String(format: "%@-%02d", month, $0) }
    }

    static func shifted(_ month: String, by offset: Int, timeZone: TimeZone = .current) -> String? {
        guard !days(month, timeZone: timeZone).isEmpty,
              let first = TrainingLocalDate.date(month + "-01", timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .month, value: offset, to: first).map { key($0, timeZone: timeZone) }
    }
}

/// Join only by explicit identity before filtering the month. A row never rewrites either entity.
struct TrainingScheduleMonthContent {
    struct Day: Identifiable {
        let localDay: String
        let entries: [Entry]
        var id: String { localDay }
    }

    enum Entry: Identifiable {
        case arrangement(ScheduledWorkout)
        case session(WorkoutSession, linkedSchedule: ScheduledWorkout?)
        case jumpRope(JumpRopeEntry, linkedSchedule: ScheduledWorkout?)

        var id: String {
            switch self {
            case .arrangement(let row): return "schedule:" + row.id.uuidString
            case .session(let row, _): return "session:" + row.id.uuidString
            case .jumpRope(let row, _): return "rope:" + row.id.uuidString
            }
        }

        func localDay(timeZone: TimeZone) -> String {
            switch self {
            case .arrangement(let row): return TrainingScheduleDate.localDay(row, timeZone: timeZone)
            case .session(let row, let plan): return TrainingHistoryDate.localDay(row, schedule: plan, timeZone: timeZone)
            case .jumpRope(let row, let plan):
                return TrainingJumpRopeDate.localDay(row, schedules: plan.map { [$0] } ?? [], timeZone: timeZone)
            }
        }

        private var sortDate: Date {
            switch self {
            case .arrangement(let row): return row.plannedDate
            case .session(let row, _): return row.startedAt
            case .jumpRope(let row, _): return row.date
            }
        }

        static func ordered(_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.sortDate == rhs.sortDate ? lhs.id < rhs.id : lhs.sortDate < rhs.sortDate
        }
    }

    let days: [Day]

    init(month: String, schedules: [ScheduledWorkout], sessions: [WorkoutSession],
         jumpRopeEntries: [JumpRopeEntry], timeZone: TimeZone = .current) {
        var seenPlans = Set<UUID>(), seenSessions = Set<UUID>(), seenRope = Set<UUID>()
        let plans = schedules.filter { seenPlans.insert($0.id).inserted }
        let actuals = sessions.filter { $0.status != .discarded && seenSessions.insert($0.id).inserted }
        let rope = jumpRopeEntries.filter { seenRope.insert($0.id).inserted }
        let planByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let represented = Set(actuals.compactMap(\.scheduledWorkoutID) + rope.compactMap(\.scheduledWorkoutID))
        let entries: [Entry] = plans.filter { !represented.contains($0.id) }.map { .arrangement($0) }
            + actuals.map { .session($0, linkedSchedule: $0.scheduledWorkoutID.flatMap { planByID[$0] }) }
            + rope.map { .jumpRope($0, linkedSchedule: $0.scheduledWorkoutID.flatMap { planByID[$0] }) }
        let monthDays = Set(TrainingScheduleMonth.days(month, timeZone: timeZone))
        let grouped = Dictionary(grouping: entries.filter { monthDays.contains($0.localDay(timeZone: timeZone)) }) {
            $0.localDay(timeZone: timeZone)
        }
        days = grouped.keys.sorted().map { Day(localDay: $0, entries: grouped[$0, default: []].sorted(by: Entry.ordered)) }
    }
}

struct TrainingActualSessionRow: View {
    let session: WorkoutSession
    let progress: TrainingWorkSetProgress?

    private var feedback: TrainingDayFeedback {
        session.status == .inProgress ? TrainingDayFeedback(states: [.inProgress])
            : TrainingDayFeedback(recordedEvents: [.init(state: .completed, workingSets: progress)])
    }

    var body: some View {
        NavigationLink {
            if session.status == .inProgress { ActiveWorkoutView(sessionID: session.id) }
            else { WorkoutDetailView(sessionID: session.id) }
        } label: {
            HStack(spacing: 12) {
                TrainingStatusMarker(feedback: feedback).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(TrainingWorkoutPresentation.title(session.templateName)).font(.headline).foregroundStyle(AppTheme.posterWarmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feedback.label).font(.caption).foregroundStyle(feedback.color)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.frame(minHeight: 44, alignment: .leading).cardSurface(padding: 14)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("实际训练-\(session.id.uuidString)")
            .accessibilityLabel("\(session.templateName)，\(feedback.label)")
            .accessibilityHint(session.status == .inProgress ? "继续本次训练" : "查看本次实际训练记录")
    }
}

struct TrainingActualJumpRopeRow: View {
    let entry: JumpRopeEntry
    var body: some View {
        NavigationLink { JumpRopeMenuRecordDetail(entry: entry) } label: { HStack(spacing: 12) {
            SprintIcon(systemName: "figure.jumprope", size: 38, prominent: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("已记录跳绳").font(.subheadline.bold())
                Text(entry.displaySummary).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.frame(minHeight: 44).cardSurface(padding: 14)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("跳绳实际-\(entry.id.uuidString)")
        }.buttonStyle(.plain)
    }
}

struct TrainingStatusMarker: View {
    let feedback: TrainingDayFeedback
    var body: some View {
        Group {
            if feedback.tone != .none {
                Image(systemName: feedback.symbolName)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(feedback.color)
                    .accessibilityLabel(feedback.label)
            }
        }.frame(width: 14, height: 14)
    }
}

@MainActor
enum TrainingWorkingSetProgressLoader {
    /// Bounded fetch on page entry/return/date change; no live global SetLog query while typing.
    static func load(schedules: [ScheduledWorkout], sessions: [WorkoutSession],
                     includingLocalDays: Set<String> = [], in context: ModelContext) throws -> [UUID: TrainingWorkSetProgress] {
        let scheduleIDs = Set(schedules.map(\.id))
        let sessionIDs = sessions.filter { session in
            guard session.status == .completed else { return false }
            if session.scheduledWorkoutID.map({ scheduleIDs.contains($0) }) == true { return true }
            let linked = schedules.first { $0.id == session.scheduledWorkoutID }
            return includingLocalDays.contains(TrainingHistoryDate.localDay(session, schedule: linked))
        }.map(\.id)
        guard !sessionIDs.isEmpty else { return [:] }
        let rows = try context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
            sessionIDs.contains($0.sessionID) && !$0.isWarmup
        }))
        return Dictionary(grouping: rows, by: \.sessionID).mapValues { rows in
            let active = rows.filter { $0.reductionOrder == nil }
            return TrainingWorkSetProgress(completed: active.filter(\.isCompleted).count, total: active.count)
        }
    }
}

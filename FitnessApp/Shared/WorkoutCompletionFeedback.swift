import Foundation

struct WorkoutCompletionRecord {
    var sessionID: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var isCompleted: Bool
    var isHistorical: Bool
    var startTimeKnown: Bool
    var completedWorkSets: Int
    var plannedWorkSets: Int
}

struct WorkoutCompletionSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let title: String
    let completedWorkSets: Int
    let durationSeconds: Int?

    var durationLabel: String {
        guard let durationSeconds else { return "时长未记录" }
        return "\(durationSeconds / 60) 分 \(durationSeconds % 60) 秒"
    }
}

/// Receives an explicit successful live-finish event, never observes saved history/imports.
@MainActor
final class WorkoutCompletionFeedback {
    static let shared = WorkoutCompletionFeedback(
        defaults: ProcessInfo.processInfo.arguments.contains("--ui-testing") ? nil : .standard
    )
    private let defaults: UserDefaults?
    private let storageKey = "workout-completion-presented-session-ids-v1"
    private var presented: Set<String>

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        presented = Set(defaults?.stringArray(forKey: storageKey) ?? [])
    }

    func receiveSavedCompletion(record: WorkoutCompletionRecord, allDaySchedulesCompleted: Bool? = nil,
                                now: Date = .now) -> WorkoutCompletionSummary? {
        guard record.isCompleted, !record.isHistorical, let ended = record.completedAt,
              ended <= now.addingTimeInterval(5), now.timeIntervalSince(ended) <= 60,
              !presented.contains(record.sessionID.uuidString) else { return nil }
        let allWorkSetsCompleted = record.plannedWorkSets > 0 && record.completedWorkSets == record.plannedWorkSets
        let title = allWorkSetsCompleted
            ? (allDaySchedulesCompleted == true ? "今日训练完成" : "本次训练已记录")
            : "本次训练已记录"
        let duration = ended.timeIntervalSince(record.startedAt)
        let seconds = record.startTimeKnown && duration >= 0 ? Int(duration) : nil
        presented.insert(record.sessionID.uuidString)
        defaults?.set(Array(presented).sorted(), forKey: storageKey)
        return WorkoutCompletionSummary(id: record.sessionID, name: record.name, title: title,
            completedWorkSets: record.completedWorkSets, durationSeconds: seconds)
    }
}

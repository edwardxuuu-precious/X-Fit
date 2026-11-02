import Foundation

struct TrainingWorkSetProgress: Equatable {
    let completed: Int
    let total: Int

    var completionFraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

struct TrainingDayFeedback: Equatable {
    enum State: String { case planned, inProgress, completed, skipped }
    enum Tone { case none, amber, purple, green, gray }
    struct Event {
        let state: State
        var workingSets: TrainingWorkSetProgress? = nil
        var isPartiallyRecorded: Bool {
            state == .completed && (workingSets.map { $0.total > 0 && $0.completed < $0.total } ?? false)
        }
    }
    let tone: Tone
    let label: String
    let completed: Int
    let total: Int
    let isPartial: Bool

    init(states: [State]) {
        self.init(events: states.map { Event(state: $0) })
    }

    /// Actual records are independent of whether a separate schedule was fulfilled.
    init(recordedEvents: [Event]) {
        let result = Self(events: recordedEvents)
        tone = result.tone
        completed = result.completed
        total = result.total
        isPartial = result.isPartial
        if recordedEvents.isEmpty {
            label = "暂无训练记录"
        } else if result.isPartial {
            let sets = recordedEvents.compactMap(\.workingSets)
            if sets.count == recordedEvents.count {
                label = "已记录 \(sets.reduce(0) { $0 + $1.completed })/\(sets.reduce(0) { $0 + $1.total }) 组"
            } else {
                label = "已记录训练 · 部分组未记录"
            }
        } else {
            label = "已记录训练"
        }
    }

    init(events: [Event]) {
        total = events.count
        completed = events.filter { $0.state == .completed && !$0.isPartiallyRecorded }.count
        isPartial = events.contains(where: \.isPartiallyRecorded) || (completed > 0 && completed < total)
        if events.isEmpty {
            tone = .none; label = "暂无安排"
        } else if events.contains(where: { $0.state == .inProgress }) {
            tone = .purple; label = "训练进行中"
        } else if completed == total {
            tone = .green; label = "已完成"
        } else if isPartial {
            tone = .amber
            if events.count == 1, let sets = events[0].workingSets, sets.total > 0 {
                label = "已记录 \(sets.completed)/\(sets.total) 组"
            } else {
                label = "部分完成 \(completed)/\(total)"
            }
        } else if events.allSatisfy({ $0.state == .skipped }) {
            tone = .gray; label = "已跳过"
        } else {
            tone = .amber; label = "待完成"
        }
    }

    var symbolName: String {
        switch tone {
        case .none: return ""
        case .amber: return isPartial ? "circle.lefthalf.filled" : "clock"
        case .purple: return "arrow.triangle.2.circlepath"
        case .green: return "checkmark.circle.fill"
        case .gray: return "forward.end"
        }
    }
}

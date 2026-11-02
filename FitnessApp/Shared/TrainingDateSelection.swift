import Foundation
import Observation

enum TrainingLocalDate {
    static func key(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ key: String, timeZone: TimeZone = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              Self.key(date, timeZone: timeZone) == key else { return nil }
        return date
    }
}

enum TrainingHistoricalDateEditing {
    static func apply(to session: WorkoutSession, originalStartedAt: Date, editedStartedAt: Date,
                      calendar: Calendar = .current) {
        guard !calendar.isDate(originalStartedAt, inSameDayAs: editedStartedAt) else { return }
        session.plannedDate = calendar.startOfDay(for: editedStartedAt)
        session.trainingLocalDay = TrainingLocalDate.key(editedStartedAt, timeZone: calendar.timeZone)
        session.trainingTimeZoneIdentifier = calendar.timeZone.identifier
    }

    static func plannedDate(original: Date, originalStartedAt: Date, editedStartedAt: Date,
                            calendar: Calendar = .current) -> Date {
        calendar.isDate(originalStartedAt, inSameDayAs: editedStartedAt)
            ? original : calendar.startOfDay(for: editedStartedAt)
    }
}

/// Shared presentation selection, not a rewrite of stored workout dates.
@MainActor @Observable
final class TrainingDateSelection {
    static let shared = TrainingDateSelection()

    enum RefreshReason { case foreground, dayOrTimeZoneChanged, returnFromDetail, explicitToday }
    private(set) var selectedLocalDay: String
    private(set) var todayLocalDay: String
    private(set) var timeZone: TimeZone
    private(set) var scrollRevision = 0

    var selectedDate: Date { TrainingLocalDate.date(selectedLocalDay, timeZone: timeZone) ?? .now }
    var today: Date { TrainingLocalDate.date(todayLocalDay, timeZone: timeZone) ?? .now }

    init(now: Date = .now, timeZone: TimeZone = .current) {
        let day = TrainingLocalDate.key(now, timeZone: timeZone)
        selectedLocalDay = day
        todayLocalDay = day
        self.timeZone = timeZone
    }

    func select(localDay: String) {
        guard TrainingLocalDate.date(localDay, timeZone: timeZone) != nil else { return }
        selectedLocalDay = localDay
    }

    func shiftWeek(by weeks: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDate) else { return }
        select(localDay: TrainingLocalDate.key(date, timeZone: timeZone))
    }

    static func weekSwipeDirection(horizontal: CGFloat, vertical: CGFloat) -> Int? {
        guard abs(horizontal) >= 50, abs(horizontal) > abs(vertical) * 1.5 else { return nil }
        return horizontal < 0 ? 1 : -1
    }

    func refresh(now: Date = .now, timeZone: TimeZone = .current, reason: RefreshReason,
                 hasActiveSession: Bool = false, isEditing: Bool = false, isShowingDetail: Bool = false) {
        todayLocalDay = TrainingLocalDate.key(now, timeZone: timeZone)
        self.timeZone = timeZone
        guard reason != .returnFromDetail else { return }
        guard reason == .explicitToday || (!hasActiveSession && !isEditing && !isShowingDetail) else { return }
        selectedLocalDay = todayLocalDay
        scrollRevision += 1
    }
}

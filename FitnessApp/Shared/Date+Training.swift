import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var weekdayNumber: Int {
        Calendar.current.component(.weekday, from: self)
    }

    func addingDays(_ value: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: value, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}

enum WeekdayName {
    static let orderedCalendarValues = [2, 3, 4, 5, 6, 7, 1]

    static func short(_ value: Int) -> String {
        switch value {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return "未设置"
        }
    }
}

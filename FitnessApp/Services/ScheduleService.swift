import Foundation
import SwiftData

@MainActor
enum ScheduleService {
    static func refreshUpcoming(in context: ModelContext, days: Int = 14) throws {
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let activeTemplates = templates.filter(\.isActive)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let today = Date.now.startOfDay

        for schedule in schedules where schedule.plannedDate >= today && schedule.status == .planned {
            guard let template = activeTemplates.first(where: { $0.id == schedule.templateID }),
                  template.weekday == schedule.plannedDate.weekdayNumber else {
                context.delete(schedule)
                continue
            }
            schedule.templateName = template.name
        }

        for offset in 0..<days {
            let date = today.addingDays(offset)
            for template in activeTemplates where template.weekday == date.weekdayNumber {
                let alreadyExists = schedules.contains {
                    $0.templateID == template.id && $0.plannedDate.isSameDay(as: date)
                }
                if !alreadyExists {
                    context.insert(
                        ScheduledWorkout(
                            templateID: template.id,
                            templateName: template.name,
                            plannedDate: date
                        )
                    )
                }
            }
        }
    }
}


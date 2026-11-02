import Foundation
import SwiftData

enum ScheduleServiceError: LocalizedError, Equatable {
    case immutableSchedule
    case cannotSkipRecordedWorkout
    case duplicateSchedule
    case occupiedDay
    case unsavedChanges
    case staleUndo

    var errorDescription: String? {
        switch self {
        case .immutableSchedule:
            return "已经开始或完成的训练不能再调整日期。"
        case .cannotSkipRecordedWorkout:
            return "进行中、已完成或已有实际记录的训练不能跳过。"
        case .duplicateSchedule:
            return "这一天已经安排了同一个训练计划。"
        case .occupiedDay:
            return "这一天已有另一场力量训练，请选择其他日期。"
        case .unsavedChanges:
            return "还有未保存的修改，请保存后再调整安排。"
        case .staleUndo:
            return "这次安排已经再次修改或开始训练，不能撤销旧操作。"
        }
    }
}

struct ScheduleManagementState: Equatable {
    var id: UUID
    var templateID: UUID
    var templateName: String
    var plannedDate: Date
    var plannedLocalDay: String?
    var plannedTimeZoneIdentifier: String?
    var originalPlannedDate: Date?
    var statusRaw: String
    var skipReason: String
    var reminderDate: Date?
    var updatedAt: Date
    var planSnapshotJSON: String?
    var confirmedDailyImportJSON: String?
    var jumpRopePlanJSON: String?

    init(_ schedule: ScheduledWorkout) {
        id = schedule.id; templateID = schedule.templateID; templateName = schedule.templateName
        plannedDate = schedule.plannedDate; plannedLocalDay = schedule.plannedLocalDay
        plannedTimeZoneIdentifier = schedule.plannedTimeZoneIdentifier; originalPlannedDate = schedule.originalPlannedDate
        statusRaw = schedule.statusRaw; skipReason = schedule.skipReason; reminderDate = schedule.reminderDate
        updatedAt = schedule.updatedAt; planSnapshotJSON = schedule.planSnapshotJSON
        confirmedDailyImportJSON = schedule.confirmedDailyImportJSON; jumpRopePlanJSON = schedule.jumpRopePlanJSON
    }

    func restore(_ schedule: ScheduledWorkout) {
        schedule.templateID = templateID; schedule.templateName = templateName
        schedule.plannedDate = plannedDate; schedule.plannedLocalDay = plannedLocalDay
        schedule.plannedTimeZoneIdentifier = plannedTimeZoneIdentifier; schedule.originalPlannedDate = originalPlannedDate
        schedule.statusRaw = statusRaw; schedule.skipReason = skipReason; schedule.reminderDate = reminderDate
        schedule.updatedAt = updatedAt; schedule.planSnapshotJSON = planSnapshotJSON
        schedule.confirmedDailyImportJSON = confirmedDailyImportJSON; schedule.jumpRopePlanJSON = jumpRopePlanJSON
    }
}

struct ScheduleManagementUndo {
    let scheduleID: UUID
    let originalDate: Date
    let newDate: Date
    fileprivate let before: ScheduleManagementState
    fileprivate let after: ScheduleManagementState
    fileprivate let sourceAfter: [UUID: String]
}

@MainActor
enum ScheduleService {
    /// Marks every unfinished schedule as revoked while retaining its row, identifier and links.
    @discardableResult
    static func revokeAllUnfinished(reason: String, in context: ModelContext) throws -> Int {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else { throw ScheduleServiceError.immutableSchedule }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let targets = schedules.filter { $0.status == .planned || $0.status == .inProgress }
        for schedule in targets {
            schedule.status = .skipped
            schedule.skipReason = normalizedReason
            schedule.reminderDate = nil
            schedule.updatedAt = .now
        }
        if !targets.isEmpty {
            try context.save()
            syncNotifications(in: context)
        }
        return targets.count
    }

    static func refreshUpcoming(in context: ModelContext, days: Int = 14) throws {
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let today = Date.now.startOfDay
        _ = days

        for template in templates where !template.isOneOff {
            template.isActive = false
        }

        for schedule in schedules where schedule.plannedDate >= today && schedule.status == .planned {
            guard let template = templates.first(where: { $0.id == schedule.templateID }) else {
                context.delete(schedule)
                continue
            }
            schedule.templateName = template.name

            if !schedule.isManuallyScheduled && schedule.originalPlannedDate == nil {
                context.delete(schedule)
            }
        }
    }

    static func addManual(
        template: WorkoutTemplate,
        on date: Date,
        in context: ModelContext
    ) throws -> ScheduledWorkout {
        let targetDate = date.startOfDay
        let targetDay = TrainingLocalDate.key(targetDate)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: {
            $0.templateID == template.id && TrainingScheduleDate.localDay($0) == targetDay
        }) else {
            throw ScheduleServiceError.duplicateSchedule
        }

        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: targetDate,
            isManuallyScheduled: true
        )
        schedule.plannedLocalDay = TrainingLocalDate.key(targetDate)
        schedule.plannedTimeZoneIdentifier = TimeZone.current.identifier
        schedule.planSnapshot = try planSnapshot(templateID: template.id, in: context)
        context.insert(schedule)
        try context.save()
        syncNotifications(in: context)
        return schedule
    }

    static func freezePlanSnapshot(
        for schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws {
        guard schedule.planSnapshot.isEmpty else { return }
        schedule.planSnapshot = try planSnapshot(templateID: schedule.templateID, in: context)
    }

    static func planSnapshot(
        templateID: UUID,
        in context: ModelContext
    ) throws -> [ScheduledWorkoutExerciseSnapshot] {
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.templateID == templateID }
            .sorted { $0.order < $1.order }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return items.compactMap { item in
            guard let exercise = exerciseByID[item.exerciseID] else { return nil }
            return ScheduledWorkoutExerciseSnapshot(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                exerciseNotes: exercise.notes,
                referenceURL: exercise.referenceURL,
                volumeUnit: exercise.volumeUnit,
                order: item.order,
                targetSets: item.targetSets,
                minReps: item.minReps,
                maxReps: item.maxReps,
                targetWeight: item.targetWeight,
                restSeconds: item.restSeconds,
                plannedSets: item.plannedSets,
                planPattern: item.planPattern,
                patternSource: item.patternSource
            )
        }
    }

    static func reschedule(
        _ schedule: ScheduledWorkout,
        to date: Date,
        timeZone: TimeZone = .current,
        in context: ModelContext
    ) throws {
        _ = try performReschedule(schedule, to: date, timeZone: timeZone, strictConflicts: false, in: context)
    }

    static func skip(
        _ schedule: ScheduledWorkout,
        reason: String,
        in context: ModelContext
    ) throws {
        _ = try performSkip(schedule, reason: reason, requireCleanContext: false, in: context)
    }

    static func restore(
        _ schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws {
        _ = try performRestore(schedule, requireCleanContext: false, in: context)
    }

    static func canManage(_ schedule: ScheduledWorkout, in context: ModelContext) -> Bool {
        (try? validateUnstarted(schedule, in: context)) != nil
    }

    static func validateUnstarted(_ schedule: ScheduledWorkout, in context: ModelContext) throws {
        try validateScheduleEligibility(schedule, forSkipping: false, in: context)
    }

    private static func validateScheduleEligibility(_ schedule: ScheduledWorkout, forSkipping: Bool,
                                                     in context: ModelContext) throws {
        guard schedule.status == .planned || schedule.status == .skipped,
              !schedule.skipReason.hasPrefix("已由确认修订 ") else { throw ScheduleServiceError.immutableSchedule }
        if schedule.confirmedDailyImportJSON != nil,
           try ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) {
            throw ScheduleServiceError.immutableSchedule
        }
        if FatLossBackupService.isRegistered(WorkoutSession.self, in: context) {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.scheduledWorkoutID == schedule.id }
            if !sessions.isEmpty {
                guard forSkipping else { throw ScheduleServiceError.immutableSchedule }
                guard sessions.allSatisfy({ $0.status == .discarded }),
                      FatLossBackupService.isRegistered(SetLog.self, in: context) else {
                    throw ScheduleServiceError.cannotSkipRecordedWorkout
                }
                let sessionIDs = Set(sessions.map(\.id))
                guard try !context.fetch(FetchDescriptor<SetLog>()).contains(where: {
                    sessionIDs.contains($0.sessionID) && $0.isCompleted
                }) else { throw ScheduleServiceError.cannotSkipRecordedWorkout }
            }
        }
        if FatLossBackupService.isRegistered(JumpRopeEntry.self, in: context),
           try context.fetch(FetchDescriptor<JumpRopeEntry>()).contains(where: { $0.scheduledWorkoutID == schedule.id }) {
            throw forSkipping ? ScheduleServiceError.cannotSkipRecordedWorkout : ScheduleServiceError.immutableSchedule
        }
    }

    static func validateManagedReschedule(_ schedule: ScheduledWorkout, to date: Date, timeZone: TimeZone = .current,
                                          in context: ModelContext) throws {
        let target = try rescheduleTarget(date, timeZone: timeZone)
        try validateReschedule(schedule, to: target.date, strictConflicts: true, localDay: target.localDay, in: context)
        _ = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
    }

    private static func validateReschedule(_ schedule: ScheduledWorkout, to date: Date,
                                           strictConflicts: Bool, localDay: String? = nil, in context: ModelContext) throws {
        if strictConflicts && context.hasChanges { throw ScheduleServiceError.unsavedChanges }
        try validateUnstarted(schedule, in: context)
        let day = localDay ?? TrainingLocalDate.key(date)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: {
            $0.id != schedule.id && $0.templateID == schedule.templateID && TrainingScheduleDate.localDay($0) == day
        }) else { throw ScheduleServiceError.duplicateSchedule }
        guard strictConflicts else { return }
        let links = FatLossBackupService.isRegistered(ProgramWorkoutLink.self, in: context)
            ? try context.fetch(FetchDescriptor<ProgramWorkoutLink>()) : []
        let revisions = FatLossBackupService.isRegistered(TrainingProgramRevision.self, in: context)
            ? try context.fetch(FetchDescriptor<TrainingProgramRevision>()) : []
        let cardioIDs = TrainingDateMenuService.cardioScheduleIDs(schedules: schedules, links: links, revisions: revisions)
            .union(schedules.filter { CardioWorkoutPresentation.plan($0) != nil }.map(\.id))
        guard !cardioIDs.contains(schedule.id) else { return }
        if schedules.contains(where: {
            $0.id != schedule.id && !cardioIDs.contains($0.id) && $0.status != .skipped && TrainingScheduleDate.localDay($0) == day
        }) { throw ScheduleServiceError.occupiedDay }
        if FatLossBackupService.isRegistered(WorkoutSession.self, in: context) {
            let actuals = try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
                $0.scheduledWorkoutID != schedule.id && $0.status != .discarded && TrainingHistoryDate.localDay($0) == day
            }
            let exercises = FatLossBackupService.isRegistered(SessionExercise.self, in: context)
                ? try context.fetch(FetchDescriptor<SessionExercise>()) : []
            let logs = FatLossBackupService.isRegistered(SetLog.self, in: context)
                ? try context.fetch(FetchDescriptor<SetLog>()) : []
            if actuals.contains(where: { session in
                !(session.scheduledWorkoutID.map { cardioIDs.contains($0) } ?? false)
                    && CardioWorkoutPresentation.actual(session, exercises: exercises, logs: logs) == nil
            }) { throw ScheduleServiceError.occupiedDay }
        }
    }

    static func rescheduleManaged(_ schedule: ScheduledWorkout, to date: Date, timeZone: TimeZone = .current,
                                  in context: ModelContext,
                                  commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        try performReschedule(schedule, to: date, timeZone: timeZone, strictConflicts: true, in: context, commit: commit)
    }

    /// The selected civil day and its zone own the date value. Confirmed imports use local
    /// noon as this date-only anchor, so management must use the same exact representation.
    private static func rescheduleTarget(_ date: Date, timeZone: TimeZone) throws -> (date: Date, localDay: String) {
        let day = TrainingLocalDate.key(date, timeZone: timeZone)
        guard let anchor = MealLocalDay.date(day, timeZone: timeZone) else {
            throw ConfirmedTrainingPlanError.conflict("改期日期与时区不一致")
        }
        return (anchor, day)
    }

    private static func performReschedule(_ schedule: ScheduledWorkout, to date: Date, timeZone: TimeZone,
                                          strictConflicts: Bool,
                                          in context: ModelContext,
                                          commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        let target = try rescheduleTarget(date, timeZone: timeZone)
        try validateReschedule(schedule, to: target.date, strictConflicts: strictConflicts, localDay: target.localDay, in: context)
        return try mutate(schedule, kind: "reschedule", requireCleanContext: strictConflicts, in: context, commit: commit) {
            if schedule.originalPlannedDate == nil { schedule.originalPlannedDate = schedule.plannedDate }
            schedule.plannedDate = target.date
            schedule.plannedLocalDay = target.localDay
            schedule.plannedTimeZoneIdentifier = timeZone.identifier
            schedule.status = .planned
            schedule.skipReason = ""
        }
    }

    static func skipManaged(_ schedule: ScheduledWorkout, reason: String, in context: ModelContext,
                            commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        try performSkip(schedule, reason: reason, requireCleanContext: true, in: context, commit: commit)
    }

    private static func performSkip(_ schedule: ScheduledWorkout, reason: String, requireCleanContext: Bool,
                                     in context: ModelContext,
                                     commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        guard schedule.status == .planned else { throw ScheduleServiceError.immutableSchedule }
        return try mutate(schedule, kind: nil, requireCleanContext: requireCleanContext, forSkipping: true, in: context, commit: commit) {
            schedule.status = .skipped
            schedule.skipReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            schedule.reminderDate = nil
        }
    }

    static func restoreManaged(_ schedule: ScheduledWorkout, in context: ModelContext,
                               commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        try performRestore(schedule, requireCleanContext: true, in: context, commit: commit)
    }

    private static func performRestore(_ schedule: ScheduledWorkout, requireCleanContext: Bool, in context: ModelContext,
                                       commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduleManagementUndo {
        guard schedule.status == .skipped else { throw ScheduleServiceError.immutableSchedule }
        if requireCleanContext {
            try validateReschedule(schedule, to: schedule.plannedDate, strictConflicts: true,
                localDay: TrainingScheduleDate.localDay(schedule), in: context)
        }
        return try mutate(schedule, kind: nil, requireCleanContext: requireCleanContext, in: context, commit: commit) {
            schedule.status = .planned
            schedule.skipReason = ""
        }
    }

    static func undoManaged(_ undo: ScheduleManagementUndo, in context: ModelContext,
                            commit: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard !context.hasChanges,
              let schedule = try context.fetch(FetchDescriptor<ScheduledWorkout>()).first(where: { $0.id == undo.scheduleID }),
              ScheduleManagementState(schedule) == undo.after,
              try sourceSnapshots(for: schedule, in: context) == undo.sourceAfter else {
            throw ScheduleServiceError.staleUndo
        }
        do { try validateUnstarted(schedule, in: context) }
        catch { throw ScheduleServiceError.staleUndo }
        if undo.before.statusRaw == ScheduleStatus.planned.rawValue {
            try validateReschedule(schedule, to: undo.before.plannedDate, strictConflicts: true,
                localDay: undo.before.plannedLocalDay, in: context)
        }
        _ = try mutate(schedule, kind: "reschedule", in: context, commit: commit) {
            // Preserve the append-only provenance; append the inverse date action below.
            let provenance = schedule.confirmedDailyImportJSON
            undo.before.restore(schedule)
            schedule.confirmedDailyImportJSON = provenance
        }
    }

    private static func mutate(_ schedule: ScheduledWorkout, kind: String?, requireCleanContext: Bool = true,
                                forSkipping: Bool = false, in context: ModelContext,
                                commit: (ModelContext) throws -> Void,
                                change: () throws -> Void) throws -> ScheduleManagementUndo {
        let hadChanges = context.hasChanges
        if requireCleanContext && hadChanges { throw ScheduleServiceError.unsavedChanges }
        try validateScheduleEligibility(schedule, forSkipping: forSkipping, in: context)
        let capture = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
        let before = ScheduleManagementState(schedule)
        let previousSources = capture.weekly.map { ($0.revision, $0.revision.snapshotJSON) }
        let autosave = context.autosaveEnabled; context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            try change()
            schedule.updatedAt = .now
            if let kind { try ConfirmedTrainingPlanService.appendScheduleAdjustment(schedule, capture: capture, kind: kind, in: context) }
            _ = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
            let after = ScheduleManagementState(schedule)
            let sourceAfter = try sourceSnapshots(for: schedule, in: context)
            try commit(context)
            guard !context.hasChanges else {
                throw ConfirmedTrainingPlanError.conflict("日程提交未完成；暂存调整已回滚")
            }
            syncNotifications(in: context)
            return ScheduleManagementUndo(scheduleID: schedule.id, originalDate: before.plannedDate, newDate: after.plannedDate,
                before: before, after: after, sourceAfter: sourceAfter)
        } catch {
            before.restore(schedule)
            for (revision, json) in previousSources { revision.snapshotJSON = json }
            if !hadChanges { context.rollback() }
            throw error
        }
    }

    private static func sourceSnapshots(for schedule: ScheduledWorkout, in context: ModelContext) throws -> [UUID: String] {
        let capture = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
        return Dictionary(uniqueKeysWithValues: capture.weekly.map { ($0.revision.id, $0.revision.snapshotJSON) })
    }

    static func deleteManual(
        _ schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws {
        guard schedule.isManuallyScheduled, schedule.status == .planned || schedule.status == .skipped else {
            throw ScheduleServiceError.immutableSchedule
        }
        let templateID = schedule.templateID
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
        if FatLossBackupService.isRegistered(ProgramWorkoutLink.self, in: context) {
            let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
            links.filter { $0.scheduledWorkoutID == schedule.id }.forEach(context.delete)
        }
        context.delete(schedule)
        if let template = templates.first(where: { $0.id == templateID && $0.isOneOff }) {
            templateItems
                .filter { $0.templateID == templateID }
                .forEach(context.delete)
            context.delete(template)
        }
        try context.save()
        syncNotifications(in: context)
    }

    private static func syncNotifications(in context: ModelContext) {
        guard let allSchedules = try? context.fetch(FetchDescriptor<ScheduledWorkout>()) else { return }
        Task {
            await NotificationService.syncWorkoutReminders(allSchedules)
        }
    }
}

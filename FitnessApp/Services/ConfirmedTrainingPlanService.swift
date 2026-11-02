import CryptoKit
import Foundation
import SwiftData

/// Exact, owner-confirmed identities for this import; never a fuzzy catalog match.
struct ConfirmedTrainingCatalogAddition: Codable, Hashable {
    var id: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var volumeUnitRaw: String
    var defaultRestSeconds: Int
}

struct ConfirmedTrainingPlanPacket: Codable, Equatable {
    var version: Int
    var programID: UUID
    var startLocalDay: String
    var endLocalDay: String
    var timeZoneIdentifier: String
    var confirmedAt: Date
    var confirmationReference: String
    var sourceMarkdown: String
    var sourceSHA256: String
    var snapshot: TrainingProgramSnapshot
    var catalogAdditions: [ConfirmedTrainingCatalogAddition]? = nil
    var catalogConfirmationReference: String? = nil
}

struct ConfirmedTrainingPlanSource: Codable, Hashable {
    var packetSHA256: String
    var startLocalDay: String
    var endLocalDay: String
    var timeZoneIdentifier: String
    var confirmedAt: Date
    var confirmationReference: String
    var sourceMarkdown: String
    var sourceSHA256: String
    var scheduleIntegritySHA256: String? = nil
    // Optional so old packets/backups retain their original source fingerprint.
    var catalogAdditions: [ConfirmedTrainingCatalogAddition]? = nil
    var catalogConfirmationReference: String? = nil
    /// Append-only owner actions; the original packet and its seal stay unchanged.
    var scheduleAdjustmentsJSON: String? = nil
}

struct ConfirmedScheduleAdjustment: Codable, Equatable {
    var id: UUID
    var confirmedAt: Date
    var kind: String
    var before: ConfirmedTrainingScheduleReadback
    var after: ConfirmedTrainingScheduleReadback
}

struct ConfirmedScheduleAdjustmentCapture {
    var daily: ConfirmedTrainingScheduleReadback?
    var rope: ConfirmedTrainingScheduleReadback? = nil
    var weekly: [(revision: TrainingProgramRevision, record: ConfirmedTrainingScheduleReadback)]
}

struct ConfirmedTrainingPlanPreview: Codable, Equatable, Identifiable {
    var packet: ConfirmedTrainingPlanPacket
    var packetSHA256: String
    var destinationFingerprint: String
    var conflicts: [String]
    var scheduledDays: [String]
    var newScheduleCount: Int
    var existingRevisionID: UUID?
    var newExerciseCount: Int? = nil
    var id: String { packetSHA256 }
}

struct ConfirmedTrainingPlanReadback: Codable, Equatable {
    var revisionID: UUID
    var programID: UUID
    var snapshot: TrainingProgramSnapshot
    var scheduleIDs: [UUID]
    var schedules: [ConfirmedTrainingScheduleReadback]
}

struct ConfirmedTrainingScheduleReadback: Codable, Equatable {
    var id: UUID
    var code: String
    var templateID: UUID
    var title: String
    var localDay: String
    var timeZoneIdentifier: String
    var plannedDate: Date
    var exercises: [ScheduledWorkoutExerciseSnapshot]
}

struct ConfirmedTrainingPlanApplyResult: Codable, Equatable {
    var newScheduleCount: Int
    var readback: ConfirmedTrainingPlanReadback
    var newExerciseCount: Int? = nil
}

enum ConfirmedTrainingPlanError: LocalizedError {
    case invalidPacket(String), conflict(String), changedPreview, unsavedChanges
    var errorDescription: String? {
        switch self {
        case .invalidPacket(let detail): return "计划包不完整：\(detail)。未写入。"
        case .conflict(let detail): return "计划导入冲突：\(detail)。原记录保持不变。"
        case .changedPreview: return "预览后来源或日程发生变化，请重新预览；未写入。"
        case .unsavedChanges: return "请先保存当前编辑，再导入计划；未写入。"
        }
    }
}

/// An explicit, bounded App-owned import. Never completes or edits a workout session.
@MainActor
enum ConfirmedTrainingPlanService {
    static func preview(_ packet: ConfirmedTrainingPlanPacket, in context: ModelContext) throws -> ConfirmedTrainingPlanPreview {
        let start = try validate(packet)
        let packetSHA256 = try digest(packet)
        guard let program = try context.fetch(FetchDescriptor<FatLossProgram>()).first(where: { $0.id == packet.programID }),
              program.statusRaw == "active", start >= program.startDate, FatLossCalendar.adding(6, to: start) < program.endDate else {
            throw ConfirmedTrainingPlanError.invalidPacket("目标周期未生效或不覆盖这一周")
        }
        let preferences = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        let preference = try TrainingPreferenceService.current(in: context, on: start)
        var conflicts: [String] = []
        if preference?.revisionCode != packet.snapshot.preferenceRevisionCode ||
            preference?.snapshot?.strengthDaysPerWeek != packet.snapshot.strengthWorkouts.count {
            conflicts.append("生效偏好或力量训练天数与确认版本不同")
        }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let additions = packet.catalogAdditions ?? []
        for addition in additions {
            if exercises.contains(where: { $0.id != addition.id && catalogNameKey($0.name) == catalogNameKey(addition.name) }) {
                conflicts.append("同名动作已有另一身份，不恢复或借用：\(addition.name)")
            }
        }
        for draft in packet.snapshot.strengthWorkouts.flatMap(\.exercises) {
            if let addition = additions.first(where: { $0.id == draft.catalogExerciseID }),
               !exercises.contains(where: { $0.id == addition.id }) {
                // validate() has already checked the exact identity and the separate owner confirmation.
                continue
            }
            guard let id = draft.catalogExerciseID, let exercise = exercises.first(where: { $0.id == id }),
                  !exercise.isArchived, exercise.name == (draft.catalogName ?? draft.name), exercise.equipment == draft.equipment,
                  exercise.volumeUnit.rawValue == draft.volumeUnitRaw,
                  additions.first(where: { $0.id == id }).map({ $0.muscleGroup == exercise.muscleGroup }) ?? true else {
                conflicts.append("动作身份/器械/单位不兼容：\(draft.name)")
                continue
            }
        }
        for cardio in packet.snapshot.cardioWorkouts {
            guard let exercise = exercises.first(where: { $0.id == cardio.catalogExerciseID }),
                  !exercise.isArchived, exercise.volumeUnit == .second else {
                conflicts.append("计时有氧身份或单位不兼容：\(cardio.title)")
                continue
            }
        }
        let days = (packet.snapshot.strengthWorkouts.map(\.weekday) + packet.snapshot.cardioWorkouts.map(\.weekday))
            .map { FatLossCalendar.label(date(for: $0, start: start)) }
        let existing = try readback(code: packet.snapshot.code, in: context)
        if let existing, existing.programID != packet.programID ||
            existing.snapshot.confirmedImport?.packetSHA256 != packetSHA256 {
            conflicts.append("相同版本已有不同内容或来源")
        }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>()).filter {
            let day = TrainingScheduleDate.localDay($0)
            return day >= packet.startLocalDay && day <= packet.endLocalDay
        }
        let ownIDs = Set(existing?.scheduleIDs ?? [])
        if schedules.contains(where: { !ownIDs.contains($0.id) }) {
            conflicts.append("该周已有其他日程，不自动覆盖或取消")
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
            let day = TrainingHistoryDate.localDay($0)
            return day >= packet.startLocalDay && day <= packet.endLocalDay && $0.status != .discarded
        }
        if sessions.contains(where: { $0.scheduledWorkoutID.map { !ownIDs.contains($0) } ?? true }) {
            conflicts.append("该周已有其他实际训练，不自动覆盖")
        }
        let destination: [[String]] = [["program", program.id.uuidString, program.statusRaw,
            String(program.startDate.timeIntervalSinceReferenceDate), String(program.endDate.timeIntervalSinceReferenceDate), program.timeZoneIdentifier]]
            + preferences.map { ["preference", $0.id.uuidString, $0.snapshotJSON,
                String($0.effectiveAt.timeIntervalSinceReferenceDate)] }.sorted { $0[1] < $1[1] }
            + schedules.map { ["schedule", $0.id.uuidString, TrainingScheduleDate.localDay($0),
                $0.plannedTimeZoneIdentifier ?? "unknown", String($0.plannedDate.timeIntervalSinceReferenceDate),
                $0.templateID.uuidString, $0.templateName, $0.statusRaw, $0.planSnapshotJSON ?? ""] }.sorted { $0[1] < $1[1] }
            + exercises.filter { row in packet.snapshot.strengthWorkouts.flatMap(\.exercises).contains { $0.catalogExerciseID == row.id }
                || packet.snapshot.cardioWorkouts.contains { $0.catalogExerciseID == row.id }
                || additions.contains { catalogNameKey($0.name) == catalogNameKey(row.name) } }
                .map { ["exercise", $0.id.uuidString, $0.name, $0.muscleGroup, $0.equipment, $0.volumeUnit.rawValue,
                    String($0.isArchived), $0.referenceURL] }.sorted { $0[1] < $1[1] }
            + sessions.map { ["session", $0.id.uuidString, $0.statusRaw] }.sorted { $0[1] < $1[1] }
        return ConfirmedTrainingPlanPreview(packet: packet, packetSHA256: packetSHA256,
            destinationFingerprint: try digest(destination), conflicts: conflicts,
            scheduledDays: days, newScheduleCount: existing == nil ? days.count : 0, existingRevisionID: existing?.revisionID,
            newExerciseCount: additions.filter { addition in !exercises.contains { $0.id == addition.id } }.count)
    }

    static func apply(expectedPreview: ConfirmedTrainingPlanPreview, in context: ModelContext,
                      commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ConfirmedTrainingPlanApplyResult {
        guard !context.hasChanges else { throw ConfirmedTrainingPlanError.unsavedChanges }
        let fresh = try preview(expectedPreview.packet, in: context)
        guard expectedPreview.packetSHA256 == fresh.packetSHA256, expectedPreview.conflicts.isEmpty else {
            throw ConfirmedTrainingPlanError.changedPreview
        }
        guard fresh.conflicts.isEmpty else { throw ConfirmedTrainingPlanError.conflict(fresh.conflicts.joined(separator: "；")) }
        if fresh.existingRevisionID != nil, let stored = try readback(code: fresh.packet.snapshot.code, in: context) {
            // A successful request can be retried with its original preview. Verify stored content first.
            return ConfirmedTrainingPlanApplyResult(newScheduleCount: 0, readback: stored, newExerciseCount: 0)
        }
        guard fresh == expectedPreview else { throw ConfirmedTrainingPlanError.changedPreview }
        let packet = fresh.packet
        let start = try validate(packet)
        guard let preference = try TrainingPreferenceService.current(in: context, on: start) else {
            throw ConfirmedTrainingPlanError.conflict("生效偏好缺失")
        }
        var catalog = try context.fetch(FetchDescriptor<Exercise>())
        let revisionNumber = (try context.fetch(FetchDescriptor<TrainingProgramRevision>())
            .filter { $0.programID == packet.programID }.map(\.revision).max() ?? 0) + 1
        var snapshot = packet.snapshot
        snapshot.confirmedImport = ConfirmedTrainingPlanSource(packetSHA256: fresh.packetSHA256,
            startLocalDay: packet.startLocalDay, endLocalDay: packet.endLocalDay, timeZoneIdentifier: packet.timeZoneIdentifier,
            confirmedAt: packet.confirmedAt, confirmationReference: packet.confirmationReference,
            sourceMarkdown: packet.sourceMarkdown, sourceSHA256: packet.sourceSHA256,
            catalogAdditions: packet.catalogAdditions, catalogConfirmationReference: packet.catalogConfirmationReference)
        let revision = try TrainingProgramRevision(programID: packet.programID, preferenceRevision: preference,
            snapshot: snapshot, revision: revisionNumber, effectiveDate: start,
            reason: "已确认计划导入 · \(packet.confirmationReference)；仅这一周，长期偏好不改")
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            for addition in packet.catalogAdditions ?? [] where !catalog.contains(where: { $0.id == addition.id }) {
                let exercise = Exercise(id: addition.id, name: addition.name, muscleGroup: addition.muscleGroup,
                    equipment: addition.equipment, defaultRestSeconds: addition.defaultRestSeconds,
                    isBuiltIn: false, notes: "已确认计划新增动作 · \(packet.catalogConfirmationReference ?? "")",
                    volumeUnit: .kilogram)
                context.insert(exercise)
                catalog.append(exercise)
            }
            context.insert(revision)
            for workout in snapshot.strengthWorkouts {
                let localDay = FatLossCalendar.label(date(for: workout.weekday, start: start))
                let zone = TimeZone(identifier: packet.timeZoneIdentifier)!
                let plannedDate = MealLocalDay.date(localDay, timeZone: zone)!
                let template = WorkoutTemplate(name: workout.title, weekday: workout.weekday,
                    isActive: false, isOneOff: true, plannedForDate: plannedDate,
                    focusMuscleGroups: Array(Set(workout.exercises.map(\.muscleGroup))).sorted(),
                    trainingPreferenceSnapshotJSON: preference.snapshotJSON)
                context.insert(template)
                var frozen: [ScheduledWorkoutExerciseSnapshot] = []
                for (order, draft) in workout.exercises.enumerated() {
                    guard let exercise = catalog.first(where: { $0.id == draft.catalogExerciseID }), let plans = draft.plannedSets else {
                        throw ConfirmedTrainingPlanError.conflict("动作引用缺失")
                    }
                    let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: order,
                        targetSets: draft.sets, minReps: draft.repsLower, maxReps: draft.repsUpper,
                        targetWeight: 0, restSeconds: draft.restSeconds, plannedSets: plans)
                    context.insert(item)
                    frozen.append(ScheduledWorkoutExerciseSnapshot(id: item.id, exerciseID: exercise.id,
                        exerciseName: draft.name, muscleGroup: draft.muscleGroup, equipment: draft.equipment,
                        exerciseNotes: draft.note + "\n" + workout.guidance, referenceURL: exercise.referenceURL,
                        volumeUnit: exercise.volumeUnit, order: order, targetSets: draft.sets,
                        minReps: draft.repsLower, maxReps: draft.repsUpper, targetWeight: 0,
                        restSeconds: draft.restSeconds, plannedSets: plans, planPattern: .fixed, patternSource: .exerciseOverride))
                }
                let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name,
                    plannedDate: plannedDate, isManuallyScheduled: true, planSnapshot: frozen)
                schedule.plannedDate = plannedDate
                schedule.plannedLocalDay = localDay
                schedule.plannedTimeZoneIdentifier = packet.timeZoneIdentifier
                context.insert(schedule)
                let link = ProgramWorkoutLink(programID: packet.programID, scheduledWorkoutID: schedule.id,
                    templateCode: workout.code, originalDate: date(for: workout.weekday, start: start))
                link.trainingProgramRevisionID = revision.id
                context.insert(link)
            }
            for cardio in snapshot.cardioWorkouts {
                guard let exercise = catalog.first(where: { $0.id == cardio.catalogExerciseID }),
                      let lower = cardio.activeSeconds else { throw ConfirmedTrainingPlanError.conflict("计时有氧引用缺失") }
                let upper = cardio.activeSecondsUpper ?? lower
                let localDay = FatLossCalendar.label(date(for: cardio.weekday, start: start))
                let plannedDate = MealLocalDay.date(localDay, timeZone: TimeZone(identifier: packet.timeZoneIdentifier)!)!
                let template = WorkoutTemplate(name: cardio.title, weekday: cardio.weekday,
                    isActive: false, isOneOff: true, plannedForDate: plannedDate,
                    focusMuscleGroups: [exercise.muscleGroup], trainingPreferenceSnapshotJSON: preference.snapshotJSON)
                context.insert(template)
                let plan = WorkoutSetPlan(weight: 0, reps: lower, actualDefaultPolicy: .blank,
                    prescription: WorkoutSetPrescription(label: "有效活动秒数", repsLower: lower, repsUpper: upper,
                        restLowerSeconds: 0, restUpperSeconds: 0, effortCue: cardio.guidance))
                let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0,
                    targetSets: 1, minReps: lower, maxReps: upper, targetWeight: 0, restSeconds: 0, plannedSets: [plan])
                context.insert(item)
                let elapsed = cardio.elapsedSeconds.map { "；含休息\($0)秒" } ?? ""
                let frozen = ScheduledWorkoutExerciseSnapshot(id: item.id, exerciseID: exercise.id,
                    exerciseName: exercise.name, muscleGroup: exercise.muscleGroup, equipment: exercise.equipment,
                    exerciseNotes: cardio.timing + "；" + cardio.intervals + elapsed + "\n" + cardio.guidance,
                    referenceURL: exercise.referenceURL, volumeUnit: .second, order: 0, targetSets: 1,
                    minReps: lower, maxReps: upper, targetWeight: 0, restSeconds: 0,
                    plannedSets: [plan], planPattern: .fixed, patternSource: .exerciseOverride)
                let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name,
                    plannedDate: plannedDate, isManuallyScheduled: true, planSnapshot: [frozen])
                schedule.plannedDate = plannedDate
                schedule.plannedLocalDay = localDay
                schedule.plannedTimeZoneIdentifier = packet.timeZoneIdentifier
                context.insert(schedule)
                let link = ProgramWorkoutLink(programID: packet.programID, scheduledWorkoutID: schedule.id,
                    templateCode: cardio.code, originalDate: date(for: cardio.weekday, start: start))
                link.trainingProgramRevisionID = revision.id
                context.insert(link)
            }
            guard let staged = try readback(code: snapshot.code, in: context, allowsUnsealedStaging: true) else {
                throw ConfirmedTrainingPlanError.conflict("无法完整回读待保存周")
            }
            snapshot.confirmedImport?.scheduleIntegritySHA256 = try digest(staged.schedules)
            revision.snapshotJSON = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
            try commit(context)
        } catch {
            context.rollback()
            throw error
        }
        guard let stored = try readback(code: snapshot.code, in: context) else {
            throw ConfirmedTrainingPlanError.conflict("保存后回读缺失，请保留本次回执，不重复写入")
        }
        return ConfirmedTrainingPlanApplyResult(newScheduleCount: fresh.newScheduleCount, readback: stored,
            newExerciseCount: fresh.newExerciseCount)
    }

    static func readback(code: String, in context: ModelContext) throws -> ConfirmedTrainingPlanReadback? {
        try readback(code: code, in: context, allowsUnsealedStaging: false)
    }

    private static func readback(code: String, in context: ModelContext,
                                 allowsUnsealedStaging: Bool) throws -> ConfirmedTrainingPlanReadback? {
        let matches = try context.fetch(FetchDescriptor<TrainingProgramRevision>()).filter { $0.snapshot?.code == code }
        guard matches.count <= 1 else { throw ConfirmedTrainingPlanError.conflict("同版本存在多个编排") }
        guard let revision = matches.first, let snapshot = revision.snapshot, let programID = revision.programID else { return nil }
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.trainingProgramRevisionID == revision.id }
        let allSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        var schedules: [ConfirmedTrainingScheduleReadback] = []
        for link in links.sorted(by: { $0.templateCode < $1.templateCode }) {
            guard let row = allSchedules.first(where: { $0.id == link.scheduledWorkoutID }),
                  let template = templates.first(where: { $0.id == row.templateID }) else {
                throw ConfirmedTrainingPlanError.conflict("关联日程或菜单缺失")
            }
            let frozen = row.planSnapshot
            let templateItems = items.filter { $0.templateID == row.templateID }.sorted { $0.order < $1.order }
            guard !frozen.isEmpty, template.name == row.templateName, frozen.count == templateItems.count,
                  zip(frozen, templateItems).allSatisfy({ value in
                      let (plan, item) = value
                      return plan.exerciseID == item.exerciseID && plan.order == item.order && plan.targetSets == item.targetSets
                          && plan.minReps == item.minReps && plan.maxReps == item.maxReps && plan.targetWeight == item.targetWeight
                          && plan.restSeconds == item.restSeconds && plan.plannedSets == item.plannedSets
                  }) else { throw ConfirmedTrainingPlanError.conflict("日程冻结计划与菜单不一致") }
            schedules.append(ConfirmedTrainingScheduleReadback(id: row.id, code: link.templateCode,
                templateID: row.templateID, title: row.templateName, localDay: TrainingScheduleDate.localDay(row),
                timeZoneIdentifier: row.plannedTimeZoneIdentifier ?? "unknown", plannedDate: row.plannedDate, exercises: frozen))
        }
        guard let source = snapshot.confirmedImport else {
            throw ConfirmedTrainingPlanError.conflict("同版本已有非完整确认导入的编排")
        }
        var confirmedSnapshot = snapshot
        confirmedSnapshot.confirmedImport = nil
        let original = ConfirmedTrainingPlanPacket(version: 1, programID: programID,
            startLocalDay: source.startLocalDay, endLocalDay: source.endLocalDay,
            timeZoneIdentifier: source.timeZoneIdentifier, confirmedAt: source.confirmedAt,
            confirmationReference: source.confirmationReference, sourceMarkdown: source.sourceMarkdown,
            sourceSHA256: source.sourceSHA256, snapshot: confirmedSnapshot,
            catalogAdditions: source.catalogAdditions, catalogConfirmationReference: source.catalogConfirmationReference)
        _ = try validate(original)
        guard try digest(original) == source.packetSHA256,
              source.scheduleIntegritySHA256 != nil || allowsUnsealedStaging else {
            throw ConfirmedTrainingPlanError.conflict("确认内容或完整性来源发生变化")
        }
        do {
            guard schedules.count == snapshot.strengthWorkouts.count + snapshot.cardioWorkouts.count,
                  Set(links.map(\.templateCode)) == Set(snapshot.strengthWorkouts.map(\.code) + snapshot.cardioWorkouts.map(\.code)),
                  links.allSatisfy({ $0.programID == programID }),
                  source.scheduleIntegritySHA256.map({ $0 == (try? digest(originalSchedules(schedules,
                    adjustmentsJSON: source.scheduleAdjustmentsJSON))) }) ?? allowsUnsealedStaging else {
                throw ConfirmedTrainingPlanError.conflict("已导入周的日期、内容或关联发生变化")
            }
        }
        return ConfirmedTrainingPlanReadback(revisionID: revision.id, programID: programID, snapshot: snapshot,
            scheduleIDs: schedules.map(\.id), schedules: schedules)
    }

    /// Rewind only recorded owner actions, then check the original import seal.
    /// A date/content change without a matching action still fails closed.
    static func originalSchedules(_ current: [ConfirmedTrainingScheduleReadback],
                                  adjustmentsJSON: String?) throws -> [ConfirmedTrainingScheduleReadback] {
        guard let adjustmentsJSON else { return current }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let actions = try decoder.decode([ConfirmedScheduleAdjustment].self, from: Data(adjustmentsJSON.utf8))
        guard Set(actions.map(\.id)).count == actions.count else {
            throw ConfirmedTrainingPlanError.conflict("计划调整记录重复")
        }
        var original = current
        for action in actions.reversed() {
            guard action.confirmedAt <= .now,
                  let index = original.firstIndex(where: { $0.id == action.after.id }),
                  original[index] == action.after else {
                throw ConfirmedTrainingPlanError.conflict("计划调整链与当前日程不一致")
            }
            try validateAdjustment(kind: action.kind, before: action.before, after: action.after)
            original[index] = action.before
        }
        return original
    }

    static func addingAdjustment(kind: String, before: ConfirmedTrainingScheduleReadback,
                                 after: ConfirmedTrainingScheduleReadback, to json: String?) throws -> String? {
        guard before != after else { return json }
        try validateAdjustment(kind: kind, before: before, after: after)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var actions = try json.map { try decoder.decode([ConfirmedScheduleAdjustment].self, from: Data($0.utf8)) } ?? []
        actions.append(ConfirmedScheduleAdjustment(id: UUID(), confirmedAt: .now, kind: kind, before: before, after: after))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(actions), as: UTF8.self)
    }

    private static func validateAdjustment(kind: String, before: ConfirmedTrainingScheduleReadback,
                                           after: ConfirmedTrainingScheduleReadback) throws {
        guard before.id == after.id, before.code == after.code else {
            throw ConfirmedTrainingPlanError.conflict("调整不能替换日程身份或编排关联")
        }
        var permitted = before
        switch kind {
        case "reschedule":
            guard let zone = TimeZone(identifier: after.timeZoneIdentifier),
                  MealLocalDay.date(after.localDay, timeZone: zone) == after.plannedDate else {
                throw ConfirmedTrainingPlanError.conflict("改期日期与时区不一致")
            }
            permitted.localDay = after.localDay
            permitted.timeZoneIdentifier = after.timeZoneIdentifier
            permitted.plannedDate = after.plannedDate
        case "edit":
            permitted.templateID = after.templateID
            permitted.exercises = after.exercises
        default:
            throw ConfirmedTrainingPlanError.conflict("未知计划调整类型")
        }
        guard permitted == after else { throw ConfirmedTrainingPlanError.conflict("调整包含未允许的字段变化") }
    }

    static func scheduleRecord(_ schedule: ScheduledWorkout, code: String) -> ConfirmedTrainingScheduleReadback {
        ConfirmedTrainingScheduleReadback(id: schedule.id, code: code, templateID: schedule.templateID,
            title: schedule.templateName, localDay: schedule.plannedLocalDay ?? "",
            timeZoneIdentifier: schedule.plannedTimeZoneIdentifier ?? "unknown", plannedDate: schedule.plannedDate,
            exercises: schedule.planSnapshot)
    }

    static func captureScheduleAdjustment(_ schedule: ScheduledWorkout,
                                          in context: ModelContext) throws -> ConfirmedScheduleAdjustmentCapture {
        let daily: ConfirmedTrainingScheduleReadback?
        if schedule.confirmedDailyImportJSON != nil {
            daily = try ConfirmedDailyTrainingPlanService.readback(id: schedule.id, in: context)?.schedule
        } else { daily = nil }
        var weekly: [(revision: TrainingProgramRevision, record: ConfirmedTrainingScheduleReadback)] = []
        if FatLossBackupService.isRegistered(ProgramWorkoutLink.self, in: context),
           FatLossBackupService.isRegistered(TrainingProgramRevision.self, in: context) {
            let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.scheduledWorkoutID == schedule.id }
            let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
            for id in Set(links.compactMap(\.trainingProgramRevisionID)) {
                guard let revision = revisions.first(where: { $0.id == id }),
                      let snapshot = revision.snapshot else {
                    throw ConfirmedTrainingPlanError.conflict("编排关联或来源快照缺失")
                }
                guard snapshot.confirmedImport != nil else { continue }
                guard let readback = try readback(code: snapshot.code, in: context),
                      let record = readback.schedules.first(where: { $0.id == schedule.id }) else {
                    throw ConfirmedTrainingPlanError.conflict("已确认编排关联缺失")
                }
                weekly.append((revision, record))
            }
        }
        return ConfirmedScheduleAdjustmentCapture(daily: daily,
            rope: try ConfirmedDailyTrainingPlanService.verifiedRopeSchedule(schedule, in: context), weekly: weekly)
    }

    static func appendScheduleAdjustment(_ schedule: ScheduledWorkout, capture: ConfirmedScheduleAdjustmentCapture,
                                         kind: String, in context: ModelContext? = nil) throws {
        if let before = capture.rope {
            guard let context else { throw ConfirmedTrainingPlanError.conflict("跳绳调整缺少事务上下文") }
            try ConfirmedDailyTrainingPlanService.appendRopeScheduleAdjustment(schedule, before: before, kind: kind, in: context)
        }
        if let before = capture.daily {
            try ConfirmedDailyTrainingPlanService.appendScheduleAdjustment(schedule, before: before, kind: kind)
        }
        for entry in capture.weekly {
            guard var snapshot = entry.revision.snapshot, var source = snapshot.confirmedImport else {
                throw ConfirmedTrainingPlanError.conflict("已确认编排来源缺失")
            }
            source.scheduleAdjustmentsJSON = try addingAdjustment(kind: kind, before: entry.record,
                after: scheduleRecord(schedule, code: entry.record.code), to: source.scheduleAdjustmentsJSON)
            snapshot.confirmedImport = source
            entry.revision.snapshotJSON = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        }
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return digest(try encoder.encode(value))
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validate(_ packet: ConfirmedTrainingPlanPacket) throws -> Date {
        guard packet.version == 1, let zone = TimeZone(identifier: packet.timeZoneIdentifier),
              let start = MealLocalDay.date(packet.startLocalDay, timeZone: zone),
              let end = MealLocalDay.date(packet.endLocalDay, timeZone: zone),
              !packet.confirmationReference.isEmpty, packet.confirmedAt <= .now,
              packet.sourceMarkdown.utf8.count <= 1_048_576, !packet.sourceMarkdown.isEmpty,
              packet.sourceSHA256 == digest(Data(packet.sourceMarkdown.utf8)),
              packet.snapshot.isValid, packet.snapshot.confirmedImport == nil else {
            throw ConfirmedTrainingPlanError.invalidPacket("版本、确认、原文指纹或编排无效")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard calendar.component(.weekday, from: start) == 2,
              calendar.dateComponents([.day], from: start, to: end).day == 6 else {
            throw ConfirmedTrainingPlanError.invalidPacket("只接受周一至周日的一周，不自动续排")
        }
        for draft in packet.snapshot.strengthWorkouts.flatMap(\.exercises) {
            guard let plans = draft.plannedSets, plans.count == draft.sets,
                  plans.allSatisfy({ $0.prescription?.isValid == true && $0.actualDefaultPolicy == .blank &&
                      $0.weight == 0 && $0.reps == $0.prescription?.repsLower }) else {
                throw ConfirmedTrainingPlanError.invalidPacket("\(draft.name)需完整逐组目标和明确空重量")
            }
        }
        if let additions = packet.catalogAdditions {
            let drafts = packet.snapshot.strengthWorkouts.flatMap(\.exercises)
            guard !additions.isEmpty, additions.count <= 24,
                  let reference = packet.catalogConfirmationReference,
                  !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reference.utf8.count <= 4096,
                  Set(additions.map(\.id)).count == additions.count,
                  Set(additions.map { catalogNameKey($0.name) }).count == additions.count else {
                throw ConfirmedTrainingPlanError.invalidPacket("新增动作需独立的器械/单位确认和唯一身份")
            }
            for addition in additions {
                let referenced = drafts.filter { $0.catalogExerciseID == addition.id }
                guard !referenced.isEmpty, !catalogNameKey(addition.name).isEmpty, addition.name.utf8.count <= 512,
                      !addition.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !catalogNameKey(addition.equipment).isEmpty, addition.equipment.utf8.count <= 512,
                      !["器械", "machine", "unknown", "未知"].contains(catalogNameKey(addition.equipment)),
                      addition.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue,
                      (0...600).contains(addition.defaultRestSeconds),
                      referenced.allSatisfy({ ($0.catalogName ?? $0.name) == addition.name &&
                          $0.muscleGroup == addition.muscleGroup && $0.equipment == addition.equipment &&
                          $0.volumeUnitRaw == addition.volumeUnitRaw }) else {
                    throw ConfirmedTrainingPlanError.invalidPacket("新增动作与计划的精确名称、肌群、器械或 kg 不一致")
                }
            }
        } else if packet.catalogConfirmationReference != nil {
            throw ConfirmedTrainingPlanError.invalidPacket("动作确认缺少明确新增内容")
        }
        guard Set(packet.snapshot.strengthWorkouts.map(\.code) + packet.snapshot.cardioWorkouts.map(\.code)).count ==
                packet.snapshot.strengthWorkouts.count + packet.snapshot.cardioWorkouts.count,
              packet.snapshot.cardioWorkouts.allSatisfy({ $0.activeSeconds != nil && $0.catalogExerciseID != nil }) else {
            throw ConfirmedTrainingPlanError.invalidPacket("有氧需独立代码、准确计时目标和动作身份")
        }
        guard let civilStart = MealLocalDay.date(packet.startLocalDay, timeZone: FatLossCalendar.calendar.timeZone) else {
            throw ConfirmedTrainingPlanError.invalidPacket("日期无效")
        }
        return civilStart
    }

    private static func date(for weekday: Int, start: Date) -> Date {
        FatLossCalendar.adding((weekday + 5) % 7, to: start)
    }

    private static func catalogNameKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

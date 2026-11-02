import Foundation
import SwiftData

struct ConfirmedDailyPlanExercise: Codable, Equatable {
    var catalogExerciseID: UUID
    var catalogName: String
    var equipment: String
    var volumeUnit: ExerciseVolumeUnit
    var displayName: String
    /// Preserves plates per side, one dumbbell, or an unconfirmed machine display convention.
    var loadGuidance: String
    var notes: String
    var plannedSets: [WorkoutSetPlan]
    /// Optional and omitted when nil, preserving the canonical digest of existing packets.
    var planPattern: SetPlanPattern? = nil
}

struct ConfirmedDailyTrainingPlanPacket: Codable, Equatable {
    var version: Int
    /// Stable source identity, also used as the new schedule identity. Never regenerated on retry.
    var id: UUID
    var localDay: String
    var timeZoneIdentifier: String
    var title: String
    var preferenceRevisionCode: String
    var confirmedAt: Date
    var confirmationReference: String
    var sourceMarkdown: String
    var sourceSHA256: String
    var guidance: String
    var exercises: [ConfirmedDailyPlanExercise]
    /// Opt-in owner confirmation. Omitted for legacy packets so their canonical digest stays unchanged.
    var actualPrefillConfirmationReference: String? = nil
    var replacement: ConfirmedDailyTrainingPlanReplacement? = nil
}

struct ConfirmedDailyTrainingPlanReplacement: Codable, Equatable {
    var scheduleID: UUID
    var packetSHA256: String
}

struct ConfirmedDailyTrainingPlanPreview: Codable, Equatable {
    var packet: ConfirmedDailyTrainingPlanPacket
    var packetSHA256: String
    var destinationFingerprint: String
    var conflicts: [String]
    var newScheduleCount: Int
    var discardedDraftReview: ConfirmedDiscardedDraftReview? = nil
    var discardedDraftConfirmationReference: String? = nil
}

struct ConfirmedDiscardedDraftReview: Codable, Equatable {
    var scheduleID: UUID
    var sessionIDs: [UUID]
    var snapshotCount: Int
    var setCount: Int
    var contentSHA256: String
}

struct ConfirmedDiscardedDraftApproval: Codable, Equatable {
    var review: ConfirmedDiscardedDraftReview
    var confirmationReference: String
}

struct ConfirmedDailyTrainingPlanReadback: Codable, Equatable {
    var packet: ConfirmedDailyTrainingPlanPacket
    var packetSHA256: String
    var schedule: ConfirmedTrainingScheduleReadback
    var discardedDraftApproval: ConfirmedDiscardedDraftApproval? = nil
}

struct ConfirmedDailyTrainingPlanApplyResult: Codable, Equatable {
    var newScheduleCount: Int
    var readback: ConfirmedDailyTrainingPlanReadback
}

enum CoachWeekRequestAudit: Equatable {
    case committed
    case safelyAbsent
    case unknown
}

private struct ConfirmedDailyTrainingPlanSource: Codable {
    var packet: ConfirmedDailyTrainingPlanPacket
    var packetSHA256: String
    var scheduleIntegritySHA256: String
    var scheduleAdjustmentsJSON: String? = nil
    var discardedDraftApproval: ConfirmedDiscardedDraftApproval? = nil
}

/// A single civil day. Revisions append a plan and retire only the explicitly bound, unstarted predecessor.
@MainActor
enum ConfirmedDailyTrainingPlanService {
    static func preview(_ packet: ConfirmedDailyTrainingPlanPacket, in context: ModelContext) throws -> ConfirmedDailyTrainingPlanPreview {
        try previewInternal(packet, in: context, excludingStagedSiblingIDs: [])
    }

    private static func previewInternal(_ packet: ConfirmedDailyTrainingPlanPacket, in context: ModelContext,
                                        excludingStagedSiblingIDs: Set<UUID>) throws -> ConfirmedDailyTrainingPlanPreview {
        let date = try validate(packet)
        let digest = try ConfirmedTrainingPlanService.digest(packet)
        let preference = try TrainingPreferenceService.current(in: context, on: date)
        var conflicts: [String] = []
        if preference?.revisionCode != packet.preferenceRevisionCode {
            conflicts.append("目标日生效偏好与确认版本不同")
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        for draft in packet.exercises {
            guard let row = catalog.first(where: { $0.id == draft.catalogExerciseID }), !row.isArchived,
                  row.name == draft.catalogName, row.equipment == draft.equipment, row.volumeUnit == draft.volumeUnit else {
                conflicts.append("动作身份、器械或单位已变化：\(draft.catalogName)")
                continue
            }
        }
        let existing = try readback(id: packet.id, in: context)
        if let existing, existing.packetSHA256 != digest {
            conflicts.append("同一来源ID已有不同内容，不能覆盖")
        }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>()).filter {
            TrainingScheduleDate.localDay($0) == packet.localDay && !excludingStagedSiblingIDs.contains($0.id)
        }
        let allSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let ancestors = try replacementAncestors(packet, alreadyApplied: existing != nil,
            schedules: schedules, sessions: allSessions, existingApproval: existing?.discardedDraftApproval, in: context)
        conflicts += ancestors.conflicts
        if let existing, existing.packetSHA256 == digest {
            // A repeat of an already verified import never creates the old date again,
            // even if the owner later moved/edited it or added another plan on that date.
            // The stored seal, complete adjustment chain and replacement ancestry still pass above.
            return ConfirmedDailyTrainingPlanPreview(packet: packet, packetSHA256: digest,
                destinationFingerprint: try ConfirmedTrainingPlanService.digest(existing), conflicts: ancestors.conflicts,
                newScheduleCount: 0, discardedDraftReview: ancestors.review,
                discardedDraftConfirmationReference: existing.discardedDraftApproval?.confirmationReference)
        }
        if schedules.contains(where: { $0.id != existing?.schedule.id && !ancestors.ids.contains($0.id) }) {
            conflicts.append("目标日已有其他日程，不自动覆盖或取消")
        }
        let sessions = allSessions.filter {
            TrainingHistoryDate.localDay($0) == packet.localDay && $0.status != .discarded
        }
        if sessions.contains(where: { $0.scheduledWorkoutID != existing?.schedule.id || existing == nil }) {
            conflicts.append("目标日已有其他实际训练，不自动覆盖")
        }
        let referencedIDs = Set(packet.exercises.map(\.catalogExerciseID))
        var destination: [[String]] = []
        if let preference {
            destination.append(["preference", preference.id.uuidString, preference.snapshotJSON,
                                String(preference.effectiveAt.timeIntervalSinceReferenceDate)])
        }
        destination += catalog.filter { referencedIDs.contains($0.id) }.map {
            ["exercise", $0.id.uuidString, $0.name, $0.equipment, $0.volumeUnit.rawValue,
             $0.muscleGroup, $0.referenceURL, String($0.isArchived)]
        }.sorted { $0[1] < $1[1] }
        destination += schedules.map {
            ["schedule", $0.id.uuidString, $0.templateID.uuidString, $0.templateName, $0.statusRaw,
             String($0.plannedDate.timeIntervalSinceReferenceDate), $0.plannedLocalDay ?? "",
             $0.plannedTimeZoneIdentifier ?? "", $0.planSnapshotJSON ?? "", $0.confirmedDailyImportJSON ?? "",
             $0.skipReason, $0.reminderDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
             String($0.updatedAt.timeIntervalSinceReferenceDate)]
        }.sorted { $0[1] < $1[1] }
        destination += sessions.map {
            ["session", $0.id.uuidString, $0.statusRaw, $0.scheduledWorkoutID?.uuidString ?? "",
             String($0.plannedDate.timeIntervalSinceReferenceDate)]
        }.sorted { $0[1] < $1[1] }
        return ConfirmedDailyTrainingPlanPreview(packet: packet, packetSHA256: digest,
            destinationFingerprint: try ConfirmedTrainingPlanService.digest(destination), conflicts: conflicts,
            newScheduleCount: existing == nil ? 1 : 0, discardedDraftReview: ancestors.review)
    }

    static func apply(expectedPreview: ConfirmedDailyTrainingPlanPreview, in context: ModelContext,
                      commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ConfirmedDailyTrainingPlanApplyResult {
        try applyInternal(expectedPreview: expectedPreview, in: context, allowStagedChanges: false, commit: commit)
    }

    private static func applyInternal(expectedPreview: ConfirmedDailyTrainingPlanPreview, in context: ModelContext,
                                      allowStagedChanges: Bool, excludingStagedSiblingIDs: Set<UUID> = [],
                                      commit: (ModelContext) throws -> Void) throws -> ConfirmedDailyTrainingPlanApplyResult {
        guard allowStagedChanges || !context.hasChanges else { throw ConfirmedTrainingPlanError.unsavedChanges }
        guard try ConfirmedTrainingPlanService.digest(expectedPreview.packet) == expectedPreview.packetSHA256 else {
            throw ConfirmedTrainingPlanError.changedPreview
        }
        let fresh = try previewInternal(expectedPreview.packet, in: context, excludingStagedSiblingIDs: excludingStagedSiblingIDs)
        if let existing = try readback(id: fresh.packet.id, in: context) {
            guard fresh.conflicts.isEmpty,
                  expectedPreview.discardedDraftReview == existing.discardedDraftApproval?.review,
                  expectedPreview.discardedDraftConfirmationReference == existing.discardedDraftApproval?.confirmationReference else {
                throw ConfirmedTrainingPlanError.changedPreview
            }
            return ConfirmedDailyTrainingPlanApplyResult(newScheduleCount: 0, readback: existing)
        }
        var comparable = expectedPreview
        comparable.discardedDraftConfirmationReference = nil
        guard fresh == comparable else { throw ConfirmedTrainingPlanError.changedPreview }
        var approval: ConfirmedDiscardedDraftApproval?
        if let review = fresh.discardedDraftReview,
           let reference = expectedPreview.discardedDraftConfirmationReference,
           !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reference.count <= 2_000,
           fresh.conflicts == [discardedDraftConflict] {
            approval = ConfirmedDiscardedDraftApproval(review: review, confirmationReference: reference)
        } else {
            guard fresh.conflicts.isEmpty, expectedPreview.discardedDraftConfirmationReference == nil else {
                throw ConfirmedTrainingPlanError.conflict(fresh.conflicts.joined(separator: "；"))
            }
        }
        let packet = fresh.packet
        let date = try validate(packet)
        guard let preference = try TrainingPreferenceService.current(in: context, on: date) else {
            throw ConfirmedTrainingPlanError.conflict("生效偏好缺失")
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: packet.timeZoneIdentifier)!
        let predecessor = try context.fetch(FetchDescriptor<ScheduledWorkout>()).first {
            $0.id == packet.replacement?.scheduleID
        }
        let predecessorState = predecessor.map { ($0.statusRaw, $0.skipReason, $0.reminderDate, $0.updatedAt) }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            if packet.replacement != nil {
                guard let predecessor, predecessor.status == .planned else { throw ConfirmedTrainingPlanError.changedPreview }
                predecessor.status = .skipped
                predecessor.skipReason = replacementReason(successorID: packet.id)
                predecessor.reminderDate = nil
                predecessor.updatedAt = .now
            }
            let template = WorkoutTemplate(name: packet.title, weekday: calendar.component(.weekday, from: date),
                isActive: false, isOneOff: true, plannedForDate: date,
                focusMuscleGroups: Array(Set(catalog.filter { row in packet.exercises.contains { $0.catalogExerciseID == row.id } }.map(\.muscleGroup))).sorted(),
                trainingPreferenceSnapshotJSON: preference.snapshotJSON)
            template.plannedForDate = date
            context.insert(template)
            var frozen: [ScheduledWorkoutExerciseSnapshot] = []
            for (order, draft) in packet.exercises.enumerated() {
                guard let exercise = catalog.first(where: { $0.id == draft.catalogExerciseID }),
                      let first = draft.plannedSets.first else { throw ConfirmedTrainingPlanError.changedPreview }
                let lower = draft.plannedSets.compactMap { $0.prescription?.repsLower }.min()!
                let upper = draft.plannedSets.compactMap { $0.prescription?.repsUpper }.max()!
                let rest = draft.plannedSets.compactMap { $0.prescription?.restUpperSeconds }.max()!
                let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: order,
                    targetSets: draft.plannedSets.count, minReps: lower, maxReps: upper,
                    targetWeight: first.weight, restSeconds: rest, plannedSets: draft.plannedSets,
                    planPattern: draft.planPattern ?? .fixed, patternSource: .exerciseOverride)
                context.insert(item)
                frozen.append(ScheduledWorkoutExerciseSnapshot(id: item.id, exerciseID: exercise.id,
                    exerciseName: draft.displayName, muscleGroup: exercise.muscleGroup, equipment: exercise.equipment,
                    exerciseNotes: draft.loadGuidance + "\n" + draft.notes + "\n" + packet.guidance,
                    referenceURL: exercise.referenceURL, volumeUnit: draft.volumeUnit, order: order,
                    targetSets: draft.plannedSets.count, minReps: lower, maxReps: upper,
                    targetWeight: first.weight, restSeconds: rest, plannedSets: draft.plannedSets,
                    planPattern: draft.planPattern ?? .fixed, patternSource: .exerciseOverride))
            }
            let schedule = ScheduledWorkout(id: packet.id, templateID: template.id, templateName: packet.title,
                plannedDate: date, isManuallyScheduled: true, planSnapshot: frozen)
            schedule.plannedDate = date
            schedule.plannedLocalDay = packet.localDay
            schedule.plannedTimeZoneIdentifier = packet.timeZoneIdentifier
            let record = scheduleRecord(schedule, code: packet.id.uuidString)
            let source = ConfirmedDailyTrainingPlanSource(packet: packet, packetSHA256: fresh.packetSHA256,
                scheduleIntegritySHA256: try ConfirmedTrainingPlanService.digest(record), discardedDraftApproval: approval)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            schedule.confirmedDailyImportJSON = String(decoding: try encoder.encode(source), as: UTF8.self)
            context.insert(schedule)
            guard let staged = try readback(id: packet.id, in: context), staged.schedule == record else {
                throw ConfirmedTrainingPlanError.conflict("保存前完整回读失败")
            }
            try commit(context)
        } catch {
            // SwiftData rollback alone can leave a retained model's property cache mutated.
            // Restore the four owned fields before dropping every staged insertion.
            if let predecessor, let state = predecessorState {
                predecessor.statusRaw = state.0
                predecessor.skipReason = state.1
                predecessor.reminderDate = state.2
                predecessor.updatedAt = state.3
            }
            context.rollback()
            throw error
        }
        guard let stored = try readback(id: packet.id, in: context) else {
            throw ConfirmedTrainingPlanError.conflict("保存后回读缺失，请保留原请求并检查，不重新造ID")
        }
        return ConfirmedDailyTrainingPlanApplyResult(newScheduleCount: 1, readback: stored)
    }

    /// All destinations are preflighted before staging. Replacement is deliberately excluded:
    /// this operation never retires an existing plan or its retained model state.
    static func applyWeek(expectedPreviews: [ConfirmedDailyTrainingPlanPreview], in context: ModelContext,
                          commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> [ConfirmedDailyTrainingPlanReadback] {
        try applyWeekInternal(expectedPreviews: expectedPreviews, in: context, allowSameDayMembers: false, commit: commit)
    }

    private static func applyWeekInternal(expectedPreviews: [ConfirmedDailyTrainingPlanPreview], in context: ModelContext,
                          allowSameDayMembers: Bool, commit: (ModelContext) throws -> Void) throws -> [ConfirmedDailyTrainingPlanReadback] {
        guard !context.hasChanges else { throw ConfirmedTrainingPlanError.unsavedChanges }
        guard !expectedPreviews.isEmpty,
              Set(expectedPreviews.map { $0.packet.id }).count == expectedPreviews.count,
              (allowSameDayMembers || Set(expectedPreviews.map { $0.packet.localDay }).count == expectedPreviews.count),
              expectedPreviews.allSatisfy({ $0.packet.replacement == nil }) else {
            throw ConfirmedTrainingPlanError.invalidPacket("整周请求日期或来源重复，或包含替换日程")
        }
        let verification = ModelContext(context.container)
        let existing = try expectedPreviews.map { try readback(id: $0.packet.id, in: verification) }
        if existing.allSatisfy({ $0 != nil }) {
            return try zip(expectedPreviews, existing).map { preview, stored in
                guard let stored, stored.packetSHA256 == preview.packetSHA256,
                      try ConfirmedTrainingPlanService.digest(preview.packet) == preview.packetSHA256 else {
                    throw ConfirmedTrainingPlanError.changedPreview
                }
                try verifyTemplate(stored, in: verification)
                return stored
            }
        }
        guard existing.allSatisfy({ $0 == nil }) else {
            throw ConfirmedTrainingPlanError.conflict("整周请求只有部分日程存在，请停止并核对原请求")
        }
        for expected in expectedPreviews {
            guard try ConfirmedTrainingPlanService.digest(expected.packet) == expected.packetSHA256,
                  try preview(expected.packet, in: context) == expected, expected.conflicts.isEmpty else {
                throw ConfirmedTrainingPlanError.changedPreview
            }
        }
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            var stagedIDs = Set<UUID>()
            for expected in expectedPreviews {
                _ = try applyInternal(expectedPreview: expected, in: context, allowStagedChanges: true,
                                      excludingStagedSiblingIDs: allowSameDayMembers ? stagedIDs : [], commit: { _ in })
                stagedIDs.insert(expected.packet.id)
            }
            for expected in expectedPreviews {
                guard let staged = try readback(id: expected.packet.id, in: context),
                      staged.packetSHA256 == expected.packetSHA256 else {
                    throw ConfirmedTrainingPlanError.conflict("整周暂存来源不完整")
                }
                try verifyTemplate(staged, in: context)
            }
            try commit(context)
            guard !context.hasChanges else {
                throw ConfirmedTrainingPlanError.conflict("提交未完成，暂存已回滚；请保留原请求")
            }
        } catch {
            context.rollback()
            throw error
        }
        let storedContext = ModelContext(context.container)
        return try expectedPreviews.map { expected in
            guard let stored = try readback(id: expected.packet.id, in: storedContext),
                  stored.packetSHA256 == expected.packetSHA256 else {
                throw ConfirmedTrainingPlanError.conflict("整周保存后回读不完整，请保留原请求并核对")
            }
            try verifyTemplate(stored, in: storedContext)
            return stored
        }
    }

    /// A local-store observation, not a distributed lock or an assertion about pending CloudKit delivery.
    static func auditCoachWeekRequest(_ request: CoachWeekConfirmation, in context: ModelContext) -> CoachWeekRequestAudit {
        guard !context.hasChanges else { return .unknown }
        do {
            try CoachWeekService.validateConfirmation(request, rowID: request.id, rootID: request.draft.rootID)
            let independent = ModelContext(context.container)
            let rows = try independent.fetch(FetchDescriptor<TrainingCoachRecord>())
            let identityRows = rows.filter { $0.id == request.id }
            if !identityRows.isEmpty {
                guard identityRows.count == 1, identityRows[0].kind == "week_confirmation",
                      try TrainingCoachService.decode(CoachWeekConfirmation.self, identityRows[0]) == request else { return .unknown }
                try verifyCoachWeek(request, in: independent)
                return .committed
            }
            let ids = Set(request.members.map { $0.packet.id }).union(request.ropes.map(\.id))
            guard try independent.fetch(FetchDescriptor<ScheduledWorkout>()).allSatisfy({ !ids.contains($0.id) }) else { return .unknown }
            for row in rows {
                switch row.kind {
                case "week_confirmation":
                    let other = try TrainingCoachService.decode(CoachWeekConfirmation.self, row)
                    let otherIDs = Set(other.members.map { $0.packet.id }).union(other.ropes.map(\.id))
                    if other.id == request.id || !ids.isDisjoint(with: otherIDs) { return .unknown }
                case "week_rope_origin":
                    let origin = try TrainingCoachService.decode(RopeScheduleOrigin.self, row)
                    if origin.confirmationID == request.id || ids.contains(origin.schedule.id) { return .unknown }
                case "week_rope_adjustment":
                    let adjustment = try TrainingCoachService.decode(RopeAdjustment.self, row)
                    if adjustment.confirmationID == request.id || ids.contains(adjustment.scheduleID) { return .unknown }
                case "week_rope_schedule_adjustment":
                    if try ids.contains(TrainingCoachService.decode(RopeScheduleChange.self, row).scheduleID) { return .unknown }
                default: break
                }
            }
            return .safelyAbsent
        } catch { return .unknown }
    }

    /// Stages the request record and independent jump-rope schedules in the same save as the daily members.
    /// This remains an internal path until the complete seven-day and adjustment-chain checks are verified.
    static func applyCoachWeek(_ request: CoachWeekConfirmation, in context: ModelContext,
                               commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws {
        try CoachWeekService.validateConfirmation(request, rowID: request.id, rootID: request.draft.rootID)
        guard !context.hasChanges else { throw ConfirmedTrainingPlanError.unsavedChanges }
        let existing = try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.id == request.id }
        if !existing.isEmpty {
            guard existing.count == 1, existing[0].kind == "week_confirmation",
                  try TrainingCoachService.decode(CoachWeekConfirmation.self, existing[0]) == request else {
                throw TrainingCoachError.invalid("原周请求身份已被占用，请停止重试并核对。")
            }
            do { try verifyCoachWeek(request, in: ModelContext(context.container)) }
            catch { throw TrainingCoachError.invalid("原周请求已提交但回读待核，请保留原请求并停止重试：\(error.localizedDescription)") }
            return
        }
        guard let zone = TimeZone(identifier: request.draft.input.timeZone),
              let start = TrainingLocalDate.date(request.draft.input.startDay, timeZone: zone) else {
            throw TrainingCoachError.invalid("周请求日期或时区无效；尚未写入。")
        }
        let fresh = try CoachWeekService.capture(start: start, exception: request.draft.input.exception, coreException: request.draft.input.coreException, retainedReviews: request.draft.input.retainedReviews, ruleMethod: request.draft.input.methodVersion, in: context)
        guard try CoachWeekService.fingerprint(fresh) == request.draft.sourceFingerprint else {
            throw TrainingCoachError.invalid("七日来源已改变，请重新生成并确认；尚未写入。")
        }
        let rows = try TrainingCoachService.records(sessionID: request.draft.rootID, in: context).filter { $0.kind == "week_draft" }
        guard let latest = rows.last, try TrainingCoachService.decode(CoachWeekDraft.self, latest) == request.draft else {
            throw TrainingCoachError.invalid("草案已出现新版本；尚未写入。")
        }
        let ids = Set(request.members.map { $0.packet.id }).union(request.ropes.map(\.id))
        let current = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard ids.isDisjoint(with: Set(current.map(\.id))) else {
            throw TrainingCoachError.invalid("周请求只有部分成员已存在，请停止重试并核对。")
        }
        for rope in request.ropes {
            guard rope.plan.isValid, request.draft.days.contains(where: { $0.localDay == rope.localDay && $0.cardio == rope.plan }),
                  !current.contains(where: { TrainingScheduleDate.localDay($0) == rope.localDay }) else {
                throw TrainingCoachError.invalid("跳绳目标或目标日已改变；尚未写入。")
            }
        }
        var committed = false
        let commitStaged: (ModelContext) throws -> Void = { staging in
            for rope in request.ropes {
                guard let date = MealLocalDay.date(rope.localDay, timeZone: zone) else {
                    throw TrainingCoachError.invalid("跳绳日期无效。")
                }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                let template = WorkoutTemplate(name: "跳绳", weekday: calendar.component(.weekday, from: date),
                                               isActive: false, isOneOff: true, plannedForDate: date)
                // The initializer normalizes with Calendar.current; preserve the confirmed civil-zone instant.
                template.plannedForDate = date
                let schedule = ScheduledWorkout(id: rope.id, templateID: template.id, templateName: "跳绳",
                                                plannedDate: date, isManuallyScheduled: true)
                schedule.plannedDate = date; schedule.plannedLocalDay = rope.localDay
                schedule.plannedTimeZoneIdentifier = zone.identifier; schedule.jumpRopePlan = rope.plan
                staging.insert(template); staging.insert(schedule)
                let origin = RopeScheduleOrigin(confirmationID: request.id, requestDigest: request.requestDigest,
                    schedule: ConfirmedTrainingPlanService.scheduleRecord(schedule, code: rope.id.uuidString))
                staging.insert(TrainingCoachRecord(sessionID: request.draft.rootID, kind: "week_rope_origin",
                    payloadJSON: try TrainingCoachService.encode(origin), sequence: Int64(request.ropes.firstIndex(where: { $0.id == rope.id }) ?? 0)))
            }
            let sequence = (try TrainingCoachService.records(sessionID: request.draft.rootID, in: staging).map(\.sequence).max() ?? 0) + 1
            staging.insert(TrainingCoachRecord(id: request.id, sessionID: request.draft.rootID,
                kind: "week_confirmation", payloadJSON: try TrainingCoachService.encode(request), sequence: sequence))
            // Independent reads detect observed drift; they are not a global lock across contexts or CloudKit.
            // A race after this check is reported as committed-but-unverified by the post-save readback below.
            let independent = ModelContext(context.container)
            let precommit = try CoachWeekService.capture(start: start, exception: request.draft.input.exception, coreException: request.draft.input.coreException, retainedReviews: request.draft.input.retainedReviews, ruleMethod: request.draft.input.methodVersion, in: independent)
            guard try CoachWeekService.fingerprint(precommit) == request.draft.sourceFingerprint else {
                throw TrainingCoachError.invalid("提交前七日来源已变化；尚未写入。")
            }
            try commit(staging)
            committed = !staging.hasChanges
        }
        do {
            if request.members.isEmpty {
                let autosave = context.autosaveEnabled
                context.autosaveEnabled = false
                defer { context.autosaveEnabled = autosave }
                do {
                    try commitStaged(context)
                    guard !context.hasChanges else { throw TrainingCoachError.invalid("提交未完成。") }
                } catch { context.rollback(); throw error }
            } else {
                _ = try applyWeekInternal(expectedPreviews: request.members, in: context,
                                          allowSameDayMembers: true, commit: commitStaged)
            }
        } catch {
            // A commit hook can save and then throw. Inspect the durable seal before describing the failure.
            let persisted = try? ModelContext(context.container).fetch(FetchDescriptor<TrainingCoachRecord>())
            if committed || persisted?.contains(where: { $0.id == request.id && $0.kind == "week_confirmation" }) == true {
                throw TrainingCoachError.invalid("周请求已提交但结果待核，请保留原请求并停止重试：\(error.localizedDescription)")
            }
            throw error
        }
        do {
            let verification = ModelContext(context.container)
            try verifyCoachWeek(request, in: verification)
            let after = try CoachWeekService.capture(start: start, exception: request.draft.input.exception, coreException: request.draft.input.coreException, retainedReviews: request.draft.input.retainedReviews, ruleMethod: request.draft.input.methodVersion, in: verification)
            let source = request.draft.input
            let normalized = CoachWeekInput(startDay: after.startDay, timeZone: after.timeZone, methodVersion: after.methodVersion,
                personalRuleVersion: after.personalRuleVersion, preferences: after.preferences, exception: after.exception,
                catalog: after.catalog, history: after.history, existing: after.existing.filter { !ids.contains($0.id) },
                recovery: after.recovery, unknowns: after.unknowns,
                sourceRuleVersions: after.sourceRuleVersions, supportedFromDay: after.supportedFromDay,
                recoverySignals: after.recoverySignals, bodyReports: after.bodyReports, retainedReviews: after.retainedReviews, coreException: after.coreException,
                capturedLocalDay: after.capturedLocalDay)
            guard normalized == source else { throw TrainingCoachError.invalid("提交期间来源发生变化。") }
        } catch { throw TrainingCoachError.invalid("周请求已提交但回读待核，请保留原请求并停止重试：\(error.localizedDescription)") }
    }

    private static func verifyCoachWeek(_ request: CoachWeekConfirmation, in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.id == request.id }
        guard rows.count == 1, rows[0].kind == "week_confirmation",
              try TrainingCoachService.decode(CoachWeekConfirmation.self, rows[0]) == request else {
            throw TrainingCoachError.invalid("周请求记录缺失或不一致。")
        }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        for preview in request.members {
            guard let stored = try readback(id: preview.packet.id, in: context), stored.packetSHA256 == preview.packetSHA256,
                  let template = templates.first(where: { $0.id == stored.schedule.templateID }),
                  template.name == stored.schedule.title, template.plannedForDate == (try validate(stored.packet)),
                  let expectedPreference = request.draft.input.preferences.first(where: { $0.localDay == preview.packet.localDay })?.snapshot,
                  let json = template.trainingPreferenceSnapshotJSON?.data(using: .utf8),
                  try JSONDecoder().decode(TrainingPreferenceSnapshot.self, from: json) == expectedPreference else {
                throw TrainingCoachError.invalid("日程来源、模板或偏好回读未对齐。")
            }
            let currentItems = items.filter { $0.templateID == template.id }
            guard currentItems.count == stored.schedule.exercises.count,
                  Set(currentItems.map(\.order)).count == currentItems.count else {
                throw TrainingCoachError.invalid("模板动作数量或顺序待核。")
            }
            for frozen in stored.schedule.exercises {
                guard let item = currentItems.first(where: { $0.order == frozen.order }), item.id == frozen.id,
                      item.exerciseID == frozen.exerciseID, item.plannedSets == frozen.plannedSets,
                      item.planPattern == frozen.planPattern, item.targetSets == frozen.targetSets,
                      item.minReps == frozen.minReps, item.maxReps == frozen.maxReps,
                      item.targetWeight == frozen.targetWeight, item.restSeconds == frozen.restSeconds else {
                    throw TrainingCoachError.invalid("模板与当前逐组日程不一致。")
                }
            }
            if let zone2 = request.draft.days.first(where: { $0.localDay == preview.packet.localDay })?.zone2,
               preview.packet.exercises.count == 1, preview.packet.exercises[0].catalogExerciseID == zone2.exerciseID {
                guard let schedule = schedules.first(where: { $0.id == preview.packet.id }), CardioWorkoutPresentation.plan(schedule) != nil else {
                    throw TrainingCoachError.invalid("Zone 2 记录入口回读待核。")
                }
            }
        }
        for rope in request.ropes {
            guard let schedule = schedules.first(where: { $0.id == rope.id }),
                  try verifiedRopePlan(rope, request: request, in: context) == schedule.jumpRopePlan,
                  try verifiedRopeSchedule(schedule, in: context) != nil,
                  TrainingDateMenuService.isJumpRope(schedule, links: [], revisions: [], exercises: []),
                  templates.contains(where: { $0.id == schedule.templateID && $0.name == schedule.templateName }) else {
                throw TrainingCoachError.invalid("跳绳目标或调整记录需核对。")
            }
        }
        if let zone = TimeZone(identifier: request.draft.input.timeZone),
           let start = TrainingLocalDate.date(request.draft.input.startDay, timeZone: zone) {
            let currentInput = try CoachWeekService.capture(start: start, exception: request.draft.input.exception, coreException: request.draft.input.coreException,
                retainedReviews: request.draft.input.retainedReviews, validateRetainedReviewBindings: false, ruleMethod: request.draft.input.methodVersion, in: context)
            func sameFrozenRaw(_ before: [CoachWeekFrozenExercise]?, _ after: [CoachWeekFrozenExercise]?) -> Bool {
                guard let before, let after else { return before == nil && after == nil }
                return before.count == after.count && zip(before, after).allSatisfy { old, new in
                    old.exerciseID == new.exerciseID && old.name == new.name && old.muscle == new.muscle
                        && old.equipment == new.equipment && old.plannedSets == new.plannedSets
                }
            }
            for actual in request.draft.input.existing where actual.source == "实际训练" {
                if actual.status == WorkoutSessionStatus.inProgress.rawValue {
                    try verifyActualProgress(actual, in: context)
                } else {
                    guard let observed = currentInput.existing.first(where: { $0.id == actual.id && $0.source == actual.source }),
                          let digest = actual.contentDigest, observed.contentDigest == digest,
                          observed.localDay == actual.localDay, observed.status == actual.status,
                          observed.title == actual.title, sameFrozenRaw(actual.frozenExercises, observed.frozenExercises) else {
                        throw TrainingCoachError.invalid("确认时保留的已完成实际训练记录已变化或缺失。")
                    }
                }
            }
        }
        for preserved in request.draft.input.existing where preserved.source != "实际训练" {
            guard let schedule = schedules.first(where: { $0.id == preserved.id }),
                  ScheduleStatus(rawValue: schedule.statusRaw) != nil,
                  (preserved.status != ScheduleStatus.completed.rawValue || schedule.status == .completed) else {
                throw TrainingCoachError.invalid("保留的既有日程缺失或状态非法。")
            }
            // Sealed daily imports validate their original prescription through the legal adjustment chain.
            if schedule.confirmedDailyImportJSON != nil {
                guard let stored = try readback(id: schedule.id, in: context),
                      let expected = preserved.confirmedPacketDigest, stored.packetSHA256 == expected else {
                    throw TrainingCoachError.invalid("保留日程原处方身份不符或缺失，需重新审阅。")
                }
            } else {
                let content = [schedule.templateID.uuidString, schedule.planSnapshotJSON ?? "<missing>",
                    schedule.jumpRopePlanJSON ?? "<missing>", schedule.confirmedDailyImportJSON ?? "<missing>",
                    schedule.plannedTimeZoneIdentifier ?? "<missing>", schedule.plannedLocalDay ?? "<missing>"]
                guard try ConfirmedTrainingPlanService.digest(content) == preserved.contentDigest else {
                    throw TrainingCoachError.invalid("保留的既有日程处方已变化；需核对原请求。")
                }
            }
        }
        let allowed = Set(request.members.map { $0.packet.id }).union(request.ropes.map(\.id))
            .union(request.draft.input.existing.map(\.id))
        let daySet = Set(request.draft.days.map(\.localDay))
        guard schedules.filter({ daySet.contains(TrainingScheduleDate.localDay($0)) }).allSatisfy({ allowed.contains($0.id) }) else {
            throw TrainingCoachError.invalid("写后发现同周其他日程，需人工核对。")
        }
    }

    struct ActualProgressBaseline: Codable {
        struct Snapshot: Codable {
            var id: UUID
            var identity: [String: String?]
            var plannedSets: [WorkoutSetPlan]?
            var targetSets: Int
        }
        var sessionID: UUID
        var identity: [String: String?]
        var snapshots: [Snapshot]
        var sets: [[String: String?]]
    }

    private static let actualSessionIdentityKeys = ["id", "scheduledWorkoutID", "templateID", "templateName", "plannedDate", "trainingLocalDay", "trainingTimeZoneIdentifier", "startedAt", "importIdentifier"]
    private static let actualSnapshotIdentityKeys = ["id", "sessionID", "exerciseID", "exerciseName", "order", "minReps", "maxReps", "targetWeight", "restSeconds", "muscleGroup", "exerciseNotes", "referenceURL", "volumeUnitRaw", "planPatternRaw", "patternSourceRaw", "equipmentSnapshot"]
    private static let actualSetTargetKeys = ["id", "sessionID", "sessionExerciseID", "exerciseID", "setNumber", "targetWeight", "targetReps", "targetWeightSideRaw", "targetRepsSideRaw", "sourceHistorySetID", "isWarmup"]
    private static let completedSetActualKeys = ["actualWeight", "actualReps", "actualWeightSideRaw", "actualRepsSideRaw", "rir", "isCompleted", "actualWeightIsBlank", "actualEntrySourceRaw", "completedAt"]

    private static func selectedFields(_ fields: [String: String?], keys: [String]) -> [String: String?] {
        fields.filter { keys.contains($0.key) }
    }

    private static func savedSetPlans(_ json: String?) -> [WorkoutSetPlan]? {
        guard let json, let data = json.data(using: .utf8),
              let plans = try? JSONDecoder().decode([WorkoutSetPlan].self, from: data), !plans.isEmpty else { return nil }
        return plans
    }

    static func coachActualBaseline(_ session: WorkoutSession, in context: ModelContext) throws -> String {
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == session.id }.sorted { $0.id.uuidString < $1.id.uuidString }
        let sets = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == session.id }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard Set(snapshots.map(\.id)).count == snapshots.count,
              Set(sets.map(\.id)).count == sets.count,
              sets.allSatisfy({ set in snapshots.contains { $0.id == set.sessionExerciseID && $0.exerciseID == set.exerciseID } }) else {
            throw TrainingCoachError.invalid("进行中训练归属不完整，不能封存进展基线。")
        }
        let baseline = ActualProgressBaseline(sessionID: session.id,
            identity: selectedFields(sessionFields(session), keys: actualSessionIdentityKeys),
            snapshots: snapshots.map { .init(id: $0.id, identity: selectedFields(snapshotFields($0), keys: actualSnapshotIdentityKeys),
                plannedSets: savedSetPlans($0.plannedSetsJSON), targetSets: $0.targetSets) }, sets: sets.map(setFields))
        return try TrainingCoachService.encode(baseline)
    }

    private static func verifyActualProgress(_ original: CoachWeekExisting, in context: ModelContext) throws {
        guard let json = original.actualBaselineJSON,
              let baseline = try? JSONDecoder().decode(ActualProgressBaseline.self, from: Data(json.utf8)),
              baseline.sessionID == original.id,
              let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first(where: { $0.id == original.id }),
              session.status == .inProgress || session.status == .completed,
              selectedFields(sessionFields(session), keys: actualSessionIdentityKeys) == baseline.identity else {
            throw TrainingCoachError.invalid("进行中训练身份变化或缺少可比较基线；原周请求已提交待核。")
        }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == session.id }
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == session.id }
        guard Set(snapshots.map(\.id)).count == snapshots.count, Set(logs.map(\.id)).count == logs.count,
              logs.allSatisfy({ set in snapshots.contains { $0.id == set.sessionExerciseID && $0.exerciseID == set.exerciseID } }) else {
            throw TrainingCoachError.invalid("进行中训练出现重复或归属变化。")
        }
        for before in baseline.snapshots {
            guard let current = snapshots.first(where: { $0.id == before.id }),
                  selectedFields(snapshotFields(current), keys: actualSnapshotIdentityKeys) == before.identity,
                  current.targetSets >= before.targetSets else {
                throw TrainingCoachError.invalid("原动作身份或处方丢失/变化。")
            }
            if let originalSets = before.plannedSets {
                guard let currentSets = savedSetPlans(current.plannedSetsJSON),
                      Array(currentSets.prefix(originalSets.count)) == originalSets else {
                    throw TrainingCoachError.invalid("原逐组处方丢失或变化。")
                }
            }
        }
        for before in baseline.sets {
            guard let id = before["id"] ?? nil, let current = logs.first(where: { $0.id.uuidString == id }) else {
                throw TrainingCoachError.invalid("原训练组丢失。")
            }
            let fields = setFields(current)
            guard selectedFields(fields, keys: actualSetTargetKeys) == selectedFields(before, keys: actualSetTargetKeys) else {
                throw TrainingCoachError.invalid("原训练组目标或归属已变化。")
            }
            if (before["isCompleted"] ?? nil) == "true" {
                guard selectedFields(fields, keys: completedSetActualKeys) == selectedFields(before, keys: completedSetActualKeys) else {
                    throw TrainingCoachError.invalid("原已完成组实际发生变化。")
                }
            }
        }
    }

    struct RopeScheduleOrigin: Codable, Equatable {
        var confirmationID: UUID
        var requestDigest: String
        var schedule: ConfirmedTrainingScheduleReadback
    }

    struct RopeScheduleChange: Codable, Equatable {
        var scheduleID: UUID
        var previousDigest: String
        var adjustmentsJSON: String
    }

    /// The origin binds the generated template identity; owner actions append a hash-linked record.
    /// Existing non-coach rope schedules have no origin and retain their existing behavior.
    static func verifiedRopeSchedule(_ schedule: ScheduledWorkout, in context: ModelContext) throws -> ConfirmedTrainingScheduleReadback? {
        guard context.container.schema.entities.contains(where: { $0.name == "TrainingCoachRecord" }) else { return nil }
        let rows = TrainingCoachService.ordered(try context.fetch(FetchDescriptor<TrainingCoachRecord>()))
        let origins = try rows.filter { $0.kind == "week_rope_origin" }
            .map { try TrainingCoachService.decode(RopeScheduleOrigin.self, $0) }.filter { $0.schedule.id == schedule.id }
        guard !origins.isEmpty else { return nil }
        guard origins.count == 1, let origin = origins.first,
              let confirmationRow = rows.first(where: { $0.id == origin.confirmationID && $0.kind == "week_confirmation" }) else {
            throw TrainingCoachError.invalid("跳绳原确认封印缺失或重复。")
        }
        let confirmation = try TrainingCoachService.decode(CoachWeekConfirmation.self, confirmationRow)
        try CoachWeekService.validateConfirmation(confirmation, rowID: confirmationRow.id, rootID: confirmationRow.sessionID)
        guard let template = try context.fetch(FetchDescriptor<WorkoutTemplate>()).first(where: { $0.id == origin.schedule.templateID }),
              template.name == origin.schedule.title else { throw TrainingCoachError.invalid("跳绳原模板身份不符。") }
        guard template.plannedForDate == origin.schedule.plannedDate else { throw TrainingCoachError.invalid("跳绳模板原日期与确认时区日期不符。") }
        guard origin.requestDigest == confirmation.requestDigest else { throw TrainingCoachError.invalid("跳绳原周请求摘要不符。") }
        guard confirmation.ropes.contains(where: { $0.id == schedule.id && $0.localDay == origin.schedule.localDay }),
              origin.schedule.exercises.isEmpty else { throw TrainingCoachError.invalid("跳绳原封印的日期或动作不符。") }
        var expected = origin.schedule
        var digest = try ConfirmedTrainingPlanService.digest(origin)
        let changes = try rows.filter { $0.kind == "week_rope_schedule_adjustment" }
            .map { try TrainingCoachService.decode(RopeScheduleChange.self, $0) }.filter { $0.scheduleID == schedule.id }
        for change in changes {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let actions = try decoder.decode([ConfirmedScheduleAdjustment].self, from: Data(change.adjustmentsJSON.utf8))
            guard change.previousDigest == digest, actions.count == 1, let action = actions.first,
                  action.before == expected,
                  try ConfirmedTrainingPlanService.originalSchedules([action.after], adjustmentsJSON: change.adjustmentsJSON) == [expected] else {
                throw TrainingCoachError.invalid("跳绳日期调整链损坏。")
            }
            expected = action.after
            digest = try ConfirmedTrainingPlanService.digest(change)
        }
        let current = ConfirmedTrainingPlanService.scheduleRecord(schedule, code: schedule.id.uuidString)
        guard ScheduleStatus(rawValue: schedule.statusRaw) != nil, current == expected else { throw TrainingCoachError.invalid("跳绳日期或模板出现未确认变化。") }
        return current
    }

    static func verifyStoredRopeSchedules(in context: ModelContext) throws {
        guard context.container.schema.entities.contains(where: { $0.name == "TrainingCoachRecord" }) else { return }
        let rows = try context.fetch(FetchDescriptor<TrainingCoachRecord>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        for row in rows where ["week_rope_origin", "week_rope_adjustment", "week_rope_schedule_adjustment"].contains(row.kind) {
            let scheduleID: UUID
            switch row.kind {
            case "week_rope_origin": scheduleID = try TrainingCoachService.decode(RopeScheduleOrigin.self, row).schedule.id
            case "week_rope_adjustment":
                let adjustment = try TrainingCoachService.decode(RopeAdjustment.self, row)
                scheduleID = adjustment.scheduleID
                guard let confirmationRow = rows.first(where: { $0.id == adjustment.confirmationID && $0.kind == "week_confirmation" }),
                      confirmationRow.sessionID == row.sessionID else { throw TrainingCoachError.invalid("跳绳目标调整缺少同源周确认。") }
                let request = try TrainingCoachService.decode(CoachWeekConfirmation.self, confirmationRow)
                guard request.ropes.contains(where: { $0.id == scheduleID }) else { throw TrainingCoachError.invalid("跳绳调整不属于原周请求。") }
            default: scheduleID = try TrainingCoachService.decode(RopeScheduleChange.self, row).scheduleID
            }
            guard let schedule = schedules.first(where: { $0.id == scheduleID }),
                  try verifiedRopeSchedule(schedule, in: context) != nil else {
                throw TrainingCoachError.invalid("跳绳调整记录缺少原日程或确认封印。")
            }
        }
        for row in rows where row.kind == "week_confirmation" {
            let request = try TrainingCoachService.decode(CoachWeekConfirmation.self, row)
            for rope in request.ropes {
                guard let schedule = schedules.first(where: { $0.id == rope.id }),
                      try verifiedRopeSchedule(schedule, in: context) != nil,
                      try verifiedRopePlan(rope, request: request, in: context) == schedule.jumpRopePlan else {
                    throw TrainingCoachError.invalid("周跳绳原确认、调整链或当前记录不完整。")
                }
            }
        }
    }

    static func appendRopeScheduleAdjustment(_ schedule: ScheduledWorkout, before: ConfirmedTrainingScheduleReadback,
                                              kind: String, in context: ModelContext) throws {
        let rows = TrainingCoachService.ordered(try context.fetch(FetchDescriptor<TrainingCoachRecord>()))
        guard let originRow = try rows.first(where: {
            guard $0.kind == "week_rope_origin" else { return false }
            return try TrainingCoachService.decode(RopeScheduleOrigin.self, $0).schedule.id == schedule.id
        }) else { throw TrainingCoachError.invalid("跳绳原封印缺失。") }
        let origin = try TrainingCoachService.decode(RopeScheduleOrigin.self, originRow)
        let changes = try rows.filter { $0.kind == "week_rope_schedule_adjustment" }
            .map { try TrainingCoachService.decode(RopeScheduleChange.self, $0) }.filter { $0.scheduleID == schedule.id }
        let previous = try changes.last.map { try ConfirmedTrainingPlanService.digest($0) } ?? ConfirmedTrainingPlanService.digest(origin)
        guard let json = try ConfirmedTrainingPlanService.addingAdjustment(kind: kind, before: before,
            after: ConfirmedTrainingPlanService.scheduleRecord(schedule, code: before.code), to: nil) else { return }
        let change = RopeScheduleChange(scheduleID: schedule.id, previousDigest: previous, adjustmentsJSON: json)
        let sequence = (rows.filter { $0.sessionID == originRow.sessionID }.map(\.sequence).max() ?? 0) + 1
        context.insert(TrainingCoachRecord(sessionID: originRow.sessionID, kind: "week_rope_schedule_adjustment",
            payloadJSON: try TrainingCoachService.encode(change), sequence: sequence))
    }

    struct RopeAdjustment: Codable, Equatable {
        var confirmationID: UUID
        var scheduleID: UUID
        var previousDigest: String
        var before: JumpRopeMenuPlan
        var after: JumpRopeMenuPlan
    }

    static func appendRopeAdjustment(schedule: ScheduledWorkout, before: JumpRopeMenuPlan,
                                     in context: ModelContext) throws {
        let confirmations = try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.kind == "week_confirmation" }
        for row in confirmations {
            let request = try TrainingCoachService.decode(CoachWeekConfirmation.self, row)
            guard let rope = request.ropes.first(where: { $0.id == schedule.id }) else { continue }
            guard try verifiedRopeSchedule(schedule, in: context) != nil,
                  try verifiedRopePlan(rope, request: request, in: context) == before,
                  let after = schedule.jumpRopePlan, after.isValid else {
                throw TrainingCoachError.invalid("跳绳调整原确认链不完整。")
            }
            let chain = try ropeAdjustments(request: request, scheduleID: schedule.id, in: context)
            let previous = try chain.last.map { try ConfirmedTrainingPlanService.digest($0) } ?? request.requestDigest
            let adjustment = RopeAdjustment(confirmationID: request.id, scheduleID: schedule.id,
                previousDigest: previous, before: before, after: after)
            let sequence = (try TrainingCoachService.records(sessionID: request.draft.rootID, in: context).map(\.sequence).max() ?? 0) + 1
            context.insert(TrainingCoachRecord(sessionID: request.draft.rootID, kind: "week_rope_adjustment",
                payloadJSON: try TrainingCoachService.encode(adjustment), sequence: sequence))
        }
    }

    private static func ropeAdjustments(request: CoachWeekConfirmation, scheduleID: UUID,
                                         in context: ModelContext) throws -> [RopeAdjustment] {
        try TrainingCoachService.records(sessionID: request.draft.rootID, in: context)
            .filter { $0.kind == "week_rope_adjustment" }
            .map { try TrainingCoachService.decode(RopeAdjustment.self, $0) }
            .filter { $0.confirmationID == request.id && $0.scheduleID == scheduleID }
    }

    private static func verifiedRopePlan(_ rope: CoachWeekRopeMember, request: CoachWeekConfirmation,
                                         in context: ModelContext) throws -> JumpRopeMenuPlan {
        var plan = rope.plan
        var digest = request.requestDigest
        for adjustment in try ropeAdjustments(request: request, scheduleID: rope.id, in: context) {
            guard adjustment.previousDigest == digest, adjustment.before == plan, adjustment.after.isValid else {
                throw TrainingCoachError.invalid("跳绳调整链损坏。")
            }
            plan = adjustment.after
            digest = try ConfirmedTrainingPlanService.digest(adjustment)
        }
        return plan
    }

    private static func verifyTemplate(_ stored: ConfirmedDailyTrainingPlanReadback, in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).filter { $0.id == stored.schedule.templateID }
        let items = try context.fetch(FetchDescriptor<TemplateExercise>()).filter { $0.templateID == stored.schedule.templateID }
        guard templates.count == 1, items.count == stored.packet.exercises.count,
              Set(items.map(\.order)).count == items.count else {
            throw ConfirmedTrainingPlanError.conflict("模板动作图缺失或重复，请核对原请求")
        }
        for (order, draft) in stored.packet.exercises.enumerated() {
            guard let item = items.first(where: { $0.order == order }),
                  let frozen = stored.schedule.exercises.first(where: { $0.order == order }),
                  item.id == frozen.id, item.exerciseID == draft.catalogExerciseID,
                  item.plannedSets == draft.plannedSets, item.planPattern == (draft.planPattern ?? .fixed),
                  item.targetSets == frozen.targetSets, item.minReps == frozen.minReps,
                  item.maxReps == frozen.maxReps, item.targetWeight == frozen.targetWeight,
                  item.restSeconds == frozen.restSeconds, item.patternSource == frozen.patternSource,
                  frozen.exerciseID == draft.catalogExerciseID, frozen.equipment == draft.equipment,
                  frozen.volumeUnit == draft.volumeUnit, frozen.plannedSets == draft.plannedSets,
                  frozen.planPattern == (draft.planPattern ?? .fixed) else {
                throw ConfirmedTrainingPlanError.conflict("模板与逐组处方不一致：\(draft.catalogName)")
            }
        }
    }

    static func readback(id: UUID, in context: ModelContext) throws -> ConfirmedDailyTrainingPlanReadback? {
        let matches = try context.fetch(FetchDescriptor<ScheduledWorkout>()).filter { $0.id == id }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let schedule = matches.first, let json = schedule.confirmedDailyImportJSON else {
            throw ConfirmedTrainingPlanError.conflict("来源ID已被其他日程占用")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let source: ConfirmedDailyTrainingPlanSource
        do { source = try decoder.decode(ConfirmedDailyTrainingPlanSource.self, from: Data(json.utf8)) }
        catch { throw ConfirmedTrainingPlanError.conflict("单日确认来源损坏") }
        let date = try validate(source.packet)
        let record = scheduleRecord(schedule, code: id.uuidString)
        let original = try ConfirmedTrainingPlanService.originalSchedules([record],
            adjustmentsJSON: source.scheduleAdjustmentsJSON)[0]
        guard source.packet.id == id, try ConfirmedTrainingPlanService.digest(source.packet) == source.packetSHA256,
              try ConfirmedTrainingPlanService.digest(original) == source.scheduleIntegritySHA256,
              original.localDay == source.packet.localDay,
              original.timeZoneIdentifier == source.packet.timeZoneIdentifier,
              original.plannedDate == date, original.title == source.packet.title,
              original.exercises.count == source.packet.exercises.count else {
            throw ConfirmedTrainingPlanError.conflict("单日日程日期、处方或来源已变化")
        }
        if let approval = source.discardedDraftApproval {
            guard approval.review.scheduleID == source.packet.replacement?.scheduleID,
                  !approval.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !approval.review.sessionIDs.isEmpty,
                  Set(approval.review.sessionIDs).count == approval.review.sessionIDs.count,
                  approval.review.contentSHA256.count == 64 else {
                throw ConfirmedTrainingPlanError.conflict("空白已丢弃草稿的确认来源已变化")
            }
        }
        return ConfirmedDailyTrainingPlanReadback(packet: source.packet, packetSHA256: source.packetSHA256, schedule: record,
            discardedDraftApproval: source.discardedDraftApproval)
    }

    static func appendScheduleAdjustment(_ schedule: ScheduledWorkout, before: ConfirmedTrainingScheduleReadback,
                                         kind: String) throws {
        guard let json = schedule.confirmedDailyImportJSON else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var source = try decoder.decode(ConfirmedDailyTrainingPlanSource.self, from: Data(json.utf8))
        source.scheduleAdjustmentsJSON = try ConfirmedTrainingPlanService.addingAdjustment(kind: kind, before: before,
            after: scheduleRecord(schedule, code: before.code), to: source.scheduleAdjustmentsJSON)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        schedule.confirmedDailyImportJSON = String(decoding: try encoder.encode(source), as: UTF8.self)
    }

    static func supersededScheduleIDs(in schedules: [ScheduledWorkout]) -> Set<UUID> {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return Set(schedules.compactMap { row in
            guard let json = row.confirmedDailyImportJSON,
                  let source = try? decoder.decode(ConfirmedDailyTrainingPlanSource.self, from: Data(json.utf8)) else { return nil }
            return source.packet.replacement?.scheduleID
        })
    }

    static func isSuperseded(_ id: UUID, in context: ModelContext) throws -> Bool {
        supersededScheduleIDs(in: try context.fetch(FetchDescriptor<ScheduledWorkout>())).contains(id)
    }

    private static func scheduleRecord(_ schedule: ScheduledWorkout, code: String) -> ConfirmedTrainingScheduleReadback {
        ConfirmedTrainingScheduleReadback(id: schedule.id, code: code, templateID: schedule.templateID,
            title: schedule.templateName, localDay: schedule.plannedLocalDay ?? "",
            timeZoneIdentifier: schedule.plannedTimeZoneIdentifier ?? "", plannedDate: schedule.plannedDate,
            exercises: schedule.planSnapshot)
    }

    private static func replacementReason(successorID: UUID) -> String {
        "已由确认修订 \(successorID.uuidString) 替代；原处方保留"
    }

    private static let discardedDraftConflict = "待修订日程已有实际训练或草稿，不能替换"

    private static func replacementAncestors(_ packet: ConfirmedDailyTrainingPlanPacket, alreadyApplied: Bool,
        schedules: [ScheduledWorkout], sessions: [WorkoutSession], existingApproval: ConfirmedDiscardedDraftApproval?,
        in context: ModelContext
    ) throws -> (ids: Set<UUID>, conflicts: [String], review: ConfirmedDiscardedDraftReview?) {
        var ids: Set<UUID> = [packet.id]
        var link = packet.replacement
        var successorID = packet.id
        var isImmediate = true
        var conflicts: [String] = []
        var edgeApproval = existingApproval
        var immediateReview: ConfirmedDiscardedDraftReview?
        while let previous = link {
            guard ids.insert(previous.scheduleID).inserted,
                  let row = schedules.first(where: { $0.id == previous.scheduleID }),
                  let source = try readback(id: previous.scheduleID, in: context),
                  source.packetSHA256 == previous.packetSHA256,
                  source.packet.localDay == packet.localDay,
                  source.packet.timeZoneIdentifier == packet.timeZoneIdentifier else {
                conflicts.append("待修订日程的来源、日期或绑定摘要已变化")
                break
            }
            let mayRetire = isImmediate && !alreadyApplied
            if mayRetire ? row.status != .planned :
                (row.status != .skipped || row.skipReason != replacementReason(successorID: successorID)) {
                conflicts.append("仅可修订未开始的指定日程，旧修订链须完整保留")
            }
            let linked = sessions.filter { $0.scheduledWorkoutID == row.id }
            if !linked.isEmpty || edgeApproval != nil {
                let review = try discardedDraftReview(row, source: source, sessions: linked, in: context)
                if let approved = edgeApproval, approved.review == review,
                   !approved.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if isImmediate { immediateReview = review }
                } else {
                    conflicts.append(discardedDraftConflict)
                    if isImmediate && !alreadyApplied { immediateReview = review }
                }
            }
            successorID = row.id
            link = source.packet.replacement
            edgeApproval = source.discardedDraftApproval
            isImmediate = false
        }
        return (ids, conflicts, immediateReview)
    }

    private static func discardedDraftReview(_ schedule: ScheduledWorkout, source: ConfirmedDailyTrainingPlanReadback,
                                             sessions: [WorkoutSession],
                                             in context: ModelContext) throws -> ConfirmedDiscardedDraftReview? {
        let plans = schedule.planSnapshot
        guard !sessions.isEmpty, !plans.isEmpty,
              Set(sessions.map(\.id)).count == sessions.count,
              Set(plans.map(\.order)).count == plans.count,
              try !context.fetch(FetchDescriptor<JumpRopeEntry>()).contains(where: { $0.scheduledWorkoutID == schedule.id }) else { return nil }
        let sessionIDs = Set(sessions.map(\.id))
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { sessionIDs.contains($0.sessionID) }
        let snapshotIDs = Set(snapshots.map(\.id))
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter {
            sessionIDs.contains($0.sessionID) || snapshotIDs.contains($0.sessionExerciseID)
        }
        guard snapshotIDs.count == snapshots.count, Set(logs.map(\.id)).count == logs.count else { return nil }
        let sides = Set(MeasurementSide.allCases.map(\.rawValue))
        for session in sessions {
            guard session.statusRaw == WorkoutSessionStatus.discarded.rawValue,
                  session.templateID == schedule.templateID, session.templateName == schedule.templateName,
                  session.trainingLocalDay == TrainingScheduleDate.localDay(schedule),
                  session.trainingTimeZoneIdentifier == schedule.plannedTimeZoneIdentifier,
                  session.notes.isEmpty, session.restEndDate == nil, session.cardioResistanceLevel == nil,
                  let discardedAt = session.completedAt, discardedAt >= session.startedAt else { return nil }
            let items = snapshots.filter { $0.sessionID == session.id }
            guard items.count == plans.count, Set(items.map(\.order)) == Set(plans.map(\.order)) else { return nil }
            for item in items {
                guard let plan = plans.first(where: { $0.order == item.order }),
                      let identity = source.packet.exercises.first(where: { $0.catalogExerciseID == plan.exerciseID }),
                      item.exerciseID == plan.exerciseID, item.exerciseName == identity.catalogName,
                      item.targetSets == plan.targetSets, item.minReps == plan.minReps, item.maxReps == plan.maxReps,
                      item.targetWeight == plan.targetWeight, item.restSeconds == plan.restSeconds,
                      item.muscleGroup == plan.muscleGroup, item.exerciseNotes == plan.exerciseNotes,
                      item.referenceURL == plan.referenceURL, item.volumeUnitRaw == plan.volumeUnit.rawValue,
                      item.equipmentSnapshot == plan.equipment, item.plannedSets == plan.plannedSets,
                      item.hasManuallyReducedSets != true, item.performanceNotes.isEmpty, item.feelingRaw == nil, item.exerciseCompletedAt == nil,
                      item.exerciseStartedAt == nil || (item.order == plans.map(\.order).min() && item.exerciseStartedAt == session.startedAt) else { return nil }
                let sets = logs.filter { $0.sessionExerciseID == item.id }
                guard !plan.plannedSets.isEmpty, sets.count == plan.plannedSets.count,
                      Set(sets.map(\.setNumber)) == Set(1...plan.plannedSets.count) else { return nil }
                for set in sets {
                    let target = plan.plannedSets[set.setNumber - 1]
                    guard set.reductionOrder == nil, set.sessionID == session.id, set.exerciseID == item.exerciseID,
                          set.targetWeight == target.weight, set.targetReps == target.reps,
                          set.targetWeightSideRaw == target.weightSide.rawValue, set.targetRepsSideRaw == target.repsSide.rawValue,
                          sides.contains(set.targetWeightSideRaw ?? ""), sides.contains(set.targetRepsSideRaw ?? ""),
                          set.actualWeightSideRaw == set.targetWeightSideRaw, set.actualRepsSideRaw == set.targetRepsSideRaw,
                          !set.isCompleted, !set.isWarmup, set.actualWeightIsBlank == true,
                          set.actualEntrySourceRaw == WorkoutActualEntrySource.blank.rawValue,
                          set.actualWeight == 0, set.actualReps == 0, set.rir == nil,
                          set.startedAt == nil, set.completedAt == nil, set.restStartedAt == nil,
                          set.restEndedAt == nil, set.restDurationSeconds == nil, set.sourceHistorySetID == nil else { return nil }
                }
            }
        }
        guard logs.allSatisfy({ snapshotIDs.contains($0.sessionExerciseID) }) else { return nil }
        let graph = [
            "sessions": sessions.sorted { $0.id.uuidString < $1.id.uuidString }.map(sessionFields),
            "snapshots": snapshots.sorted { $0.id.uuidString < $1.id.uuidString }.map(snapshotFields),
            "sets": logs.sorted { $0.id.uuidString < $1.id.uuidString }.map(setFields)
        ]
        return ConfirmedDiscardedDraftReview(scheduleID: schedule.id,
            sessionIDs: sessions.map(\.id).sorted { $0.uuidString < $1.uuidString },
            snapshotCount: snapshots.count, setCount: logs.count,
            contentSHA256: try ConfirmedTrainingPlanService.digest(graph))
    }

    private static func timestamp(_ value: Date?) -> String? {
        value.map { String($0.timeIntervalSinceReferenceDate.bitPattern) }
    }

    private static func sessionFields(_ s: WorkoutSession) -> [String: String?] {
        ["id": s.id.uuidString, "scheduledWorkoutID": s.scheduledWorkoutID?.uuidString, "templateID": s.templateID?.uuidString,
         "templateName": s.templateName, "plannedDate": timestamp(s.plannedDate), "trainingLocalDay": s.trainingLocalDay,
         "trainingTimeZoneIdentifier": s.trainingTimeZoneIdentifier, "startedAt": timestamp(s.startedAt),
         "startTimeKnownRaw": s.startTimeKnownRaw.map(String.init), "completedAt": timestamp(s.completedAt),
         "statusRaw": s.statusRaw, "notes": s.notes, "restEndDate": timestamp(s.restEndDate), "restModeRaw": s.restModeRaw,
         "importIdentifier": s.importIdentifier, "defaultPlanPatternRaw": s.defaultPlanPatternRaw,
         "cardioResistanceLevel": s.cardioResistanceLevel.map { String($0.bitPattern) }]
    }

    private static func snapshotFields(_ s: SessionExercise) -> [String: String?] {
        ["id": s.id.uuidString, "sessionID": s.sessionID.uuidString, "exerciseID": s.exerciseID.uuidString,
         "exerciseName": s.exerciseName, "order": String(s.order), "targetSets": String(s.targetSets),
         "minReps": String(s.minReps), "maxReps": String(s.maxReps), "targetWeight": String(s.targetWeight.bitPattern),
         "restSeconds": String(s.restSeconds), "muscleGroup": s.muscleGroup, "exerciseNotes": s.exerciseNotes,
         "referenceURL": s.referenceURL, "volumeUnitRaw": s.volumeUnitRaw, "performanceNotes": s.performanceNotes,
         "plannedSetsJSON": s.plannedSetsJSON, "planPatternRaw": s.planPatternRaw, "patternSourceRaw": s.patternSourceRaw,
         "feelingRaw": s.feelingRaw, "exerciseStartedAt": timestamp(s.exerciseStartedAt), "exerciseCompletedAt": timestamp(s.exerciseCompletedAt),
         "bodyWeightKgSnapshot": s.bodyWeightKgSnapshot.map { String($0.bitPattern) },
         "bodyWeightSnapshotSourceDate": timestamp(s.bodyWeightSnapshotSourceDate), "equipmentSnapshot": s.equipmentSnapshot]
    }

    private static func setFields(_ s: SetLog) -> [String: String?] {
        ["id": s.id.uuidString, "sessionID": s.sessionID.uuidString, "sessionExerciseID": s.sessionExerciseID.uuidString,
         "exerciseID": s.exerciseID.uuidString, "setNumber": String(s.setNumber), "targetWeight": String(s.targetWeight.bitPattern),
         "targetReps": String(s.targetReps), "actualWeight": String(s.actualWeight.bitPattern), "actualReps": String(s.actualReps),
         "rir": s.rir.map(String.init), "isWarmup": String(s.isWarmup), "isCompleted": String(s.isCompleted),
         "startedAt": timestamp(s.startedAt), "completedAt": timestamp(s.completedAt), "restStartedAt": timestamp(s.restStartedAt),
         "restEndedAt": timestamp(s.restEndedAt), "restDurationSeconds": s.restDurationSeconds.map(String.init),
         "targetWeightSideRaw": s.targetWeightSideRaw, "targetRepsSideRaw": s.targetRepsSideRaw,
         "actualWeightSideRaw": s.actualWeightSideRaw, "actualRepsSideRaw": s.actualRepsSideRaw,
         "actualEntrySourceRaw": s.actualEntrySourceRaw, "sourceHistorySetID": s.sourceHistorySetID?.uuidString,
         "actualWeightIsBlank": s.actualWeightIsBlank.map(String.init)]
    }

    private static func validate(_ packet: ConfirmedDailyTrainingPlanPacket) throws -> Date {
        let prefill = packet.actualPrefillConfirmationReference != nil
        if let reference = packet.actualPrefillConfirmationReference {
            guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reference.utf8.count <= 4096 else {
                throw ConfirmedTrainingPlanError.invalidPacket("建议预填需要本人明确确认")
            }
        }
        if let replacement = packet.replacement {
            guard replacement.scheduleID != packet.id,
                  replacement.packetSHA256.count == 64,
                  replacement.packetSHA256.allSatisfy({ $0.isHexDigit }) else {
                throw ConfirmedTrainingPlanError.invalidPacket("修订必须绑定不同的原日程与完整来源摘要")
            }
        }
        guard packet.version == 1, let zone = TimeZone(identifier: packet.timeZoneIdentifier),
              let date = MealLocalDay.date(packet.localDay, timeZone: zone),
              !packet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, packet.title.utf8.count <= 512,
              !packet.preferenceRevisionCode.isEmpty, !packet.confirmationReference.isEmpty,
              packet.confirmationReference.utf8.count <= 4096, packet.confirmedAt <= .now,
              !packet.sourceMarkdown.isEmpty, packet.sourceMarkdown.utf8.count <= 1_048_576,
              packet.sourceSHA256 == ConfirmedTrainingPlanService.digest(Data(packet.sourceMarkdown.utf8)),
              !packet.guidance.isEmpty, packet.guidance.utf8.count <= 16_384,
              (1...24).contains(packet.exercises.count),
              Set(packet.exercises.map(\.catalogExerciseID)).count == packet.exercises.count,
              packet.exercises.reduce(0, { $0 + $1.plannedSets.count }) <= 120 else {
            throw ConfirmedTrainingPlanError.invalidPacket("单日日期、来源确认或动作数量无效")
        }
        var setIDs = Set<UUID>()
        for draft in packet.exercises {
            if prefill {
                let instructions = draft.loadGuidance + draft.notes + packet.guidance
                guard draft.volumeUnit == .kilogram,
                      !instructions.contains("重量待当天热身确定"), !instructions.contains("重量留空") else {
                    throw ConfirmedTrainingPlanError.invalidPacket("建议预填仅用于口径明确的抗阻计划，不能含留空指令")
                }
            }
            guard !draft.catalogName.isEmpty, !draft.equipment.isEmpty, !draft.displayName.isEmpty,
                  draft.displayName.utf8.count <= 512, !draft.loadGuidance.isEmpty,
                  draft.loadGuidance.utf8.count <= 4096, draft.notes.utf8.count <= 16_384,
                  (1...20).contains(draft.plannedSets.count), draft.plannedSets.allSatisfy({ plan in
                      guard let target = plan.prescription else { return false }
                      return target.isValid && !target.label.isEmpty && target.label.utf8.count <= 1024 &&
                          (target.effortCue?.utf8.count ?? 0) <= 4096 && plan.weight.isFinite && (0...10_000).contains(plan.weight) &&
                          (draft.volumeUnit.recordsNumericLoad || plan.weight == 0) &&
                          (prefill ? (target.repsLower...target.repsUpper).contains(plan.reps)
                                   : plan.reps == target.repsLower) &&
                          (prefill ? (plan.actualDefaultPolicy == .plan && plan.weight > 0 &&
                                      plan.weightSide != .unknown && plan.repsSide != .unknown) : plan.actualDefaultPolicy == .blank) &&
                          setIDs.insert(plan.id).inserted
                  }) else {
                throw ConfirmedTrainingPlanError.invalidPacket("\(draft.displayName)需完整的逐组目标、负重口径及实际留空策略")
            }
        }
        return date
    }
}

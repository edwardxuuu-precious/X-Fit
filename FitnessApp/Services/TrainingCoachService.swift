import Foundation
import SwiftData

@MainActor
enum TrainingCoachService {
    static let kinds: Set<String> = ["after", "morning", "draft", "confirmation", "receipt", "cancelled", "week_draft", "week_confirmation", "week_rope_adjustment", "week_rope_origin", "week_rope_schedule_adjustment", "week_rule_activation"]

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ row: TrainingCoachRecord) throws -> T {
        try JSONDecoder().decode(type, from: Data(row.payloadJSON.utf8))
    }

    static func ordered(_ rows: [TrainingCoachRecord]) -> [TrainingCoachRecord] {
        rows.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    static func records(sessionID: UUID, in context: ModelContext) throws -> [TrainingCoachRecord] {
        ordered(try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.sessionID == sessionID })
    }

    static func latestFeedback(_ stage: String, rows: [TrainingCoachRecord]) throws -> CoachFeedback {
        guard let row = rows.last(where: { $0.kind == stage }) else { return CoachFeedback(stage: stage) }
        return try decode(CoachFeedback.self, row)
    }

    static func latestDraft(rows: [TrainingCoachRecord]) throws -> CoachDraft? {
        try rows.last(where: { $0.kind == "draft" }).map { try decode(CoachDraft.self, $0) }
    }

    static func confirmations(rows: [TrainingCoachRecord]) throws -> [CoachConfirmation] {
        try rows.filter { $0.kind == "confirmation" }.map { try decode(CoachConfirmation.self, $0) }
    }

    static func isCancelled(_ confirmation: CoachConfirmation, rows: [TrainingCoachRecord]) -> Bool {
        rows.contains { $0.kind == "cancelled" && (try? decode(UUID.self, $0)) == confirmation.id }
    }

    static func cancelUnwritten(_ confirmation: CoachConfirmation, in context: ModelContext) throws {
        let verification = ModelContext(context.container)
        guard try ConfirmedDailyTrainingPlanService.readback(id: confirmation.preview.packet.id, in: verification) == nil else {
            throw TrainingCoachError.invalid("已经找到原安排，请核对保存结果，不能取消为未保存。")
        }
        let rows = try records(sessionID: confirmation.draft.sessionID, in: context)
        if !isCancelled(confirmation, rows: rows) {
            try append(confirmation.id, kind: "cancelled", sessionID: confirmation.draft.sessionID, in: context)
        }
    }

    static func hasReceipt(_ confirmation: CoachConfirmation, rows: [TrainingCoachRecord]) throws -> Bool {
        try rows.filter { $0.kind == "receipt" }.contains {
            let receipt = try decode(CoachSavedReceipt.self, $0)
            return receipt.confirmationID == confirmation.id && receipt.scheduleID == confirmation.preview.packet.id
                && receipt.packetSHA256 == confirmation.preview.packetSHA256
        }
    }

    static func append<T: Encodable>(_ value: T, kind: String, sessionID: UUID,
                                    id: UUID = UUID(), in context: ModelContext) throws {
        guard !context.hasChanges else { throw TrainingCoachError.invalid("请先保存当前编辑，再记录反馈或计划。") }
        let sequence = (try records(sessionID: sessionID, in: context).map(\.sequence).max() ?? 0) + 1
        let row = TrainingCoachRecord(id: id, sessionID: sessionID, kind: kind, payloadJSON: try encode(value), sequence: sequence)
        context.insert(row)
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    static func saveFeedback(_ feedback: CoachFeedback, sessionID: UUID, now: Date = .now,
                             in context: ModelContext) throws {
        guard ["after", "morning"].contains(feedback.stage),
              ["none", "yes", "unknown"].contains(feedback.pain),
              ["normal", "limited", "unknown"].contains(feedback.function),
              ["good", "ordinary", "poor", "unknown"].contains(feedback.recovery),
              feedback.lastRIR.values.allSatisfy({ (0...10).contains($0) }), feedback.note.count <= 4000 else {
            throw TrainingCoachError.invalid("反馈字段无效，请检查后保存。")
        }
        let source = try review(sessionID: sessionID, now: now, in: context)
        guard feedback.stage != "morning" || TrainingLocalDate.key(now) > source.localDay else {
            throw TrainingCoachError.invalid("次晨尚未到，先保留未知，明早再补恢复。")
        }
        let ids = Set(source.observations.map { $0.id.uuidString })
        guard Set(feedback.lastRIR.keys).isSubset(of: ids), Set(feedback.quality.keys).isSubset(of: ids),
              Set(feedback.loadConventions.keys).isSubset(of: ids), Set(feedback.repsSides.keys).isSubset(of: ids) else {
            throw TrainingCoachError.invalid("反馈对应的动作已变化，请重新打开复盘。")
        }
        if try latestFeedback(feedback.stage, rows: source.records) == feedback { return }
        try append(feedback, kind: feedback.stage, sessionID: sessionID, in: context)
    }

    static func isTechnical(_ item: SessionExercise) -> Bool {
        let text = item.exerciseName.lowercased()
        return text.contains("高翻") || text.contains("power clean") || text.contains("抓举")
            || item.plannedSets.contains { $0.prescription?.label.contains("技术") == true }
    }

    static func review(sessionID: UUID, preferenceDate: Date = .now, now: Date = .now,
                       in context: ModelContext) throws -> CoachReview {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard let session = sessions.first(where: { $0.id == sessionID && $0.status == .completed }) else {
            throw TrainingCoachError.invalid("请先结束并保存这次训练，再查看复盘。")
        }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let sets = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.reductionOrder == nil }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let schedule = schedules.first { $0.id == session.scheduledWorkoutID }
        let packet = schedule.flatMap { try? ConfirmedDailyTrainingPlanService.readback(id: $0.id, in: context)?.packet }
        let sourceDay = TrainingHistoryDate.localDay(session)
        let rows = try records(sessionID: sessionID, in: context)
        let after = try latestFeedback("after", rows: rows)
        let morning = try latestFeedback("morning", rows: rows)
        let preference = try TrainingPreferenceService.current(in: context, on: preferenceDate)
        var observations = snapshots.filter { $0.sessionID == sessionID }.sorted { $0.order < $1.order }.map { item in
            let frozen = schedule?.planSnapshot.first { $0.exerciseID == item.exerciseID }
            return CoachObservation(id: item.id, exerciseID: item.exerciseID, name: item.exerciseName,
                muscleGroup: item.muscleGroup, equipment: item.equipmentSnapshot ?? frozen?.equipment ?? "",
                unit: item.volumeUnit, notes: item.exerciseNotes, plannedSets: item.plannedSets,
                actual: sets.filter { $0.sessionExerciseID == item.id && $0.sessionID == sessionID }
                    .sorted { $0.setNumber < $1.setNumber }.map {
                        CoachActualSet(id: $0.id, weight: $0.isActualWeightBlank ? nil : $0.actualWeight,
                            reps: $0.actualReps, rir: $0.rir, weightSide: $0.actualWeightSide,
                            repsSide: $0.actualRepsSide, completed: $0.isCompleted, warmup: $0.isWarmup)
                    }, loadGuidance: packet?.exercises.first { $0.catalogExerciseID == item.exerciseID }?.loadGuidance ?? "",
                isTechnical: isTechnical(item), performanceNotes: item.performanceNotes, feelingRaw: item.feelingRaw,
                historicalClassificationUnknown: session.importIdentifier.lowercased().contains("notes") || item.exerciseNotes.contains("Notes"))
        }
        let anchor = TrainingLocalDate.date(sourceDay, timeZone: .current) ?? session.plannedDate
        var existingRecovery: [String] = []
        let checkIns = try context.fetch(FetchDescriptor<DailyBodyCheckIn>()).filter { $0.date >= anchor && $0.date <= now }.sorted { $0.date < $1.date }
        for entry in checkIns.suffix(2) {
            existingRecovery.append("App体感 \(TrainingLocalDate.key(entry.date))：\(entry.discomfortNotes.isEmpty ? "已有体感与身体标记记录，不能直接换算为恢复正常" : entry.discomfortNotes)")
        }
        let sleepLogs = try context.fetch(FetchDescriptor<ProgramDailyLog>()).filter { $0.date >= anchor && $0.date <= now }.sorted { $0.date < $1.date }
        for entry in sleepLogs.suffix(2) {
            if let hours = entry.sleepHours { existingRecovery.append("App睡眠 \(TrainingLocalDate.key(entry.date))：\(hours.formatted())小时；时长不代替睡眠质量或功能反馈。") }
        }
        let allCoachRows = ordered(try context.fetch(FetchDescriptor<TrainingCoachRecord>()))
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let genericEquipment: Set<String> = ["器械", "机器", "其他", "未知", ""]
        for index in observations.indices {
            let current = observations[index]
            guard !genericEquipment.contains(current.equipment), let side = current.working.last,
                  side.weightSide != .unknown, side.repsSide != .unknown else { continue }
            let previous = snapshots.filter { item in
                guard item.exerciseID == current.exerciseID, item.sessionID != sessionID,
                      item.volumeUnit == current.unit, let prior = sessionByID[item.sessionID], prior.status == .completed,
                      TrainingHistoryDate.localDay(prior) < sourceDay, prior.plannedDate >= anchor.addingDays(-42) else { return false }
                let equipment = item.equipmentSnapshot ?? schedules.first(where: { $0.id == prior.scheduledWorkoutID })?.planSnapshot.first(where: { $0.exerciseID == item.exerciseID })?.equipment ?? ""
                return equipment == current.equipment
            }.sorted { (sessionByID[$0.sessionID]?.plannedDate ?? .distantPast) > (sessionByID[$1.sessionID]?.plannedDate ?? .distantPast) }
            observations[index].previous = try previous.prefix(3).compactMap { item in
                let priorSets = sets.filter { $0.sessionExerciseID == item.id && $0.isCompleted && !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber }
                guard !priorSets.isEmpty, priorSets.allSatisfy({ !$0.isActualWeightBlank && $0.actualWeightSide == side.weightSide && $0.actualRepsSide == side.repsSide }) else { return nil }
                let feedback = try latestFeedback("after", rows: allCoachRows.filter { $0.sessionID == item.sessionID })
                return CoachHistoricalPerformance(id: item.sessionID, localDay: TrainingHistoryDate.localDay(sessionByID[item.sessionID]!),
                    plannedSets: item.plannedSets, actual: priorSets.map {
                        CoachActualSet(id: $0.id, weight: $0.actualWeight, reps: $0.actualReps, rir: $0.rir,
                            weightSide: $0.actualWeightSide, repsSide: $0.actualRepsSide, completed: true, warmup: false)
                    }, supplementaryLastRIR: feedback.lastRIR[item.id.uuidString])
            }
        }
        let recentSessions = sessions.filter {
            $0.status == .completed && TrainingHistoryDate.localDay($0) <= sourceDay
                && TrainingHistoryDate.localDay($0) >= TrainingLocalDate.key(anchor.addingDays(-6))
        }
        let recentIDs = Set(recentSessions.map(\.id))
        let recentSets = sets.filter { recentIDs.contains($0.sessionID) && $0.isCompleted && !$0.isWarmup }
        let rawCount = recentSets.count
        let ropes = try context.fetch(FetchDescriptor<JumpRopeEntry>()).filter {
            let day = $0.trainingLocalDay ?? TrainingLocalDate.key($0.date)
            return day >= TrainingLocalDate.key(anchor.addingDays(-6)) && day <= sourceDay
        }
        var coverage = ["训练日前7天：\(recentSessions.count)次力量记录，\(rawCount)条非热身完成记录；性质分别判断，不等同有效组。",
                        "同期跳绳：\(ropes.compactMap(\.count).reduce(0, +))次（仅合计有次数的记录；未记录项未知）。"]
        let groups = Dictionary(grouping: recentSets, by: { set in snapshots.first(where: { $0.id == set.sessionExerciseID })?.muscleGroup ?? "未注明肌群" })
        for group in groups.keys.sorted() { coverage.append("\(group.isEmpty ? "未注明肌群" : group)：\(groups[group]!.count)条非热身完成记录；不重复折算重叠肌群。") }
        let upcoming = schedules.filter {
            $0.status == .planned && $0.plannedDate >= now.startOfDay && $0.plannedDate < now.addingDays(2).startOfDay
        }.sorted { $0.plannedDate < $1.plannedDate }
        if !upcoming.isEmpty { coverage.append("未来约48小时已安排：" + upcoming.map { "\(TrainingScheduleDate.localDay($0)) \($0.templateName)" }.joined(separator: "；")) }
        // Include actual comparable history, current catalog and preference in the source guard.
        let relevantIDs = Set(observations.map(\.exerciseID))
        let historySessionIDs = Set(sessions.filter {
            $0.status == .completed && $0.plannedDate <= session.plannedDate && $0.plannedDate >= anchor.addingDays(-42)
        }.map(\.id))
        let historySnapshots = snapshots.filter { historySessionIDs.contains($0.sessionID) && relevantIDs.contains($0.exerciseID) }
        let historySnapshotIDs = Set(historySnapshots.map(\.id))
        var signature = [session.id.uuidString, session.statusRaw, session.notes, sourceDay,
                         try encode(observations), try encode(after), try encode(morning), preference?.snapshotJSON ?? "",
                         try encode(coverage), try encode(existingRecovery)]
        signature += historySnapshots.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.equipmentSnapshot ?? "")|\($0.volumeUnitRaw ?? "")|\($0.plannedSetsJSON ?? "")|\($0.performanceNotes)"
        }
        signature += sets.filter { historySnapshotIDs.contains($0.sessionExerciseID) }.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.isCompleted)|\($0.isWarmup)|\($0.actualWeight)|\($0.actualReps)|\($0.rir.map(String.init) ?? "?")|\($0.actualWeightSideRaw ?? "?")|\($0.actualRepsSideRaw ?? "?")|\($0.isActualWeightBlank)"
        }
        signature += catalog.filter { relevantIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.name)|\($0.equipment)|\($0.volumeUnitRaw ?? "")|\($0.isArchived)"
        }
        return CoachReview(sessionID: sessionID, name: session.templateName, localDay: sourceDay,
            observations: observations, records: rows, after: after, morning: morning,
            preferenceCode: preference?.revisionCode ?? "", sourceFingerprint: try ConfirmedTrainingPlanService.digest(signature), coverage: coverage, existingRecovery: existingRecovery)
    }

    static func insight(for item: CoachObservation, after: CoachFeedback) -> String {
        if item.feelingRaw == WorkoutFeeling.painful.rawValue { return "已有不适反馈，先核实恢复与动作" }
        guard let last = item.working.last else { return "缺完成记录，先核漏记或省去原因" }
        if item.isTechnical {
            return after.quality[item.id.uuidString] == "stable" ? "维持低次技术组，快拉稳接" : "技术质量待补，暂不加重"
        }
        guard let rir = last.rir ?? after.lastRIR[item.id.uuidString] else { return "余力未知，先保留起点待校准" }
        if rir <= 1 { return "接近力竭，下次优先降档校准" }
        if last.reps < (item.plannedSets.last?.prescription?.repsLower ?? item.plannedSets.last?.reps ?? 1) {
            return "仍有余力，先调整可执行次数区间"
        }
        if rir >= 5 { return "末组余力较多，先校准强度" }
        return "维持起点，验证全部工作组达标"
    }

    static func makeDraft(sessionID: UUID, date: Date? = nil, now: Date = .now,
                          in context: ModelContext) throws -> CoachDraft {
        let source = try review(sessionID: sessionID, preferenceDate: date ?? now, now: now, in: context)
        guard !source.preferenceCode.isEmpty else { throw TrainingCoachError.invalid("生效训练偏好缺失，先核对偏好，不能用旧版本猜补。") }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let preference = try TrainingPreferenceService.current(in: context, on: date ?? now)?.snapshot
        let items: [CoachPlanItem] = try source.observations.map { observed in
            guard let exercise = catalog.first(where: { $0.id == observed.exerciseID }), !exercise.isArchived,
                  exercise.volumeUnit == observed.unit else { throw TrainingCoachError.invalid("动作已归档、缺失或单位变化：\(observed.name)") }
            var plans = observed.plannedSets
            guard !plans.isEmpty else { throw TrainingCoachError.invalid("\(observed.name)缺少原始处方，请先手动安排并核对。") }
            let minimum = observed.isTechnical ? plans.count : (plans.count >= 4 ? 4 : 3)
            while plans.count < minimum { var added = plans.last!; added.id = UUID(); plans.append(added) }
            let supplement = source.after.lastRIR[observed.id.uuidString]
            let last = observed.working.last
            let sameEquipment = !observed.equipment.isEmpty && observed.equipment == exercise.equipment
            let sourceDate = TrainingLocalDate.date(source.localDay, timeZone: .current) ?? .distantPast
            let recentSource = (date ?? now).timeIntervalSince(sourceDate) <= 42 * 86_400
            let convention = source.after.loadConventions[observed.id.uuidString] ?? observed.loadGuidance
            let unitVerified = observed.unit == .bodyweight || (!convention.isEmpty && convention != "unknown")
            var reason = "沿用原处方；\(observed.working.count)条完成记录。余力或可比性不足时不自动加重。"
            if observed.isTechnical {
                reason = "技术动作单独计量，按速度和动作稳定性结束；保持原处方起点，不由高次数或其他动作推算重量。"
            }
            let machineDisplay = convention.contains("同机显示") || convention.contains("机器显示")
            let sourceCanCalibrate = observed.feelingRaw != WorkoutFeeling.painful.rawValue && !observed.isTechnical
                && observed.unit == .kilogram && recentSource && sameEquipment && unitVerified
            let patternKeys = Set(plans.map { plan in
                "\(plan.weight)|\(plan.reps)|\(plan.prescription?.repsUpper ?? plan.reps)|\(plan.prescription?.rirLower ?? -1)|\(plan.prescription?.rirUpper ?? -1)|\(plan.weightSide.rawValue)|\(plan.repsSide.rawValue)"
            })
            let pattern = observed.isTechnical ? SetPlanPattern.fixed : (preference?.defaultPattern(for: exercise) ?? .fixed)
            let uniform = pattern != .pyramidUp && patternKeys.count == 1 && !observed.working.dropLast().contains { ($0.rir ?? 10) <= 1 }
            var roleEvidence: [String] = []
            for index in plans.indices {
                plans[index].id = UUID()
                plans[index].actualDefaultPolicyRaw = WorkoutActualDefaultPolicy.blank.rawValue
                var target = plans[index].prescription ?? WorkoutSetPrescription(label: observed.isTechnical ? "技术组" : "工作组",
                    repsLower: plans[index].reps, repsUpper: max(plans[index].reps, plans[index].reps + 2),
                    rirLower: observed.isTechnical ? nil : 2, rirUpper: observed.isTechnical ? nil : 3,
                    restLowerSeconds: observed.isTechnical ? 120 : 90, restUpperSeconds: observed.isTechnical ? 180 : 120,
                    effortCue: observed.isTechnical ? "动作稳定、速度可控" : nil)
                if observed.isTechnical {
                    if target.repsUpper > 5 { target.repsLower = 3; target.repsUpper = 3 }
                    target.rirLower = nil; target.rirUpper = nil
                    if target.effortCue?.isEmpty != false { target.effortCue = "快拉稳接，降速或不稳即结束" }
                    target.restLowerSeconds = max(120, target.restLowerSeconds)
                    target.restUpperSeconds = max(180, target.restUpperSeconds)
                }
                // A later estimate describes only the last set. Distinct top/back-off roles keep their own evidence.
                let candidate = uniform ? last : (observed.working.count == observed.plannedSets.count && index < observed.working.count ? observed.working[index] : nil)
                let effort = candidate?.rir ?? (candidate?.id == last?.id ? supplement : nil)
                let reportedReps = source.after.repsSides[observed.id.uuidString] ?? .unknown
                let side = candidate?.repsSide == .unknown ? reportedReps : candidate?.repsSide ?? .unknown
                let eligible = sourceCanCalibrate && candidate?.weight != nil && side != .unknown
                    && (candidate?.weightSide != .unknown || machineDisplay)
                    && candidate?.weightSide == plans[index].weightSide && side == plans[index].repsSide
                if eligible, let weight = candidate?.weight, let reps = candidate?.reps, reps > 0, let effort {
                    if effort >= 2 {
                        plans[index].weight = weight
                        if reps < target.repsLower { target.repsLower = reps; target.repsUpper = max(reps, min(target.repsUpper, reps + 2)) }
                        let evidence = "\(uniform ? "末组" : "第\(index + 1)组")\(weight.formatted())×\(reps)，\(candidate?.rir != nil ? "App记录" : "本人随后估计")RIR约\(effort)"
                        roleEvidence.append(evidence)
                        reason = "同动作、同器械及记重口径；\(evidence)。作为下一次起点校准，不据此自动加重或判定全部组达标。"
                    } else if let lower = observed.working.compactMap(\.weight).filter({ $0 < weight }).max() {
                        plans[index].weight = min(plans[index].weight, lower)
                        roleEvidence.append("第\(index + 1)组接近力竭，参考已知较低档\(lower.formatted())校准")
                        reason = "已有组接近力竭；优先参考较低已记录档位并按目标余力校准，不追加容量。"
                    } else { reason = "已有组接近力竭但无已知邻近低档。原处方仅作参考，须在热身后选择实际可用较低档，不自动套百分比。" }
                }
                if (!recentSource && observed.unit == .kilogram) || !observed.unit.recordsNumericLoad { plans[index].weight = 0 }
                plans[index].prescription = target
                plans[index].reps = target.repsLower
            }
            if !uniform && !observed.isTechnical {
                reason = "保留顶组、回退或递增的各自目标；缺余力的组保留原处方供校准，不用末组负重覆盖全部组。" + roleEvidence.joined(separator: "；")
            }
            if observed.feelingRaw == WorkoutFeeling.painful.rawValue {
                reason += " 上次动作已标记不适，负重仅作参考；先核实动作与热身反应，出现不适即省去受影响动作，不补课。"
            }
            if !recentSource { reason = "本次记录超出42天自动负荷窗口，组次仅作参考；工作重量留待热身及实机档位校准，不套用旧公斤数。" }
            if let previous = observed.previous.first, let peak = previous.actual.last {
                reason += " 可比历史\(previous.localDay)：末组\(peak.weight?.formatted() ?? "未知")×\(peak.reps)，\((peak.rir ?? previous.supplementaryLastRIR).map { "余力约\($0)" } ?? "余力未知")。"
            } else { reason += " 近42天未取得可直接比较的同器械、单位及侧别场次。" }
            if source.morning.sleep == "poor" { reason += " 训练后当晚睡眠较差，下次以热身状态和目标余力校准，不追加容量。" }
            if pattern == .pyramidUp {
                reason += " 新建默认递增金字塔；每组分别核对可比实际与余力，缺项保留原候选待校准，不按固定步长生成器械重量。"
            }
            let guidance = observed.unit == .bodyweight ? "自重" : (convention.isEmpty ? "待核对记重口径；不换算总重" : convention)
            let warmup = "先用空杆、自重或器械最低可用档试3–5次，再按实际档位递增至工作起点；热身另计，不为估余力做力竭测试。"
            let adjustment = observed.isTechnical ? "降速、接杠失稳或不适时降低可用档位；仍不稳即停止。" : "首组达到目标余力即结束；不足次数下限或过早接近力竭时降低邻近档。明显不适、代偿或异常疲劳时停止受影响动作；本次不补组。"
            return CoachPlanItem(exercise: ConfirmedDailyPlanExercise(catalogExerciseID: exercise.id, catalogName: exercise.name,
                equipment: exercise.equipment, volumeUnit: observed.unit, displayName: observed.name,
                loadGuidance: guidance, notes: [reason, warmup, adjustment, observed.notes].joined(separator: "\n"), plannedSets: plans, planPattern: pattern),
                reason: reason, warmup: warmup, adjustment: adjustment, unitVerified: observed.unit == .bodyweight || (unitVerified && sameEquipment),
                technical: observed.isTechnical, minimumSets: observed.isTechnical ? 0 : minimum)
        }
        guard !items.isEmpty else { throw TrainingCoachError.invalid("没有可编排动作；请使用当天菜单手动安排。") }
        let previous = try latestDraft(rows: source.records)
        var draft = CoachDraft(id: UUID(), sessionID: sessionID, revision: (previous?.revision ?? 0) + 1,
            sourceFingerprint: source.sourceFingerprint, preferenceCode: source.preferenceCode,
            localDay: date.map { TrainingLocalDate.key($0) }, title: source.name, items: items, coverage: source.coverage,
            method: "APP-COACH-2")
        let cancelledDrafts = Set(try confirmations(rows: source.records).filter { isCancelled($0, rows: source.records) }.map { $0.draft.id })
        if let previous, previous.sourceFingerprint == draft.sourceFingerprint, previous.localDay == draft.localDay, !cancelledDrafts.contains(previous.id) {
            return previous
        }
        draft.changeReason = "依据本次实际、已保存反馈与生效偏好形成；草案需完整确认。"
        try append(draft, kind: "draft", sessionID: sessionID, id: draft.id, in: context)
        return draft
    }

    static func revise(_ proposed: CoachDraft, in context: ModelContext) throws -> CoachDraft {
        let source = try review(sessionID: proposed.sessionID,
            preferenceDate: proposed.localDay.flatMap { TrainingLocalDate.date($0, timeZone: .current) } ?? .now, in: context)
        guard source.sourceFingerprint == proposed.sourceFingerprint else { throw TrainingCoachError.invalid("实际、反馈或偏好已变化，请根据新来源重新生成草案。") }
        let previous = try latestDraft(rows: source.records)
        var draft = proposed
        draft.id = UUID(); draft.revision = (previous?.revision ?? 0) + 1
        draft.changeReason = "本人在App修订完整草案；本次变化只属于新版本。"
        for index in draft.items.indices where !draft.items[index].exceptionReason.isEmpty {
            let note = "本次减量说明：" + draft.items[index].exceptionReason
            if !draft.items[index].exercise.notes.contains(note) { draft.items[index].exercise.notes += "\n" + note }
        }
        try append(draft, kind: "draft", sessionID: draft.sessionID, id: draft.id, in: context)
        return draft
    }

    static func blockingReasons(_ draft: CoachDraft, now: Date = .now, in context: ModelContext) throws -> [String] {
        let date = draft.localDay.flatMap { TrainingLocalDate.date($0, timeZone: .current) }
        let fresh = try review(sessionID: draft.sessionID, preferenceDate: date ?? now, now: now, in: context)
        var issues: [String] = []
        if try latestDraft(rows: fresh.records) != draft { issues.append("草案已有新的版本，请审阅最新完整计划") }
        if fresh.sourceFingerprint != draft.sourceFingerprint { issues.append("实际、反馈、动作或偏好已变化，请生成并审阅新版本") }
        if !fresh.morning.supportsNormalDose { issues.append("次晨恢复未补足或需要核实，正常剂量暂缓确认") }
        if draft.items.contains(where: { !$0.technical && $0.exercise.plannedSets.count < $0.minimumSets && $0.exceptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("低于正常组数的动作需要明确减量原因")
        }
        if draft.items.contains(where: { !$0.unitVerified }) { issues.append("有动作的器械或记重口径待核对") }
        for item in draft.items where item.technical {
            if let observed = fresh.observations.first(where: { $0.exerciseID == item.id }),
               fresh.after.quality[observed.id.uuidString] != "stable" {
                issues.append("技术动作质量尚未确认稳定：\(item.exercise.displayName)")
            }
        }
        if let day = draft.localDay {
            if day <= fresh.localDay || day < TrainingLocalDate.key(now) { issues.append("请选择本次训练之后且未过去的日期") }
        } else { issues.append("请明确选择训练日期") }
        if draft.items.contains(where: { $0.exercise.plannedSets.isEmpty || $0.exercise.plannedSets.contains { $0.prescription?.isValid != true } }) {
            issues.append("组次、余力或休息范围不完整")
        }
        return issues
    }

    static func prepareConfirmation(_ draft: CoachDraft, now: Date = .now,
                                    in context: ModelContext) throws -> CoachConfirmation {
        let issues = try blockingReasons(draft, now: now, in: context)
        guard issues.isEmpty, let day = draft.localDay else { throw TrainingCoachError.invalid(issues.joined(separator: "；")) }
        let rows = try records(sessionID: draft.sessionID, in: context)
        // A draft has one stable request identity. Unknown saves must be reconciled first.
        if let existing = try confirmations(rows: rows).last(where: { $0.draft.id == draft.id }) { return existing }
        let pending = try confirmations(rows: rows).filter { try !hasReceipt($0, rows: rows) && !isCancelled($0, rows: rows) }
        guard pending.isEmpty else { throw TrainingCoachError.invalid("已有确认版本等待核对，先检查原请求的保存结果。") }
        let source = try encode(draft)
        let packet = ConfirmedDailyTrainingPlanPacket(version: 1, id: draft.id, localDay: day,
            timeZoneIdentifier: TimeZone.current.identifier, title: draft.title,
            preferenceRevisionCode: draft.preferenceCode, confirmedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
            confirmationReference: "App完整计划确认 · \(draft.id) · V\(draft.revision)", sourceMarkdown: source,
            sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
            guidance: "热身另计；实际留空；按本版目标校准，不为补量缩短休息；疼痛或技术失稳时停止受影响动作。",
            exercises: draft.items.map(\.exercise))
        let preview = try ConfirmedDailyTrainingPlanService.preview(packet, in: context)
        guard preview.conflicts.isEmpty else { throw TrainingCoachError.invalid(preview.conflicts.joined(separator: "；")) }
        return CoachConfirmation(id: UUID(), draft: draft, preview: preview)
    }

    static func confirm(_ confirmation: CoachConfirmation, now: Date = .now, in context: ModelContext) throws -> CoachSavedReceipt {
        let rows = try records(sessionID: confirmation.draft.sessionID, in: context)
        if let receipt = try reconcile(confirmation, in: context) { return receipt }
        guard !isCancelled(confirmation, rows: rows) else { throw TrainingCoachError.invalid("该未保存请求已取消，请审阅新版本后重新确认。") }
        let issues = try blockingReasons(confirmation.draft, now: now, in: context)
        guard issues.isEmpty else { throw TrainingCoachError.invalid(issues.joined(separator: "；")) }
        if !rows.contains(where: { $0.id == confirmation.id && $0.kind == "confirmation" }) {
            try append(confirmation, kind: "confirmation", sessionID: confirmation.draft.sessionID, id: confirmation.id, in: context)
        }
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: confirmation.preview, in: context)
        guard let receipt = try reconcile(confirmation, in: context) else {
            throw TrainingCoachError.invalid("已提交确认，但保存结果待核对；请检查同一请求，不重复创建。")
        }
        return receipt
    }

    static func reconcile(_ confirmation: CoachConfirmation, in context: ModelContext) throws -> CoachSavedReceipt? {
        // A fresh context must independently observe the committed schedule.
        let verification = ModelContext(context.container)
        guard let readback = try ConfirmedDailyTrainingPlanService.readback(id: confirmation.preview.packet.id, in: verification) else { return nil }
        guard readback.packetSHA256 == confirmation.preview.packetSHA256 else { throw TrainingCoachError.invalid("原请求内容不一致，停止重复保存。") }
        let receipt = CoachSavedReceipt(confirmationID: confirmation.id, scheduleID: readback.schedule.id, packetSHA256: readback.packetSHA256)
        let rows = try records(sessionID: confirmation.draft.sessionID, in: context)
        if try !hasReceipt(confirmation, rows: rows) {
            try append(receipt, kind: "receipt", sessionID: confirmation.draft.sessionID, in: context)
        }
        return receipt
    }
}

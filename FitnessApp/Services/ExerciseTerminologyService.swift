import Foundation
import SwiftData

struct ExerciseTerminologyCandidate: Equatable, Sendable {
    let rawNames: [String]
    let canonicalID: String
    let standardNameZH: String
    let standardNameEN: String
    let reviewStatus: ExerciseTerminologyReviewStatus
    let confidence: ExerciseTerminologyConfidence
    let mergeGroup: String?
    let reviewNote: String
}

struct ExerciseTerminologyCheckInput: Codable, Equatable, Sendable {
    let rawName: String
    let muscleGroup: String
    let equipment: String
    let locale: String
}

struct ExerciseTerminologyCheckResponse: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let canonicalID: String?
    let standardNameZH: String?
    let standardNameEN: String?
    let reviewStatusRaw: String
    let confidenceRaw: String
    let ambiguity: String
    let evidenceLabels: [String]
}

private struct ExerciseTerminologyCheckRequest: Encodable {
    let schemaVersion: Int
    let rawName: String
    let muscleGroup: String
    let equipment: String
    let locale: String
    let providerPreference: String
}

enum ExerciseTerminologyAPIError: LocalizedError, Equatable {
    case insecureEndpoint
    case invalidResponse
    case unsupportedSchema
    case invalidCandidate
    case inconsistentMergeGroup

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            return "动作术语代理必须使用 HTTPS；API Key 不应保存在 App 内。"
        case .invalidResponse:
            return "术语代理没有返回有效的 HTTP 响应。"
        case .unsupportedSchema:
            return "术语代理返回了当前 X-Fit 不支持的结构版本。"
        case .invalidCandidate:
            return "术语代理返回的候选缺少审核状态、置信度或双语名称。"
        case .inconsistentMergeGroup:
            return "同组动作的标准身份、训练属性或审核元数据不一致，已取消整组审核。"
        }
    }
}

/// Provider-agnostic proxy client. The proxy may call DeepSeek or another LLM,
/// but no provider secret is embedded in the iPhone app.
struct ExerciseTerminologyAPIClient {
    static let schemaVersion = 1

    static func makeRequest(endpoint: URL, input: ExerciseTerminologyCheckInput) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw ExerciseTerminologyAPIError.insecureEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("x-fit-exercise-terminology-v1", forHTTPHeaderField: "X-XFit-Contract")
        request.httpBody = try JSONEncoder().encode(
            ExerciseTerminologyCheckRequest(
                schemaVersion: schemaVersion,
                rawName: input.rawName,
                muscleGroup: input.muscleGroup,
                equipment: input.equipment,
                locale: input.locale,
                providerPreference: "deepseek"
            )
        )
        return request
    }

    static func validate(_ response: ExerciseTerminologyCheckResponse) throws {
        guard response.schemaVersion == schemaVersion else {
            throw ExerciseTerminologyAPIError.unsupportedSchema
        }
        guard ExerciseTerminologyReviewStatus(rawValue: response.reviewStatusRaw) != nil,
              ExerciseTerminologyConfidence(rawValue: response.confidenceRaw) != nil else {
            throw ExerciseTerminologyAPIError.invalidCandidate
        }
        if response.reviewStatusRaw != ExerciseTerminologyReviewStatus.unresolved.rawValue {
            guard let canonicalID = response.canonicalID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !canonicalID.isEmpty,
                  let standardNameZH = response.standardNameZH?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !standardNameZH.isEmpty,
                  let standardNameEN = response.standardNameEN?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !standardNameEN.isEmpty else {
                throw ExerciseTerminologyAPIError.invalidCandidate
            }
        }
    }
}

enum ExerciseTerminologyService {
    static let catalogVersion = "xfit-terminology-2026-09-27-v2"

    static let catalog: [ExerciseTerminologyCandidate] = [
        candidate(["MTS 下斜卧推"], "hammer_strength_mts_iso_lateral_decline_press", "Hammer Strength MTS Iso-Lateral 下斜推胸", "Hammer Strength MTS Iso-Lateral Decline Press", .approvalReady, .high, note: "品牌和系列不可丢失。"),
        candidate(["MTS 划船"], "hammer_strength_mts_iso_lateral_row", "Hammer Strength MTS Iso-Lateral 划船", "Hammer Strength MTS Iso-Lateral Row", .approvalReady, .high, note: "不能仅凭名称改成 High Row。"),
        candidate(["V 型深蹲"], "machine_v_squat", "V 型深蹲机", "V-Squat Machine", .approvalReady, .high, note: "与哈克深蹲、钟摆深蹲分开。"),
        candidate(["三头下压", "绳索下压"], "cable_triceps_pushdown", "绳索三头肌下压", "Cable Triceps Pushdown", .mergeReview, .high, mergeGroup: "merge_cable_triceps_pushdown", note: "需确认把手附件与重量口径一致；确认前不共享 PR。"),
        candidate(["三头下压机", "seated dip", "坐姿器械臂屈伸"], "machine_triceps_press", "坐姿器械臂屈伸", "Seated Dip", .approvalReady, .high, note: "用户确认的坐姿器械臂屈伸；旧名称保留为别名，与绳索三头下压分开。"),
        candidate(["三角肌训练机"], "machine_deltoid_unverified", "三角肌训练机（待确认）", "Deltoid Machine (Unverified)", .unresolved, .low, note: "可能是侧平举机、反向蝴蝶机或肩推机。"),
        candidate(["上斜卧推"], "incline_barbell_bench_press", "上斜杠铃卧推", "Incline Barbell Bench Press", .approvalReady, .high),
        candidate(["上斜哑铃卧推"], "incline_dumbbell_bench_press", "上斜哑铃卧推", "Incline Dumbbell Bench Press", .approvalReady, .high, note: "长凳角度宜另存属性。"),
        candidate(["上背下拉机"], "machine_upper_back_pulldown_unverified", "上背下拉机（待确认）", "Upper-Back Pulldown Machine (Unverified)", .unresolved, .low, note: "需器械铭牌或照片；可能是 Front Pulldown 或 High Row。"),
        candidate(["上背划船机"], "machine_upper_back_row_unverified", "上背划船机（待确认）", "Upper-Back Row Machine (Unverified)", .unresolved, .low, note: "水平划船、高位划船和胸托划船路径不同。"),
        candidate(["严格深蹲"], "barbell_back_squat", "杠铃深蹲", "Barbell Squat", .variantReview, .medium, note: "已确认与“深蹲”是同一动作；仍需补充前/后蹲及高杠/低杠变式。"),
        candidate(["举腿"], "bodyweight_leg_raise", "举腿", "Leg Raise", .variantReview, .medium, note: "需确认悬垂、仰卧或双杠支撑。"),
        candidate(["单腿钟摆推举"], "machine_single_leg_pendulum_unverified", "单腿钟摆式腿推/深蹲（待确认）", "Single-Leg Pendulum Press/Squat (Unverified)", .unresolved, .low, note: "无法判断是 Pendulum Squat 还是 Pendulum Leg Press。"),
        candidate(["史密斯上斜卧推"], "smith_machine_incline_bench_press", "史密斯机上斜卧推", "Smith Machine Incline Bench Press", .approvalReady, .high),
        candidate(["史密斯卧推"], "smith_machine_bench_press", "史密斯机平板卧推", "Smith Machine Bench Press", .approvalReady, .high),
        candidate(["史密斯肩推"], "smith_machine_shoulder_press", "史密斯机肩上推举", "Smith Machine Shoulder Press", .approvalReady, .high, note: "坐姿或站姿宜另存属性。"),
        candidate(["哑铃侧平举"], "dumbbell_lateral_raise", "哑铃侧平举", "Dumbbell Lateral Raise", .approvalReady, .high),
        candidate(["哑铃弯举"], "dumbbell_biceps_curl", "哑铃二头肌弯举", "Dumbbell Biceps Curl", .approvalReady, .high, note: "同步、交替和握法宜另存属性。"),
        candidate(["哑铃行走弓步"], "dumbbell_walking_lunge", "哑铃行走弓步", "Dumbbell Walking Lunge", .approvalReady, .high),
        candidate(["器械上斜卧推", "坐姿上斜推胸机"], "machine_incline_chest_press", "坐姿上斜推胸机", "Incline Chest Press Machine", .mergeReview, .high, mergeGroup: "merge_machine_incline_chest_press", note: "需确认是同一器械与负重口径；片载式和配重片式不能直接比较。"),
        candidate(["器械下斜卧推", "坐姿下斜推胸机"], "machine_decline_chest_press", "坐姿下斜推胸机", "Decline Chest Press Machine", .mergeReview, .high, mergeGroup: "merge_machine_decline_chest_press", note: "需确认是同一器械与负重口径。"),
        candidate(["器械肩推"], "machine_shoulder_press", "器械肩上推举", "Shoulder Press Machine", .approvalReady, .high, note: "握法和轨迹宜另存属性。"),
        candidate(["坐姿划船"], "machine_seated_row", "坐姿器械划船", "Seated Row Machine", .variantReview, .medium, note: "需确认绳索、片载式或固定轨迹。"),
        candidate(["坐姿哑铃侧平举"], "seated_dumbbell_lateral_raise", "坐姿哑铃侧平举", "Seated Dumbbell Lateral Raise", .approvalReady, .high, note: "不与站姿版本合并历史。"),
        candidate(["坐姿推举", "坐姿肩推"], "seated_dumbbell_shoulder_press", "坐姿哑铃肩上推举", "Seated Dumbbell Shoulder Press", .mergeReview, .high, mergeGroup: "merge_seated_dumbbell_shoulder_press", note: "需确认动作方式与哑铃重量口径一致。"),
        candidate(["坐姿推胸机"], "machine_seated_chest_press", "坐姿推胸机", "Seated Chest Press Machine", .approvalReady, .high, note: "默认水平推胸；轨迹宜另存属性。"),
        candidate(["坐姿飞鸟"], "machine_pec_deck_fly", "坐姿器械夹胸（蝴蝶机飞鸟）", "Pec Deck Fly", .approvalReady, .high, note: "历史肌群为胸部，因此不按反向飞鸟处理。"),
        candidate(["引体向上"], "bodyweight_pull_up", "引体向上", "Pull-Up", .variantReview, .medium, note: "需确认握向、握距及是否负重。"),
        candidate(["杠铃划船"], "barbell_bent_over_row", "杠铃俯身划船", "Barbell Bent-Over Row", .approvalReady, .high, note: "躯干角度和正反握宜另存属性。"),
        candidate(["杠铃卧推"], "barbell_bench_press", "杠铃平板卧推", "Barbell Bench Press", .approvalReady, .high),
        candidate(["深蹲"], "barbell_back_squat", "杠铃深蹲", "Barbell Squat", .variantReview, .medium, note: "已确认“严格深蹲”是同一动作；仍需确认前/后蹲及高杠/低杠。"),
        candidate(["火箭推"], "barbell_thruster_unverified", "杠铃火箭推（疑似前蹲推举）", "Barbell Thruster (Unverified)", .unresolved, .low, note: "很可能是 Thruster，但仅凭俗称不能唯一确认。"),
        candidate(["窄握下拉"], "close_grip_lat_pulldown", "窄握高位下拉", "Close-Grip Lat Pulldown", .variantReview, .medium, note: "需确认正握、反握或 V 把中立握。"),
        candidate(["站姿哑铃肩推"], "standing_dumbbell_shoulder_press", "站姿哑铃肩上推举", "Standing Dumbbell Shoulder Press", .approvalReady, .high),
        candidate(["站姿提踵"], "machine_standing_calf_raise", "器械站姿提踵", "Standing Calf Raise Machine", .approvalReady, .high, note: "负重口径宜另存属性。"),
        candidate(["站姿绳索夹胸", "绳索夹胸"], "standing_cable_chest_fly", "站姿绳索夹胸", "Standing Cable Chest Fly", .mergeReview, .high, mergeGroup: "merge_standing_cable_chest_fly", note: "需确认姿势、滑轮高度与重量口径一致。"),
        candidate(["站姿髋推"], "machine_standing_hip_thrust_unverified", "站姿髋推机（待确认）", "Standing Hip Thrust Machine (Unverified)", .unresolved, .low, note: "可能是站姿髋伸展、髋推机或后踢腿机。"),
        candidate(["绳索侧平举"], "cable_lateral_raise", "绳索侧平举", "Cable Lateral Raise", .approvalReady, .high, note: "单臂或双臂宜另存属性。"),
        candidate(["绳索卷腹"], "cable_crunch", "绳索卷腹", "Cable Crunch", .approvalReady, .high, note: "跪姿或站姿宜另存属性。"),
        candidate(["绳索反向飞鸟"], "cable_rear_delt_fly", "绳索反向飞鸟（后三角肌飞鸟）", "Cable Rear Delt Fly", .approvalReady, .high),
        candidate(["绳索躯干旋转"], "cable_trunk_rotation", "绳索躯干旋转", "Cable Trunk Rotation", .variantReview, .medium, note: "需确认水平旋转或高到低/低到高 Wood Chop。"),
        candidate(["罗马尼亚硬拉"], "barbell_romanian_deadlift", "杠铃罗马尼亚硬拉", "Barbell Romanian Deadlift", .approvalReady, .high),
        candidate(["腿举"], "machine_leg_press", "器械腿举", "Leg Press Machine", .variantReview, .medium, note: "需确认 45°、水平、坐姿、垂直或单腿。"),
        candidate(["腿弯举"], "machine_leg_curl", "器械腿弯举", "Leg Curl Machine", .variantReview, .medium, note: "需确认坐姿、俯卧或站姿。"),
        candidate(["臀推"], "barbell_hip_thrust", "杠铃臀推", "Barbell Hip Thrust", .approvalReady, .high),
        candidate(["钟摆深蹲"], "machine_pendulum_squat", "钟摆深蹲机", "Pendulum Squat Machine", .approvalReady, .high, note: "不与 V 型深蹲合并。"),
        candidate(["面拉"], "cable_face_pull", "绳索面拉", "Cable Face Pull", .approvalReady, .high, note: "把手附件宜另存属性。"),
        candidate(["颈后下拉"], "behind_neck_lat_pulldown", "颈后高位下拉", "Behind-the-Neck Lat Pulldown", .approvalReady, .high, note: "独立动作，不作为普通高位下拉别名。"),
        candidate(["高位下拉"], "lat_pulldown", "高位下拉", "Lat Pulldown", .approvalReady, .high, note: "握距和握向当前未知。"),
        candidate(["高翻"], "barbell_power_clean", "杠铃力量翻", "Barbell Power Clean", .variantReview, .medium, note: "需确认从地面或悬垂起始以及接杠高度。")
    ]

    static func candidate(for rawName: String) -> ExerciseTerminologyCandidate? {
        catalogByNormalizedName[normalized(rawName)]
    }

    private static let catalogByNormalizedName: [String: ExerciseTerminologyCandidate] = {
        var index: [String: ExerciseTerminologyCandidate] = [:]
        for item in catalog {
            for name in item.rawNames + [item.standardNameZH, item.standardNameEN] {
                index[normalized(name)] = item
            }
        }
        return index
    }()

    @MainActor
    static func stageCatalogCandidates(in context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var changed = false
        for exercise in exercises {
            changed = stageCandidate(for: exercise) || changed
        }
        if changed {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    @discardableResult
    static func stageCandidate(for exercise: Exercise) -> Bool {
        guard exercise.terminologyDecision == .pending else { return false }
        let match = candidate(for: exercise.name)
        let nextCanonicalID = match?.canonicalID
        let nextZH = match?.standardNameZH ?? exercise.name
        let nextEN = match?.standardNameEN ?? ""
        let nextStatus = match?.reviewStatus ?? .unresolved
        let nextConfidence = match?.confidence ?? .low
        let nextMergeGroup = match?.mergeGroup
        let nextNote = match?.reviewNote ?? "本地候选库没有匹配项；可通过受控 AI 代理生成候选后再人工审核。"

        let changed = exercise.terminologyCanonicalID != nextCanonicalID
            || exercise.terminologyStandardNameZH != nextZH
            || exercise.terminologyStandardNameEN != nextEN
            || exercise.terminologyReviewStatus != nextStatus
            || exercise.terminologyConfidence != nextConfidence
            || exercise.terminologyMergeGroup != nextMergeGroup
            || exercise.terminologyReviewNote != nextNote
            || exercise.terminologyCatalogVersion != catalogVersion

        guard changed else { return false }
        exercise.terminologyCanonicalID = nextCanonicalID
        exercise.terminologyStandardNameZH = nextZH
        exercise.terminologyStandardNameEN = nextEN
        exercise.terminologyReviewStatus = nextStatus
        exercise.terminologyConfidence = nextConfidence
        exercise.terminologyMergeGroup = nextMergeGroup
        exercise.terminologyReviewNote = nextNote
        exercise.terminologyCatalogVersion = catalogVersion
        return true
    }

    @MainActor
    static func accept(
        _ exercise: Exercise,
        among exercises: [Exercise],
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let targets = reviewTargets(for: exercise, among: exercises)
        try validateAcceptableTargets(targets)
        try persistDecision(.accepted, for: targets, in: context, save: save)
    }

    @MainActor
    static func reject(
        _ exercise: Exercise,
        among exercises: [Exercise],
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try persistDecision(
            .rejected,
            for: reviewTargets(for: exercise, among: exercises),
            in: context,
            save: save
        )
    }

    @MainActor
    static func reset(
        _ exercise: Exercise,
        among exercises: [Exercise],
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try persistDecision(
            .pending,
            for: reviewTargets(for: exercise, among: exercises),
            in: context,
            save: save
        )
    }

    static func canonicalIdentityKey(for exercise: Exercise) -> String? {
        guard let value = exercise.approvedCanonicalID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func reviewTargets(for exercise: Exercise, among exercises: [Exercise]) -> [Exercise] {
        guard let mergeGroup = exercise.terminologyMergeGroup, !mergeGroup.isEmpty else {
            return [exercise]
        }
        let grouped = exercises.filter { $0.terminologyMergeGroup == mergeGroup }
        return grouped.isEmpty ? [exercise] : grouped
    }

    private static func validateAcceptableTargets(_ targets: [Exercise]) throws {
        guard !targets.isEmpty,
              targets.allSatisfy({ target in
                  !normalized(target.terminologyCanonicalID.orEmpty).isEmpty
                      && !normalized(target.terminologyStandardNameZH.orEmpty).isEmpty
                      && !normalized(target.terminologyStandardNameEN.orEmpty).isEmpty
                      && target.terminologyReviewStatus != nil
                      && target.terminologyReviewStatus != .unresolved
                      && target.terminologyConfidence != nil
              }) else {
            throw ExerciseTerminologyAPIError.invalidCandidate
        }

        guard targets.count > 1 else { return }
        let first = targets[0]
        let isCoherent = targets.dropFirst().allSatisfy { target in
            normalized(target.terminologyCanonicalID.orEmpty)
                == normalized(first.terminologyCanonicalID.orEmpty)
                && normalized(target.terminologyStandardNameZH.orEmpty)
                    == normalized(first.terminologyStandardNameZH.orEmpty)
                && normalized(target.terminologyStandardNameEN.orEmpty)
                    == normalized(first.terminologyStandardNameEN.orEmpty)
                && normalized(target.muscleGroup) == normalized(first.muscleGroup)
                && normalized(target.equipment) == normalized(first.equipment)
                && target.volumeUnit == first.volumeUnit
                && target.terminologyReviewStatus == first.terminologyReviewStatus
                && target.terminologyConfidence == first.terminologyConfidence
        }
        guard isCoherent else {
            throw ExerciseTerminologyAPIError.inconsistentMergeGroup
        }
    }

    @MainActor
    private static func persistDecision(
        _ decision: ExerciseTerminologyDecision,
        for targets: [Exercise],
        in context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws {
        let reviewedAt = decision == .pending ? nil : Date.now
        for target in targets {
            target.terminologyDecision = decision
            target.terminologyReviewedAt = reviewedAt
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN"))
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func candidate(
        _ rawNames: [String],
        _ canonicalID: String,
        _ standardNameZH: String,
        _ standardNameEN: String,
        _ reviewStatus: ExerciseTerminologyReviewStatus,
        _ confidence: ExerciseTerminologyConfidence,
        mergeGroup: String? = nil,
        note: String = "候选名称仍需用户批准；不会自动改写历史快照。"
    ) -> ExerciseTerminologyCandidate {
        ExerciseTerminologyCandidate(
            rawNames: rawNames,
            canonicalID: canonicalID,
            standardNameZH: standardNameZH,
            standardNameEN: standardNameEN,
            reviewStatus: reviewStatus,
            confidence: confidence,
            mergeGroup: mergeGroup,
            reviewNote: note
        )
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

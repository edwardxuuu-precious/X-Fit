import Foundation
import SwiftData

enum ExerciseCatalogSaveKind: Equatable {
    case created
    case updated
    case reused
    case restored
}

/// Native search input keeps marked text local; only settled queries reach the
/// catalog. A monotonic timestamp makes the 300 ms policy independently testable.
struct ExerciseSearchInputState {
    private var text: String
    private var publishedQuery: String
    private var isComposing = false
    private var changedAt: TimeInterval = 0

    init(initialQuery: String) {
        text = initialQuery
        publishedQuery = initialQuery
    }

    mutating func receive(_ value: String, isComposing: Bool, at time: TimeInterval) {
        text = value
        self.isComposing = isComposing
        changedAt = time
    }

    mutating func publishIfReady(at time: TimeInterval, force: Bool = false) -> String? {
        guard !isComposing, text != publishedQuery,
              force || time - changedAt >= 0.3 else { return nil }
        publishedQuery = text
        return text
    }
}

struct ExerciseCatalogSaveResult {
    let exercise: Exercise
    let kind: ExerciseCatalogSaveKind
}

enum ExerciseCatalogError: LocalizedError, Equatable {
    case missingName
    case missingMuscleGroup
    case missingEquipment
    case invalidReferenceURL
    case notesTooLong
    case duplicateName
    case conflictingIdentity

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "请输入动作名称。"
        case .missingMuscleGroup:
            return "请输入目标肌群。"
        case .missingEquipment:
            return "请输入所需器械。"
        case .invalidReferenceURL:
            return "参考链接需要是有效的 http 或 https 地址。"
        case .notesTooLong:
            return "动作注意事项最多 40 个字，请只保留最重要的一到两点。"
        case .duplicateName:
            return "动作库中已经存在同名动作。"
        case .conflictingIdentity:
            return "动作库中存在同名但肌群、器械或计量单位不同的动作，请先改名或审核动作身份。"
        }
    }
}

enum ExerciseCatalogService {
    struct NotesCatalogSupplementEntry {
        let id: UUID
        let name: String
        let muscleGroup: String
        let equipment: String
        let unit: ExerciseVolumeUnit
    }

    struct NotesCatalogSupplementResult {
        let createdIDs: [UUID]
        let conflictingNames: [String]
    }

    /// Owner-confirmed catalog-only supplement, REQ-20261021-103533.
    /// Stable identities make retries safe even after the owner renames/archives an item.
    /// No completed session, planned workout, set log or existing catalog field is changed.
    static let notesSupplementEntries: [NotesCatalogSupplementEntry] = [
        .init(id: UUID(uuidString: "E2A9B2AC-B8C0-50D0-8431-F6076AE100DC")!, name: "杠铃片胸前转体", muscleGroup: "核心", equipment: "杠铃片", unit: .kilogram),
        .init(id: UUID(uuidString: "127E006F-F93E-5BD0-AD26-BE083009E305")!, name: "杠铃片过头提膝行进", muscleGroup: "核心", equipment: "杠铃片", unit: .kilogram),
        .init(id: UUID(uuidString: "22A76B09-D7F7-59E4-B23A-406B7F0ECC4D")!, name: "垫高绳索站姿侧屈", muscleGroup: "核心", equipment: "龙门架", unit: .kilogram),
        .init(id: UUID(uuidString: "5C52DA81-1416-5684-A5A0-0D45AE4E6980")!, name: "杠铃片交替曲髋绕颈（单边）", muscleGroup: "核心", equipment: "杠铃片", unit: .kilogram),
        .init(id: UUID(uuidString: "6E4B410E-45A2-5FC3-BDC8-0FD0717846A8")!, name: "杠铃片铰链曲髋转体（单边）", muscleGroup: "核心", equipment: "杠铃片", unit: .kilogram),
        .init(id: UUID(uuidString: "E2E25B0E-FF79-5645-A14B-C2786E494305")!, name: "杠铃片过头侧屈（单边）", muscleGroup: "核心", equipment: "杠铃片", unit: .kilogram),
        .init(id: UUID(uuidString: "7A1D53AE-AB5E-5575-95F2-68272D574DDB")!, name: "站姿绳索划船", muscleGroup: "背部", equipment: "龙门架", unit: .kilogram),
        .init(id: UUID(uuidString: "46EE66C4-50FA-5DD0-9020-CF6FFD9F2EDA")!, name: "站姿绳索下拉", muscleGroup: "背部", equipment: "龙门架", unit: .kilogram),
        .init(id: UUID(uuidString: "87270BEA-2C8B-5B64-B02E-C1C01759A0A9")!, name: "绳索跪姿卷腹", muscleGroup: "核心", equipment: "龙门架", unit: .kilogram),
        .init(id: UUID(uuidString: "747E76E2-2ABC-532A-A68F-9DA6448CC547")!, name: "平板支撑", muscleGroup: "核心", equipment: "自重", unit: .second),
        .init(id: UUID(uuidString: "A5C2FC39-AF50-5B53-881D-F57155843020")!, name: "侧平板支撑", muscleGroup: "核心", equipment: "自重", unit: .second),
        .init(id: UUID(uuidString: "BBEDB20F-F74D-5F69-BD79-34B1E49EB1CE")!, name: "开合跳", muscleGroup: "全身", equipment: "自重", unit: .count),
        .init(id: UUID(uuidString: "F16408B6-8C53-581D-AA5E-D461E5381A42")!, name: "跑步机坡度走", muscleGroup: "心肺", equipment: "跑步机", unit: .second),
        .init(id: UUID(uuidString: "7BF38382-DB2C-5564-BD4C-843F642AF0A8")!, name: "最伟大拉伸", muscleGroup: "全身", equipment: "自重", unit: .count)
    ]

    @discardableResult
    static func ensureNotesCatalogSupplement(in context: ModelContext) throws -> NotesCatalogSupplementResult {
        var catalog = try context.fetch(FetchDescriptor<Exercise>())
        var inserted: [Exercise] = []
        var conflicts: [String] = []
        for entry in notesSupplementEntries {
            // A renamed or manually archived identity belongs to the owner. Never reset it.
            if catalog.contains(where: { $0.id == entry.id }) { continue }
            if let existing = exactNameMatch(named: entry.name, in: catalog) {
                if !semanticallyCompatible(existing, muscleGroup: entry.muscleGroup,
                                           equipment: entry.equipment, volumeUnit: entry.unit) {
                    conflicts.append(entry.name)
                }
                continue
            }
            let item = Exercise(id: entry.id, name: entry.name, muscleGroup: entry.muscleGroup,
                                equipment: entry.equipment, defaultRestSeconds: 90,
                                isBuiltIn: false, notes: "Notes动作目录补齐；计重和次数口径以本次确认为准。",
                                volumeUnit: entry.unit)
            ExerciseTerminologyService.stageCandidate(for: item)
            context.insert(item)
            inserted.append(item)
            catalog.append(item)
        }
        if !inserted.isEmpty {
            do { try context.save() }
            catch {
                // Discard only this batch's inserts; do not roll back unrelated pending edits.
                for item in inserted { context.delete(item) }
                throw error
            }
        }
        return NotesCatalogSupplementResult(createdIDs: inserted.map(\.id), conflictingNames: conflicts)
    }

    /// Lexical search hints from the source Notes. These are not equivalence approvals:
    /// they never affect exactNameMatch, canonical IDs, PRs or historical ownership.
    static let notesSearchHints: [String: [String]] = [
        "杠铃片胸前转体": ["腹部杠铃片胸前转体", "杠铃片胸前转体(单边）", "杠铃片胸前转体（单边）"],
        "站姿绳索划船": ["Standing Cable Row"],
        "平板支撑": ["Plank hold"],
        "侧平板支撑": ["Side plank hold"],
        "跑步机坡度走": ["Treadmill Incline Walk", "inclined walking"],
        "双滑轮高位下拉": ["Dual Pulley Pulldown", "Dual Pulley Lat Pull down", "Dual Pulley pull down", "Dual Pulley Lat Pull"],
        "双滑轮低位划船": ["Dual Pulley Low Row", "Dual Pulley Seated Row"],
        "史密斯卧推": ["Smith Bench Press", "Bench press smith machine", "bench press smith"],
        "史密斯上斜卧推": ["Smith Inclined Bench Press", "Inclined bench press smith machine"],
        "MTS器械下斜推胸": ["MTS Declined Bench Press", "MTS Machine Declined Bench Press"],
        "绳索弯举": ["Cable arm curl", "Cable bicep curl"],
        "绳索下压": ["三头绳索下压", "Cable Triceps Pushdown"],
        "直臂下压": ["绳索直臂下压"],
        "杠铃划船": ["Barbell Row"],
        "站姿杠铃肩推": ["standing barbell shoulder press"],
        "哑铃侧平举": ["dumbbell side raise"],
        "哑铃反向飞鸟": ["dumbbell reverse fly"],
        "绳索侧平举": ["Cable Side Pull", "Cable Side Fly"],
        "绳索反向飞鸟": ["Cable Rear Pull", "Cable Rear Delt Pull", "Rear Delts Cable Pull", "Cable Reverse Fly", "Cable Reverse Pull"],
        "仰卧起坐": ["sit up"],
        "举腿": ["leg raise"],
        "引体向上": ["pullup"],
        "深蹲": ["squat", "strict form squat"],
        "罗马尼亚硬拉": ["RDL"],
        "腿举": ["Leg Press"],
        "腿弯举": ["Hamstring Curl", "Leg Curl"],
        "腿屈伸": ["器械腿屈伸"],
        "坐姿比目鱼肌等长": ["坐姿负重比目鱼肌等长保持"],
        "跳绳": ["jump rope"]
    ]

    static func search(
        _ exercises: [Exercise],
        query: String,
        excludedExerciseIDs: Set<UUID> = []
    ) -> [Exercise] {
        let normalizedQuery = normalizedSearchToken(query)

        return exercises
            .filter { exercise in
                guard !excludedExerciseIDs.contains(exercise.id) else { return false }
                if let primary = mergedPrimary(for: exercise, among: exercises),
                   excludedExerciseIDs.contains(primary.id) { return false }

                // Archived exercises stay out of the default list, but remain discoverable
                // by search so the picker can restore the original catalog item.
                guard !normalizedQuery.isEmpty else { return !exercise.isArchived }

                let terminologyCandidate = ExerciseTerminologyService.candidate(for: exercise.name)
                let searchableText = ([
                    exercise.name,
                    searchAliases(for: exercise.name).joined(separator: " "),
                    exercise.terminologyStandardNameZH ?? "",
                    exercise.terminologyStandardNameEN ?? "",
                    exercise.terminologyCanonicalID ?? "",
                    exercise.muscleGroup,
                    muscleSummary(for: exercise) ?? "",
                    exercise.equipment,
                    exercise.notes,
                    exercise.referenceURL
                ] + EquipmentCatalogService.searchTerms(for: exercise.equipment)
                  + ExternalExerciseCatalogService.searchTerms(for: exercise) + [
                    terminologyCandidate?.rawNames.joined(separator: " ") ?? "",
                    terminologyCandidate?.standardNameZH ?? "",
                    terminologyCandidate?.standardNameEN ?? "",
                    terminologyCandidate?.canonicalID ?? ""
                ])
                    .map(normalizedSearchToken)
                    .joined(separator: " ")

                return searchableText.contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.isArchived != rhs.isArchived {
                    return !lhs.isArchived
                }
                let lhsPinyin = pinyinSortKey(for: lhs.name)
                let rhsPinyin = pinyinSortKey(for: rhs.name)
                if lhsPinyin != rhsPinyin {
                    return lhsPinyin < rhsPinyin
                }

                let lhsName = normalizedSearchText(lhs.name)
                let rhsName = normalizedSearchText(rhs.name)
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func pinyinSortKey(for value: String) -> String {
        let latin = value.applyingTransform(.toLatin, reverse: false) ?? value
        let withoutTones = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return normalizedSearchToken(withoutTones)
    }

    static func exactNameMatch(
        named name: String,
        in exercises: [Exercise],
        excludingID: UUID? = nil
    ) -> Exercise? {
        let normalizedTarget = canonicalName(name)
        guard !normalizedTarget.isEmpty else { return nil }

        let matches = exercises.filter { canonicalName($0.name) == normalizedTarget }

        // A confirmed historical alias must never become a new catalog identity,
        // including when the user has manually archived the entire group.
        if let group = seatedDipGroup(named: name), let primary = preferredPrimary(in: matches, group: group) {
            return primary.id == excludingID ? nil : primary
        }

        let otherMatches = matches.filter { $0.id != excludingID }
        return otherMatches.first(where: { !$0.isArchived }) ?? otherMatches.first
    }

    static func save(
        exercise: Exercise?,
        name: String,
        muscleGroup: String,
        equipment: String,
        volumeUnit: ExerciseVolumeUnit = .kilogram,
        defaultRestSeconds: Int,
        notes: String,
        referenceURL: String,
        allExercises: [Exercise],
        in modelContext: ModelContext
    ) throws -> ExerciseCatalogSaveResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMuscleGroup = muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEquipment = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else { throw ExerciseCatalogError.missingName }
        guard !cleanMuscleGroup.isEmpty else { throw ExerciseCatalogError.missingMuscleGroup }
        guard !cleanEquipment.isEmpty else { throw ExerciseCatalogError.missingEquipment }
        guard cleanNotes.count <= 40 || cleanNotes == exercise?.notes else {
            throw ExerciseCatalogError.notesTooLong
        }
        guard let cleanReferenceURL = normalizedReferenceURL(from: referenceURL) else {
            throw ExerciseCatalogError.invalidReferenceURL
        }

        if let exercise {
            if let duplicate = exactNameMatch(named: cleanName, in: allExercises, excludingID: exercise.id) {
                if !semanticallyCompatible(
                    duplicate,
                    muscleGroup: cleanMuscleGroup,
                    equipment: cleanEquipment,
                    volumeUnit: volumeUnit
                ) {
                    throw ExerciseCatalogError.conflictingIdentity
                }
                throw ExerciseCatalogError.duplicateName
            }

            apply(
                name: cleanName,
                muscleGroup: cleanMuscleGroup,
                equipment: cleanEquipment,
                volumeUnit: volumeUnit,
                defaultRestSeconds: defaultRestSeconds,
                notes: cleanNotes,
                referenceURL: cleanReferenceURL,
                to: exercise
            )
            ExerciseTerminologyService.stageCandidate(for: exercise)
            try modelContext.save()
            return ExerciseCatalogSaveResult(exercise: exercise, kind: .updated)
        }

        if let matchingExercise = exactNameMatch(named: cleanName, in: allExercises) {
            guard semanticallyCompatible(
                matchingExercise,
                muscleGroup: cleanMuscleGroup,
                equipment: cleanEquipment,
                volumeUnit: volumeUnit
            ) else {
                throw ExerciseCatalogError.conflictingIdentity
            }
            if matchingExercise.isArchived {
                if let aliasGroup = seatedDipGroup(named: cleanName) {
                    // Creating an old alias is an explicit restore of the known
                    // identity, not permission to apply a new form's defaults.
                    updateConfirmedIdentity(matchingExercise, group: aliasGroup, isPrimary: true, isArchived: false)
                    try modelContext.save()
                    return ExerciseCatalogSaveResult(exercise: matchingExercise, kind: .restored)
                }
                apply(
                    name: cleanName,
                    muscleGroup: cleanMuscleGroup,
                    equipment: cleanEquipment,
                    volumeUnit: volumeUnit,
                    defaultRestSeconds: defaultRestSeconds,
                    notes: cleanNotes,
                    referenceURL: cleanReferenceURL,
                    to: matchingExercise
                )
                ExerciseTerminologyService.stageCandidate(for: matchingExercise)
                matchingExercise.isArchived = false
                matchingExercise.updatedAt = .now
                try modelContext.save()
                return ExerciseCatalogSaveResult(exercise: matchingExercise, kind: .restored)
            }

            if ExerciseTerminologyService.stageCandidate(for: matchingExercise) {
                try modelContext.save()
            }
            return ExerciseCatalogSaveResult(exercise: matchingExercise, kind: .reused)
        }

        let newExercise = Exercise(
            name: cleanName,
            muscleGroup: cleanMuscleGroup,
            equipment: cleanEquipment,
            defaultRestSeconds: max(0, defaultRestSeconds),
            isBuiltIn: false,
            notes: cleanNotes,
            referenceURL: cleanReferenceURL,
            volumeUnit: volumeUnit
        )
        ExerciseTerminologyService.stageCandidate(for: newExercise)
        modelContext.insert(newExercise)
        try modelContext.save()
        return ExerciseCatalogSaveResult(exercise: newExercise, kind: .created)
    }

    @discardableResult
    static func restore(_ exercise: Exercise, in modelContext: ModelContext) throws -> Exercise {
        guard exercise.isArchived else { return exercise }
        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        let target = mergedPrimary(for: exercise, among: exercises) ?? exercise
        guard target.isArchived else { return target }
        target.isArchived = false
        target.updatedAt = .now
        try modelContext.save()
        return target
    }

    /// A merged historical alias is a route to the main identity, not a second
    /// exercise to restore. Ordinary manually archived exercises still restore.
    static func mergedPrimary(for exercise: Exercise, among exercises: [Exercise]) -> Exercise? {
        guard exercise.isArchived, let canonical = exercise.approvedCanonicalID,
              let group = confirmedAliasGroups.first(where: { $0.canonicalID == canonical }) else { return nil }
        let matches = exercises.filter { $0.approvedCanonicalID == canonical }
        guard let primary = preferredPrimary(in: matches, group: group), primary.id != exercise.id else { return nil }
        return primary
    }

    /// Informational anatomy is deliberately separate from muscleGroup, which
    /// remains the primary workload/recommendation bucket in existing records.
    static func muscleSummary(for exercise: Exercise) -> String? {
        let canonical = exercise.approvedCanonicalID
            ?? ExerciseTerminologyService.candidate(for: exercise.name)?.canonicalID
        guard canonical == "machine_triceps_press" else { return nil }
        return "主要：肱三头肌 · 辅助：胸部（不重复计组）"
    }

    /// The user explicitly confirmed this one equivalence. Current plans and metrics
    /// are unified while completed session names remain untouched as historical snapshots.
    static func consolidateConfirmedSquatDuplicate(in modelContext: ModelContext) throws {
        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        let strictSquats = exercises.filter { normalizedName($0.name) == normalizedName("严格深蹲") }
        guard !strictSquats.isEmpty else { return }

        let standardSquat = exercises.first {
            normalizedName($0.name) == normalizedName("深蹲") && !$0.isArchived
        } ?? exercises.first { normalizedName($0.name) == normalizedName("深蹲") }

        guard let primary = standardSquat ?? strictSquats.first else { return }
        if normalizedName(primary.name) == normalizedName("严格深蹲") {
            primary.name = "深蹲"
            primary.isArchived = false
            primary.updatedAt = .now
        }

        let duplicates = strictSquats.filter { $0.id != primary.id }
        guard !duplicates.isEmpty else { return }
        let duplicateIDs = Set(duplicates.map(\.id))

        let templateItems = try modelContext.fetch(FetchDescriptor<TemplateExercise>())
        for item in templateItems where duplicateIDs.contains(item.exerciseID) {
            let alreadyHasPrimary = templateItems.contains {
                $0.id != item.id && $0.templateID == item.templateID && $0.exerciseID == primary.id
            }
            if alreadyHasPrimary {
                modelContext.delete(item)
            } else {
                item.exerciseID = primary.id
            }
        }

        let snapshots = try modelContext.fetch(FetchDescriptor<SessionExercise>())
        for snapshot in snapshots where duplicateIDs.contains(snapshot.exerciseID) {
            snapshot.exerciseID = primary.id
        }
        let logs = try modelContext.fetch(FetchDescriptor<SetLog>())
        for log in logs where duplicateIDs.contains(log.exerciseID) {
            log.exerciseID = primary.id
        }

        for duplicate in duplicates where !duplicate.isArchived {
            duplicate.isArchived = true
            duplicate.updatedAt = .now
        }
    }

    struct ConfirmedAliasGroup {
        let canonicalID: String
        let primaryName: String
        let aliases: [String]
    }

    static let confirmedAliasGroups: [ConfirmedAliasGroup] = [
        .init(canonicalID: "cable_triceps_pushdown", primaryName: "绳索下压", aliases: ["绳索下压", "三头下压"]),
        .init(canonicalID: "machine_incline_chest_press", primaryName: "器械上斜卧推", aliases: ["器械上斜卧推", "坐姿上斜推胸机"]),
        .init(
            canonicalID: "machine_decline_chest_press",
            primaryName: "器械下斜卧推",
            aliases: ["器械下斜卧推", "坐姿下斜推胸机", "declined bench press", "MTS 下斜卧推"]
        ),
        .init(canonicalID: "seated_dumbbell_shoulder_press", primaryName: "坐姿哑铃肩推", aliases: ["坐姿哑铃肩推", "坐姿推举", "坐姿肩推"]),
        .init(canonicalID: "standing_cable_chest_fly", primaryName: "站姿绳索夹胸", aliases: ["站姿绳索夹胸", "绳索夹胸"]),
        .init(canonicalID: "landmine_zercher_squat", primaryName: "地雷杆泽奇蹲", aliases: ["地雷杆泽奇蹲", "地雷杠泽奇蹲"]),
        .init(canonicalID: "landmine_rotation", primaryName: "地雷杆转体", aliases: ["地雷杆转体", "地雷杆转向"]),
        .init(canonicalID: "barbell_conventional_deadlift", primaryName: "传统硬拉", aliases: ["传统硬拉", "硬拉"]),
        .init(
            canonicalID: "machine_shoulder_press",
            primaryName: "器械肩推",
            aliases: ["器械肩推", "shoulder press", "side press", "三角肌训练机"]
        ),
        .init(canonicalID: "machine_pec_deck_fly", primaryName: "坐姿飞鸟", aliases: ["坐姿飞鸟", "fly"]),
        .init(canonicalID: "machine_reverse_fly", primaryName: "器械反向飞鸟", aliases: ["器械反向飞鸟", "Reverse Fly", "rear dealt"]),
        .init(canonicalID: "barbell_hip_thrust", primaryName: "杠铃臀推", aliases: ["杠铃臀推", "臀推", "顶髋"]),
        .init(canonicalID: "barbell_thruster", primaryName: "杠铃火箭推", aliases: ["杠铃火箭推", "火箭推", "半蹲上推"]),
        .init(canonicalID: "machine_triceps_press", primaryName: "坐姿器械臂屈伸", aliases: ["坐姿器械臂屈伸", "三头下压机", "seated dip"]),
        .init(canonicalID: "dumbbell_side_lunge", primaryName: "哑铃侧弓步", aliases: ["哑铃侧弓步", "哑铃侧边蹲"])
    ]

    private static let confirmedRenames: [(from: String, to: String)] = [
        (from: "地雷杠侧边蹲", to: "地雷杆侧边蹲"),
        (from: "壶铃饶颈侧拉", to: "壶铃绕颈侧拉")
    ]

    private static let confirmedArchiveNames: Set<String> = [
        "真机分享动作 20260823",
        "真机菜单动作 20260823",
        "真机训练中动作 20260823"
    ]

    /// Rewires future plan references only. Completed session snapshots keep their original
    /// names and exercise identifiers as immutable history.
    static func consolidateConfirmedAliases(in modelContext: ModelContext) throws {
        let activeSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .contains { $0.status == .inProgress }
        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        if activeSessions {
            // An unfinished workout blocks reference rewiring and new identity
            // decisions, not labels for an identity the user already confirmed.
            // Keep every archive state, plan, snapshot and actual set unchanged.
            if let group = confirmedAliasGroups.first(where: { $0.canonicalID == "machine_triceps_press" }) {
                let approved = exercises.filter { $0.approvedCanonicalID == group.canonicalID }
                if let primary = preferredPrimary(in: approved, group: group) {
                    let aliasKeys = Set(group.aliases.map(normalizedName))
                    for exercise in approved {
                        updateConfirmedIdentity(exercise, group: group,
                            isPrimary: exercise.id == primary.id && aliasKeys.contains(normalizedName(exercise.name)),
                            isArchived: exercise.isArchived)
                    }
                }
            }
            return
        }

        let templateItems = try modelContext.fetch(FetchDescriptor<TemplateExercise>())

        for group in confirmedAliasGroups {
            let aliasKeys = Set(group.aliases.map(normalizedName))
            let candidates = exercises.filter {
                $0.terminologyCanonicalID == group.canonicalID
                    || aliasKeys.contains(normalizedName($0.name))
            }
            guard let primary = preferredPrimary(in: candidates, group: group) else { continue }
            // An established identity is stronger evidence than an unreviewed
            // name collision. Leave incompatible manual records entirely alone.
            let matches = candidates.filter { candidate in
                guard primary.approvedCanonicalID == group.canonicalID,
                      candidate.approvedCanonicalID != group.canonicalID else { return true }
                return semanticallyCompatible(candidate, muscleGroup: primary.muscleGroup,
                    equipment: primary.equipment, volumeUnit: primary.volumeUnit)
            }
            let keepGroupArchived = matches.allSatisfy(\.isArchived)
            updateConfirmedIdentity(primary, group: group, isPrimary: true, isArchived: keepGroupArchived)

            let duplicateIDs = Set(matches.filter { $0.id != primary.id }.map(\.id))
            for item in templateItems where duplicateIDs.contains(item.exerciseID) {
                let alreadyHasPrimary = templateItems.contains {
                    $0.id != item.id && $0.templateID == item.templateID && $0.exerciseID == primary.id
                }
                if alreadyHasPrimary {
                    modelContext.delete(item)
                } else {
                    item.exerciseID = primary.id
                }
            }
            for duplicate in matches where duplicate.id != primary.id {
                updateConfirmedIdentity(duplicate, group: group, isPrimary: false, isArchived: true)
            }
        }

        for rename in confirmedRenames {
            let sourceKey = normalizedName(rename.from)
            for exercise in exercises where normalizedName(exercise.name) == sourceKey {
                exercise.name = rename.to
                exercise.updatedAt = .now
            }
        }

        let archiveKeys = Set(confirmedArchiveNames.map(normalizedName))
        for exercise in exercises where archiveKeys.contains(normalizedName(exercise.name)) {
            exercise.isArchived = true
            exercise.updatedAt = .now
        }
    }

    private static func preferredPrimary(in matches: [Exercise], group: ConfirmedAliasGroup) -> Exercise? {
        let approved = matches.filter { $0.approvedCanonicalID == group.canonicalID }
        let identityCandidates = approved.isEmpty ? matches : approved
        let ordered = identityCandidates.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return $0.id.uuidString < $1.id.uuidString
        }
        return ordered.first { normalizedName($0.name) == normalizedName(group.primaryName) }
            ?? ordered.first { group.canonicalID == "machine_triceps_press" && normalizedName($0.name) == normalizedName("三头下压机") }
            ?? ordered.first
    }

    private static func seatedDipGroup(named name: String) -> ConfirmedAliasGroup? {
        let key = normalizedName(name)
        return confirmedAliasGroups.first {
            $0.canonicalID == "machine_triceps_press" && $0.aliases.contains { normalizedName($0) == key }
        }
    }

    private static func updateConfirmedIdentity(_ exercise: Exercise, group: ConfirmedAliasGroup, isPrimary: Bool, isArchived: Bool) {
        var changed = false
        if isPrimary && exercise.name != group.primaryName { exercise.name = group.primaryName; changed = true }
        if exercise.isArchived != isArchived { exercise.isArchived = isArchived; changed = true }
        if exercise.terminologyCanonicalID != group.canonicalID { exercise.terminologyCanonicalID = group.canonicalID; changed = true }
        if exercise.terminologyDecision != .accepted { exercise.terminologyDecision = .accepted; changed = true }
        if group.canonicalID == "machine_triceps_press",
           let candidate = ExerciseTerminologyService.candidate(for: group.primaryName) {
            if exercise.terminologyStandardNameZH != candidate.standardNameZH { exercise.terminologyStandardNameZH = candidate.standardNameZH; changed = true }
            if exercise.terminologyStandardNameEN != candidate.standardNameEN { exercise.terminologyStandardNameEN = candidate.standardNameEN; changed = true }
            if exercise.terminologyReviewStatus != candidate.reviewStatus { exercise.terminologyReviewStatus = candidate.reviewStatus; changed = true }
            if exercise.terminologyConfidence != candidate.confidence { exercise.terminologyConfidence = candidate.confidence; changed = true }
            if exercise.terminologyReviewNote != candidate.reviewNote { exercise.terminologyReviewNote = candidate.reviewNote; changed = true }
            if exercise.terminologyCatalogVersion != ExerciseTerminologyService.catalogVersion {
                exercise.terminologyCatalogVersion = ExerciseTerminologyService.catalogVersion; changed = true
            }
        }
        if changed { exercise.updatedAt = .now }
    }

    private static func apply(
        name: String,
        muscleGroup: String,
        equipment: String,
        volumeUnit: ExerciseVolumeUnit,
        defaultRestSeconds: Int,
        notes: String,
        referenceURL: String,
        to exercise: Exercise
    ) {
        exercise.name = name
        exercise.muscleGroup = muscleGroup
        exercise.equipment = equipment
        exercise.volumeUnit = volumeUnit
        exercise.defaultRestSeconds = max(0, defaultRestSeconds)
        exercise.notes = notes
        exercise.referenceURL = referenceURL
        exercise.updatedAt = .now
    }

    private static func normalizedName(_ value: String) -> String {
        normalizedSearchText(value)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func canonicalName(_ value: String) -> String {
        let normalized = normalizedName(value)
        if let group = seatedDipGroup(named: value) { return normalizedName(group.primaryName) }
        if normalized == normalizedName("严格深蹲") {
            return normalizedName("深蹲")
        }
        return normalized
    }

    private static func searchAliases(for name: String) -> [String] {
        let normalized = canonicalName(name)
        let confirmed = normalized == normalizedName("深蹲")
            ? ["深蹲", "严格深蹲"] : (confirmedAliasesByNormalizedName[normalized] ?? [])
        let hints = notesSearchHints.first { normalizedName($0.key) == normalized }?.value ?? []
        return confirmed + hints
    }

    private static let confirmedAliasesByNormalizedName: [String: [String]] = {
        var index: [String: [String]] = [:]
        for group in confirmedAliasGroups {
            for alias in group.aliases {
                index[normalizedName(alias)] = group.aliases
            }
        }
        return index
    }()

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
    }

    private static func normalizedSearchToken(_ value: String) -> String {
        normalizedSearchText(value).filter { character in
            !character.isWhitespace && character != "-" && character != "_"
        }
    }

    private static func isValidReferenceURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private static func normalizedReferenceURL(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "" }
        if isValidReferenceURL(trimmedValue) {
            return trimmedValue
        }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }
        let fullRange = NSRange(trimmedValue.startIndex..., in: trimmedValue)
        for match in detector.matches(in: trimmedValue, options: [], range: fullRange) {
            guard let range = Range(match.range, in: trimmedValue) else { continue }
            let candidate = String(trimmedValue[range])
            if isValidReferenceURL(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func semanticallyCompatible(
        _ exercise: Exercise,
        muscleGroup: String,
        equipment: String,
        volumeUnit: ExerciseVolumeUnit
    ) -> Bool {
        normalizedName(exercise.muscleGroup) == normalizedName(muscleGroup)
            && normalizedName(exercise.equipment) == normalizedName(equipment)
            && exercise.volumeUnit == volumeUnit
    }
}

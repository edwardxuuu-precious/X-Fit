import Foundation
import SwiftData

enum ExerciseCatalogSaveKind: Equatable {
    case created
    case updated
    case reused
    case restored
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
    static func search(
        _ exercises: [Exercise],
        query: String,
        excludedExerciseIDs: Set<UUID> = []
    ) -> [Exercise] {
        let normalizedQuery = normalizedSearchToken(query)

        return exercises
            .filter { exercise in
                guard !excludedExerciseIDs.contains(exercise.id) else { return false }

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
                    exercise.equipment,
                    exercise.notes,
                    exercise.referenceURL
                ] + EquipmentCatalogService.searchTerms(for: exercise.equipment) + [
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

        let matches = exercises.filter { exercise in
            exercise.id != excludingID && canonicalName(exercise.name) == normalizedTarget
        }

        return matches.first(where: { !$0.isArchived }) ?? matches.first
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
        exercise.isArchived = false
        exercise.updatedAt = .now
        try modelContext.save()
        return exercise
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

        for duplicate in duplicates {
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
        .init(canonicalID: "machine_triceps_press", primaryName: "三头下压机", aliases: ["三头下压机", "seated dip"]),
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
        guard !activeSessions else { return }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        let templateItems = try modelContext.fetch(FetchDescriptor<TemplateExercise>())

        for group in confirmedAliasGroups {
            let aliasKeys = Set(group.aliases.map(normalizedName))
            let matches = exercises.filter {
                $0.terminologyCanonicalID == group.canonicalID
                    || aliasKeys.contains(normalizedName($0.name))
            }
            guard !matches.isEmpty else { continue }
            let primary = matches.first { normalizedName($0.name) == normalizedName(group.primaryName) && !$0.isArchived }
                ?? matches.first { !$0.isArchived }
                ?? matches[0]
            primary.name = group.primaryName
            primary.isArchived = false
            primary.terminologyCanonicalID = group.canonicalID
            primary.terminologyDecision = .accepted
            primary.updatedAt = .now

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
                duplicate.isArchived = true
                duplicate.terminologyCanonicalID = group.canonicalID
                duplicate.terminologyDecision = .accepted
                duplicate.updatedAt = .now
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
        if normalized == normalizedName("严格深蹲") {
            return normalizedName("深蹲")
        }
        return normalized
    }

    private static func searchAliases(for name: String) -> [String] {
        let normalized = canonicalName(name)
        if normalized == normalizedName("深蹲") { return ["深蹲", "严格深蹲"] }
        return confirmedAliasesByNormalizedName[normalized] ?? []
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

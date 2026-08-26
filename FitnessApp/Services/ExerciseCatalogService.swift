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
        let normalizedQuery = normalizedSearchText(query)

        return exercises
            .filter { exercise in
                guard !excludedExerciseIDs.contains(exercise.id) else { return false }

                // Archived exercises stay out of the default list, but remain discoverable
                // by search so the picker can restore the original catalog item.
                guard !normalizedQuery.isEmpty else { return !exercise.isArchived }

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
                ] + EquipmentCatalogService.searchTerms(for: exercise.equipment))
                    .map(normalizedSearchText)
                    .joined(separator: " ")

                return searchableText.contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.isArchived != rhs.isArchived {
                    return !lhs.isArchived
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
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
        let cleanReferenceURL = referenceURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else { throw ExerciseCatalogError.missingName }
        guard !cleanMuscleGroup.isEmpty else { throw ExerciseCatalogError.missingMuscleGroup }
        guard !cleanEquipment.isEmpty else { throw ExerciseCatalogError.missingEquipment }
        guard cleanNotes.count <= 40 || cleanNotes == exercise?.notes else {
            throw ExerciseCatalogError.notesTooLong
        }
        guard isValidReferenceURL(cleanReferenceURL) else {
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
        canonicalName(name) == normalizedName("深蹲") ? ["深蹲", "严格深蹲"] : []
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
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

import Foundation
import SwiftData

/// A bundled reference catalog, never a seed or a second workout identity system.
struct ExternalExerciseCatalog: Decodable {
    let schemaVersion: Int
    let repository: String
    let commit: String
    let sourceSHA256: String
    let licenseText: String
    let entries: [ExternalExerciseEntry]
}

struct ExternalExerciseEntry: Decodable, Identifiable, Equatable {
    let sourceID: String
    let nameZH: String
    let nameEN: String
    let equipment: String
    let equipmentEN: String
    let muscleGroup: String
    let target: String
    let targetEN: String
    let secondaryMuscles: [String]
    let stepsZH: [String]
    let stepsEN: [String]
    let aliases: [String]
    let candidateAliases: [String]
    let reviewNote: String

    var id: String { sourceID }
    var needsReview: Bool { !reviewNote.isEmpty }
}

struct ExternalExerciseMatch: Identifiable {
    let exercise: Exercise
    /// Exact only means a specific catalog match; it does not approve a canonical ID.
    let isExact: Bool
    let reason: String
    var id: UUID { exercise.id }
}

struct ExerciseDemonstration: Equatable {
    let sourceID: String
    let videoURL: URL
    let sourceURL: URL
    let author: String
    let licenseURL: URL
    let approximateMegabytes: String
}

enum ExternalExerciseCatalogError: LocalizedError {
    case missingResource, invalidResource, unitRequired, nameConflict, existingUnitConflict

    var errorDescription: String? {
        switch self {
        case .missingResource: return "扩展动作库资源缺失，请更新 App 后重试。"
        case .invalidResource: return "扩展动作库校验未通过，已停止加载。"
        case .unitRequired: return "请选择这个动作的训练量单位。"
        case .nameConflict: return "已有同名动作。请先核对并选用已有动作，或为新变式填写能区分的名称。"
        case .existingUnitConflict: return "这个来源动作已加入个人库，请使用已有动作并保留原记录单位。"
        }
    }
}

enum ExternalExerciseCatalogService {
    static let expectedCommit = "7455efae41b330c265e7cd4b78dfa848e7ce5ebd"
    static let expectedCount = 1_324
    static let catalogResult: Result<ExternalExerciseCatalog, Error> = Result { try load() }
    private static let entriesByName: [String: [ExternalExerciseEntry]] = {
        guard case .success(let catalog) = catalogResult else { return [:] }
        var index: [String: [ExternalExerciseEntry]] = [:]
        for entry in catalog.entries {
            for key in Set(([entry.nameZH, entry.nameEN] + entry.aliases + entry.candidateAliases).map(normalized)) {
                index[key, default: []].append(entry)
            }
        }
        return index
    }()
    private static let entriesByID: [String: ExternalExerciseEntry] = {
        guard case .success(let catalog) = catalogResult else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.sourceID, $0) })
    }()

    static func load(bundle: Bundle = .main) throws -> ExternalExerciseCatalog {
        guard let url = bundle.url(forResource: "ExternalExerciseCatalog", withExtension: "json") else {
            throw ExternalExerciseCatalogError.missingResource
        }
        let catalog = try JSONDecoder().decode(ExternalExerciseCatalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1, catalog.commit == expectedCommit,
              catalog.entries.count == expectedCount,
              Set(catalog.entries.map(\.sourceID)).count == expectedCount,
              catalog.entries.allSatisfy({ !$0.nameZH.isEmpty && !$0.nameEN.isEmpty && !$0.stepsZH.isEmpty }),
              catalog.licenseText.contains("MIT License") else {
            throw ExternalExerciseCatalogError.invalidResource
        }
        return catalog
    }

    static func search(_ entries: [ExternalExerciseEntry], query: String,
                       muscleGroup: String = "全部", equipment: String = "全部") -> [ExternalExerciseEntry] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map { normalized(String($0)) }
        return entries.filter { entry in
            guard muscleGroup == "全部" || entry.muscleGroup == muscleGroup,
                  equipment == "全部" || entry.equipment == equipment else { return false }
            let text = normalized(([entry.nameZH, entry.nameEN, entry.equipment, entry.equipmentEN,
                                    entry.muscleGroup, entry.target, entry.targetEN, entry.sourceID] + entry.aliases + entry.candidateAliases).joined(separator: " "))
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    /// Discovery only. No mutation, archival, canonical approval, or PR aggregation.
    static func matches(for entry: ExternalExerciseEntry, among exercises: [Exercise],
                        excludedIDs: Set<UUID> = []) -> [ExternalExerciseMatch] {
        let names = Set(([entry.nameZH, entry.nameEN] + entry.aliases).map(normalized))
        let candidateNames = Set(entry.candidateAliases.map(normalized))
        let discoveryNames = names.union(candidateNames)
        return exercises.compactMap { exercise in
            guard !exercise.isArchived, !excludedIDs.contains(exercise.id) else { return nil }
            let linked = sourceID(in: exercise.referenceURL) == entry.sourceID
            let labels = [exercise.name, exercise.terminologyStandardNameZH ?? "", exercise.terminologyStandardNameEN ?? ""]
            let nameMatches = labels.contains { discoveryNames.contains(normalized($0)) }
            // Candidate standard labels are searchable, but cannot establish identity.
            let raw = normalized(exercise.name)
            let rawNameMatches = names.contains(raw) && !candidateNames.contains(raw)
            guard linked || nameMatches else { return nil }
            let compatible = equipmentMatches(exercise.equipment, entry: entry)
            let otherSource = sourceID(in: exercise.referenceURL).map { $0 != entry.sourceID } ?? false
            let exact = linked || (rawNameMatches && compatible && !entry.needsReview && !otherSource)
            return ExternalExerciseMatch(exercise: exercise, isExact: exact,
                reason: linked ? "已从此来源加入，保留个人定义与单位" : exact ? "名称与器械相符，保留已有单位和历史" : "请核对器械、姿势与变式后选择")
        }.sorted {
            if $0.isExact != $1.isExact { return $0.isExact }
            return $0.exercise.name.localizedStandardCompare($1.exercise.name) == .orderedAscending
        }
    }

    /// Supplies bilingual discovery to the original personal picker without changing its identity rules.
    static func searchTerms(for exercise: Exercise) -> [String] {
        let raw = normalized(exercise.name)
        if let linkedID = sourceID(in: exercise.referenceURL), let entry = entriesByID[linkedID] {
            return [entry.nameZH, entry.nameEN] + entry.aliases + entry.candidateAliases
        }
        return (entriesByName[raw] ?? []).filter { !($0.needsReview) && equipmentMatches(exercise.equipment, entry: $0) }
            .flatMap { [$0.nameZH, $0.nameEN] + $0.aliases + $0.candidateAliases }
    }

    static func referenceURL(for entry: ExternalExerciseEntry) -> String {
        "https://github.com/hasaneyldrm/exercises-dataset/blob/\(expectedCommit)/data/exercises.json?exercise=\(entry.sourceID)"
    }

    /// Only an explicit source reference establishes the destination. Names remain candidates.
    static func linkedEntry(reference: String) -> ExternalExerciseEntry? {
        sourceID(in: reference).flatMap { entriesByID[$0] }
    }

    static func explanationCandidates(name: String, equipment: String) -> [ExternalExerciseEntry] {
        let exact = entriesByName[normalized(name)] ?? []
        return exact.sorted { lhs, rhs in
            let left = equipmentMatches(equipment, entry: lhs), right = equipmentMatches(equipment, entry: rhs)
            if left != right { return left }
            if lhs.needsReview != rhs.needsReview { return !lhs.needsReview }
            return lhs.nameZH.localizedStandardCompare(rhs.nameZH) == .orderedAscending
        }
    }

    /// Video identity, equipment and licence were verified individually against wger records and footage.
    /// Streams are unchanged and are never used as proof of a personal exercise identity.
    static func demonstration(for entry: ExternalExerciseEntry) -> ExerciseDemonstration? {
        let videos: [String: (video: Int, exercise: Int, uuid: String, size: String)] = [
            "0025": (21, 73, "2bdb390c-312c-4497-a722-5eed2c823e5a", "1.1 MB"),
            "0289": (17, 75, "080c799b-8afd-4130-8d72-9cef0cd79f54", "4.6 MB"),
            "0314": (24, 537, "b9c937e9-daeb-42a9-be8e-7a77e368478c", "10.6 MB"),
            "0047": (16, 538, "4349a6f6-4cee-4c09-828b-c5e7fc2c1ff1", "6.2 MB"),
            "0334": (6, 348, "de69928a-8a35-4096-821c-1f46de5e0e03", "43.9 MB"),
            "0603": (11, 543, "dbfd396b-1aab-4a64-a50b-2c31ff0a2cf7", "23.5 MB"),
            "0405": (12, 567, "64f33c19-1d96-4b7c-af17-6c6a4941c614", "62.9 MB")
        ]
        guard let item = videos[entry.sourceID],
              let video = URL(string: "https://wger.de/media/exercise-video/\(item.exercise)/\(item.uuid).MOV"),
              let source = URL(string: "https://wger.de/api/v2/video/\(item.video)/"),
              let license = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") else { return nil }
        return ExerciseDemonstration(sourceID: entry.sourceID, videoURL: video, sourceURL: source,
            author: "Goulart", licenseURL: license, approximateMegabytes: item.size)
    }

    static func sourceID(in reference: String) -> String? {
        guard let url = URLComponents(string: reference), url.host == "github.com",
              url.path.hasPrefix("/hasaneyldrm/exercises-dataset/blob/"),
              url.path.hasSuffix("/data/exercises.json") else { return nil }
        return url.queryItems?.first(where: { $0.name == "exercise" })?.value
    }

    /// Called only by an explicit save after unit selection. Existing records are never rewritten.
    @MainActor
    static func add(_ entry: ExternalExerciseEntry, name: String, unit: ExerciseVolumeUnit?,
                    exercises: [Exercise], in context: ModelContext) throws -> Exercise {
        guard let unit else { throw ExternalExerciseCatalogError.unitRequired }
        // Fetch again at commit time; a stale UI query must not create duplicates.
        let current = try context.fetch(FetchDescriptor<Exercise>())
        if let existing = current.first(where: { sourceID(in: $0.referenceURL) == entry.sourceID }) {
            guard existing.volumeUnit == unit, !existing.isArchived else { throw ExternalExerciseCatalogError.existingUnitConflict }
            return existing
        }
        guard !matches(for: entry, among: current).contains(where: \.isExact) else {
            throw ExternalExerciseCatalogError.nameConflict
        }
        guard ExerciseCatalogService.exactNameMatch(named: name, in: current) == nil else {
            throw ExternalExerciseCatalogError.nameConflict
        }
        return try ExerciseCatalogService.save(exercise: nil, name: name, muscleGroup: entry.muscleGroup,
            equipment: entry.equipment, volumeUnit: unit, defaultRestSeconds: 90,
            notes: "", referenceURL: referenceURL(for: entry), allExercises: current, in: context).exercise
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func equipmentMatches(_ equipment: String, entry: ExternalExerciseEntry) -> Bool {
        let key = normalized(equipment)
        if key == normalized(entry.equipment) || key == normalized(entry.equipmentEN) { return true }
        let synonyms: [String: [String]] = [
            "cable": ["龙门架", "绳索", "滑轮器械"],
            "smith machine": ["史密斯机", "史密斯"],
            "body weight": ["自重", "无"]
        ]
        // A branded/custom machine, unknown equipment, or a different resistance type never auto-matches.
        return synonyms[entry.equipmentEN]?.contains(where: { normalized($0) == key }) ?? false
    }
}

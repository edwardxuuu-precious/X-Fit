import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "takeoutbag.and.cup.and.straw.fill"
        }
    }
}

@Model
final class NutritionTarget {
    var id: UUID = UUID()
    var calories: Int = 2_400
    var proteinGrams: Int = 160
    var carbsGrams: Int = 250
    var fatGrams: Int = 80
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        calories: Int = 2400,
        proteinGrams: Int = 160,
        carbsGrams: Int = 250,
        fatGrams: Int = 80,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.updatedAt = updatedAt
    }
}

@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var mealTypeRaw: String = MealType.snack.rawValue
    var name: String = ""
    var calories: Int = 0
    var proteinGrams: Int = 0
    var carbsGrams: Int = 0
    var fatGrams: Int = 0
    // Optional fields keep pre-program stores lightweight-migratable.
    var programID: UUID?
    var plannedMealID: UUID?
    var recipeSnapshotJSON: String?
    var actualPortions: Double?
    var nutritionKnown: Bool?
    var knownNutritionFieldsRaw: String?
    var estimationMethod: String?
    var isVoided: Bool?
    var tasteRating: Int?
    var preparationDifficulty: Int?
    var bloatingScore: Int?
    var feedbackNotes: String?

    var isActiveMeal: Bool { isVoided != true }
    private func isFieldKnown(_ field: String) -> Bool {
        guard let knownNutritionFieldsRaw else { return nutritionKnown != false }
        return knownNutritionFieldsRaw.split(separator: ",").contains(Substring(field))
    }
    var isCalorieKnown: Bool { isFieldKnown("calories") }
    var isProteinKnown: Bool { isFieldKnown("protein") }
    var isCarbsKnown: Bool { isFieldKnown("carbs") }
    var isFatKnown: Bool { isFieldKnown("fat") }
    var isNutritionKnown: Bool { isCalorieKnown && isProteinKnown && isCarbsKnown && isFatKnown }

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        mealType: MealType,
        name: String,
        calories: Int,
        proteinGrams: Int,
        carbsGrams: Int,
        fatGrams: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

enum BodyMeasurementSource: String, Codable {
    case manual
    case healthKit
}

enum BodyMarkerKind: String, Codable, CaseIterable, Identifiable {
    case area
    case jointFascia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return "肌肉 / 区域"
        case .jointFascia: return "关节 / 筋膜"
        }
    }
}

struct BodyMapMarker: Codable, Hashable, Identifiable {
    let regionID: String
    let kind: BodyMarkerKind

    var id: String { "\(regionID):\(kind.rawValue)" }
}

enum BodyMapViewSide: String, CaseIterable, Hashable, Identifiable {
    case front
    case back

    var id: String { rawValue }
    var title: String { self == .front ? "正面" : "背面" }
}

struct BodyRegionDefinition: Identifiable {
    let id: String
    let name: String
    let side: BodyMapViewSide
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct BodyRegionImagePlacement: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

enum BodyRegionImageLayout {
    static func placement(for region: BodyRegionDefinition) -> BodyRegionImagePlacement {
        let centerX: CGFloat = region.side == .front ? 0.28 : 0.735
        let horizontalScale: CGFloat = region.side == .front ? 0.52 : 0.55
        let verticalScale: CGFloat = 0.92

        return BodyRegionImagePlacement(
            x: centerX + (region.x - 0.5) * horizontalScale,
            y: 0.04 + region.y * verticalScale,
            width: region.width * horizontalScale,
            height: region.height * verticalScale
        )
    }
}

struct BodyMarkerInferenceResult: Equatable {
    let markers: [BodyMapMarker]
    let unresolvedTerms: [String]
    let ignoredNegatedTerms: [String]

    var requiresConfirmation: Bool { !unresolvedTerms.isEmpty }
}

enum BodyRegionCatalog {
    static let all: [BodyRegionDefinition] = [
        .init(id: "front-neck", name: "颈前", side: .front, x: 0.50, y: 0.16, width: 0.13, height: 0.055),
        .init(id: "front-left-shoulder", name: "左肩", side: .front, x: 0.33, y: 0.23, width: 0.17, height: 0.075),
        .init(id: "front-right-shoulder", name: "右肩", side: .front, x: 0.67, y: 0.23, width: 0.17, height: 0.075),
        .init(id: "front-chest", name: "胸部", side: .front, x: 0.50, y: 0.28, width: 0.30, height: 0.12),
        .init(id: "front-left-biceps", name: "左肱二头肌", side: .front, x: 0.22, y: 0.36, width: 0.10, height: 0.15),
        .init(id: "front-right-biceps", name: "右肱二头肌", side: .front, x: 0.78, y: 0.36, width: 0.10, height: 0.15),
        .init(id: "front-left-forearm", name: "左前臂", side: .front, x: 0.16, y: 0.49, width: 0.09, height: 0.16),
        .init(id: "front-right-forearm", name: "右前臂", side: .front, x: 0.84, y: 0.49, width: 0.09, height: 0.16),
        .init(id: "front-abdomen", name: "腹部", side: .front, x: 0.50, y: 0.43, width: 0.22, height: 0.19),
        .init(id: "front-left-hip", name: "左髋 / 腹股沟", side: .front, x: 0.41, y: 0.55, width: 0.14, height: 0.075),
        .init(id: "front-right-hip", name: "右髋 / 腹股沟", side: .front, x: 0.59, y: 0.55, width: 0.14, height: 0.075),
        .init(id: "front-left-quadriceps", name: "左股四头肌", side: .front, x: 0.40, y: 0.68, width: 0.14, height: 0.22),
        .init(id: "front-right-quadriceps", name: "右股四头肌", side: .front, x: 0.60, y: 0.68, width: 0.14, height: 0.22),
        .init(id: "front-left-knee", name: "左膝", side: .front, x: 0.40, y: 0.80, width: 0.10, height: 0.06),
        .init(id: "front-right-knee", name: "右膝", side: .front, x: 0.60, y: 0.80, width: 0.10, height: 0.06),
        .init(id: "front-left-shin", name: "左小腿前侧", side: .front, x: 0.40, y: 0.89, width: 0.10, height: 0.16),
        .init(id: "front-right-shin", name: "右小腿前侧", side: .front, x: 0.60, y: 0.89, width: 0.10, height: 0.16),
        .init(id: "back-neck", name: "后颈 / 斜方肌", side: .back, x: 0.50, y: 0.18, width: 0.20, height: 0.10),
        .init(id: "back-left-shoulder", name: "左肩后束", side: .back, x: 0.33, y: 0.24, width: 0.17, height: 0.08),
        .init(id: "back-right-shoulder", name: "右肩后束", side: .back, x: 0.67, y: 0.24, width: 0.17, height: 0.08),
        .init(id: "back-upper", name: "上背", side: .back, x: 0.50, y: 0.29, width: 0.28, height: 0.12),
        .init(id: "back-left-triceps", name: "左肱三头肌", side: .back, x: 0.22, y: 0.36, width: 0.10, height: 0.15),
        .init(id: "back-right-triceps", name: "右肱三头肌", side: .back, x: 0.78, y: 0.36, width: 0.10, height: 0.15),
        .init(id: "back-left-lat", name: "左背阔肌", side: .back, x: 0.40, y: 0.40, width: 0.15, height: 0.18),
        .init(id: "back-right-lat", name: "右背阔肌", side: .back, x: 0.60, y: 0.40, width: 0.15, height: 0.18),
        .init(id: "back-lower", name: "下背 / 竖脊肌", side: .back, x: 0.50, y: 0.50, width: 0.22, height: 0.14),
        .init(id: "back-left-glute", name: "左臀", side: .back, x: 0.41, y: 0.59, width: 0.17, height: 0.12),
        .init(id: "back-right-glute", name: "右臀", side: .back, x: 0.59, y: 0.59, width: 0.17, height: 0.12),
        .init(id: "back-left-hamstring", name: "左腘绳肌", side: .back, x: 0.40, y: 0.70, width: 0.14, height: 0.21),
        .init(id: "back-right-hamstring", name: "右腘绳肌", side: .back, x: 0.60, y: 0.70, width: 0.14, height: 0.21),
        .init(id: "back-left-knee", name: "左膝后侧", side: .back, x: 0.40, y: 0.80, width: 0.10, height: 0.06),
        .init(id: "back-right-knee", name: "右膝后侧", side: .back, x: 0.60, y: 0.80, width: 0.10, height: 0.06),
        .init(id: "back-left-calf", name: "左小腿后侧", side: .back, x: 0.40, y: 0.89, width: 0.11, height: 0.17),
        .init(id: "back-right-calf", name: "右小腿后侧", side: .back, x: 0.60, y: 0.89, width: 0.11, height: 0.17)
    ]

    private struct AliasGroup {
        let label: String
        let aliases: [String]
        let ids: [String]
    }

    private static let aliasGroups: [AliasGroup] = [
        .init(label: "颈部", aliases: ["颈", "脖子"], ids: ["front-neck", "back-neck"]),
        .init(label: "肩部", aliases: ["肩", "三角肌"], ids: ["front-left-shoulder", "front-right-shoulder", "back-left-shoulder", "back-right-shoulder"]),
        .init(label: "胸部", aliases: ["胸", "胸肌"], ids: ["front-chest"]),
        .init(label: "肱二头肌", aliases: ["二头", "肱二头"], ids: ["front-left-biceps", "front-right-biceps"]),
        .init(label: "肱三头肌", aliases: ["三头", "肱三头"], ids: ["back-left-triceps", "back-right-triceps"]),
        .init(label: "前臂", aliases: ["前臂", "手腕"], ids: ["front-left-forearm", "front-right-forearm"]),
        .init(label: "腹部", aliases: ["腹", "肚子", "核心"], ids: ["front-abdomen"]),
        .init(label: "上背", aliases: ["上背", "斜方肌"], ids: ["back-upper", "back-neck"]),
        .init(label: "背阔肌", aliases: ["背阔", "背部"], ids: ["back-left-lat", "back-right-lat"]),
        .init(label: "下背", aliases: ["下背", "腰", "竖脊肌"], ids: ["back-lower"]),
        .init(label: "髋部", aliases: ["髋", "腹股沟"], ids: ["front-left-hip", "front-right-hip"]),
        .init(label: "臀部", aliases: ["臀"], ids: ["back-left-glute", "back-right-glute"]),
        .init(label: "大腿前侧", aliases: ["大腿前", "股四头"], ids: ["front-left-quadriceps", "front-right-quadriceps"]),
        .init(label: "大腿后侧", aliases: ["大腿后", "腘绳肌"], ids: ["back-left-hamstring", "back-right-hamstring"]),
        .init(label: "膝部", aliases: ["膝"], ids: ["front-left-knee", "front-right-knee", "back-left-knee", "back-right-knee"]),
        .init(label: "小腿前侧", aliases: ["小腿前", "胫骨前"], ids: ["front-left-shin", "front-right-shin"]),
        .init(label: "小腿后侧", aliases: ["小腿", "腓肠肌"], ids: ["back-left-calf", "back-right-calf"])
    ]

    private static let negationTerms = [
        "没有", "没痛", "没疼", "无痛", "无不适", "不痛", "不疼", "不酸", "不胀", "不紧", "正常", "已恢复", "没事"
    ]

    static func definition(for id: String) -> BodyRegionDefinition? {
        all.first { $0.id == id }
    }

    static func inferMarkers(in notes: String, kind: BodyMarkerKind) -> BodyMarkerInferenceResult {
        let normalized = notes
            .replacingOccurrences(of: "但是", with: "，")
            .replacingOccurrences(of: "但", with: "，")
        let clauses = normalized.components(separatedBy: CharacterSet(charactersIn: "，,。；;、\n"))

        var markerSet = Set<BodyMapMarker>()
        var unresolved = Set<String>()
        var ignored = Set<String>()

        for rawClause in clauses {
            let clause = rawClause.replacingOccurrences(of: " ", with: "")
            guard !clause.isEmpty else { continue }

            let matchingGroups = aliasGroups.filter { group in
                group.aliases.contains(where: clause.contains)
            }
            guard !matchingGroups.isEmpty else { continue }

            if negationTerms.contains(where: clause.contains) {
                ignored.insert(clause)
                continue
            }

            let wantsLeft = clause.contains("左")
            let wantsRight = clause.contains("右")
            let wantsBoth = clause.contains("双侧") || clause.contains("两侧") || clause.contains("左右")
            let wantsFront = ["前侧", "前面", "前部", "正面"].contains(where: clause.contains)
            let wantsBack = ["后侧", "后面", "后部", "背面", "后束"].contains(where: clause.contains)

            for group in matchingGroups {
                var candidates = group.ids
                if wantsLeft && !wantsRight {
                    candidates = candidates.filter { $0.contains("left") || (!$0.contains("left") && !$0.contains("right")) }
                } else if wantsRight && !wantsLeft {
                    candidates = candidates.filter { $0.contains("right") || (!$0.contains("left") && !$0.contains("right")) }
                }
                if wantsFront && !wantsBack {
                    candidates = candidates.filter { $0.hasPrefix("front-") }
                } else if wantsBack && !wantsFront {
                    candidates = candidates.filter { $0.hasPrefix("back-") }
                }

                let spansSides = Set(candidates.compactMap { definition(for: $0)?.side }).count > 1
                let hasLeftAndRight = candidates.contains(where: { $0.contains("left") })
                    && candidates.contains(where: { $0.contains("right") })
                if spansSides || (hasLeftAndRight && !wantsBoth && !wantsLeft && !wantsRight) {
                    unresolved.insert(group.label)
                    continue
                }

                markerSet.formUnion(candidates.map { BodyMapMarker(regionID: $0, kind: kind) })
            }
        }

        return BodyMarkerInferenceResult(
            markers: markerSet.sorted { $0.id < $1.id },
            unresolvedTerms: unresolved.sorted(),
            ignoredNegatedTerms: ignored.sorted()
        )
    }

    static func inferredMarkers(in notes: String, kind: BodyMarkerKind) -> [BodyMapMarker] {
        inferMarkers(in: notes, kind: kind).markers
    }
}

@Model
final class DailyBodyCheckIn {
    var id: UUID = UUID()
    var date: Date = Date.now
    var conditionScore: Int = 3
    var discomfortNotes: String = ""
    /// Optional JSON keeps the record lightweight and allows new body regions later.
    var bodyMarkersJSON: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var bodyMarkers: [BodyMapMarker] {
        get {
            guard let bodyMarkersJSON,
                  let data = bodyMarkersJSON.data(using: .utf8),
                  let markers = try? JSONDecoder().decode([BodyMapMarker].self, from: data) else {
                return []
            }
            return markers
        }
        set {
            let normalized = Array(Set(newValue)).sorted { $0.id < $1.id }
            guard !normalized.isEmpty,
                  let data = try? JSONEncoder().encode(normalized) else {
                bodyMarkersJSON = nil
                return
            }
            bodyMarkersJSON = String(data: data, encoding: .utf8)
        }
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        conditionScore: Int,
        discomfortNotes: String = "",
        bodyMarkers: [BodyMapMarker] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date.startOfDay
        self.conditionScore = min(max(conditionScore, 1), 5)
        self.discomfortNotes = discomfortNotes
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.bodyMarkers = bodyMarkers
    }
}

enum DailyBodyCheckInService {
    @discardableResult
    static func save(
        existing preferredRecord: DailyBodyCheckIn? = nil,
        date: Date,
        conditionScore: Int,
        discomfortNotes: String,
        bodyMarkers: [BodyMapMarker],
        in context: ModelContext
    ) throws -> DailyBodyCheckIn {
        let records = try context.fetch(FetchDescriptor<DailyBodyCheckIn>())
            .filter { $0.date.isSameDay(as: date) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let target: DailyBodyCheckIn
        if let preferredRecord, preferredRecord.date.isSameDay(as: date) {
            target = preferredRecord
        } else if let first = records.first {
            target = first
        } else {
            target = DailyBodyCheckIn(date: date, conditionScore: conditionScore)
            context.insert(target)
        }

        target.date = date.startOfDay
        target.conditionScore = min(max(conditionScore, 1), 5)
        target.discomfortNotes = discomfortNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.bodyMarkers = bodyMarkers
        target.updatedAt = .now

        for duplicate in records where duplicate.id != target.id {
            context.delete(duplicate)
        }

        try context.save()
        return target
    }
}

@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date.now
    var weightKg: Double?
    var bodyFatPercent: Double?
    var waistCm: Double?
    var chestCm: Double?
    var armCm: Double?
    var notes: String = ""
    var sourceRaw: String = BodyMeasurementSource.manual.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var source: BodyMeasurementSource {
        get { BodyMeasurementSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double? = nil,
        bodyFatPercent: Double? = nil,
        waistCm: Double? = nil,
        chestCm: Double? = nil,
        armCm: Double? = nil,
        notes: String = "",
        source: BodyMeasurementSource = .manual,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.armCm = armCm
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class HydrationEntry {
    var id: UUID = UUID()
    var milliliters: Int = 0
    var date: Date = Date.now
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), milliliters: Int, date: Date = .now, createdAt: Date = .now) {
        self.id = id
        self.milliliters = milliliters
        self.date = date
        self.createdAt = createdAt
    }
}

@Model
final class JumpRopeEntry {
    var id: UUID = UUID()
    var count: Int = 0
    // Legacy duration is deliberately not inferred as active or elapsed time.
    var durationSeconds: Int?
    var activeDurationSeconds: Int?
    var elapsedDurationSeconds: Int?
    var date: Date = Date.now
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        count: Int,
        durationSeconds: Int? = nil,
        activeDurationSeconds: Int? = nil,
        elapsedDurationSeconds: Int? = nil,
        date: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.count = count
        self.durationSeconds = durationSeconds
        self.activeDurationSeconds = activeDurationSeconds
        self.elapsedDurationSeconds = elapsedDurationSeconds
        self.date = date
        self.createdAt = createdAt
    }
}

enum JumpRopeDurationValidation {
    static func isValid(active: Int?, elapsed: Int?) -> Bool {
        guard active.map({ (1...86_400).contains($0) }) ?? true,
              elapsed.map({ (1...86_400).contains($0) }) ?? true else { return false }
        if let active, let elapsed { return active <= elapsed }
        return true
    }
}

@Model
final class SedentarySession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, createdAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
    }

    var durationSeconds: Int {
        guard let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

enum WellnessToolCommand: Equatable {
    case recordJumpRope(count: Int, durationMinutes: Int?, at: Date)
    case recordWater(milliliters: Int, at: Date)
    case startSedentary(at: Date)
    case stopSedentary(at: Date)
    case recordSedentary(startedAt: Date, durationMinutes: Int)
    case recordWeight(kilograms: Double, at: Date)
    case queryTodaySummary(on: Date)

    var requiresConfirmation: Bool {
        if case .queryTodaySummary = self { return false }
        return true
    }

    var previewTitle: String {
        switch self {
        case .recordJumpRope: return "记录跳绳"
        case .recordWater: return "记录喝水"
        case .startSedentary: return "开始久坐计时"
        case .stopSedentary: return "结束久坐计时"
        case .recordSedentary: return "补录久坐"
        case .recordWeight: return "记录体重"
        case .queryTodaySummary: return "查看今日记录"
        }
    }

    var previewDetail: String {
        switch self {
        case let .recordJumpRope(count, durationMinutes, _):
            return durationMinutes.map { "\(count) 个 · \($0) 分钟" } ?? "\(count) 个"
        case let .recordWater(milliliters, _): return "\(milliliters) ml"
        case let .startSedentary(date): return date.formatted(date: .omitted, time: .shortened)
        case let .stopSedentary(date): return date.formatted(date: .omitted, time: .shortened)
        case let .recordSedentary(startedAt, durationMinutes):
            return "\(startedAt.formatted(date: .omitted, time: .shortened)) · \(durationMinutes) 分钟"
        case let .recordWeight(kilograms, _): return "\(TrainingFormatters.weight(kilograms)) kg"
        case .queryTodaySummary: return "喝水、跳绳与久坐"
        }
    }
}

enum WellnessAgentInterpretation: Equatable {
    case pending(WellnessToolCommand)
    case unsupported(message: String)
}

struct WellnessToolResult: Equatable {
    let message: String
    let recordID: UUID?
    let undoAction: WellnessToolUndoAction?
}

enum WellnessToolUndoAction: Equatable {
    case deleteHydration(UUID)
    case deleteJumpRope(UUID)
    case deleteSedentary(UUID)
    case restoreSedentaryEnd(id: UUID, endedAt: Date?)
}

struct WellnessToolSummary: Equatable {
    let waterMilliliters: Int
    let jumpRopeCount: Int
    let sedentaryMinutes: Int
}

enum WellnessToolError: LocalizedError, Equatable {
    case invalidValue(String)
    case sedentaryAlreadyActive
    case noActiveSedentarySession
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case let .invalidValue(message): return message
        case .sedentaryAlreadyActive: return "已经有一段久坐正在计时。"
        case .noActiveSedentarySession: return "当前没有正在进行的久坐计时。"
        case .recordNotFound: return "这条记录已经不存在。"
        }
    }
}

@MainActor
enum WellnessToolService {
    static func recordJumpRope(
        count: Int, activeDurationSeconds: Int?, elapsedDurationSeconds: Int?,
        at date: Date, in context: ModelContext
    ) throws -> WellnessToolResult {
        guard (1...100_000).contains(count),
              JumpRopeDurationValidation.isValid(active: activeDurationSeconds, elapsed: elapsedDurationSeconds) else {
            throw WellnessToolError.invalidValue("有效跳绳时长不能超过含休息总时长，时长需为 1 到 86400 秒。")
        }
        let entry = JumpRopeEntry(count: count, activeDurationSeconds: activeDurationSeconds,
                                  elapsedDurationSeconds: elapsedDurationSeconds, date: date)
        context.insert(entry)
        try context.save()
        return WellnessToolResult(message: "已记录跳绳 \(count) 个", recordID: entry.id,
                                  undoAction: .deleteJumpRope(entry.id))
    }

    static func execute(_ command: WellnessToolCommand, in context: ModelContext) throws -> WellnessToolResult {
        switch command {
        case let .recordWater(milliliters, date):
            guard (1...5_000).contains(milliliters) else {
                throw WellnessToolError.invalidValue("饮水量需要在 1 到 5000 ml 之间。")
            }
            let entry = HydrationEntry(milliliters: milliliters, date: date)
            context.insert(entry)
            try context.save()
            return WellnessToolResult(
                message: "已记录 \(milliliters) ml 饮水",
                recordID: entry.id,
                undoAction: .deleteHydration(entry.id)
            )
        case let .recordJumpRope(count, durationMinutes, date):
            guard (1...100_000).contains(count) else {
                throw WellnessToolError.invalidValue("跳绳次数需要在 1 到 100000 之间。")
            }
            if let durationMinutes, !(1...1_440).contains(durationMinutes) {
                throw WellnessToolError.invalidValue("跳绳时长需要在 1 到 1440 分钟之间。")
            }
            let entry = JumpRopeEntry(
                count: count,
                durationSeconds: durationMinutes.map { $0 * 60 },
                date: date
            )
            context.insert(entry)
            try context.save()
            return WellnessToolResult(
                message: "已记录跳绳 \(count) 个",
                recordID: entry.id,
                undoAction: .deleteJumpRope(entry.id)
            )
        case let .startSedentary(date):
            guard try activeSedentarySession(in: context) == nil else {
                throw WellnessToolError.sedentaryAlreadyActive
            }
            let session = SedentarySession(startedAt: date)
            context.insert(session)
            try context.save()
            return WellnessToolResult(
                message: "久坐计时已开始",
                recordID: session.id,
                undoAction: .deleteSedentary(session.id)
            )
        case let .stopSedentary(date):
            guard let session = try activeSedentarySession(in: context) else {
                throw WellnessToolError.noActiveSedentarySession
            }
            guard date > session.startedAt else {
                throw WellnessToolError.invalidValue("结束时间必须晚于开始时间。")
            }
            let previousEnd = session.endedAt
            session.endedAt = date
            try context.save()
            let minutes = max(1, Int(date.timeIntervalSince(session.startedAt) / 60))
            return WellnessToolResult(
                message: "已记录久坐 \(minutes) 分钟",
                recordID: session.id,
                undoAction: .restoreSedentaryEnd(id: session.id, endedAt: previousEnd)
            )
        case let .recordSedentary(startedAt, durationMinutes):
            guard (1...1_440).contains(durationMinutes) else {
                throw WellnessToolError.invalidValue("久坐时长需要在 1 到 1440 分钟之间。")
            }
            let session = SedentarySession(
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(Double(durationMinutes * 60))
            )
            context.insert(session)
            try context.save()
            return WellnessToolResult(
                message: "已补录久坐 \(durationMinutes) 分钟",
                recordID: session.id,
                undoAction: .deleteSedentary(session.id)
            )
        case let .recordWeight(kilograms, date):
            let measurement = try BodyMeasurementService.saveQuickEntry(
                BodyMeasurementQuickEntry(date: date, weightKg: kilograms),
                in: context
            )
            return WellnessToolResult(
                message: "已记录体重 \(TrainingFormatters.weight(kilograms)) kg",
                recordID: measurement.id,
                undoAction: nil
            )
        case let .queryTodaySummary(date):
            let summary = todaySummary(
                on: date,
                hydrationEntries: try context.fetch(FetchDescriptor<HydrationEntry>()),
                jumpRopeEntries: try context.fetch(FetchDescriptor<JumpRopeEntry>()),
                sedentarySessions: try context.fetch(FetchDescriptor<SedentarySession>())
            )
            return WellnessToolResult(
                message: "今天喝水 \(summary.waterMilliliters) ml，跳绳 \(summary.jumpRopeCount) 个，久坐 \(summary.sedentaryMinutes) 分钟。",
                recordID: nil,
                undoAction: nil
            )
        }
    }

    static func undo(_ action: WellnessToolUndoAction, in context: ModelContext) throws {
        switch action {
        case let .deleteHydration(id):
            guard let record = try context.fetch(FetchDescriptor<HydrationEntry>()).first(where: { $0.id == id }) else {
                throw WellnessToolError.recordNotFound
            }
            context.delete(record)
        case let .deleteJumpRope(id):
            guard let record = try context.fetch(FetchDescriptor<JumpRopeEntry>()).first(where: { $0.id == id }) else {
                throw WellnessToolError.recordNotFound
            }
            context.delete(record)
        case let .deleteSedentary(id):
            guard let record = try context.fetch(FetchDescriptor<SedentarySession>()).first(where: { $0.id == id }) else {
                throw WellnessToolError.recordNotFound
            }
            context.delete(record)
        case let .restoreSedentaryEnd(id, endedAt):
            guard let record = try context.fetch(FetchDescriptor<SedentarySession>()).first(where: { $0.id == id }) else {
                throw WellnessToolError.recordNotFound
            }
            record.endedAt = endedAt
        }
        try context.save()
    }

    static func todaySummary(
        on date: Date,
        hydrationEntries: [HydrationEntry],
        jumpRopeEntries: [JumpRopeEntry],
        sedentarySessions: [SedentarySession],
        calendar: Calendar = .current
    ) -> WellnessToolSummary {
        WellnessToolSummary(
            waterMilliliters: hydrationEntries
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(0) { $0 + $1.milliliters },
            jumpRopeCount: jumpRopeEntries
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(0) { $0 + $1.count },
            sedentaryMinutes: sedentarySeconds(
                on: date,
                sessions: sedentarySessions,
                calendar: calendar
            ) / 60
        )
    }

    static func activeSedentarySession(in context: ModelContext) throws -> SedentarySession? {
        try context.fetch(FetchDescriptor<SedentarySession>())
            .filter { $0.endedAt == nil }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    private static func sedentarySeconds(
        on date: Date,
        sessions: [SedentarySession],
        calendar: Calendar
    ) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        return sessions.reduce(0) { total, session in
            let start = max(session.startedAt, dayStart)
            let end = min(session.endedAt ?? date, dayEnd)
            guard end > start else { return total }
            return total + Int(end.timeIntervalSince(start))
        }
    }
}

enum LocalWellnessAgent {
    static func interpret(_ input: String, now: Date = .now) -> WellnessAgentInterpretation {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return .unsupported(message: "告诉我你想记录什么，例如“喝水 250 ml”。")
        }

        if normalized.contains("今天"),
           normalized.contains("多少"),
           (normalized.contains("水") || normalized.contains("跳绳") || normalized.contains("久坐")) {
            return .pending(.queryTodaySummary(on: now))
        }

        if normalized.contains("喝水") || normalized.contains("水") && normalized.localizedCaseInsensitiveContains("ml") {
            guard let amount = firstInteger(in: normalized), amount > 0 else {
                return .unsupported(message: "请告诉我喝了多少毫升，例如“喝水 250 ml”。")
            }
            return .pending(.recordWater(milliliters: amount, at: now))
        }

        if normalized.contains("跳绳"),
           let count = firstInteger(matching: #"(\d+)\s*(?:个|次)?"#, in: normalized),
           count > 0 {
            let duration = firstInteger(matching: #"(\d+)\s*(?:分钟|分)"#, in: normalized)
            return .pending(.recordJumpRope(count: count, durationMinutes: duration, at: now))
        }

        if normalized.contains("开始久坐") || normalized.contains("开始计时") && normalized.contains("久坐") {
            return .pending(.startSedentary(at: now))
        }

        if normalized.contains("结束久坐") || normalized.contains("停止久坐") {
            return .pending(.stopSedentary(at: now))
        }

        if normalized.contains("久坐") || normalized.contains("坐了"),
           let minutes = firstInteger(matching: #"(\d+)\s*(?:分钟|分)"#, in: normalized),
           minutes > 0 {
            return .pending(.recordSedentary(
                startedAt: now.addingTimeInterval(Double(-minutes * 60)),
                durationMinutes: minutes
            ))
        }

        if normalized.contains("体重"),
           let kilograms = firstDouble(matching: #"(\d+(?:\.\d+)?)\s*(?:kg|公斤|千克)?"#, in: normalized),
           kilograms > 0 {
            return .pending(.recordWeight(kilograms: kilograms, at: now))
        }

        return .unsupported(message: "我暂时只能处理跳绳、喝水、久坐和体重记录。")
    }

    private static func firstInteger(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    private static func firstInteger(matching pattern: String, in text: String) -> Int? {
        guard let value = firstCapture(matching: pattern, in: text) else { return nil }
        return Int(value)
    }

    private static func firstDouble(matching pattern: String, in text: String) -> Double? {
        guard let value = firstCapture(matching: pattern, in: text) else { return nil }
        return Double(value)
    }

    private static func firstCapture(matching pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capture])
    }
}

struct BodyMeasurementQuickEntry: Equatable {
    var date: Date
    var weightKg: Double
    var bodyFatPercent: Double?
    var waistCm: Double?
    var chestCm: Double?
    var armCm: Double?
    var notes: String
    var includesExtendedFields: Bool

    init(
        date: Date = .now,
        weightKg: Double,
        bodyFatPercent: Double? = nil,
        waistCm: Double? = nil,
        chestCm: Double? = nil,
        armCm: Double? = nil,
        notes: String = "",
        includesExtendedFields: Bool = false
    ) {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.armCm = armCm
        self.notes = notes
        self.includesExtendedFields = includesExtendedFields
    }
}

struct BodyWeightDailyValue: Identifiable, Equatable {
    let date: Date
    let weightKg: Double
    let source: BodyMeasurementSource
    let measurementID: UUID

    var id: Date { date }
}

enum BodyWeightTrendPeriod: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth: return "1月"
        case .threeMonths: return "3月"
        case .sixMonths: return "6月"
        case .all: return "全部"
        }
    }
}

struct BodyWeightTrendPoint: Identifiable, Equatable {
    let date: Date
    let weightKg: Double
    let movingAverageKg: Double?

    var id: Date { date }
}

enum BodyMeasurementServiceError: LocalizedError {
    case invalidWeight

    var errorDescription: String? {
        switch self {
        case .invalidWeight:
            return "请输入有效体重。"
        }
    }
}

@MainActor
enum BodyMeasurementService {
    @discardableResult
    static func saveQuickEntry(
        _ entry: BodyMeasurementQuickEntry,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> BodyMeasurement {
        guard entry.weightKg.isFinite, entry.weightKg > 0 else {
            throw BodyMeasurementServiceError.invalidWeight
        }

        let records = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let existing = records
            .filter { $0.source == .manual && calendar.isDate($0.date, inSameDayAs: entry.date) }
            .max(by: { $0.date < $1.date })
        let saved = existing ?? BodyMeasurement(source: .manual)
        if existing == nil {
            context.insert(saved)
        }

        saved.date = entry.date
        saved.weightKg = sanitized(entry.weightKg)
        saved.notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.includesExtendedFields {
            saved.bodyFatPercent = sanitized(entry.bodyFatPercent)
            saved.waistCm = sanitized(entry.waistCm)
            saved.chestCm = sanitized(entry.chestCm)
            saved.armCm = sanitized(entry.armCm)
        }
        saved.source = .manual
        saved.updatedAt = .now
        try context.save()
        return saved
    }

    static func dailyRepresentativeWeights(
        from measurements: [BodyMeasurement],
        calendar: Calendar = .current
    ) -> [BodyWeightDailyValue] {
        let valid = measurements.filter { measurement in
            guard let weight = measurement.weightKg else { return false }
            return weight.isFinite && weight > 0
        }
        let grouped = Dictionary(grouping: valid) { measurement in
            calendar.startOfDay(for: measurement.date)
        }

        return grouped.compactMap { day, records in
            let preferred = records
                .filter { $0.source == .manual }
                .max(by: { $0.date < $1.date })
                ?? records.max(by: { $0.date < $1.date })
            guard let preferred, let weightKg = preferred.weightKg else { return nil }
            return BodyWeightDailyValue(
                date: day,
                weightKg: weightKg,
                source: preferred.source,
                measurementID: preferred.id
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func trendPoints(from values: [BodyWeightDailyValue]) -> [BodyWeightTrendPoint] {
        let sorted = values.sorted { $0.date < $1.date }
        return sorted.enumerated().map { index, value in
            let movingAverage: Double?
            if index >= 6 {
                let window = sorted[(index - 6)...index]
                movingAverage = window.map(\.weightKg).reduce(0, +) / Double(window.count)
            } else {
                movingAverage = nil
            }
            return BodyWeightTrendPoint(
                date: value.date,
                weightKg: value.weightKg,
                movingAverageKg: movingAverage
            )
        }
    }

    static func filteredTrendPoints(
        _ points: [BodyWeightTrendPoint],
        period: BodyWeightTrendPeriod,
        through endDate: Date = .now,
        calendar: Calendar = .current
    ) -> [BodyWeightTrendPoint] {
        guard period != .all else { return points.filter { $0.date <= endDate } }
        let months: Int
        switch period {
        case .oneMonth: months = 1
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .all: months = 0
        }
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: endDate) else {
            return points.filter { $0.date <= endDate }
        }
        return points.filter { $0.date >= startDate && $0.date <= endDate }
    }

    private static func sanitized(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

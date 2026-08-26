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

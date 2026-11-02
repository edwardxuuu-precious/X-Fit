import Foundation
import CryptoKit

enum MealLocalDay {
    static let legacyTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    static func string(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ day: String, timeZone: TimeZone = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, day.count == 10 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              string(for: date, timeZone: timeZone) == day else { return nil }
        return date
    }
}

struct MealPhotoAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    let relativePath: String
    let sha256: String
    let byteCount: Int
    let capturedAt: Date
    let localDay: String
    let timeZoneIdentifier: String
}

struct MealPhotoAsset: Codable, Equatable {
    let attachment: MealPhotoAttachment
    let data: Data
}

struct MealEstimateRange: Codable, Equatable {
    let lower: Double
    let upper: Double
    var midpoint: Double { (lower + upper) / 2 }
    var isValid: Bool { lower.isFinite && upper.isFinite && lower >= 0 && upper >= lower }
}

struct MealDishEstimate: Codable, Equatable {
    let name: String
    let portionDescription: String
}

struct MealAssessment: Codable, Equatable, Identifiable {
    let id: UUID
    var batchID: UUID?
    let mealID: UUID
    let sourceFingerprint: String
    let reviewedAt: Date
    let provider: String
    let dishes: [MealDishEstimate]
    let calories: MealEstimateRange?
    let proteinGrams: MealEstimateRange?
    let carbsGrams: MealEstimateRange?
    let fatGrams: MealEstimateRange?
    let summary: String
    let limitations: [String]

    init(id: UUID = UUID(), batchID: UUID? = nil, mealID: UUID, sourceFingerprint: String,
         reviewedAt: Date = .now, provider: String = "Codex", dishes: [MealDishEstimate] = [],
         calories: MealEstimateRange? = nil, proteinGrams: MealEstimateRange? = nil,
         carbsGrams: MealEstimateRange? = nil, fatGrams: MealEstimateRange? = nil,
         summary: String, limitations: [String] = []) {
        self.id = id
        self.batchID = batchID
        self.mealID = mealID
        self.sourceFingerprint = sourceFingerprint
        self.reviewedAt = reviewedAt
        self.provider = provider
        self.dishes = dishes
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.summary = summary
        self.limitations = limitations
    }
}

struct MealReviewBatch: Codable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let assessments: [MealAssessment]

    init(schemaVersion: Int = 1, id: UUID = UUID(), createdAt: Date = .now, assessments: [MealAssessment]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.assessments = assessments
    }
}

struct MealOwnerNutrition: Codable, Equatable {
    let calories: Int?
    let proteinGrams: Int?
    let carbsGrams: Int?
    let fatGrams: Int?
    let source: String?
}

struct MealWeekSource: Codable {
    let mealID: UUID
    let date: Date
    let localDay: String
    let timeZoneIdentifier: String
    let timeKnown: Bool?
    let mealType: String
    let originalText: String
    let originalFeedback: String?
    let ownerNutrition: MealOwnerNutrition
    let photos: [MealPhotoAsset]
    let sourceFingerprint: String
}

struct MealWeekPackage: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let startLocalDay: String
    let endLocalDay: String
    let meals: [MealWeekSource]
}

struct MealReviewApplyResult: Codable, Equatable {
    let appliedCount: Int
    let duplicateCount: Int
}

/// Future server adapters can implement this boundary; the offline app provides none.
protocol MealRecognitionProvider {
    func evaluate(_ package: MealWeekPackage) async throws -> MealReviewBatch
}

/// The fingerprint intentionally excludes updatedAt and assessment history.
/// Any owner-source change invalidates an assessment; appending an assessment does not.
enum MealSourceFingerprint {
    private struct Source: Encodable {
        let mealID: UUID
        // Exchange/legacy backups use ISO8601 seconds, so source-time precision is seconds.
        let dateEpochSeconds: Double
        let localDay: String
        let timeZoneIdentifier: String
        let timeKnown: Bool?
        let mealType: String
        let name: String
        let feedback: String?
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let nutritionKnown: Bool?
        let knownFields: String?
        let estimationMethod: String?
        let portions: Double?
        let recipe: String?
        let active: Bool
        let photos: [MealPhotoAttachment]
    }

    static func value(for meal: MealEntry) throws -> String {
        let photos: [MealPhotoAttachment]
        if let raw = meal.mealPhotosJSON {
            guard let encoded = raw.data(using: .utf8) else { throw MealPhotoError.invalidMetadata }
            photos = try JSONDecoder().decode([MealPhotoAttachment].self, from: encoded)
        } else { photos = [] }
        let source = Source(mealID: meal.id, dateEpochSeconds: floor(meal.date.timeIntervalSince1970), localDay: meal.stableLocalDay,
            timeZoneIdentifier: meal.captureTimeZoneIdentifier ?? MealLocalDay.legacyTimeZone.identifier,
            timeKnown: meal.recordedTimeKnown, mealType: meal.mealTypeRaw, name: meal.name, feedback: meal.feedbackNotes,
            calories: meal.calories, protein: meal.proteinGrams, carbs: meal.carbsGrams, fat: meal.fatGrams,
            nutritionKnown: meal.nutritionKnown, knownFields: meal.knownNutritionFieldsRaw, estimationMethod: meal.estimationMethod,
            portions: meal.actualPortions, recipe: meal.recipeSnapshotJSON, active: meal.isActiveMeal, photos: photos)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(source)).map { String(format: "%02x", $0) }.joined()
    }
}

enum MealPhotoError: LocalizedError {
    case unavailableStorage
    case invalidPhoto
    case tooManyPhotos
    case invalidMetadata
    case unsafePath
    case corruptPhoto
    case conflictingPhoto

    var errorDescription: String? {
        switch self {
        case .unavailableStorage: return "照片存储暂时不可用，请重试。"
        case .invalidPhoto: return "照片为空、过大或不是有效的 JPEG 图片，未保存餐食。"
        case .tooManyPhotos: return "每餐最多保存 12 张照片。"
        case .invalidMetadata: return "餐食照片信息不完整，未修改原记录。"
        case .unsafePath: return "照片路径无效，已停止操作。"
        case .corruptPhoto: return "照片缺失或完整性校验失败，已停止操作。"
        case .conflictingPhoto: return "同一照片标识对应不同内容，未覆盖原文件。"
        }
    }
}

extension MealEntry {
    var stableLocalDay: String {
        recordedLocalDay ?? MealLocalDay.string(for: date, timeZone: MealLocalDay.legacyTimeZone)
    }

    var mealPhotos: [MealPhotoAttachment] {
        guard let mealPhotosJSON, let data = mealPhotosJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MealPhotoAttachment].self, from: data)) ?? []
    }

    var mealAssessments: [MealAssessment] {
        guard let mealAssessmentsJSON, let data = mealAssessmentsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MealAssessment].self, from: data)) ?? []
    }

    var latestApplicableAssessment: MealAssessment? {
        guard isActiveMeal, let fingerprint = try? MealSourceFingerprint.value(for: self) else { return nil }
        // Applied append order is authoritative; an evaluator's clock must not win forever.
        return mealAssessments.last { $0.mealID == id && $0.sourceFingerprint == fingerprint }
    }

    var photoReviewStatus: String {
        if latestApplicableAssessment != nil { return "已评估" }
        return mealAssessments.isEmpty ? "未评估" : "待重新评估"
    }

    var displayCalorieRange: MealEstimateRange? {
        if isCalorieKnown { return MealEstimateRange(lower: Double(calories), upper: Double(calories)) }
        return latestApplicableAssessment?.calories
    }

    var calorieProvenanceLabel: String {
        if isCalorieKnown { return estimationMethod ?? "手动记录" }
        return latestApplicableAssessment?.calories == nil ? "未估算" : "AI 估算"
    }
}

enum MealReviewError: LocalizedError {
    case invalidWeek
    case invalidBatch
    case confirmationRequired
    case missingMeal
    case changedSource
    case conflictingAssessment
    case corruptHistory

    var errorDescription: String? {
        switch self {
        case .invalidWeek: return "请选择连续最多 7 天的有效日期范围。"
        case .invalidBatch: return "评估文件格式或估算数值无效，未写入记录。"
        case .confirmationRequired: return "请先确认整周评估，再写入 App。"
        case .missingMeal: return "评估对应的餐食不存在或已作废，未写入记录。"
        case .changedSource: return "原餐食或照片已变化，请重新评估后确认。"
        case .conflictingAssessment: return "重复评估的内容不一致，未覆盖已有评估。"
        case .corruptHistory: return "已有评估记录无法读取，已停止写入以保护历史。"
        }
    }
}

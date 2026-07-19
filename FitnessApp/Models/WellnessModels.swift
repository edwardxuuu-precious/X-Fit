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
    @Attribute(.unique) var id: UUID
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var updatedAt: Date

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
    @Attribute(.unique) var id: UUID
    var date: Date
    var mealTypeRaw: String
    var name: String
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var createdAt: Date
    var updatedAt: Date

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

@Model
final class BodyMeasurement {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var waistCm: Double?
    var chestCm: Double?
    var armCm: Double?
    var notes: String
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date

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

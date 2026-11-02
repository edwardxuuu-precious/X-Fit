import Foundation
import SwiftData

enum FatLossCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func adding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: day(date))!
    }
    static func distance(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: day(start), to: day(end)).day ?? 0
    }
    static func sameDay(_ lhs: Date, _ rhs: Date) -> Bool { day(lhs) == day(rhs) }
    static func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct RecipeIngredient: Codable, Hashable, Identifiable {
    var name: String
    var amountText: String
    var referenceGrams: Double? = nil
    var isMedicalPortionPending: Bool = false
    var id: String { name }
}

struct RecipeSource: Codable, Hashable {
    var title: String
    var url: String
    var verification: String
}

struct RecipeDraft: Codable, Hashable, Identifiable {
    var key: String
    var title: String
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var equipment: [String]
    var householdPortion: String
    var portions: Double = 1
    var cookingMinutes: Int
    var storageNote: String
    var substitutions: [String] = []
    var sources: [RecipeSource] = []
    var calories: Int? = nil
    var proteinGrams: Int? = nil
    var carbsGrams: Int? = nil
    var fatGrams: Int? = nil
    var nutritionSource: String = "未核算；医学份量待确认"
    var id: String { key }
    var hasCompleteNutrition: Bool {
        calories != nil && proteinGrams != nil && carbsGrams != nil && fatGrams != nil
    }
}

struct ProgramExerciseDraft: Codable, Hashable, Identifiable {
    var name: String
    var muscleGroup: String
    var equipment: String
    var sets: Int = 2
    var repsLower: Int
    var repsUpper: Int
    var restSeconds: Int = 120
    var volumeUnitRaw: String = ExerciseVolumeUnit.kilogram.rawValue
    var unilateral: Bool = false
    var note: String = "保留约 3 次余力；工作重量按当天状态选择"
    var catalogExerciseID: UUID? = nil
    /// Exact raw catalog label at preview time; the confirmed plan label remains separate.
    var catalogName: String? = nil
    var plannedSets: [WorkoutSetPlan]? = nil
    var id: String { name }
}

struct ProgramWorkoutDraft: Codable, Hashable, Identifiable {
    var code: String
    var title: String
    var weekday: Int
    var exercises: [ProgramExerciseDraft]
    var guidance: String
    var id: String { code }
}

@Model
final class FatLossProgram {
    var id: UUID = UUID()
    var title: String = "13 周减脂"
    var startDate: Date = Date.now
    /// This date is the endpoint review; meal/training execution ends the previous day.
    var endDate: Date = Date.now
    var timeZoneIdentifier: String = "Asia/Shanghai"
    var reportedStartWeightKg: Double = 85
    var targetWeightKg: Double = 77.5
    var statusRaw: String = "active"
    var createdAt: Date = Date.now
    init(id: UUID = UUID(), startDate: Date, endDate: Date,
         reportedStartWeightKg: Double = 85, targetWeightKg: Double = 77.5) {
        self.id = id
        self.startDate = FatLossCalendar.day(startDate)
        self.endDate = FatLossCalendar.day(endDate)
        self.reportedStartWeightKg = reportedStartWeightKg
        self.targetWeightKg = targetWeightKg
    }
    var executionDays: Int { FatLossCalendar.distance(startDate, endDate) }
    func contains(_ date: Date, includeReviewDay: Bool = true) -> Bool {
        let value = FatLossCalendar.day(date)
        return value >= startDate && (includeReviewDay ? value <= endDate : value < endDate)
    }
    func dayNumber(on date: Date) -> Int { FatLossCalendar.distance(startDate, date) + 1 }
    func weekNumber(on date: Date) -> Int { min(13, max(1, (dayNumber(on: date) - 1) / 7 + 1)) }
}

@Model
final class ProgramTargetRevision {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var effectiveDate: Date = Date.now
    var createdAt: Date = Date.now
    var reason: String = ""
    var sourceNote: String = ""
    var isNutritionConfirmed: Bool = false
    var targetWeightKg: Double?
    var calories: Int?
    var proteinGrams: Int?
    var carbsGrams: Int?
    var fatGrams: Int?
    var steps: Int?
    init(programID: UUID, effectiveDate: Date, reason: String) {
        self.programID = programID
        self.effectiveDate = FatLossCalendar.day(effectiveDate)
        self.reason = reason
    }
}

@Model
final class RecipeVersion {
    var id: UUID = UUID()
    var catalogKey: String = ""
    var version: Int = 1
    var draftJSON: String = ""
    var createdAt: Date = Date.now
    init(draft: RecipeDraft, version: Int = 1) throws {
        self.catalogKey = draft.key
        self.version = version
        self.draftJSON = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
    }
    var draft: RecipeDraft? {
        try? JSONDecoder().decode(RecipeDraft.self, from: Data(draftJSON.utf8))
    }
    var title: String { draft?.title ?? "食谱内容暂不可读" }
}

@Model
final class PlannedMeal {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var date: Date = Date.now
    var mealTypeRaw: String = MealType.lunch.rawValue
    var recipeID: UUID = UUID()
    var recipeSnapshotJSON: String = ""
    var isCurrent: Bool = true
    var previousPlanID: UUID?
    var statusRaw: String = "planned"
    var changeReason: String = ""
    var createdAt: Date = Date.now
    init(programID: UUID, date: Date, mealType: MealType, recipe: RecipeVersion) {
        self.programID = programID
        self.date = FatLossCalendar.day(date)
        self.mealTypeRaw = mealType.rawValue
        self.recipeID = recipe.id
        self.recipeSnapshotJSON = recipe.draftJSON
    }
    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .snack }
    var recipe: RecipeDraft? {
        try? JSONDecoder().decode(RecipeDraft.self, from: Data(recipeSnapshotJSON.utf8))
    }
    var title: String { recipe?.title ?? "食谱内容暂不可读" }
}

@Model
final class ProgramDailyLog {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var date: Date = Date.now
    var steps: Int?
    var sleepHours: Double?
    var bloatingScore: Int?
    var explicitlyNoWorkout: Bool = false
    var notes: String = ""
    var updatedAt: Date = Date.now
    init(programID: UUID, date: Date) {
        self.programID = programID
        self.date = FatLossCalendar.day(date)
    }
}

@Model
final class ProgramHealthRecord {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var metric: String = ""
    var value: Double?
    var unit: String?
    var measuredAt: Date?
    var notes: String = ""
    var source: String = "本人记录"
    var createdAt: Date = Date.now
    init(programID: UUID, metric: String) {
        self.programID = programID
        self.metric = metric
    }
}

@Model
final class ProgramWeeklyReview {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var weekStart: Date = Date.now
    var weekEnd: Date = Date.now
    var snapshotJSON: String = ""
    var notes: String = ""
    var nextAction: String = ""
    var previousReviewID: UUID?
    var createdAt: Date = Date.now
    init(programID: UUID, weekStart: Date, weekEnd: Date) {
        self.programID = programID
        self.weekStart = FatLossCalendar.day(weekStart)
        self.weekEnd = FatLossCalendar.day(weekEnd)
    }
}

@Model
final class ProgramWorkoutLink {
    var id: UUID = UUID()
    var programID: UUID = UUID()
    var scheduledWorkoutID: UUID = UUID()
    var trainingProgramRevisionID: UUID?
    var templateCode: String = ""
    var originalDate: Date = Date.now
    var createdAt: Date = Date.now
    init(programID: UUID, scheduledWorkoutID: UUID, templateCode: String, originalDate: Date) {
        self.programID = programID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.templateCode = templateCode
        self.originalDate = FatLossCalendar.day(originalDate)
    }
}

struct FatLossDaySummary: Codable, Identifiable {
    var date: Date
    var weightKg: Double?
    var waistCm: Double?
    var loggedMeals: Int
    var plannedMeals: Int
    var skippedMeals: Int
    var knownCalories: Int
    var unknownNutritionMeals: Int
    var completedWorkouts: Int
    var plannedWorkouts: Int
    var jumpCount: Int?
    var jumpActiveSeconds: Int?
    var jumpElapsedSeconds: Int?
    var waterMilliliters: Int
    var steps: Int?
    var sleepHours: Double?
    var bloatingScore: Int?
    var explicitlyNoWorkout: Bool
    var hasDailyLog: Bool
    var resolvedMealTypes: [String] = []
    var knownCalorieMeals: Int = 0
    var bodyFeeling: String?
    var workoutNotes: [String]?
    var id: Date { date }
    var hasRecords: Bool {
        weightKg != nil || waistCm != nil || loggedMeals > 0 || skippedMeals > 0
            || completedWorkouts > 0 || jumpCount == nil || (jumpCount ?? 0) > 0 || jumpActiveSeconds != nil || jumpElapsedSeconds != nil
            || waterMilliliters > 0 || hasDailyLog || bodyFeeling != nil
    }
    var nutritionComplete: Bool { loggedMeals > 0 && unknownNutritionMeals == 0 }
    func status(relativeTo now: Date) -> String {
        if date > FatLossCalendar.day(now) { return "未到日期" }
        guard hasRecords else { return "未记录" }
        return [MealType.breakfast, .lunch, .dinner].allSatisfy { resolvedMealTypes.contains($0.rawValue) }
            && (completedWorkouts > 0 || explicitlyNoWorkout || plannedWorkouts == 0)
            ? "已记录" : "部分记录"
    }
}

struct FatLossWeightAverage: Equatable {
    var value: Double?
    var recordedDays: Int
}

struct ProgramImportPreview: Identifiable, Equatable {
    var trainingProgramRevisionID: UUID? = nil
    var loadPlans: [String: WorkoutSetPlan] = [:]
    var date: Date
    var workout: ProgramWorkoutDraft
    var alreadyImported: Bool
    var conflictingNames: [String]
    var id: String { "\(FatLossCalendar.label(date))-\(workout.code)" }
}

struct ProgramCardioImportPreview: Identifiable, Equatable {
    var trainingProgramRevisionID: UUID
    var date: Date
    var cardio: ProgramCardioDraft
    var alreadyImported: Bool
    var conflictingNames: [String]
    var id: String { "\(FatLossCalendar.label(date))-\(cardio.code)" }
}

struct ProgramImportSummary: Equatable {
    var importableCount: Int
    var conflictCount: Int
    var alreadyImportedCount: Int

    init(preview: [ProgramImportPreview]) {
        importableCount = preview.filter { !$0.alreadyImported && $0.conflictingNames.isEmpty }.count
        conflictCount = preview.filter { !$0.alreadyImported && !$0.conflictingNames.isEmpty }.count
        alreadyImportedCount = preview.filter(\.alreadyImported).count
    }

    var canImport: Bool { importableCount > 0 }
    var actionTitle: String {
        guard canImport else { return "没有可导入的训练" }
        return conflictCount > 0 || alreadyImportedCount > 0
            ? "导入其余 \(importableCount) 天"
            : "导入 \(importableCount) 天训练"
    }
    var unavailableReason: String? {
        guard !canImport else { return nil }
        if alreadyImportedCount > 0 && conflictCount == 0 { return "这些训练已经导入，无需重复操作。" }
        if conflictCount > 0 { return "所选日期都有现有训练；将保留现有记录，不会覆盖。" }
        return "所选范围内没有已确认的力量训练。"
    }
}

enum ProgramImportConflictPolicy { case reject, skipConflicts }

struct ShoppingItem: Identifiable {
    var name: String
    var portions: Int
    var amounts: [String]
    var isMedicalPortionPending: Bool
    var referenceGrams: Double? = nil
    var id: String { name }
}

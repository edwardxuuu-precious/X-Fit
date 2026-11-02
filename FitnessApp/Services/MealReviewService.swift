import Foundation
import SwiftData

@MainActor
struct MealReviewService {
    private let photoService: MealPhotoService

    init(photoService: MealPhotoService? = nil) {
        self.photoService = photoService ?? MealPhotoService()
    }

    func exportWeek(meals: [MealEntry], startLocalDay: String, endLocalDay: String) throws -> MealWeekPackage {
        let utc = TimeZone(secondsFromGMT: 0)!
        guard let start = MealLocalDay.date(startLocalDay, timeZone: utc),
              let end = MealLocalDay.date(endLocalDay, timeZone: utc),
              end >= start, end.timeIntervalSince(start) <= 6 * 86_400 else { throw MealReviewError.invalidWeek }
        let selected = meals.filter { $0.isActiveMeal && $0.stableLocalDay >= startLocalDay && $0.stableLocalDay <= endLocalDay }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        guard Set(selected.map(\.id)).count == selected.count else { throw MealReviewError.invalidBatch }
        let sources = try selected.map { meal in
            MealWeekSource(mealID: meal.id, date: meal.date, localDay: meal.stableLocalDay,
                timeZoneIdentifier: meal.captureTimeZoneIdentifier ?? MealLocalDay.legacyTimeZone.identifier,
                timeKnown: meal.recordedTimeKnown, mealType: meal.mealTypeRaw, originalText: meal.name,
                originalFeedback: meal.feedbackNotes,
                ownerNutrition: MealOwnerNutrition(calories: meal.isCalorieKnown ? meal.calories : nil,
                    proteinGrams: meal.isProteinKnown ? meal.proteinGrams : nil,
                    carbsGrams: meal.isCarbsKnown ? meal.carbsGrams : nil, fatGrams: meal.isFatKnown ? meal.fatGrams : nil,
                    source: meal.estimationMethod),
                photos: try photoService.exportAssets(for: [meal]), sourceFingerprint: try MealSourceFingerprint.value(for: meal))
        }
        return MealWeekPackage(schemaVersion: 1, exportedAt: .now, startLocalDay: startLocalDay, endLocalDay: endLocalDay, meals: sources)
    }

    /// Whole-batch validation occurs before mutation. Owner nutrition is never replaced.
    func apply(_ batch: MealReviewBatch, confirmed: Bool, context: ModelContext) throws -> MealReviewApplyResult {
        guard confirmed else { throw MealReviewError.confirmationRequired }
        guard batch.schemaVersion == 1, !batch.assessments.isEmpty,
              Set(batch.assessments.map(\.id)).count == batch.assessments.count,
              Set(batch.assessments.map(\.mealID)).count == batch.assessments.count else { throw MealReviewError.invalidBatch }
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        let byID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pending: [(meal: MealEntry, original: String?, originalUpdatedAt: Date, encoded: String)] = []
        var duplicates = 0
        for input in batch.assessments {
            try validate(input)
            guard input.batchID == nil || input.batchID == batch.id else { throw MealReviewError.invalidBatch }
            let assessment = canonicalAssessment(input, batchID: batch.id)
            guard let meal = byID[assessment.mealID], meal.isActiveMeal else { throw MealReviewError.missingMeal }
            // Read bytes, not only stored digests: an altered or missing photo also blocks the batch.
            _ = try photoService.exportAssets(for: [meal])
            guard try MealSourceFingerprint.value(for: meal) == assessment.sourceFingerprint else { throw MealReviewError.changedSource }
            var history = try assessments(for: meal)
            if let existing = history.first(where: { $0.id == assessment.id || $0.batchID == batch.id }) {
                guard canonicalAssessment(existing, batchID: batch.id) == assessment else { throw MealReviewError.conflictingAssessment }
                duplicates += 1
                continue
            }
            history.append(assessment)
            let encoded = String(decoding: try JSONEncoder().encode(history), as: UTF8.self)
            pending.append((meal, meal.mealAssessmentsJSON, meal.updatedAt, encoded))
        }
        for change in pending {
            change.meal.mealAssessmentsJSON = change.encoded
            change.meal.updatedAt = .now
        }
        do {
            if !pending.isEmpty { try context.save() }
        } catch {
            for change in pending {
                change.meal.mealAssessmentsJSON = change.original
                change.meal.updatedAt = change.originalUpdatedAt
            }
            throw error
        }
        return MealReviewApplyResult(appliedCount: pending.count, duplicateCount: duplicates)
    }

    func assessments(for meal: MealEntry) throws -> [MealAssessment] {
        guard let raw = meal.mealAssessmentsJSON else { return [] }
        guard let data = raw.data(using: .utf8), let history = try? JSONDecoder().decode([MealAssessment].self, from: data) else {
            throw MealReviewError.corruptHistory
        }
        guard Set(history.map(\.id)).count == history.count, history.allSatisfy({ $0.mealID == meal.id }) else {
            throw MealReviewError.corruptHistory
        }
        for assessment in history { try validate(assessment) }
        return history
    }

    private func validate(_ assessment: MealAssessment) throws {
        let ranges = [assessment.calories, assessment.proteinGrams, assessment.carbsGrams, assessment.fatGrams].compactMap { $0 }
        guard !assessment.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              assessment.sourceFingerprint.count == 64,
              assessment.sourceFingerprint.allSatisfy({ $0.isHexDigit }),
              ranges.allSatisfy(\.isValid),
              assessment.dishes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MealReviewError.invalidBatch
        }
    }

    /// Wire dates are ISO8601 seconds. Normalize new writes and comparisons, never old history.
    private func canonicalAssessment(_ value: MealAssessment, batchID: UUID) -> MealAssessment {
        MealAssessment(id: value.id, batchID: batchID, mealID: value.mealID,
            sourceFingerprint: value.sourceFingerprint,
            reviewedAt: Date(timeIntervalSince1970: floor(value.reviewedAt.timeIntervalSince1970)),
            provider: value.provider, dishes: value.dishes, calories: value.calories,
            proteinGrams: value.proteinGrams, carbsGrams: value.carbsGrams, fatGrams: value.fatGrams,
            summary: value.summary, limitations: value.limitations)
    }
}

import SwiftUI

struct MealAssessmentCard: View {
    let assessment: MealAssessment
    var title = "已确认的 AI 评估"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SprintSectionHeading(title: title, icon: "sparkles")
            ForEach(Array(assessment.dishes.enumerated()), id: \.offset) { _, dish in
                VStack(alignment: .leading, spacing: 3) {
                    Text(dish.name).font(.subheadline.bold())
                    Text(dish.portionDescription).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
            }
            range("热量", assessment.calories, unit: "kcal")
            range("蛋白质", assessment.proteinGrams, unit: "g")
            range("碳水", assessment.carbsGrams, unit: "g")
            range("脂肪", assessment.fatGrams, unit: "g")
            if !assessment.summary.isEmpty {
                Text(assessment.summary).font(.subheadline).textSelection(.enabled)
            }
            if !assessment.limitations.isEmpty {
                DisclosureGroup("仍不确定 · \(assessment.limitations.count) 项") {
                    ForEach(Array(assessment.limitations.enumerated()), id: \.offset) { _, item in
                        Text("• \(item)").font(.caption)
                    }
                }.font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Text("来源：\(assessment.provider) · \(assessment.reviewedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text("照片估算，不是称重或实测；不覆盖本人记录。")
                .font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func range(_ name: String, _ range: MealEstimateRange?, unit: String) -> some View {
        HStack {
            Text(name).foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(range.map { Self.rangeText($0, unit: unit) } ?? "未知")
                .monospacedDigit()
        }.font(.subheadline)
    }

    static func rangeText(_ range: MealEstimateRange, unit: String) -> String {
        let lower = range.lower.formatted(.number.precision(.fractionLength(0...1)))
        let upper = range.upper.formatted(.number.precision(.fractionLength(0...1)))
        return range.lower == range.upper ? "约 \(lower) \(unit)" : "约 \(lower)–\(upper) \(unit)"
    }
}

import SwiftData
import SwiftUI

struct MealPhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var meal: MealEntry
    @State private var showsCapture = false
    @State private var showsEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        SprintIcon(systemName: meal.mealType.systemImage, size: 48, prominent: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meal.mealType.title).font(.title2.bold())
                            Text("\(meal.stableLocalDay) · \(MealPhotoPresentation.time(meal))")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Text(meal.captureTimeZoneIdentifier ?? "Asia/Shanghai")
                            .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                    }

                    if !meal.mealPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(meal.mealPhotos) { photo in
                                    MealStoredPhoto(photo: photo, contentMode: .fit)
                                        .frame(width: 280, height: 320)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                        Text("\(meal.mealPhotos.count) 张原照片")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .accessibilityIdentifier("餐食详情-照片数")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SprintSectionHeading(title: "本人记录", icon: "person.crop.circle")
                        Text(meal.name.isEmpty ? "只拍照，未填写备注。" : meal.name)
                            .font(.body).textSelection(.enabled)
                        if let notes = meal.feedbackNotes, !notes.isEmpty {
                            Text(notes).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                        if meal.isCalorieKnown || meal.isProteinKnown || meal.isCarbsKnown || meal.isFatKnown {
                            Text(meal.estimationMethod ?? "原记录营养")
                                .font(.caption).foregroundStyle(AppTheme.ink)
                            nutrient("热量", known: meal.isCalorieKnown, value: meal.calories, unit: "kcal")
                            nutrient("蛋白质", known: meal.isProteinKnown, value: meal.proteinGrams, unit: "g")
                            nutrient("碳水", known: meal.isCarbsKnown, value: meal.carbsGrams, unit: "g")
                            nutrient("脂肪", known: meal.isFatKnown, value: meal.fatGrams, unit: "g")
                        } else {
                            Text("营养未知 · 尚未评估")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                    }.cardSurface()

                    if let assessment = meal.latestApplicableAssessment {
                        MealAssessmentCard(assessment: assessment)
                    } else if !meal.mealAssessments.isEmpty {
                        Label("原记录已变化，上次评估不再用于汇总。请重新评估。", systemImage: "arrow.clockwise")
                            .font(.subheadline).foregroundStyle(AppTheme.orange).cardSurface()
                    }
                    if !meal.mealAssessments.isEmpty {
                        DisclosureGroup("评估历史（\(meal.mealAssessments.count)）") {
                            ForEach(meal.mealAssessments.sorted { $0.reviewedAt > $1.reviewedAt }) { assessment in
                                MealAssessmentCard(assessment: assessment, title: "历史估算")
                            }
                        }.font(.subheadline)
                    }

                    DisclosureGroup {
                        Text("手机连接 Mac 后，Codex 可以查看指定周的餐食照片。你确认整周评估后，结果会单独保留，不覆盖原照片和本人记录。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    } label: {
                        Label("周评估说明", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.cardSurface()

                    Button { showsEditor = true } label: {
                        Label("编辑本人记录", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(SprintSecondaryButtonStyle()).accessibilityIdentifier("餐食详情-编辑本人记录")
                }.padding(20)
            }
            .sprintPage()
            .safeAreaInset(edge: .bottom) {
                Button { showsCapture = true } label: {
                    Label("追加照片", systemImage: "camera.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(SprintPrimaryButtonStyle())
                    .disabled(meal.mealPhotos.count >= MealPhotoService.maximumPhotosPerMeal)
                    .accessibilityIdentifier("餐食详情-追加照片")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.background)
            }
            .navigationTitle("餐食详情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("餐食详情-关闭")
                }
            }
            .sheet(isPresented: $showsCapture) {
                MealPhotoComposer(date: meal.date, mealType: meal.mealType, isAppending: true) { photos, _, _, _ in
                    try MealPhotoService().appendPhotos(photos, to: meal, context: context)
                }
            }
            .sheet(isPresented: $showsEditor) {
                MealEditorView(meal: meal, date: meal.date).sprintPage()
            }
        }.sprintPage().tint(AppTheme.ink)
    }

    private func nutrient(_ title: String, known: Bool, value: Int, unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Spacer()
            Text(known ? "\(value) \(unit)" : "未知").monospacedDigit()
        }.font(.subheadline)
    }
}

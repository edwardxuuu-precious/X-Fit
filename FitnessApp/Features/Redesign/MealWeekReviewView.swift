import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MealWeekReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \MealEntry.date) private var allMeals: [MealEntry]
    @State private var selectedDate: Date
    @State private var showsImporter = false
    @State private var pendingBatch: MealReviewBatch?
    @State private var showsPreview = false
    @State private var exportedURL: URL?
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var selectedMeal: MealEntry?

    init(date: Date) { _selectedDate = State(initialValue: date) }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    private var weekStart: Date {
        let offset = (calendar.component(.weekday, from: selectedDate) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: selectedDate) ?? selectedDate
    }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var firstDay: String { MealLocalDay.string(for: weekStart) }
    private var lastDay: String { MealLocalDay.string(for: days.last ?? weekStart) }
    private var meals: [MealEntry] {
        allMeals.filter { $0.isActiveMeal && $0.stableLocalDay >= firstDay && $0.stableLocalDay <= lastDay }
    }
    private var pendingCount: Int { meals.filter { $0.latestApplicableAssessment == nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SprintPageHeader(title: "周回顾", icon: "calendar")
                    weekSelector
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(meals.count) 餐记录 · \(meals.filter { !$0.mealPhotos.isEmpty }.count) 餐有照片")
                            .font(.title3.bold()).accessibilityIdentifier("餐食周回顾-记录数")
                        Text("待评估 / 重评 \(pendingCount) 餐")
                            .font(.subheadline).foregroundStyle(AppTheme.ink)
                        Text("未记录、未评估均不按 0 kcal 计算。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .accessibilityIdentifier("餐食周回顾-覆盖说明")
                    }.cardSurface()

                    VStack(alignment: .leading, spacing: 14) {
                        SprintSectionHeading(title: "整周评估", icon: "sparkles")
                        DisclosureGroup("连接与评估方式") {
                            Text("连接并解锁手机后，让 Codex 读取这个日期范围。评估先交给你确认一次，再由 App 回写。没有连接时保持待处理。")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            Text("也可以导出这一周的照片与记录，或导入 Codex 返回的评估文件。不会自动上传，也不会修改个人营养目标。")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Button(action: exportWeek) {
                            Label("导出照片与记录", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(SprintSecondaryButtonStyle()).disabled(meals.isEmpty)
                            .accessibilityIdentifier("餐食周回顾-导出")
                        if let exportedURL {
                            ShareLink(item: exportedURL) {
                                Label("分享本周资料包", systemImage: "square.and.arrow.up.on.square")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(SprintSecondaryButtonStyle()).accessibilityIdentifier("餐食周回顾-分享")
                            Text("资料包含原餐食照片与备注，只分享给你信任的对象。")
                                .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                        }
                        Button { showsImporter = true } label: {
                            Label("导入整周评估", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(SprintSecondaryButtonStyle()).accessibilityIdentifier("餐食周回顾-导入评估")
                        if let resultMessage {
                            Label(resultMessage, systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(AppTheme.ink)
                                .accessibilityIdentifier("餐食周回顾-回写结果")
                        }
                    }.cardSurface()

                    VStack(alignment: .leading, spacing: 20) {
                        SprintSectionHeading(title: "本周记录", icon: "list.bullet")
                        ForEach(days, id: \.self) { date in daySection(date) }
                    }
                }.padding(20)
            }
            .sprintPage().navigationTitle("餐食周回顾").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                readReviewFile(result)
            }
            .sheet(isPresented: $showsPreview, onDismiss: { pendingBatch = nil }) {
                if let pendingBatch {
                    MealWeekAssessmentPreview(batch: pendingBatch, meals: meals) {
                        // Re-read and validate the entire source before any writes.
                        let result = try MealReviewService().apply(pendingBatch, confirmed: true, context: context)
                        resultMessage = "新增 \(result.appliedCount) 餐评估 · \(result.duplicateCount) 餐已存在"
                    }
                }
            }
            .sheet(item: $selectedMeal) { meal in MealPhotoDetailView(meal: meal) }
            .alert("无法处理餐食资料", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }.sprintPage().tint(AppTheme.ink)
            .environment(\.calendar, calendar).environment(\.timeZone, TimeZone.current)
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private var weekSelector: some View {
        VStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(firstDay).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("餐食周回顾-起始日期")
                    Text("至").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(lastDay).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("餐食周回顾-结束日期")
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    weekStep(-1, icon: "chevron.left", label: "上一周")
                    Spacer()
                    weekStep(1, icon: "chevron.right", label: "下一周")
                }
            } else {
                HStack {
                    weekStep(-1, icon: "chevron.left", label: "上一周")
                    Spacer()
                    Text("\(firstDay) — \(lastDay)").font(.subheadline.bold()).multilineTextAlignment(.center)
                    Spacer()
                    weekStep(1, icon: "chevron.right", label: "下一周")
                }
            }
            Text("按每餐记录时的当地日期归档")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func weekStep(_ offset: Int, icon: String, label: String) -> some View {
        Button { changeWeek(offset) } label: {
            Image(systemName: icon).frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(label)
    }

    private func daySection(_ date: Date) -> some View {
        let day = MealLocalDay.string(for: date)
        let entries = meals.filter { $0.stableLocalDay == day }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(date, format: .dateTime.month().day().weekday()).font(.subheadline.bold())
                Spacer()
                Text(entries.isEmpty ? "未记录" : "\(entries.count) 餐记录")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(entries) { meal in
                Button { selectedMeal = meal } label: {
                    HStack(spacing: 12) {
                        if let photo = meal.mealPhotos.first {
                            MealStoredPhoto(photo: photo).frame(width: 58, height: 58).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "text.alignleft").foregroundStyle(AppTheme.secondaryText)
                                .frame(width: 58, height: 58).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(meal.mealType.title) · \(MealPhotoPresentation.time(meal))").font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(MealPhotoPresentation.title(meal)).font(.subheadline).lineLimit(2)
                            Text(meal.photoReviewStatus).font(.caption2).foregroundStyle(AppTheme.ink)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }.frame(minHeight: 60).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider().overlay(AppTheme.line)
        }
    }

    private func changeWeek(_ offset: Int) {
        selectedDate = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) ?? selectedDate
        exportedURL = nil
        resultMessage = nil
    }

    private func exportWeek() {
        do {
            let package = try MealReviewService().exportWeek(meals: allMeals, startLocalDay: firstDay, endLocalDay: lastDay)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("XFitMealExports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("xfit-meals-\(firstDay)-\(lastDay).json")
            try encoder.encode(package).write(to: url, options: .atomic)
            exportedURL = url
        } catch { errorMessage = error.localizedDescription }
    }

    private func readReviewFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5 * 1_024 * 1_024 else { throw MealReviewError.invalidBatch }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let batch = try decoder.decode(MealReviewBatch.self, from: Data(contentsOf: url))
            let selectedIDs = Set(meals.map(\.id))
            guard batch.schemaVersion == 1, !batch.assessments.isEmpty,
                  batch.assessments.allSatisfy({ selectedIDs.contains($0.mealID) }) else {
                throw FatLossError.invalidInput("评估文件包含不属于当前这一周的餐食，或没有可确认的评估。请先选择对应周。")
            }
            pendingBatch = batch
            showsPreview = true
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct MealWeekAssessmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let batch: MealReviewBatch
    let meals: [MealEntry]
    let onConfirm: () throws -> Void
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SprintPageHeader(title: "\(batch.assessments.count) 餐待确认", icon: "checkmark.shield")
                    Text("这是一份待确认的照片估算。请核对菜式、共餐份额和不确定项；确认后一次写入整批，不覆盖本人记录或调整营养目标。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    ForEach(batch.assessments) { assessment in
                        VStack(alignment: .leading, spacing: 8) {
                            if let meal = meals.first(where: { $0.id == assessment.mealID }) {
                                Text("\(meal.stableLocalDay) · \(meal.mealType.title)").font(.headline)
                                Text(MealPhotoPresentation.title(meal)).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            MealAssessmentCard(assessment: assessment, title: "待确认估算")
                        }
                    }
                }.padding(20)
            }
            .sprintPage().navigationTitle("确认整周评估").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("暂不写入") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    do { try onConfirm(); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Text("确认整周并写入 App").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(SprintPrimaryButtonStyle())
                    .accessibilityIdentifier("餐食周回顾-确认写入")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.background)
            }
            .alert("未写入评估", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }.sprintPage().tint(AppTheme.ink)
    }
}

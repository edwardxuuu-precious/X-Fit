import SwiftData
import SwiftUI

struct NutritionPreviewCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [MealEntry]
    @Query private var targets: [NutritionTarget]

    private var todayMeals: [MealEntry] {
        meals.filter { $0.isActiveMeal && FatLossCalendar.sameDay($0.date, .now) }
    }

    private var calories: Int {
        todayMeals.filter(\.isCalorieKnown).reduce(0) { $0 + $1.calories }
    }

    private var displayTarget: NutritionDisplayTarget {
        NutritionDisplayTarget.resolve(on: .now, legacy: targets.first, in: modelContext)
    }
    private var hasUnknownNutrition: Bool { todayMeals.contains { !$0.isNutritionKnown } }

    var body: some View {
        NavigationLink(destination: NutritionView()) {
            HStack(spacing: 18) {
                NeonProgressRing(
                    progress: displayTarget.calories.map { Double(calories) / Double(max(1, $0)) } ?? 0,
                    value: todayMeals.isEmpty ? "—" : (todayMeals.contains(where: \.isCalorieKnown) ? "\(calories)" : "未知"),
                    detail: displayTarget.calories.map { "/ \($0) kcal" } ?? "目标待确认"
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text("今日营养")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(todayMeals.isEmpty ? "还没有记录餐食" : (hasUnknownNutrition ? "部分记录 · 含营养未知餐食" : "已记录 \(calories) kcal"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Label("打开营养记录", systemImage: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("打开营养记录")
    }
}

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var targets: [NutritionTarget]

    @State private(set) var selectedDate = FatLossCalendar.day(.now)
    @State private var showMealEditor = false
    @State private var editingMeal: MealEntry?
    @State private var showTargetEditor = false
    @State private var errorMessage: String?

    init(initialDate: Date = .now) {
        _selectedDate = State(initialValue: FatLossCalendar.day(initialDate))
    }

    private var target: NutritionTarget? { targets.first }
    private var displayTarget: NutritionDisplayTarget {
        NutritionDisplayTarget.resolve(on: selectedDate, legacy: target, in: modelContext)
    }
    private var hasUnknownNutrition: Bool { selectedMeals.contains { !$0.isNutritionKnown } }
    private var selectedMeals: [MealEntry] {
        meals.filter { $0.isActiveMeal && FatLossCalendar.sameDay($0.date, selectedDate) }
    }
    private var calories: Int { selectedMeals.filter(\.isCalorieKnown).reduce(0) { $0 + $1.calories } }
    private var protein: Int { selectedMeals.filter(\.isProteinKnown).reduce(0) { $0 + $1.proteinGrams } }
    private var carbs: Int { selectedMeals.filter(\.isCarbsKnown).reduce(0) { $0 + $1.carbsGrams } }
    private var fat: Int { selectedMeals.filter(\.isFatKnown).reduce(0) { $0 + $1.fatGrams } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                dateSelector
                calorieCard
                if hasUnknownNutrition {
                    Text("部分营养未知 · 仅合计已知数值")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }

                HStack {
                    SectionHeader(title: "餐食", actionTitle: "\(selectedMeals.count) 条")
                    Spacer()
                    if displayTarget.isProgram {
                        Text("目标在减脂计划中管理")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Button("调整目标") { showTargetEditor = true }
                            .frame(minHeight: 44).font(.caption.bold()).foregroundStyle(AppTheme.accent)
                    }
                }

                if selectedMeals.isEmpty {
                    ContentUnavailableView(
                        "当天还没有餐食",
                        systemImage: "fork.knife.circle",
                        description: Text("吃完后记录，营养可留空。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    ForEach(selectedMeals) { meal in
                        mealRow(meal)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground().fatLossCalendar()
        .navigationTitle("饮食记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingMeal = nil
                    showMealEditor = true
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .disabled(FatLossCalendar.day(selectedDate) > FatLossCalendar.day(.now))
                    .accessibilityLabel("记录餐食")
            }
        }
        .sheet(isPresented: $showMealEditor) {
            MealEditorView(meal: editingMeal, date: selectedDate)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .sheet(isPresented: $showTargetEditor) {
            NutritionTargetEditorView(target: target)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var dateSelector: some View {
        HStack {
            Button { selectedDate = FatLossCalendar.adding(-1, to: selectedDate) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("前一天")
            DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden().frame(maxWidth: .infinity, minHeight: 44)
            Button { selectedDate = FatLossCalendar.adding(1, to: selectedDate) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.accessibilityLabel("后一天")
        }.foregroundStyle(.white)
    }

    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedMeals.isEmpty ? "—" : (selectedMeals.contains(where: \.isCalorieKnown) ? "\(calories)" : "未知"))
                    .font(AppTheme.metricValue).foregroundStyle(.white)
                Text("kcal 已记录").font(.caption).foregroundStyle(AppTheme.secondaryText)
                Spacer()
            }
            Text(displayTarget.calories.map { "目标 \($0) kcal" } ?? "目标待确认")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            macroRow(name: "蛋白质", value: selectedMeals.contains(where: \.isProteinKnown) ? protein : nil, target: displayTarget.protein, tint: AppTheme.secondaryText)
            macroRow(name: "碳水", value: selectedMeals.contains(where: \.isCarbsKnown) ? carbs : nil, target: displayTarget.carbs, tint: AppTheme.secondaryText)
            macroRow(name: "脂肪", value: selectedMeals.contains(where: \.isFatKnown) ? fat : nil, target: displayTarget.fat, tint: AppTheme.secondaryText)
        }.padding(.vertical, 8)
    }

    private func macroRow(name: String, value: Int?, target: Int?, tint: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(tint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text((value.map { "\($0)g" } ?? "未知") + (target.map { " / \($0)g" } ?? " · 目标待确认"))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    private func mealRow(_ meal: MealEntry) -> some View {
        Button {
            editingMeal = meal
            showMealEditor = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: meal.mealType.systemImage)
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("\(meal.mealType.title) · 蛋白 \(meal.isProteinKnown ? "\(meal.proteinGrams)g" : "未知") · 碳水 \(meal.isCarbsKnown ? "\(meal.carbsGrams)g" : "未知") · 脂肪 \(meal.isFatKnown ? "\(meal.fatGrams)g" : "未知")")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(meal.isCalorieKnown ? "\(meal.calories) kcal" : "未知")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 12).frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                meal.isVoided = true
                meal.updatedAt = .now
                do {
                    try modelContext.save()
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("删除餐食", systemImage: "trash")
            }
        }
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let meal: MealEntry?
    let date: Date

    @State private var name: String
    @State private var mealType: MealType
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var errorMessage: String?

    init(meal: MealEntry?, date: Date, initialMealType: MealType = .breakfast) {
        self.meal = meal
        self.date = meal?.date ?? FatLossCalendar.day(date)
        _name = State(initialValue: meal?.name ?? "")
        _mealType = State(initialValue: meal?.mealType ?? initialMealType)
        _calories = State(initialValue: meal.flatMap { $0.isCalorieKnown ? String($0.calories) : nil } ?? "")
        _protein = State(initialValue: meal.flatMap { $0.isProteinKnown ? String($0.proteinGrams) : nil } ?? "")
        _carbs = State(initialValue: meal.flatMap { $0.isCarbsKnown ? String($0.carbsGrams) : nil } ?? "")
        _fat = State(initialValue: meal.flatMap { $0.isFatKnown ? String($0.fatGrams) : nil } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("餐食") {
                    TextField("名称", text: $name)
                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Text(date, format: .dateTime.year().month().day())
                        .foregroundStyle(.secondary)
                }
                Section("营养") {
                    numberField("热量", value: $calories, unit: "kcal")
                    numberField("蛋白质", value: $protein, unit: "g")
                    numberField("碳水", value: $carbs, unit: "g")
                    numberField("脂肪", value: $fat, unit: "g")
                    Text("知道哪项填哪项；未知留空，实际为零请填写 0。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).screenBackground().fatLossCalendar().fatLossInput()
            .navigationTitle(meal == nil ? "记录餐食" : "编辑餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func numberField(_ title: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("未知", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80, height: 44)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard FatLossCalendar.day(date) <= FatLossCalendar.day(.now) else {
            errorMessage = "未来日期只能安排餐单，吃完后再记录实际。"
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let values = try MealNutritionInput(calories: calories, protein: protein, carbs: carbs, fat: fat)
            let entry = meal ?? MealEntry(date: date, mealType: mealType, name: cleanName,
                                         calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
            if meal == nil { modelContext.insert(entry) }
            entry.name = cleanName
            entry.mealType = mealType
            values.apply(to: entry)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MealNutritionInput {
    let values: [Int?]
    static let keys = ["calories", "protein", "carbs", "fat"]

    init(calories: String, protein: String, carbs: String, fat: String) throws {
        values = try [calories, protein, carbs, fat].map { raw in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            guard let value = Int(text), (0...100_000).contains(value) else {
                throw WellnessToolError.invalidValue("营养值请填非负整数；未知留空。")
            }
            return value
        }
    }

    @MainActor func apply(to meal: MealEntry) {
        meal.calories = values[0] ?? 0
        meal.proteinGrams = values[1] ?? 0
        meal.carbsGrams = values[2] ?? 0
        meal.fatGrams = values[3] ?? 0
        meal.knownNutritionFieldsRaw = zip(Self.keys, values).compactMap { key, value in value == nil ? nil : key }.joined(separator: ",")
        meal.nutritionKnown = values.allSatisfy { $0 != nil }
        meal.estimationMethod = values.contains(where: { $0 != nil }) ? "本人手动核算" : "未核算"
        meal.updatedAt = .now
    }
}

/// Historical targets resolve without requiring legacy test stores to register program models.
struct NutritionDisplayTarget {
    var isProgram: Bool
    var calories: Int?
    var protein: Int?
    var carbs: Int?
    var fat: Int?

    @MainActor static func resolve(on date: Date, legacy: NutritionTarget?, in context: ModelContext) -> Self {
        let legacyValue = Self(isProgram: false, calories: legacy?.calories ?? 2400,
                               protein: legacy?.proteinGrams ?? 160, carbs: legacy?.carbsGrams ?? 250,
                               fat: legacy?.fatGrams ?? 80)
        guard FatLossBackupService.isRegistered(FatLossProgram.self, in: context) else { return legacyValue }
        let pending = Self(isProgram: true, calories: nil, protein: nil, carbs: nil, fat: nil)
        do {
            let programs = try context.fetch(FetchDescriptor<FatLossProgram>())
            guard let program = programs.filter({
                $0.statusRaw != "cancelled" && ($0.contains(date)
                    || ($0.statusRaw == "active" && (FatLossCalendar.day(date) >= $0.startDate
                        || (FatLossCalendar.sameDay(date, .now) && FatLossCalendar.day(date) < $0.startDate))))
            })
                .sorted(by: { $0.createdAt > $1.createdAt }).first else { return legacyValue }
            guard FatLossBackupService.isRegistered(ProgramTargetRevision.self, in: context) else { return pending }
            let revisions = try context.fetch(FetchDescriptor<ProgramTargetRevision>())
            guard let revision = revisions.filter({ $0.programID == program.id && $0.effectiveDate <= FatLossCalendar.day(date) })
                .sorted(by: { $0.effectiveDate == $1.effectiveDate ? $0.createdAt > $1.createdAt : $0.effectiveDate > $1.effectiveDate }).first,
                  revision.isNutritionConfirmed else { return pending }
            return Self(isProgram: true, calories: revision.calories, protein: revision.proteinGrams,
                        carbs: revision.carbsGrams, fat: revision.fatGrams)
        } catch { return pending }
    }
}

private struct NutritionTargetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let target: NutritionTarget?
    @State private var calories: Int
    @State private var protein: Int
    @State private var carbs: Int
    @State private var fat: Int

    init(target: NutritionTarget?) {
        self.target = target
        _calories = State(initialValue: target?.calories ?? 2400)
        _protein = State(initialValue: target?.proteinGrams ?? 160)
        _carbs = State(initialValue: target?.carbsGrams ?? 250)
        _fat = State(initialValue: target?.fatGrams ?? 80)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("热量：\(calories) kcal", value: $calories, in: 800...6000, step: 50)
                Stepper("蛋白质：\(protein) g", value: $protein, in: 0...500, step: 5)
                Stepper("碳水：\(carbs) g", value: $carbs, in: 0...800, step: 5)
                Stepper("脂肪：\(fat) g", value: $fat, in: 0...300, step: 5)
            }
            .scrollContentBackground(.hidden).screenBackground().fatLossCalendar()
            .navigationTitle("每日营养目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = target ?? NutritionTarget()
                        if target == nil { modelContext.insert(saved) }
                        saved.calories = calories
                        saved.proteinGrams = protein
                        saved.carbsGrams = carbs
                        saved.fatGrams = fat
                        saved.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

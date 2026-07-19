import SwiftData
import SwiftUI

struct NutritionPreviewCard: View {
    @Query private var meals: [MealEntry]
    @Query private var targets: [NutritionTarget]

    private var todayMeals: [MealEntry] {
        meals.filter { $0.date.isSameDay(as: .now) }
    }

    private var calories: Int {
        todayMeals.reduce(0) { $0 + $1.calories }
    }

    private var calorieTarget: Int {
        targets.first?.calories ?? 2400
    }

    var body: some View {
        NavigationLink(destination: NutritionView()) {
            HStack(spacing: 18) {
                NeonProgressRing(
                    progress: Double(calories) / Double(max(1, calorieTarget)),
                    value: "\(calories)",
                    detail: "/ \(calorieTarget) kcal"
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text("今日营养")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(todayMeals.isEmpty ? "还没有记录餐食" : "还可摄入 \(max(0, calorieTarget - calories)) kcal")
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
    }
}

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var targets: [NutritionTarget]

    @State private var selectedDate = Date.now.startOfDay
    @State private var showMealEditor = false
    @State private var editingMeal: MealEntry?
    @State private var showTargetEditor = false
    @State private var errorMessage: String?

    private var target: NutritionTarget? { targets.first }
    private var selectedMeals: [MealEntry] {
        meals.filter { $0.date.isSameDay(as: selectedDate) }
    }
    private var calories: Int { selectedMeals.reduce(0) { $0 + $1.calories } }
    private var protein: Int { selectedMeals.reduce(0) { $0 + $1.proteinGrams } }
    private var carbs: Int { selectedMeals.reduce(0) { $0 + $1.carbsGrams } }
    private var fat: Int { selectedMeals.reduce(0) { $0 + $1.fatGrams } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: selectedDate.formatted(
                        .dateTime.locale(Locale(identifier: "zh_Hans_CN")).month().day().weekday(.wide)
                    ),
                    title: "营养",
                    trailingSystemImage: "plus",
                    trailingAction: {
                        editingMeal = nil
                        showMealEditor = true
                    }
                )

                dateSelector
                calorieCard

                HStack {
                    SectionHeader(title: "餐食", actionTitle: "\(selectedMeals.count) 条")
                    Spacer()
                    Button("调整目标") { showTargetEditor = true }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }

                if selectedMeals.isEmpty {
                    ContentUnavailableView(
                        "当天还没有餐食",
                        systemImage: "fork.knife.circle",
                        description: Text("点击右上角，记录真实的热量和宏量营养素。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    ForEach(selectedMeals) { meal in
                        mealRow(meal)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
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
            Button {
                selectedDate = selectedDate.addingDays(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Button {
                selectedDate = Date.now.startOfDay
            } label: {
                Text(selectedDate.isSameDay(as: .now) ? "今天" : selectedDate.formatted(.dateTime.month().day()))
                    .font(.subheadline.bold())
            }
            Spacer()
            Button {
                selectedDate = selectedDate.addingDays(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedDate.isSameDay(as: .now))
        }
        .foregroundStyle(AppTheme.accent)
        .cardSurface(padding: 13, cornerRadius: 14)
    }

    private var calorieCard: some View {
        let calorieTarget = target?.calories ?? 2400
        return HStack(spacing: 20) {
            NeonProgressRing(
                progress: Double(calories) / Double(max(1, calorieTarget)),
                value: "\(calories)",
                detail: "/ \(calorieTarget) kcal",
                size: 112
            )
            VStack(alignment: .leading, spacing: 12) {
                macroRow(name: "蛋白质", value: protein, target: target?.proteinGrams ?? 160, tint: AppTheme.accent)
                macroRow(name: "碳水", value: carbs, target: target?.carbsGrams ?? 250, tint: AppTheme.orange)
                macroRow(name: "脂肪", value: fat, target: target?.fatGrams ?? 80, tint: AppTheme.purple)
            }
        }
        .cardSurface(padding: 18, cornerRadius: 20)
    }

    private func macroRow(name: String, value: Int, target: Int, tint: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(tint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("\(value)g / \(target)g")
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
                    Text("\(meal.mealType.title) · 蛋白 \(meal.proteinGrams)g · 碳水 \(meal.carbsGrams)g · 脂肪 \(meal.fatGrams)g")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(meal.calories) kcal")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            .cardSurface(padding: 12, cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(meal)
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

private struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let meal: MealEntry?
    let date: Date

    @State private var name: String
    @State private var mealType: MealType
    @State private var calories: Int
    @State private var protein: Int
    @State private var carbs: Int
    @State private var fat: Int
    @State private var errorMessage: String?

    init(meal: MealEntry?, date: Date) {
        self.meal = meal
        self.date = date
        _name = State(initialValue: meal?.name ?? "")
        _mealType = State(initialValue: meal?.mealType ?? .breakfast)
        _calories = State(initialValue: meal?.calories ?? 0)
        _protein = State(initialValue: meal?.proteinGrams ?? 0)
        _carbs = State(initialValue: meal?.carbsGrams ?? 0)
        _fat = State(initialValue: meal?.fatGrams ?? 0)
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
                }
            }
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

    private func numberField(_ title: String, value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let meal {
            meal.name = cleanName
            meal.mealType = mealType
            meal.calories = max(0, calories)
            meal.proteinGrams = max(0, protein)
            meal.carbsGrams = max(0, carbs)
            meal.fatGrams = max(0, fat)
            meal.updatedAt = .now
        } else {
            modelContext.insert(
                MealEntry(
                    date: date,
                    mealType: mealType,
                    name: cleanName,
                    calories: max(0, calories),
                    proteinGrams: max(0, protein),
                    carbsGrams: max(0, carbs),
                    fatGrams: max(0, fat)
                )
            )
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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

import SwiftData
import SwiftUI

struct NutritionHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \FatLossProgram.createdAt, order: .reverse) private var programs: [FatLossProgram]
    @Query private var plans: [PlannedMeal]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query private var water: [HydrationEntry]
    @State private var selectedDate = Date.now
    @State private var selectedPlan: PlannedMeal?
    @State private var selectedActual: MealEntry?
    @State private var showsExtraMeal = false
    @State private var extraMealType: MealType = .snack
    @State private var showsPrep = false
    @State private var showsMenu = false
    @State private var showsWater = false
    @State private var showsDatePicker = false
    @State private var errorMessage: String?

    private var program: FatLossProgram? { programs.first { $0.statusRaw == "active" } }
    private var today: Date { FatLossCalendar.day(selectedDate) }
    private var isToday: Bool { FatLossCalendar.sameDay(today, .now) }
    private var isFuture: Bool { today > FatLossCalendar.day(.now) }
    private var todaysMeals: [MealEntry] {
        meals.filter { $0.isActiveMeal && FatLossCalendar.sameDay($0.date, today) }
    }
    private var loggedSlots: Int {
        [MealType.breakfast, .lunch, .dinner].filter { type in todaysMeals.contains { $0.mealType == type } }.count
    }
    private var primaryMealType: MealType? {
        guard !isFuture else { return nil }
        return [MealType.breakfast, .lunch, .dinner].first { type in
            !todaysMeals.contains { $0.mealType == type } && plans.contains {
                $0.programID == program?.id && $0.isCurrent && $0.mealType == type
                    && $0.statusRaw != "skipped" && FatLossCalendar.sameDay($0.date, today)
            }
        }
    }
    private var waterTotal: Int {
        water.filter { FatLossCalendar.sameDay($0.date, today) }.reduce(0) { $0 + $1.milliliters }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("X-FIT / NUTRITION")
                        .font(.caption2.weight(.heavy)).tracking(2)
                        .foregroundStyle(AppTheme.secondaryText)
                    HStack(alignment: .center) {
                        Text(isToday ? "今日饮食" : "饮食")
                            .font(AppTheme.pageTitle).foregroundStyle(AppTheme.posterWarmWhite)
                        Spacer(minLength: 8)
                        Button { showsDatePicker = true } label: {
                            Image(systemName: "calendar")
                                .font(.title3).foregroundStyle(AppTheme.posterWarmWhite)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("选择饮食日期")
                            .accessibilityIdentifier("饮食-日期选择")
                    }
                    let dateLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
                    dateLayout {
                        Text(today, format: .dateTime.month().day().weekday(.wide))
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Text("\(loggedSlots)/3 餐已记")
                            .accessibilityIdentifier("饮食-已记录餐数")
                            .accessibilityValue("\(loggedSlots)/3")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.accent)
                        if !isToday {
                            Button("今天") { selectedDate = .now }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("饮食-返回今天")
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                        mealSlot(type)
                        if type != .dinner { Divider().overlay(AppTheme.line) }
                    }
                }

                if let program {
                    Button { showsPrep = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "basket")
                                .font(.title2.weight(.light)).foregroundStyle(AppTheme.accent)
                                .frame(width: 48, height: 48)
                                .background(AppTheme.accent.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isToday ? "明日备餐" : "次日备餐")
                                    .font(.title3.weight(.bold)).foregroundStyle(AppTheme.posterWarmWhite)
                                Text("午晚餐 · 采购清单 · 一键分享")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }.padding(.vertical, 22)
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .overlay(alignment: .top) { Rectangle().fill(AppTheme.accent.opacity(0.5)).frame(height: 1) }
                            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("饮食-明日备餐")
                        .disabled(!program.contains(FatLossCalendar.adding(1, to: today), includeReviewDay: false))
                } else {
                    NavigationLink(destination: GoalHomeView()) {
                        FatLossNavigationRow(title: "设置主目标与餐单", icon: "target")
                    }.buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    Button { extraMealType = .snack; showsExtraMeal = true } label: {
                        FatLossNavigationRow(title: "记录外卖 / 加餐", icon: "plus", trailing: "手动填写")
                    }.accessibilityIdentifier("饮食-记录外卖加餐").disabled(isFuture)
                    Divider().overlay(AppTheme.line)
                    Button { showsWater = true } label: {
                        FatLossNavigationRow(title: "饮水", icon: "drop", trailing: "\(waterTotal) ml")
                    }.accessibilityIdentifier("饮食-饮水").disabled(isFuture)
                    Divider().overlay(AppTheme.line)
                    NavigationLink(destination: NutritionView(initialDate: today)) {
                        FatLossNavigationRow(title: "饮食记录", icon: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("饮食-全部记录")
                    if let program {
                        Divider().overlay(AppTheme.line)
                        NavigationLink(destination: FatLossMealsView(program: program, initialDate: today)) {
                            FatLossNavigationRow(title: "餐单日历与食谱", icon: "calendar")
                        }.accessibilityIdentifier("饮食-餐单日历")
                    }
                }.buttonStyle(.plain)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
        }
        .screenBackground().fatLossCalendar().toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsDatePicker) {
            NavigationStack {
                ScrollView {
                    DatePicker("饮食日期", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding(20)
                        .accessibilityIdentifier("饮食-日期日历")
                }
                .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsDatePicker = false }
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .fatLossCalendar().environment(\.locale, Locale(identifier: "zh_CN"))
            }.preferredColorScheme(.dark)
        }
        .sheet(item: $selectedPlan) { meal in
            NavigationStack { FatLossMealDetailView(meal: meal) }.preferredColorScheme(.dark)
        }
        .sheet(item: $selectedActual) { meal in
            MealEditorView(meal: meal, date: meal.date).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsExtraMeal) {
            MealEditorView(meal: nil, date: today, initialMealType: extraMealType).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsWater) {
            WaterQuickEntrySheet(initialAmount: 250, initialDate: isToday ? .now : today) { amount, date in
                do { _ = try WellnessToolService.execute(.recordWater(milliliters: amount, at: date), in: context) }
                catch { errorMessage = error.localizedDescription }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsPrep) {
            if let program {
                NavigationStack { FatLossPrepView(program: program, date: FatLossCalendar.adding(1, to: today)) }
                    .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showsMenu) {
            if let program {
                NavigationStack { FatLossMenuPreview(program: program, startDate: max(today, program.startDate)) }
                    .preferredColorScheme(.dark)
            }
        }
        .fatLossError($errorMessage)
    }

    @ViewBuilder private func mealSlot(_ type: MealType) -> some View {
        let plan = plans.first { $0.programID == program?.id && $0.isCurrent && $0.mealType == type && FatLossCalendar.sameDay($0.date, today) }
        let actuals = todaysMeals.filter { $0.mealType == type }
        let isPrimary = primaryMealType == type
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    mealPhoto(type)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(type.title).font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer(minLength: 4)
                        if !actuals.isEmpty {
                            Label("已记录", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(AppTheme.accent)
                        } else if plan?.statusRaw == "skipped" {
                            Text("明确未吃").font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    Text(actuals.isEmpty ? (plan?.title ?? "尚未安排") : actuals.map(\.name).joined(separator: "、"))
                        .font(.headline.weight(.bold)).foregroundStyle(AppTheme.posterWarmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    if !actuals.isEmpty {
                        Text(actuals.allSatisfy(\.isCalorieKnown)
                             ? "\(actuals.reduce(0) { $0 + $1.calories }) kcal"
                             : (actuals.count == 1 ? "营养待核算" : "营养未完整"))
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    } else if plan != nil {
                        Text(isFuture ? "计划餐食" : "计划已安排，等待实吃记录")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let actual = actuals.first {
                HStack {
                    Spacer()
                    if actuals.count > 1 {
                        NavigationLink(destination: NutritionView(initialDate: today)) {
                            Text("调整实吃")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.posterWarmWhite)
                                .frame(minWidth: 88, minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("饮食-调整实吃-\(type.title)")
                    } else {
                        Button("调整实吃") {
                            if let linked = plans.first(where: { $0.id == actual.plannedMealID }) { selectedPlan = linked }
                            else { selectedActual = actual }
                        }.font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.posterWarmWhite)
                            .frame(minWidth: 88, minHeight: 44).contentShape(Rectangle())
                            .accessibilityIdentifier("饮食-调整实吃-\(type.title)")
                    }
                }
            } else if let plan {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button { record(plan) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                            Text("按计划吃了")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isPrimary ? Color.black : AppTheme.posterWarmWhite)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        .padding(.horizontal, 8)
                        .background(isPrimary ? AppTheme.accent : AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityIdentifier("饮食-按计划吃了-\(type.title)").disabled(isFuture)
                    Button(isFuture ? "查看计划" : "调整实吃") { selectedPlan = plan }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.posterWarmWhite)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        .accessibilityIdentifier("饮食-调整实吃-\(type.title)")
                }.buttonStyle(.plain)
            } else {
                HStack {
                    if let program, program.contains(today, includeReviewDay: false) {
                        Button("选择餐单") { showsMenu = true }
                            .frame(minHeight: 44).foregroundStyle(AppTheme.posterWarmWhite)
                    }
                    Spacer()
                    Button("记录吃了什么") { extraMealType = type; showsExtraMeal = true }
                        .frame(minHeight: 44).foregroundStyle(AppTheme.posterWarmWhite).disabled(isFuture)
                }.font(.subheadline)
            }
        }.padding(.vertical, 12).accessibilityElement(children: .contain)
            .accessibilityIdentifier("饮食-餐次-\(type.title)")
    }

    private func mealPhoto(_ type: MealType) -> some View {
        let asset = type == .breakfast ? "EditorialBreakfast" : type == .lunch ? "EditorialLunch" : "EditorialDinner"
        return Image(asset).resizable().scaledToFill()
            .frame(width: 116, height: 88).clipped()
            .overlay(alignment: .bottom) {
                Text("菜式示意").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9)).padding(.vertical, 3)
                    .frame(maxWidth: .infinity).background(.black.opacity(0.55))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func record(_ plan: PlannedMeal) {
        do {
            let latest = try context.fetch(FetchDescriptor<MealEntry>())
            guard !latest.contains(where: { $0.isActiveMeal && $0.mealType == plan.mealType && FatLossCalendar.sameDay($0.date, plan.date) && ($0.programID == nil || $0.programID == plan.programID) }) else { return }
            _ = try FatLossService.recordMeal(plan, in: context)
        } catch { errorMessage = error.localizedDescription }
    }
}

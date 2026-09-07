import SwiftData
import SwiftUI

struct FatLossMealsView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [PlannedMeal]
    @Query private var actuals: [MealEntry]
    let program: FatLossProgram
    @State private var date: Date
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showsPreview = false
    @State private var showsPrep = false
    init(program: FatLossProgram, initialDate: Date? = nil) {
        self.program = program
        _date = State(initialValue: min(max(FatLossCalendar.day(initialDate ?? .now), program.startDate), FatLossCalendar.adding(-1, to: program.endDate)))
    }
    private var selected: [PlannedMeal] {
        plans.filter { $0.programID == program.id && $0.isCurrent && FatLossCalendar.sameDay($0.date, date) }
            .sorted { order($0.mealType) < order($1.mealType) }
    }
    private func order(_ type: MealType) -> Int { [.breakfast, .lunch, .dinner, .snack].firstIndex(of: type) ?? 3 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                DatePicker("查看日期", selection: $date, in: program.startDate...FatLossCalendar.adding(-1, to: program.endDate), displayedComponents: .date)
                    .datePickerStyle(.compact).tint(AppTheme.accent)
                HStack {
                    Button("14 天餐单预览") { showsPreview = true }.buttonStyle(.bordered)
                    Spacer()
                    Button { showsPrep = true } label: { Label(FatLossCalendar.sameDay(date, .now) ? "明日备餐" : "次日备餐", systemImage: "basket") }.buttonStyle(.bordered)
                        .disabled(FatLossCalendar.adding(1, to: date) >= program.endDate)
                }

                if selected.isEmpty {
                    ContentUnavailableView("当天尚未导入餐单", systemImage: "fork.knife", description: Text("查看 14 天轮换方案后，可导入选定日期开始的餐单。"))
                    Button("预览并导入餐单") { showsPreview = true }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("预览导入餐单")
                }
                ForEach(selected) { meal in
                    NavigationLink(destination: FatLossMealDetailView(meal: meal)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(meal.mealType.title, systemImage: meal.mealType.systemImage)
                                    .font(.caption.bold()).foregroundStyle(AppTheme.accent)
                                Spacer()
                                Text(actuals.contains { $0.plannedMealID == meal.id && $0.isActiveMeal } ? "已记录实吃" : (meal.statusRaw == "skipped" ? "明确未吃" : "计划"))
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Text(meal.title).font(.title3.bold()).foregroundStyle(.white)
                        }.padding(.vertical, 12)
                    }.buttonStyle(.plain).accessibilityIdentifier("计划餐-\(meal.mealType.title)")
                }
                NavigationLink("查看所有饮食记录 / 记录加餐", destination: NutritionView(initialDate: date))
                    .font(.subheadline.bold()).foregroundStyle(AppTheme.accent)
                NavigationLink("小红书博主与备餐来源", destination: FatLossRecipeSourcesView())
                    .font(.subheadline.bold()).foregroundStyle(AppTheme.accent)
                if let notice { Text(notice).font(.caption).foregroundStyle(AppTheme.accent) }
            }.padding(20)
        }.screenBackground().fatLossCalendar().navigationTitle("餐单与备餐").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showsPreview) {
                NavigationStack { FatLossMenuPreview(program: program, startDate: date) }.preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showsPrep) {
                NavigationStack { FatLossPrepView(program: program, date: min(FatLossCalendar.adding(1, to: date), FatLossCalendar.adding(-1, to: program.endDate))) }.preferredColorScheme(.dark)
            }
            .fatLossError($errorMessage)
    }
}

struct FatLossRecipeSourcesView: View {
    var body: some View {
        List {
            Section {
                Text("家常菜草案；博主用于口味参考，非原配方。")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            Section("已找到作者自述") {
                sourceRows(FatLossCatalog.sources.filter { $0.title.contains("曼食慢语") })
            }
            Section("待核验候选") { sourceRows(FatLossCatalog.creatorCandidates) }
            Section("储存与复热依据") {
                sourceRows(FatLossCatalog.sources.filter { !$0.title.contains("曼食慢语") })
            }
        }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar().navigationTitle("博主与来源").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
    private func sourceRows(_ sources: [RecipeSource]) -> some View {
        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
            VStack(alignment: .leading, spacing: 7) {
                if let url = URL(string: source.url) { Link(source.title, destination: url) }
                else { Text(source.title) }
                Text(source.verification).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.padding(.vertical, 4)
        }
    }
}

struct FatLossMenuPreview: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let program: FatLossProgram
    let startDate: Date
    @State private var allRemaining = false
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section {
                Text("从 \(FatLossCalendar.label(startDate)) 开始，每 14 天轮换。已存在餐次保持原样。")
                Toggle("导入到周期结束", isOn: $allRemaining)
                Text(allRemaining ? "导入剩余周期，按 14 天循环" : "先导入接下来 14 天")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(0..<14, id: \.self) { offset in
                let day = FatLossCalendar.adding(offset, to: startDate)
                if day < program.endDate {
                    Section(FatLossCalendar.label(day)) {
                        ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                            if let recipe = FatLossCatalog.recipe(dayIndex: FatLossCalendar.distance(program.startDate, day), mealType: type) {
                                NavigationLink(destination: FatLossRecipeView(recipe: recipe)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(type.title).font(.caption).foregroundStyle(AppTheme.accent)
                                        Text(recipe.title)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar().navigationTitle("14 天餐单预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do {
                            _ = try FatLossService.importMeals(program: program, from: startDate, days: allRemaining ? program.executionDays : 14, in: context)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.accessibilityIdentifier("确认导入餐单")
                }
            }.fatLossError($errorMessage)
    }
}

struct FatLossRecipeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsSteps = false
    let recipe: RecipeDraft
    private var asset: String {
        recipe.key.hasPrefix("breakfast") ? "EditorialBreakfast" : recipe.key.hasPrefix("lunch") ? "EditorialLunch" : "EditorialDinner"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(asset).resizable().scaledToFill().frame(height: 164).clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Text("餐食示意").font(.caption2).padding(7).background(.black.opacity(0.6), in: Capsule()).padding(12)
                    }.clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.title).font(.title2.bold()).foregroundStyle(AppTheme.posterWarmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(recipe.cookingMinutes) 分钟 · 原配方 \(recipe.portions.formatted()) 份")
                        .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("食谱-原配方份数")
                    if recipe.ingredients.contains(where: \.isMedicalPortionPending) {
                        Label("个人份量待确认", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
                layout {
                    recipeTab("食材", steps: false)
                    recipeTab("做法", steps: true)
                }.padding(4).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                if showsSteps { stepsContent } else { ingredientsContent }
                DisclosureGroup("份量与营养说明") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.householdPortion)
                        Text(recipe.nutritionSource)
                        if recipe.ingredients.contains(where: \.isMedicalPortionPending) {
                            Text("个人份量待医生建议确认，不据此定量。")
                        }
                    }.font(.subheadline).foregroundStyle(AppTheme.secondaryText).padding(.top, 8)
                }.accessibilityIdentifier("食谱-份量说明")
                DisclosureGroup("保存与复热") { Text(recipe.storageNote).padding(.top, 8) }
                DisclosureGroup("食材替换") {
                    ForEach(recipe.substitutions, id: \.self) { Text($0).padding(.top, 8) }
                }
                if !recipe.sources.isEmpty {
                    DisclosureGroup("来源与核验") {
                        ForEach(Array(recipe.sources.enumerated()), id: \.offset) { _, source in
                            VStack(alignment: .leading, spacing: 5) {
                                if let url = URL(string: source.url) { Link(source.title, destination: url) }
                                else { Text(source.title) }
                                Text(source.verification).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }.padding(20)
        }.screenBackground().fatLossCalendar().navigationTitle("食谱详情")
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { showsSteps.toggle() } label: {
                    Label(showsSteps ? "查看食材" : "查看做法", systemImage: showsSteps ? "carrot" : "list.number")
                        .neonButtonStyle()
                }.accessibilityIdentifier("食谱-切换内容")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.background)
            }
    }
    private func recipeTab(_ title: String, steps: Bool) -> some View {
        Button { showsSteps = steps } label: {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(showsSteps == steps ? AppTheme.background : AppTheme.secondaryText)
                .background(showsSteps == steps ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier(steps ? "食谱-做法" : "食谱-食材")
            .accessibilityAddTraits(showsSteps == steps ? .isSelected : [])
    }
    private var ingredientsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整批用量").font(.headline)
            Text("以下为原配方，备餐时按每餐 1 份折算。")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            VStack(spacing: 0) {
                ForEach(recipe.ingredients) { ingredient in
                    DisclosureGroup {
                        Text(ingredient.amountText).font(.subheadline).foregroundStyle(AppTheme.secondaryText).padding(.bottom, 10)
                        if let grams = ingredient.referenceGrams {
                            Text("整批参考 \(grams.formatted()) g · 未称重估算")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    } label: {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            Text(ingredient.name).foregroundStyle(AppTheme.posterWarmWhite)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                            Text(ingredient.isMedicalPortionPending ? "待确认" : ingredient.referenceGrams.map { "≈ \($0.formatted()) g" } ?? "量具用量")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                        }.frame(minHeight: 52).padding(.vertical, 4)
                    }.accessibilityIdentifier("食谱-食材-\(ingredient.name)")
                    if ingredient.id != recipe.ingredients.last?.id { Divider() }
                }
            }.padding(.horizontal, 16).padding(.vertical, 4)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private var stepsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(recipe.equipment.joined(separator: " · "), systemImage: "frying.pan")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 16) {
                    Text(String(format: "%02d", index + 1)).font(.title3.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text(step).font(.body).foregroundStyle(AppTheme.posterWarmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("食谱-步骤-\(index + 1)")
            }
        }
    }
}

struct FatLossPrepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var allMeals: [PlannedMeal]
    @State private var showsShopping = false
    @State private var showsPortionDetails = false
    let program: FatLossProgram
    let date: Date
    private var meals: [PlannedMeal] {
        PrepPresentation.selectedMeals(allMeals, programID: program.id, date: date)
    }
    private var shopping: [ShoppingItem] { FatLossService.shoppingList(meals: meals) }
    private func items(_ group: PrepPresentation.Group) -> [ShoppingItem] {
        shopping.filter { PrepPresentation.group(for: $0) == group }
    }
    private var storageNotes: [String] {
        meals.compactMap { $0.recipe?.storageNote }.reduce(into: []) { notes, note in
            if !note.isEmpty && !notes.contains(note) { notes.append(note) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                pageSwitch
                if meals.isEmpty {
                    ContentUnavailableView("还没有餐单", systemImage: "takeoutbag.and.cup.and.straw", description: Text("安排午晚餐后，在这里查看分装与采购。"))
                    NavigationLink("选择餐单", destination: FatLossMenuPreview(program: program, startDate: date))
                } else if showsShopping {
                    shoppingContent
                } else {
                    menuContent
                }
            }.padding(20)
        }.screenBackground().fatLossCalendar()
            .navigationTitle(FatLossCalendar.sameDay(date, FatLossCalendar.adding(1, to: .now)) ? "明日备餐" : "次日备餐")
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !meals.isEmpty {
                    ShareLink(item: FatLossService.prepText(program: program, date: date, meals: meals)) {
                        Label(typeSize.isAccessibilitySize ? "分享备餐单" : "分享给备餐人", systemImage: "square.and.arrow.up")
                            .neonButtonStyle()
                    }.accessibilityIdentifier("备餐-底部分享")
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(AppTheme.background)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }.frame(minHeight: 44)
                        .accessibilityIdentifier("备餐-完成")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !meals.isEmpty {
                        ShareLink(item: FatLossService.prepText(program: program, date: date, meals: meals)) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }.accessibilityLabel("分享备餐与采购清单")
                            .accessibilityIdentifier("备餐-分享")
                    }
                }
            }
            .sheet(isPresented: $showsPortionDetails) { portionDetails }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FatLossCalendar.label(date)).font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
            Text(showsShopping ? "照单采购" : "餐盒计划")
                .font(AppTheme.pageTitle)
            Text("1 人 · \(meals.count) 餐 · 每餐 1 份")
                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("备餐-份数摘要")
            if !items(.pending).isEmpty {
                Button { showsPortionDetails = true } label: {
                    Label("\(items(.pending).count) 项用量待确认", systemImage: "info.circle")
                        .font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("备餐-首屏用量说明")
            }
        }
    }
    private var pageSwitch: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            pageButton("菜单与分装", icon: "takeoutbag.and.cup.and.straw", shopping: false)
            pageButton("采购清单", icon: "basket", shopping: true)
        }.padding(4).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func pageButton(_ title: String, icon: String, shopping: Bool) -> some View {
        Button { showsShopping = shopping } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(showsShopping == shopping ? AppTheme.background : AppTheme.secondaryText)
                .background(showsShopping == shopping ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .accessibilityIdentifier(shopping ? "备餐-采购页" : "备餐-菜单页")
            .accessibilityAddTraits(showsShopping == shopping ? .isSelected : [])
    }
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(meals) { meal in
                if let recipe = meal.recipe {
                    NavigationLink(destination: FatLossRecipeView(recipe: recipe)) {
                        mealCard(meal)
                    }.buttonStyle(.plain).accessibilityIdentifier("备餐-食谱-\(meal.mealType.title)")
                } else {
                    Text("\(meal.mealType.title) · \(meal.title) · 食谱待补全")
                        .foregroundStyle(AppTheme.orange).cardSurface()
                }
            }
            if items(.pending).isEmpty { portionNotice }
            DisclosureGroup {
                ForEach(storageNotes, id: \.self) { note in
                    Text(note).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
            } label: {
                Label("保存与复热", systemImage: "refrigerator")
                    .font(.subheadline).foregroundStyle(.white).frame(minHeight: 44)
            }.tint(AppTheme.secondaryText).accessibilityIdentifier("备餐-保存与复热")
        }
    }
    private func mealCard(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if typeSize.isAccessibilitySize {
                mealPhoto(meal).frame(height: 170).clipped()
                mealDescription(meal).padding(18)
            } else {
                HStack(spacing: 0) {
                    mealDescription(meal).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    mealPhoto(meal).frame(width: 132, height: 138).clipped()
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                Text("装入\(meal.mealType.title)餐盒")
                Spacer(minLength: 0)
                Text("1 份").fontWeight(.bold).foregroundStyle(AppTheme.accent)
                Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.secondaryText)
            }.font(.caption).foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 18).padding(.vertical, 13)
                .background(AppTheme.elevatedSurface.opacity(0.55))
        }.background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func mealDescription(_ meal: PlannedMeal) -> some View {
        let parts = meal.title.components(separatedBy: "＋")
        return VStack(alignment: .leading, spacing: 10) {
            Text(meal.mealType.title).font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent)
            Text(parts.first ?? meal.title).font(.title3.weight(.bold)).foregroundStyle(AppTheme.posterWarmWhite)
                .fixedSize(horizontal: false, vertical: true)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func mealPhoto(_ meal: PlannedMeal) -> some View {
        // These reusable illustrations represent a meal type, not a photo of the selected recipe.
        GeometryReader { geometry in
            Image(meal.mealType == .lunch ? "EditorialLunch" : "EditorialDinner")
                .resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
                .clipped().overlay(alignment: .bottomTrailing) {
                    Text("餐食示意").font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                        .padding(5).background(.black.opacity(0.55), in: Capsule()).padding(8)
                }
        }.accessibilityHidden(true)
    }
    private var portionNotice: some View {
        Button { showsPortionDetails = true } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "info.circle").font(.title3).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(items(.pending).isEmpty ? "用量为参考，尚未称重" : "\(items(.pending).count) 项食材用量待确认")
                        .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.posterWarmWhite)
                    Text(items(.pending).isEmpty ? "查看份数与用量说明" : items(.pending).map(\.name).joined(separator: " · "))
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("备餐-用量说明")
    }
    private var shoppingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("需要购买").font(.title3.bold())
                    Spacer()
                    Text("\(items(.purchase).count) 项").font(.caption.bold()).foregroundStyle(AppTheme.accent)
                }
                Text("已合并 \(meals.count) 餐 · 克重为未称重参考")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                VStack(spacing: 0) {
                    ForEach(items(.purchase)) { item in
                        ingredientRow(item)
                        if item.id != items(.purchase).last?.id { Divider().overlay(AppTheme.line) }
                    }
                }.padding(.horizontal, 16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18)).padding(.top, 10)
            }
            portionNotice
            ingredientDisclosure(.pantry, icon: "cabinet", subtitle: "先看家里有没有，缺少再买")
            ingredientDisclosure(.water, icon: "drop", subtitle: "备好清水，无需计入采购")
            Text("查看食材行可展开原配方用量；个人主食份量仍待整体菜单确认。")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }
    private func ingredientDisclosure(_ group: PrepPresentation.Group, icon: String, subtitle: String) -> some View {
        DisclosureGroup {
            ForEach(items(group)) { item in ingredientRow(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.posterWarmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }.frame(minHeight: 44, alignment: .center).padding(.vertical, 3)
        }.tint(AppTheme.secondaryText)
    }
    private func ingredientRow(_ item: ShoppingItem) -> some View {
        DisclosureGroup {
            if item.isMedicalPortionPending {
                Text("需结合医生建议确认，暂不据此定量。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(item.amounts, id: \.self) { amount in
                    Text("原配方：\(amount)；按份数折算。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                }
            }
        } label: {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.posterWarmWhite)
                    Text("用于 \(item.portions) 餐").font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(item.isMedicalPortionPending ? "待确认" : item.referenceGrams.map { "≈ \($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "待折算")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(item.referenceGrams != nil && !item.isMedicalPortionPending ? AppTheme.posterWarmWhite : AppTheme.accent)
                    .accessibilityLabel(PrepPresentation.amountSummary(item))
                    .accessibilityIdentifier("备餐用量-\(item.name)")
            }.frame(minHeight: 44, alignment: .leading).padding(.vertical, 10)
        }.tint(AppTheme.secondaryText)
    }
    private var portionDetails: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("个人份量待确认").font(.title2.bold())
                    Text("肉蛋奶豆等用量需结合医生建议确认，再据此采购和分装。")
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach(items(.pending)) { item in ingredientRow(item) }
                    NavigationLink("查看目标与健康资料", destination: FatLossTargetsView(program: program))
                        .frame(minHeight: 44).foregroundStyle(AppTheme.accent)
                    Divider()
                    Text("每餐准备 1 份").font(.headline)
                    Text("原配方为 2 份时，这一餐只用一半。已知克重为未称重参考，不是个性化摄入目标；个人主食份量仍待整体菜单确认。")
                        .foregroundStyle(AppTheme.secondaryText)
                }.padding(20)
            }.screenBackground().navigationTitle("份量说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showsPortionDetails = false } } }
        }.tint(AppTheme.accent)
    }
}

struct FatLossMealDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var actuals: [MealEntry]
    @Query private var recipes: [RecipeVersion]
    @Query private var mealHistory: [PlannedMeal]
    let meal: PlannedMeal
    @State private var portions = 1.0
    @State private var notes = ""
    @State private var taste = 0
    @State private var difficulty = 0
    @State private var bloating = -1
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showsNutrition = false
    @State private var replacementID: UUID?
    @State private var replacementReason = ""
    @State private var errorMessage: String?
    private var actual: MealEntry? { actuals.first { $0.plannedMealID == meal.id && $0.isActiveMeal } }
    var body: some View {
        Form {
            Section {
                Text(meal.title).font(.title2.bold())
                if let recipe = meal.recipe {
                    NavigationLink("查看完整食谱", destination: FatLossRecipeView(recipe: recipe))
                    Text(recipe.householdPortion).font(.caption)
                }
            }
            Section("实际吃了多少") {
                Stepper("\(portions.formatted()) 份", value: $portions, in: 0.25...10, step: 0.25)
                Text("1 份 = 食谱中的一人份")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                TextField("替换、剩余或加餐说明", text: $notes, axis: .vertical).frame(minHeight: 44)
                    .accessibilityIdentifier("计划餐实吃备注")
                Picker("口味", selection: $taste) {
                    Text("未评价").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
                Picker("备餐难度", selection: $difficulty) {
                    Text("未评价").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
                Picker("餐后腹胀", selection: $bloating) {
                    Text("未记录").tag(-1)
                    Text("无").tag(0); Text("轻").tag(1); Text("中").tag(2); Text("重").tag(3)
                }.accessibilityIdentifier("计划餐腹胀反馈")
            }
            Section {
                Button { showsNutrition.toggle() } label: {
                    HStack {
                        Text("营养选填")
                        Spacer()
                        Image(systemName: showsNutrition ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("实吃-展开营养")
                    .accessibilityValue(showsNutrition ? "已展开" : "已收起")
                if showsNutrition {
                    nutrient("热量 kcal", text: $calories)
                    nutrient("蛋白质 g", text: $protein)
                    nutrient("碳水 g", text: $carbs)
                    nutrient("脂肪 g", text: $fat)
                    Text("已知填数值，未知留空；0 表示实际为零。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            Section {
                if let actual {
                    Button("撤销本次实吃记录", role: .destructive) {
                        do { try FatLossService.undoMeal(actual, in: context); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                } else {
                    Button("明确这餐没吃") {
                        do { try FatLossService.skipMeal(meal, reason: notes, in: context); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(meal.date > FatLossCalendar.day(.now))
                }
            }
            if actual == nil && meal.isCurrent {
                Section("更换计划菜式") {
                    Picker("替换为", selection: $replacementID) {
                        Text("选择菜式").tag(nil as UUID?)
                        ForEach(recipes) { recipe in Text(recipe.title).tag(recipe.id as UUID?) }
                    }.accessibilityIdentifier("计划餐替换选择")
                    TextField("换菜原因", text: $replacementReason).frame(minHeight: 44).accessibilityIdentifier("计划餐换菜原因")
                    Button("保存换菜") {
                        guard let recipe = recipes.first(where: { $0.id == replacementID }) else { return }
                        do { _ = try FatLossService.replaceMeal(meal, with: recipe, reason: replacementReason, in: context); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(replacementID == nil || replacementReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !previousPlans.isEmpty {
                Section("这餐的计划历史") {
                    ForEach(previousPlans) { previous in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(previous.title).font(.headline)
                            Text(previous.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            if !previous.changeReason.isEmpty { Text(previous.changeReason).font(.caption) }
                            if let recipe = previous.recipe {
                                NavigationLink("查看当时食谱", destination: FatLossRecipeView(recipe: recipe))
                            }
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).screenBackground().fatLossCalendar().fatLossInput().navigationTitle("餐食与反馈").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear(perform: load)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).frame(minHeight: 44)
                        .disabled(meal.date > FatLossCalendar.day(.now))
                        .accessibilityIdentifier("保存计划实吃")
                }
            }
            .fatLossError($errorMessage)
    }
    private func nutrient(_ title: String, text: Binding<String>) -> some View {
        HStack { Text(title); TextField("未知", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minHeight: 44).accessibilityIdentifier("实吃-\(title)") }
    }
    private var previousPlans: [PlannedMeal] {
        mealHistory.filter {
            $0.programID == meal.programID && FatLossCalendar.sameDay($0.date, meal.date)
                && $0.mealTypeRaw == meal.mealTypeRaw && !$0.isCurrent
        }.sorted { $0.createdAt > $1.createdAt }
    }
    private func load() {
        guard let actual else { return }
        portions = actual.actualPortions ?? 1
        notes = actual.feedbackNotes ?? ""
        taste = actual.tasteRating ?? 0
        difficulty = actual.preparationDifficulty ?? 0
        bloating = actual.bloatingScore ?? -1
        calories = actual.isCalorieKnown ? String(actual.calories) : ""
        protein = actual.isProteinKnown ? String(actual.proteinGrams) : ""
        carbs = actual.isCarbsKnown ? String(actual.carbsGrams) : ""
        fat = actual.isFatKnown ? String(actual.fatGrams) : ""
    }
    private func save() {
        let fields = [calories, protein, carbs, fat]
        guard fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty || (Int($0).map { (0...100_000).contains($0) } ?? false) }) else {
            errorMessage = "营养值请填写有效非负整数，未知可留空。"; return
        }
        do {
            let entry = try FatLossService.recordMeal(meal, portions: portions, in: context)
            try FatLossService.updateMeal(entry, portions: portions, calories: Int(calories), proteinGrams: Int(protein), carbsGrams: Int(carbs), fatGrams: Int(fat), tasteRating: taste == 0 ? nil : taste, preparationDifficulty: difficulty == 0 ? nil : difficulty, bloatingScore: bloating < 0 ? nil : bloating, notes: notes, in: context)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

import Foundation

/// Read-only kitchen instructions. Recipe quantities remain references, never an approved intake target.
enum PrepPresentation {
    enum Group: String, CaseIterable, Identifiable {
        case pending = "个人份量待确认"
        case purchase = "需要购买"
        case pantry = "家中常备 · 核对库存"
        case water = "烹调用水"
        var id: String { rawValue }
    }

    static func selectedMeals(_ meals: [PlannedMeal], programID: UUID, date: Date) -> [PlannedMeal] {
        meals.filter {
            $0.programID == programID && $0.isCurrent && $0.statusRaw != "skipped"
                && FatLossCalendar.sameDay($0.date, date) && [.lunch, .dinner].contains($0.mealType)
        }.sorted { ($0.mealType == .lunch ? 0 : 1) < ($1.mealType == .lunch ? 0 : 1) }
    }

    static func group(for item: ShoppingItem) -> Group {
        if item.isMedicalPortionPending { return .pending }
        if ["水", "温水", "清水", "饮用水", "开水"].contains(item.name) { return .water }
        if ["食用油", "橄榄油", "生抽", "老抽", "盐", "食盐", "糖", "白糖", "醋", "米醋", "玉米淀粉", "淀粉", "胡椒粉", "姜葱蒜"].contains(item.name) { return .pantry }
        return .purchase
    }

    static func amountSummary(_ item: ShoppingItem) -> String {
        if item.isMedicalPortionPending { return "待确认用量 · 用于 \(item.portions) 餐" }
        if let grams = item.referenceGrams {
            return "约 \(grams.formatted(.number.precision(.fractionLength(0...1)))) g 合计 · 用于 \(item.portions) 餐"
        }
        return "用量待折算 · 用于 \(item.portions) 餐"
    }

    static func packing(_ meal: PlannedMeal) -> String {
        "准备 1 份 · 装入\(meal.mealType.title)餐盒"
    }

    @MainActor
    static func shareText(program: FatLossProgram, date: Date, meals: [PlannedMeal]) -> String {
        let selected = selectedMeals(meals, programID: program.id, date: date)
        var lines = ["\(FatLossCalendar.label(date)) 午晚餐备餐单", "给 1 人准备；每餐 1 份，共 \(selected.count) 餐。早餐自理。", ""]
        if selected.isEmpty { return (lines + ["当天尚未安排午晚餐。"]).joined(separator: "\n") }
        lines += ["做什么 / 怎么分装"]
        for meal in selected {
            lines += ["• \(meal.mealType.title)：\(meal.title)", "  \(packing(meal))"]
            if meal.recipe == nil { lines += ["  食谱缺失，食材与做法待补全。"] }
        }
        lines += ["", "食材按每餐 1 份折算；原配方若为 2 份，备这一餐只取一半。不要把整份配方都装进一人一餐。", "已知克重为未称重参考，不是个性化摄入目标。", ""]
        let items = FatLossService.shoppingList(meals: selected)
        for group in Group.allCases {
            let grouped = items.filter { self.group(for: $0) == group }
            guard !grouped.isEmpty else { continue }
            lines.append(group.rawValue)
            if group == .pending { lines.append("以下肉蛋奶豆等用量需结合医生建议确认；未确认前不能照参考克重定量。") }
            if group == .pantry { lines.append("请先核对库存，缺少的再购买。") }
            for item in grouped {
                lines.append("• \(item.name)：\(amountSummary(item))")
                if item.referenceGrams == nil && !item.isMedicalPortionPending {
                    lines += item.amounts.map { "  原配方用量参考：\($0)；按份数折算。" }
                }
            }
            lines.append("")
        }
        lines += ["制作 / 保存与复热（原配方步骤）", "下列做法保留原配方的分份说明；本单每餐只准备 1 份，食材与分装按上方备餐单执行。"]
        for meal in selected {
            guard let recipe = meal.recipe else { continue }
            lines += ["", "\(meal.mealType.title)：\(recipe.title)（原配方 \(recipe.portions.formatted()) 份）"]
            lines += recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
            lines += ["厨具：\(recipe.equipment.joined(separator: "、"))", "保存与复热：\(recipe.storageNote)"]
            lines += recipe.sources.map { "来源：\($0.title) \($0.url)（\($0.verification)）" }
        }
        return lines.joined(separator: "\n")
    }
}

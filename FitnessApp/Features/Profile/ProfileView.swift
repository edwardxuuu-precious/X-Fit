import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var sessions: [WorkoutSession]
    @Query private var schedules: [ScheduledWorkout]

    private var completedSessions: [WorkoutSession] {
        sessions.filter { $0.status == .completed }
    }

    private var activeMinutes: Int {
        completedSessions.compactMap { session in
            session.completedAt.map { max(1, Int($0.timeIntervalSince(session.startedAt) / 60)) }
        }.reduce(0, +)
    }

    private var completedPlans: Int {
        schedules.filter { $0.status == .completed }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "PERSONAL CENTER", title: "我的", trailingSystemImage: "gearshape.fill")
                profileCard
                targetCard

                SectionHeader(title: "健康概览")
                NutritionPreviewCard()

                SectionHeader(title: "更多")
                VStack(spacing: 0) {
                    NavigationLink(destination: HistoryView()) {
                        settingsRow(icon: "clock.arrow.circlepath", title: "训练历史", subtitle: "查看全部完成记录")
                    }
                    Divider().overlay(AppTheme.line).padding(.leading, 54)
                    NavigationLink(destination: NutritionView()) {
                        settingsRow(icon: "fork.knife", title: "营养记录", subtitle: "记录热量和宏量营养")
                    }
                    Divider().overlay(AppTheme.line).padding(.leading, 54)
                    settingsRow(icon: "lock.shield.fill", title: "本地隐私", subtitle: "训练数据仅保存在这台设备")
                }
                .cardSurface(padding: 0, cornerRadius: 18)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var profileCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(AppTheme.elevatedSurface)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(AppTheme.accent.opacity(0.45), lineWidth: 2))

                VStack(alignment: .leading, spacing: 5) {
                    Text("训练者")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("持续、记录、进步")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Label("本地训练档案", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                profileMetric("\(completedSessions.count)", label: "训练次数")
                profileMetric("\(activeMinutes)", label: "训练分钟")
                profileMetric("\(completedPlans)", label: "完成计划")
            }
        }
        .cardSurface(padding: 18, cornerRadius: 20)
    }

    private func profileMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1, height: 28)
        }
    }

    private var targetCard: some View {
        HStack(spacing: 18) {
            NeonProgressRing(
                progress: min(Double(completedSessions.count) / 12, 1),
                value: "\(min(completedSessions.count, 12))/12",
                detail: "训练"
            )
            VStack(alignment: .leading, spacing: 7) {
                Text("阶段目标")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text("完成 12 次高质量训练")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("不用追求完美，只要每一次都留下真实记录。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(14)
    }
}

private struct NutritionPreviewCard: View {
    @AppStorage("nutritionCalories") private var calories = 0
    private let target = 2400

    var body: some View {
        NavigationLink(destination: NutritionView()) {
            HStack(spacing: 18) {
                NeonProgressRing(
                    progress: Double(calories) / Double(target),
                    value: "\(calories)",
                    detail: "/ \(target) kcal"
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text("今日营养")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(calories == 0 ? "还没有记录餐食" : "还可摄入 \(max(0, target - calories)) kcal")
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
    @AppStorage("nutritionCalories") private var calories = 0
    @AppStorage("nutritionProtein") private var protein = 0
    @AppStorage("nutritionCarbs") private var carbs = 0
    @AppStorage("nutritionFat") private var fat = 0
    @State private var showMealPicker = false

    private let calorieTarget = 2400

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: Date.now.formatted(
                        .dateTime
                            .locale(Locale(identifier: "zh_Hans_CN"))
                            .month()
                            .day()
                            .weekday(.wide)
                    ),
                    title: "营养",
                    trailingSystemImage: "plus",
                    trailingAction: { showMealPicker = true }
                )
                calorieCard
                SectionHeader(title: "餐食", actionTitle: "添加")
                mealRow(title: "早餐", detail: "燕麦、水果或鸡蛋", calories: 450, icon: "sunrise.fill")
                mealRow(title: "午餐", detail: "优质蛋白与蔬菜", calories: 650, icon: "sun.max.fill")
                mealRow(title: "晚餐", detail: "均衡碳水与蛋白", calories: 750, icon: "moon.stars.fill")

                Button("清空今日记录", role: .destructive) {
                    reset()
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("添加一份餐食", isPresented: $showMealPicker) {
            Button("早餐 · 450 kcal") { addMeal(calories: 450, protein: 25, carbs: 55, fat: 12) }
            Button("午餐 · 650 kcal") { addMeal(calories: 650, protein: 45, carbs: 70, fat: 18) }
            Button("晚餐 · 750 kcal") { addMeal(calories: 750, protein: 50, carbs: 80, fat: 22) }
            Button("取消", role: .cancel) {}
        }
    }

    private var calorieCard: some View {
        HStack(spacing: 20) {
            NeonProgressRing(
                progress: Double(calories) / Double(calorieTarget),
                value: "\(calories)",
                detail: "/ \(calorieTarget) kcal",
                size: 112
            )
            VStack(alignment: .leading, spacing: 12) {
                macroRow(name: "蛋白质", value: protein, target: 160, tint: AppTheme.accent)
                macroRow(name: "碳水", value: carbs, target: 250, tint: AppTheme.orange)
                macroRow(name: "脂肪", value: fat, target: 80, tint: AppTheme.purple)
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

    private func mealRow(title: String, detail: String, calories: Int, icon: String) -> some View {
        Button {
            switch calories {
            case 450: addMeal(calories: 450, protein: 25, carbs: 55, fat: 12)
            case 650: addMeal(calories: 650, protein: 45, carbs: 70, fat: 18)
            default: addMeal(calories: 750, protein: 50, carbs: 80, fat: 22)
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("\(calories) kcal")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
            .cardSurface(padding: 12, cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func addMeal(calories: Int, protein: Int, carbs: Int, fat: Int) {
        self.calories += calories
        self.protein += protein
        self.carbs += carbs
        self.fat += fat
    }

    private func reset() {
        calories = 0
        protein = 0
        carbs = 0
        fat = 0
    }
}

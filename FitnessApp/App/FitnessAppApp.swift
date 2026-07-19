import SwiftData
import SwiftUI

@main
struct FitnessAppApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            NutritionTarget.self,
            MealEntry.self,
            BodyMeasurement.self
        ])
        let isUITesting = CommandLine.arguments.contains("--ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建本地训练数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

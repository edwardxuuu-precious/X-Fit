import SwiftData
import SwiftUI
import UIKit

@main
struct FitnessAppApp: App {
    private let modelContainer: ModelContainer
    private let viewDefaults: UserDefaults = {
#if DEBUG
        if CloudSyncRuntime.isUITesting {
            guard let defaults = UserDefaults(suiteName: "com.edward.FitnessApp.UITestingPreferences") else {
                fatalError("无法准备 UI 测试偏好设置")
            }
            return defaults
        }
#endif
        return .standard
    }()

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--ui-testing-animations") {
            UIView.setAnimationsEnabled(false)
        }
#endif
        CloudSyncEventRecorder.shared.start()
        modelContainer = Self.makeModelContainer()
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            TrainingCoachRecord.self,
            NutritionTarget.self,
            MealEntry.self,
            DailyBodyCheckIn.self,
            BodyMeasurement.self,
            HydrationEntry.self,
            JumpRopeEntry.self,
            SedentarySession.self,
            TrainingPreferenceRevision.self,
            TrainingProgramRevision.self,
            FatLossProgram.self,
            ProgramTargetRevision.self,
            RecipeVersion.self,
            PlannedMeal.self,
            ProgramDailyLog.self,
            ProgramHealthRecord.self,
            ProgramWeeklyReview.self,
            ProgramWorkoutLink.self
        ])
        let configuration: ModelConfiguration
        if CloudSyncRuntime.usesPersistentUITestStore {
            let directory = URL.applicationSupportDirectory
                .appending(path: "XFitUITesting", directoryHint: .isDirectory)
            let storeURL = directory.appending(path: "FreestylePersistence.store")
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                if CloudSyncRuntime.shouldResetPersistentUITestStore {
                    for suffix in ["", "-wal", "-shm"] {
                        let url = URL(fileURLWithPath: storeURL.path + suffix)
                        if FileManager.default.fileExists(atPath: url.path) {
                            try FileManager.default.removeItem(at: url)
                        }
                    }
                }
            } catch {
                fatalError("无法准备 UI 测试数据库：\(error.localizedDescription)")
            }
            configuration = ModelConfiguration(
                "XFitUITesting",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: CloudSyncRuntime.isTesting,
                cloudKitDatabase: CloudSyncRuntime.database
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建本地训练数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .defaultAppStorage(viewDefaults)
        }
        .modelContainer(modelContainer)
    }
}

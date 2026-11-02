import Foundation
import HealthKit

struct HealthBodySnapshot {
    let weightKg: Double?
    let bodyFatPercent: Double?
    let date: Date
}

final class HealthKitService {
    static let shared = HealthKitService()
    static let enabledKey = "healthKitEnabled"

    private let healthStore = HKHealthStore()
    private let healthDataAvailable: () -> Bool
    private let workoutWriter: (Date, Date) async throws -> Void
    private let arguments: [String]
    private let isXCTestHost: Bool

    init(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        healthDataAvailable: @escaping () -> Bool = HKHealthStore.isHealthDataAvailable,
        workoutWriter: ((Date, Date) async throws -> Void)? = nil
    ) {
        self.arguments = arguments
        self.isXCTestHost = environment["XCTestConfigurationFilePath"] != nil
        self.healthDataAvailable = healthDataAvailable
        self.workoutWriter = workoutWriter ?? { [healthStore] start, end in
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor

            let builder = HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: configuration,
                device: .local()
            )
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        }
    }

    var isAvailable: Bool {
        healthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw CocoaError(.featureUnsupported, userInfo: [
                NSLocalizedDescriptionKey: "这台设备不支持 Apple 健康。"
            ])
        }

        let workoutType = HKObjectType.workoutType()
        let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
        try await healthStore.requestAuthorization(
            toShare: [workoutType],
            read: [workoutType, weightType, bodyFatType]
        )
        guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
            throw CocoaError(.userCancelled, userInfo: [
                NSLocalizedDescriptionKey: "未获得写入力量训练的权限。你仍可继续使用 X-Fit 的本机记录功能。"
            ])
        }
    }

    func saveWorkout(start: Date, end: Date) async throws {
        // Persistent UI tests deliberately bypass the in-memory store flag;
        // both UI modes and XCTest hosts must still suppress external writes.
        guard !arguments.contains("--ui-testing"),
              !arguments.contains("--ui-testing-persistent"),
              !isXCTestHost,
              isAvailable, end > start else { return }
        try await workoutWriter(start, end)
    }

    func latestBodySnapshot() async throws -> HealthBodySnapshot? {
        let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
        async let weightSample = latestSample(for: weightType)
        async let bodyFatSample = latestSample(for: bodyFatType)
        let (weight, bodyFat) = try await (weightSample, bodyFatSample)

        guard weight != nil || bodyFat != nil else { return nil }
        let latestDate = max(weight?.endDate ?? .distantPast, bodyFat?.endDate ?? .distantPast)
        return HealthBodySnapshot(
            weightKg: weight?.quantity.doubleValue(for: .gramUnit(with: .kilo)),
            bodyFatPercent: bodyFat.map { $0.quantity.doubleValue(for: .percent()) * 100 },
            date: latestDate
        )
    }

    func weightKg(onOrBefore date: Date) async throws -> Double? {
        let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let predicate = HKQuery.predicateForSamples(
            withStart: nil,
            end: date,
            options: .strictEndDate
        )
        return try await latestSample(for: weightType, predicate: predicate)?
            .quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    private func latestSample(
        for type: HKQuantityType,
        predicate: NSPredicate? = nil
    ) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
            }
            healthStore.execute(query)
        }
    }
}

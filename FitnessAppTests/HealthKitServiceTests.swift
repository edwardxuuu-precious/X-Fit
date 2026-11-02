import Foundation
import XCTest
@testable import FitnessApp

@MainActor
final class HealthKitServiceTests: XCTestCase {
    func testSavingTestWorkoutsNeverCreatesExternalHealthRecords() async throws {
        let modes: [(arguments: [String], environment: [String: String])] = [
            (["FitnessApp", "--ui-testing"], [:]),
            (["FitnessApp", "--ui-testing", "--ui-testing-persistent"], [:]),
            (["FitnessApp", "--ui-testing-persistent"], [:]),
            (["FitnessApp"], ["XCTestConfigurationFilePath": "/test-only/configuration"]),
            (["FitnessApp", "--ui-testing-persistent"], ["XCTestConfigurationFilePath": "/test-only/configuration"])
        ]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var externalRecords: [(Date, Date)] = []
        for mode in modes {
            let service = HealthKitService(
                arguments: mode.arguments,
                environment: mode.environment,
                healthDataAvailable: { true },
                workoutWriter: { externalRecords.append(($0, $1)) }
            )
            try await service.saveWorkout(start: start, end: start.addingTimeInterval(300))
        }
        XCTAssertTrue(externalRecords.isEmpty, "测试训练不得进入真实健康写入边界")
    }

    func testNormalWorkoutPreservesItsOriginalStartAndEndAtHealthBoundary() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(334.28)
        var externalRecords: [(Date, Date)] = []
        let service = HealthKitService(
            arguments: ["FitnessApp"], environment: [:], healthDataAvailable: { true },
            workoutWriter: { externalRecords.append(($0, $1)) }
        )

        try await service.saveWorkout(start: start, end: end)

        XCTAssertEqual(externalRecords.count, 1)
        let record = try XCTUnwrap(externalRecords.first)
        XCTAssertEqual(record.0, start)
        XCTAssertEqual(record.1, end)
    }

    func testUnavailableHealthOrInvalidDurationCreatesNoExternalRecord() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let requests: [(available: Bool, end: Date)] = [
            (false, start.addingTimeInterval(300)),
            (true, start),
            (true, start.addingTimeInterval(-1))
        ]
        var externalRecords: [(Date, Date)] = []
        for request in requests {
            let service = HealthKitService(
                arguments: ["FitnessApp"], environment: [:],
                healthDataAvailable: { request.available },
                workoutWriter: { externalRecords.append(($0, $1)) }
            )
            try await service.saveWorkout(start: start, end: request.end)
        }
        XCTAssertTrue(externalRecords.isEmpty)
    }
}

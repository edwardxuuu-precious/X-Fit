import CoreData
import Foundation
import SwiftData

enum CloudSyncRuntime {
    static let containerIdentifier = "iCloud.com.edward.FitnessApp"

    static var isUITesting: Bool {
        CommandLine.arguments.contains("--ui-testing")
    }

    static var isConfigured: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "XFitCloudSyncEnabled")
        if let boolean = value as? Bool { return boolean }
        guard let string = value as? String else { return false }
        return ["1", "true", "yes"].contains(string.lowercased())
    }

    static var isTesting: Bool {
        if usesPersistentUITestStore { return false }
        return isUITesting
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var usesPersistentUITestStore: Bool {
        CommandLine.arguments.contains("--ui-testing-persistent")
    }

    static var shouldResetPersistentUITestStore: Bool {
        CommandLine.arguments.contains("--ui-testing-reset-store")
    }

    static func shouldSyncWorkoutReminders(
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        !arguments.contains("--ui-testing")
            || arguments.contains("--ui-testing-workout-reminders")
    }

    static func shouldReadShareDraft(
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        !arguments.contains("--ui-testing")
            || arguments.contains("--ui-testing-share-draft")
    }

    static var isDisabled: Bool {
        !isConfigured
            || isUITesting
            || isTesting
            || CommandLine.arguments.contains("--disable-cloud-sync")
    }

    static var allowsInitialSeed: Bool {
        isUITesting
            || isDisabled
            || CommandLine.arguments.contains("--initialize-empty-cloud-store")
    }

    static var database: ModelConfiguration.CloudKitDatabase {
        isDisabled ? .none : .private(containerIdentifier)
    }
}

private struct CloudSyncEventReceipt: Codable {
    let recordedAt: Date
    let type: String
    let startedAt: Date
    let endedAt: Date?
    let succeeded: Bool
    let errorMessage: String?
}

final class CloudSyncEventRecorder {
    static let shared = CloudSyncEventRecorder()

    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard !CloudSyncRuntime.isDisabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
                return
            }
            Self.record(event)
        }
    }

    private static func record(_ event: NSPersistentCloudKitContainer.Event) {
        let type: String
        switch event.type {
        case .setup: type = "setup"
        case .import: type = "import"
        case .export: type = "export"
        @unknown default: type = "unknown"
        }

        let receipt = CloudSyncEventReceipt(
            recordedAt: .now,
            type: type,
            startedAt: event.startDate,
            endedAt: event.endDate,
            succeeded: event.succeeded,
            errorMessage: event.error?.localizedDescription
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(receipt) else { return }
        try? data.write(
            to: URL.documentsDirectory.appendingPathComponent("cloud-sync-event-\(type).json"),
            options: .atomic
        )
    }
}

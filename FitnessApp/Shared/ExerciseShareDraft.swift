import Foundation
import UniformTypeIdentifiers

/// Shared storage contract used by both the main app and the share extension.
/// Keep these values stable so an app update can still read drafts written by
/// an older extension process.
enum ExerciseShareDraftStorage {
    static let appGroupIdentifier = "group.com.edward.FitnessApp"
    static let pendingDraftKey = "exercise-share-draft.pending.v1"
    static let uiTestingPendingDraftKey = "exercise-share-draft.pending.ui-testing.v1"
    static let schemaVersion = 1

    static func makeUserDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

/// A lightweight handoff object. It intentionally contains no SwiftData types
/// so the share extension does not need access to the app's model container.
struct ExerciseShareDraft: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let sharedText: String
    let sourceURL: URL?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sharedText: String = "",
        sourceURL: URL? = nil
    ) {
        self.schemaVersion = ExerciseShareDraftStorage.schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.sharedText = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceURL = sourceURL
    }

    var isEmpty: Bool {
        sharedText.isEmpty && sourceURL == nil
    }

    /// A conservative suggestion for pre-filling the exercise name field.
    /// The app should always let the user review and edit it before saving.
    var suggestedExerciseName: String {
        let firstUsefulLine = sharedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                guard !line.isEmpty else { return false }
                return URL(string: line)?.scheme == nil
            }

        guard let firstUsefulLine else { return "" }
        return String(firstUsefulLine.prefix(80))
    }
}

struct ExerciseSharedContent: Equatable {
    let texts: [String]
    let urls: [URL]

    var combinedText: String {
        var seen = Set<String>()
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: "\n\n")
    }
}

/// Collects the system share boundary into a deterministic, SwiftData-free payload.
/// Both the extension and the main target compile this file so the real parser can
/// be exercised without copying its behavior into a test-only implementation.
final class ExerciseSharedContentCollector {
    private let lock = NSLock()
    private var texts: [String]
    private var urls: [URL] = []

    private init(initialTexts: [String]) {
        texts = initialTexts
    }

    static func collect(
        providers: [NSItemProvider],
        initialTexts: [String],
        completion: @escaping (ExerciseSharedContent) -> Void
    ) {
        let collector = ExerciseSharedContentCollector(initialTexts: initialTexts)
        let group = DispatchGroup()

        for provider in providers {
            collector.loadURL(from: provider, group: group)
            collector.loadText(from: provider, group: group)
        }

        group.notify(queue: .main) {
            completion(collector.snapshot())
        }
    }

    private func loadURL(from provider: NSItemProvider, group: DispatchGroup) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return }
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            defer { group.leave() }
            guard let self else { return }

            let url: URL?
            switch item {
            case let value as URL:
                url = value
            case let value as NSURL:
                url = value as URL
            case let value as String:
                url = URL(string: value)
            default:
                url = nil
            }

            guard let url else { return }
            self.lock.withLock {
                self.urls.append(url)
            }
        }
    }

    private func loadText(from provider: NSItemProvider, group: DispatchGroup) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else { return }
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
            defer { group.leave() }
            guard let self else { return }

            let text: String?
            switch item {
            case let value as String:
                text = value
            case let value as NSAttributedString:
                text = value.string
            default:
                text = nil
            }

            guard let text else { return }
            self.lock.withLock {
                self.texts.append(text)
            }
        }
    }

    private func snapshot() -> ExerciseSharedContent {
        lock.withLock {
            var seenURLs = Set<String>()
            let uniqueURLs = urls.filter { seenURLs.insert($0.absoluteString).inserted }
            return ExerciseSharedContent(texts: texts, urls: uniqueURLs)
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ action: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return action()
    }
}

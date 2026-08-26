import Foundation

/// Reads the single pending share-extension handoff from the App Group suite.
/// The latest share replaces an older unconsumed draft by design.
struct ExerciseShareDraftInbox {
    private let defaults: UserDefaults?
    private let decoder: JSONDecoder
    private let pendingDraftKey: String

    init(
        defaults: UserDefaults? = ExerciseShareDraftStorage.makeUserDefaults(),
        decoder: JSONDecoder = JSONDecoder(),
        pendingDraftKey: String = ExerciseShareDraftStorage.pendingDraftKey
    ) {
        self.defaults = defaults
        self.decoder = decoder
        self.pendingDraftKey = pendingDraftKey
    }

    func pendingDraft() -> ExerciseShareDraft? {
        guard
            let data = defaults?.data(forKey: pendingDraftKey),
            let draft = try? decoder.decode(ExerciseShareDraft.self, from: data),
            draft.schemaVersion == ExerciseShareDraftStorage.schemaVersion
        else {
            return nil
        }

        return draft
    }

    @discardableResult
    func consumePendingDraft() -> ExerciseShareDraft? {
        guard let draft = pendingDraft() else { return nil }
        clearPendingDraft(matching: draft.id)
        return draft
    }

    func clearPendingDraft() {
        defaults?.removeObject(forKey: pendingDraftKey)
    }

    /// Avoids deleting a newer draft if another share arrives while the app is
    /// presenting the currently-read draft.
    func clearPendingDraft(matching draftID: UUID) {
        guard pendingDraft()?.id == draftID else { return }
        clearPendingDraft()
    }
}

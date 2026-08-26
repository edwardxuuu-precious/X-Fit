import Social

final class ShareViewController: SLComposeServiceViewController {
    private var isSaving = false

    override func isContentValid() -> Bool {
        let hasComposerText = !(contentText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasAttachments = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .contains { !($0.attachments ?? []).isEmpty } ?? false
        return hasComposerText || hasAttachments
    }

    override func didSelectPost() {
        guard !isSaving else { return }
        isSaving = true

        let extensionItems = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem } ?? []
        let attributedTexts = extensionItems.compactMap { $0.attributedContentText?.string }
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        ExerciseSharedContentCollector.collect(
            providers: providers,
            initialTexts: [contentText ?? ""] + attributedTexts
        ) { [weak self] content in
            guard let self else { return }

            let draft = ExerciseShareDraft(
                sharedText: content.combinedText,
                sourceURL: content.urls.first
            )

            do {
                guard !draft.isEmpty else {
                    throw ShareExtensionError.noShareableContent
                }
                try Self.persist(draft)
                self.extensionContext?.completeRequest(returningItems: nil)
            } catch {
                self.extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private static func persist(_ draft: ExerciseShareDraft) throws {
        guard let defaults = ExerciseShareDraftStorage.makeUserDefaults() else {
            throw ShareExtensionError.appGroupUnavailable
        }

        let data = try JSONEncoder().encode(draft)
        defaults.set(data, forKey: ExerciseShareDraftStorage.pendingDraftKey)
    }
}

private enum ShareExtensionError: LocalizedError {
    case appGroupUnavailable
    case noShareableContent

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "X-Fit 无法打开共享存储。"
        case .noShareableContent:
            return "没有找到可以添加到 X-Fit 的链接或文字。"
        }
    }
}

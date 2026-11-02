import CryptoKit
import Foundation
import ImageIO
import SwiftData

/// Owns persistent local photo files. No operation uploads an image.
@MainActor
struct MealPhotoService {
    static let maximumPhotosPerMeal = 12
    static let maximumPhotoBytes = 20 * 1_024 * 1_024
    private let injectedRootURL: URL?

    nonisolated init(rootURL: URL? = nil) {
        injectedRootURL = rootURL
    }

    private var rootURL: URL {
        get throws {
            if let injectedRootURL { return injectedRootURL }
            if CloudSyncRuntime.isUITesting {
                guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw MealPhotoError.unavailableStorage
                }
                // Unsigned simulator builds have no App Group entitlement. This remains
                // durable across relaunch, while isolated from the real photo store.
                return applicationSupport.appendingPathComponent("UITestMealPhotos", isDirectory: true)
            }
            if CloudSyncRuntime.isTesting {
                return FileManager.default.temporaryDirectory.appendingPathComponent("XFitUnitTestMealPhotos/\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            }
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.edward.FitnessApp") else {
                throw MealPhotoError.unavailableStorage
            }
            return group.appendingPathComponent("Library/Application Support/MealPhotos", isDirectory: true)
        }
    }

    func photoURL(for attachment: MealPhotoAttachment) throws -> URL {
        guard attachment.relativePath == attachment.id.uuidString.lowercased() + ".jpg" else {
            throw MealPhotoError.unsafePath
        }
        let root = try rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let result = root.appendingPathComponent(attachment.relativePath).resolvingSymlinksInPath()
        guard result.deletingLastPathComponent().path == root.path else { throw MealPhotoError.unsafePath }
        return result
    }

    func data(for attachment: MealPhotoAttachment) throws -> Data {
        let url = try photoURL(for: attachment)
        guard let data = try? Data(contentsOf: url) else { throw MealPhotoError.corruptPhoto }
        try validateAsset(MealPhotoAsset(attachment: attachment, data: data))
        return data
    }

    func photos(for meal: MealEntry) throws -> [MealPhotoAttachment] {
        guard let raw = meal.mealPhotosJSON else { return [] }
        guard let encoded = raw.data(using: .utf8),
              let photos = try? JSONDecoder().decode([MealPhotoAttachment].self, from: encoded),
              photos.count <= Self.maximumPhotosPerMeal,
              Set(photos.map(\.id)).count == photos.count else { throw MealPhotoError.invalidMetadata }
        for photo in photos { _ = try photoURL(for: photo) }
        return photos
    }

    func createMeal(
        photoData: [Data], date: Date, timeZone: TimeZone = .current,
        mealType: MealType, note: String, capturedAt: Date = .now, context: ModelContext
    ) throws -> MealEntry {
        let assets = try makeAssets(photoData, capturedAt: capturedAt, timeZone: timeZone)
        let metadata = try encode(assets.map(\.attachment))
        let createdURLs = try restoreAssets(assets)
        let meal = MealEntry(date: date, mealType: mealType, name: note.trimmingCharacters(in: .whitespacesAndNewlines),
                             calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        meal.knownNutritionFieldsRaw = ""
        meal.recordedLocalDay = MealLocalDay.string(for: date, timeZone: timeZone)
        meal.captureTimeZoneIdentifier = timeZone.identifier
        meal.recordedTimeKnown = true
        meal.mealPhotosJSON = metadata
        context.insert(meal)
        do { try context.save() }
        catch {
            context.delete(meal)
            rollbackRestoredAssets(createdURLs)
            throw error
        }
        return meal
    }

    func appendPhotos(
        _ photoData: [Data], to meal: MealEntry, capturedAt: Date = .now,
        timeZone: TimeZone = .current, context: ModelContext
    ) throws {
        let existing = try photos(for: meal)
        guard existing.count + photoData.count <= Self.maximumPhotosPerMeal else { throw MealPhotoError.tooManyPhotos }
        let assets = try makeAssets(photoData, capturedAt: capturedAt, timeZone: timeZone)
        let metadata = try encode(existing + assets.map(\.attachment))
        let createdURLs = try restoreAssets(assets)
        let original = meal.mealPhotosJSON
        let updatedAt = meal.updatedAt
        meal.mealPhotosJSON = metadata
        meal.updatedAt = .now
        do { try context.save() }
        catch {
            meal.mealPhotosJSON = original
            meal.updatedAt = updatedAt
            rollbackRestoredAssets(createdURLs)
            throw error
        }
    }

    func exportAssets(for meals: [MealEntry]) throws -> [MealPhotoAsset] {
        var output: [MealPhotoAsset] = []
        var ids = Set<UUID>()
        for meal in meals {
            for photo in try photos(for: meal) {
                guard ids.insert(photo.id).inserted else { throw MealPhotoError.invalidMetadata }
                output.append(MealPhotoAsset(attachment: photo, data: try data(for: photo)))
            }
        }
        return output
    }

    func validateAssets(_ assets: [MealPhotoAsset]) throws {
        guard Set(assets.map { $0.attachment.id }).count == assets.count else { throw MealPhotoError.invalidMetadata }
        for asset in assets { try validateAsset(asset) }
    }

    /// Validates the complete set before writing. Existing files are never overwritten.
    @discardableResult
    func restoreAssets(_ assets: [MealPhotoAsset]) throws -> [URL] {
        try validateAssets(assets)
        for asset in assets {
            let url = try photoURL(for: asset.attachment)
            if FileManager.default.fileExists(atPath: url.path), try Data(contentsOf: url) != asset.data {
                throw MealPhotoError.conflictingPhoto
            }
        }
        guard !assets.isEmpty else { return [] }
        try FileManager.default.createDirectory(at: try rootURL, withIntermediateDirectories: true)
        var created: [URL] = []
        do {
            for asset in assets {
                let url = try photoURL(for: asset.attachment)
                if FileManager.default.fileExists(atPath: url.path) { continue }
                try asset.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                created.append(url)
            }
        } catch {
            rollbackRestoredAssets(created)
            throw error
        }
        return created
    }

    /// Only accepts paths directly under this store, returned by restoreAssets.
    func rollbackRestoredAssets(_ urls: [URL]) {
        guard let root = try? rootURL.standardizedFileURL.resolvingSymlinksInPath() else { return }
        for url in urls where url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path == root.path {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makeAssets(_ photos: [Data], capturedAt: Date, timeZone: TimeZone) throws -> [MealPhotoAsset] {
        guard !photos.isEmpty else { throw MealPhotoError.invalidPhoto }
        guard photos.count <= Self.maximumPhotosPerMeal else { throw MealPhotoError.tooManyPhotos }
        let capturedAt = Date(timeIntervalSince1970: floor(capturedAt.timeIntervalSince1970))
        return try photos.map { data in
            try validateImage(data)
            let id = UUID()
            return MealPhotoAsset(attachment: MealPhotoAttachment(id: id, relativePath: id.uuidString.lowercased() + ".jpg",
                sha256: Self.digest(data), byteCount: data.count, capturedAt: capturedAt,
                localDay: MealLocalDay.string(for: capturedAt, timeZone: timeZone), timeZoneIdentifier: timeZone.identifier), data: data)
        }
    }

    private func validateAsset(_ asset: MealPhotoAsset) throws {
        _ = try photoURL(for: asset.attachment)
        guard asset.attachment.byteCount == asset.data.count,
              asset.attachment.sha256 == Self.digest(asset.data),
              let timeZone = TimeZone(identifier: asset.attachment.timeZoneIdentifier),
              MealLocalDay.string(for: asset.attachment.capturedAt, timeZone: timeZone) == asset.attachment.localDay else {
            throw MealPhotoError.corruptPhoto
        }
        try validateImage(asset.data)
    }

    private func validateImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumPhotoBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "public.jpeg",
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw MealPhotoError.invalidPhoto }
    }

    private func encode(_ photos: [MealPhotoAttachment]) throws -> String {
        String(decoding: try JSONEncoder().encode(photos), as: UTF8.self)
    }

    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

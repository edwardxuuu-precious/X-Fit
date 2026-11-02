import SwiftUI
import UIKit

struct MealStoredPhoto: View {
    let photo: MealPhotoAttachment
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            AppTheme.elevatedSurface
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if loadFailed {
                VStack(spacing: 10) {
                    SprintIcon(systemName: "photo", size: 40)
                    Text("照片暂不可用").font(.caption).foregroundStyle(AppTheme.secondaryText)
                }.padding(12)
            } else { ProgressView().tint(AppTheme.ink) }
        }
        .task(id: photo.id) {
            do {
                let bytes = try MealPhotoService().data(for: photo)
                guard let decoded = UIImage(data: bytes) else { throw MealPhotoError.corruptPhoto }
                image = decoded
                loadFailed = false
            } catch { loadFailed = true }
        }
        .accessibilityLabel(loadFailed ? "餐食照片暂不可用，原记录仍保留" : "餐食实拍照片")
    }
}

enum MealPhotoPresentation {
    static func time(_ meal: MealEntry) -> String {
        guard meal.recordedTimeKnown == true else { return "时间未记录" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = meal.captureTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? MealLocalDay.legacyTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: meal.date)
    }

    static func title(_ meal: MealEntry) -> String {
        meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "照片记录" : meal.name
    }
}

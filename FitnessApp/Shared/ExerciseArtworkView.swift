import SwiftUI
import UIKit

enum ExerciseArtwork {
    private struct Entry {
        let id: UUID
        let acceptedNames: Set<String>
        let tile: Int
    }

    private static let entries: [Entry] = [
        Entry(id: UUID(uuidString: "8C2B39A3-8F47-413E-BC5F-93EC3CB313DA")!, acceptedNames: ["史密斯卧推，胸部主项", "Smith Bench Press"], tile: 0),
        Entry(id: UUID(uuidString: "62B7E172-C76F-4502-8643-87249F7199E3")!, acceptedNames: ["器械上斜卧推，上胸推举", "器械上斜卧推"], tile: 1),
        Entry(id: UUID(uuidString: "2FFA02FD-85F0-4938-A9C9-59A3561C241E")!, acceptedNames: ["坐姿飞鸟，胸部夹胸", "坐姿飞鸟"], tile: 2),
        Entry(id: UUID(uuidString: "8DE3EE03-A5A3-4767-954B-333D4BD17332")!, acceptedNames: ["站姿绳索夹胸，胸部夹胸", "站姿绳索夹胸"], tile: 3),
        Entry(id: UUID(uuidString: "57E855E6-E0AB-46FB-AE88-AED4ABF9144B")!, acceptedNames: ["史密斯肩推，肩前束", "Smith shoulder press"], tile: 4),
        Entry(id: UUID(uuidString: "785412EA-AC6A-4910-9942-8C3B2E380CB8")!, acceptedNames: ["坐姿哑铃侧平举，肩中束", "坐姿哑铃侧平举"], tile: 5),
        Entry(id: UUID(uuidString: "67518BD0-1C2E-464C-8753-EB48E62581DB")!, acceptedNames: ["绳索反向飞鸟，肩后束", "绳索反向飞鸟"], tile: 6),
        Entry(id: UUID(uuidString: "9BB12534-10A3-435D-BE9A-10A70ED0616F")!, acceptedNames: ["器械坐姿侧平举，肩中束", "器械坐姿侧平举"], tile: 7)
    ]

    private static let images: [UIImage?] = {
        guard let atlas = UIImage(named: "SavedPlanExerciseAtlas")?.cgImage else { return [] }
        return (0..<8).map { tile in
            atlas.cropping(to: tileRect(tile: tile, width: atlas.width, height: atlas.height))
                .map { UIImage(cgImage: $0) }
        }
    }()

    static func tile(exerciseID: UUID, name: String) -> Int? {
        entries.first { $0.id == exerciseID && $0.acceptedNames.contains(name) }?.tile
    }

    static func tileRect(tile: Int, width: Int, height: Int) -> CGRect {
        let column = tile % 4, row = tile / 4
        let left = column * width / 4, right = (column + 1) * width / 4
        let top = row * height / 2, bottom = (row + 1) * height / 2
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func image(tile: Int) -> UIImage? {
        images.indices.contains(tile) ? images[tile] : nil
    }
}

struct ExerciseArtworkView: View {
    let exerciseID: UUID
    let name: String
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let tile = ExerciseArtwork.tile(exerciseID: exerciseID, name: name),
               let image = ExerciseArtwork.image(tile: tile) {
                Image(uiImage: image).resizable().scaledToFit().padding(3)
            } else {
                Image(systemName: "dumbbell")
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
        .accessibilityHidden(true)
    }
}

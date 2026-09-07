import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct EquipmentRecognitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [SessionExercise]
    @Query private var setLogs: [SetLog]

    let onConfiguredSelect: (Exercise, ExerciseSetupDraft) -> Void

    @State private var images: [UIImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var response: EquipmentRecognitionResponse?
    @State private var isRecognizing = false
    @State private var pendingSetupExercise: Exercise?
    @State private var pendingDraft: ExerciseSetupDraft?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    captureCard

                    if isRecognizing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在识别器械、动作和目标肌群…")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }

                    if let response {
                        resultCard(response)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("拍照识别器械")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    guard let image else { return }
                    appendImage(image)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $pendingSetupExercise) { exercise in
                ExerciseSetupSheet(
                    exercise: exercise,
                    draft: pendingDraft ?? ExerciseSetupDraft.suggested(
                        for: exercise,
                        sessions: sessions,
                        sessionExercises: sessionExercises,
                        setLogs: setLogs
                    )
                ) { draft in
                    onConfiguredSelect(exercise, draft)
                    dismiss()
                }
            }
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotoItems(items) }
            }
            .onAppear {
#if DEBUG
                if CommandLine.arguments.contains("--ui-testing-equipment-recognition"),
                   images.isEmpty {
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
                    images = [renderer.image { context in
                        UIColor.darkGray.setFill()
                        context.fill(CGRect(origin: .zero, size: CGSize(width: 32, height: 32)))
                    }]
                }
#endif
            }
            .alert("无法识别器械", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("拍机器全景和说明标牌", systemImage: "camera.viewfinder")
                .font(.headline)
            Text("最多 3 张。机器轮廓、品牌或动作示意图越清楚，候选结果越可靠。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(images.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: images[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Button {
                                    images.remove(at: index)
                                    response = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.7))
                                }
                                .padding(5)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorMessage = "当前设备没有可用相机；可以从相册选择图片。"
                        return
                    }
                    showCamera = true
                } label: {
                    Label("拍照", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(images.count >= 3)

                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: max(1, 3 - images.count),
                    matching: .images
                ) {
                    Label("相册", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(images.count >= 3)
            }

            Button {
                recognize()
            } label: {
                Label("开始识别", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .foregroundStyle(.black)
            .disabled(images.isEmpty || isRecognizing)
            .accessibilityIdentifier("开始识别器械")
        }
        .cardSurface()
    }

    private func resultCard(_ result: EquipmentRecognitionResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.machine.nameZH)
                        .font(.title3.bold())
                    Text(result.machine.nameEN)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(result.machine.confidence * 100))% 候选")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(result.machine.confidence >= 0.8 ? AppTheme.accent : AppTheme.orange)
            }

            if result.needsConfirmation {
                Label("识别结果需要你确认，不会自动写入动作库。", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(AppTheme.orange)
            }

            let muscles = Array(Set(result.exerciseCandidates.flatMap { $0.primaryMuscles }))
            MuscleMapView(highlightedMuscles: muscles)
                .frame(maxWidth: .infinity)

            Text("可以做什么动作")
                .font(.headline)

            ForEach(result.exerciseCandidates) { candidate in
                Button {
                    choose(candidate, machine: result.machine)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.nameZH)
                                .font(.subheadline.bold())
                            Text(candidate.nameEN)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text((candidate.primaryMuscles + candidate.secondaryMuscles).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.accent)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(12)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("识别动作-\(candidate.nameZH)")
            }

            ForEach(result.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.orange)
            }
        }
        .cardSurface()
    }

    private func recognize() {
        isRecognizing = true
        response = nil
        Task {
            do {
                let result = try await EquipmentRecognitionService().recognize(images: images)
                await MainActor.run {
                    response = result
                    isRecognizing = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRecognizing = false
                }
            }
        }
    }

    @MainActor
    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for item in items where images.count < 3 {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            appendImage(image)
        }
    }

    private func appendImage(_ image: UIImage) {
        guard images.count < 3 else { return }
        images.append(image)
        response = nil
    }

    private func choose(_ candidate: RecognizedExerciseCandidate, machine: RecognizedMachine) {
        do {
            let existing = ExerciseCatalogService.search(exercises, query: candidate.nameEN)
                .first(where: {
                    $0.terminologyCanonicalID == candidate.canonicalID
                        || $0.terminologyStandardNameEN == candidate.nameEN
                        || $0.terminologyStandardNameZH == candidate.nameZH
                        || $0.name == candidate.nameZH
                })
            let exercise: Exercise
            if let existing {
                exercise = existing
            } else {
                let result = try ExerciseCatalogService.save(
                    exercise: nil,
                    name: candidate.nameZH,
                    muscleGroup: candidate.primaryMuscles.first ?? "其他",
                    equipment: machine.nameZH,
                    volumeUnit: .kilogram,
                    defaultRestSeconds: 90,
                    notes: "",
                    referenceURL: "",
                    allExercises: exercises,
                    in: modelContext
                )
                exercise = result.exercise
            }
            pendingDraft = ExerciseSetupDraft.suggested(
                for: exercise,
                sessions: sessions,
                sessionExercises: sessionExercises,
                setLogs: setLogs
            )
            pendingSetupExercise = exercise
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MuscleMapView: View {
    let highlightedMuscles: [String]

    var body: some View {
        ZStack {
            Image("MuscleMapBase")
                .resizable()
                .scaledToFit()
                .opacity(0.78)

            GeometryReader { proxy in
                ForEach(markers, id: \.id) { marker in
                    Ellipse()
                        .fill(AppTheme.accent.opacity(0.5))
                        .overlay(Ellipse().stroke(AppTheme.accent, lineWidth: 1.5))
                        .frame(
                            width: proxy.size.width * marker.width,
                            height: proxy.size.height * marker.height
                        )
                        .position(
                            x: proxy.size.width * marker.x,
                            y: proxy.size.height * marker.y
                        )
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .padding(8)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("主要肌群：\(highlightedMuscles.joined(separator: "、"))")
    }

    private var markers: [MuscleMarker] {
        highlightedMuscles.flatMap { muscle in
            MuscleMarker.markers(for: muscle)
        }
    }
}

private struct MuscleMarker: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    static func markers(for muscle: String) -> [MuscleMarker] {
        switch muscle {
        case "胸部": return [.init(id: "chest", x: 0.30, y: 0.24, width: 0.18, height: 0.08)]
        case "背部": return [.init(id: "back", x: 0.72, y: 0.31, width: 0.18, height: 0.17)]
        case "肩部": return [
            .init(id: "shoulder-front", x: 0.20, y: 0.23, width: 0.07, height: 0.06),
            .init(id: "shoulder-back", x: 0.83, y: 0.23, width: 0.07, height: 0.06)
        ]
        case "手臂": return [
            .init(id: "arms-front", x: 0.16, y: 0.35, width: 0.06, height: 0.15),
            .init(id: "arms-back", x: 0.87, y: 0.35, width: 0.06, height: 0.15)
        ]
        case "核心": return [.init(id: "core", x: 0.30, y: 0.38, width: 0.12, height: 0.16)]
        case "臀部": return [.init(id: "glutes", x: 0.72, y: 0.51, width: 0.17, height: 0.11)]
        case "腿部": return [
            .init(id: "legs-front", x: 0.30, y: 0.61, width: 0.18, height: 0.22),
            .init(id: "legs-back", x: 0.72, y: 0.61, width: 0.18, height: 0.22)
        ]
        case "小腿": return [
            .init(id: "calves-front", x: 0.30, y: 0.79, width: 0.14, height: 0.15),
            .init(id: "calves-back", x: 0.72, y: 0.79, width: 0.14, height: 0.15)
        ]
        default: return []
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.onCapture(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

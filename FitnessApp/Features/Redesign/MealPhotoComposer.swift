import PhotosUI
import SwiftUI
import UIKit

struct MealPhotoComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let isAppending: Bool
    let onSave: ([Data], Date, MealType, String) throws -> Void

    @State private var images: [UIImage] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var date: Date
    @State private var mealType: MealType
    @State private var note = ""
    @State private var showsCamera = false
    @State private var cameraMessage: String?
    @State private var permissionDenied = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let maximumPhotos = 12

    init(date: Date, mealType: MealType? = nil, isAppending: Bool = false,
         onSave: @escaping ([Data], Date, MealType, String) throws -> Void) {
        self.isAppending = isAppending
        self.onSave = onSave
        let selected = Calendar.current.isDateInToday(date) ? Date.now : date
        _date = State(initialValue: selected)
        let hour = Calendar.current.component(.hour, from: selected)
        _mealType = State(initialValue: mealType ?? (hour < 10 ? .breakfast : hour < 15 ? .lunch : hour < 21 ? .dinner : .snack))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if images.isEmpty {
                        VStack(spacing: 12) {
                            SprintIcon(systemName: "camera.viewfinder", size: 80, prominent: true)
                            Text("拍照记餐").font(.title2.bold())
                            Text("先保存照片，之后按周评估。")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(images.indices, id: \.self) { index in
                                    Image(uiImage: images[index]).resizable().scaledToFill()
                                        .frame(width: 220, height: 260).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(alignment: .topTrailing) {
                                            Button { images.remove(at: index) } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title2).symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.7))
                                                    .frame(width: 44, height: 44)
                                            }.accessibilityLabel("移除第 \(index + 1) 张照片")
                                        }
                                }
                            }
                        }
                        Text("\(images.count) 张待保存")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }

                    if let cameraMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(cameraMessage, systemImage: "camera.fill")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                                .accessibilityIdentifier("餐食照片-相机提示")
                            if permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                                Button("打开设置允许相机") { openURL(url) }
                                    .frame(minHeight: 44).accessibilityIdentifier("餐食照片-打开设置")
                            }
                        }.cardSurface()
                    }

                    HStack(spacing: 12) {
                        Button { Task { await openCamera() } } label: {
                            Label(images.isEmpty ? "拍照" : "继续拍摄", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(SprintSecondaryButtonStyle()).accessibilityIdentifier("餐食照片-继续拍摄")
                        PhotosPicker(selection: $selection, maxSelectionCount: max(1, maximumPhotos - images.count), matching: .images) {
                            Label("相册", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(SprintSecondaryButtonStyle()).accessibilityIdentifier("餐食照片-相册")
                    }.disabled(isLoading || images.count >= maximumPhotos)
                    if isLoading { ProgressView("正在读取所选照片…") }

                    if !isAppending {
                        VStack(alignment: .leading, spacing: 16) {
                            SprintSectionHeading(title: "餐食信息", icon: "fork.knife")
                            DatePicker("记录时间", selection: $date, in: ...Date.now,
                                       displayedComponents: [.date, .hourAndMinute])
                                .accessibilityIdentifier("餐食照片-记录时间")
                            Picker("餐次", selection: $mealType) {
                                ForEach(MealType.allCases) { type in Text(type.title).tag(type) }
                            }.accessibilityIdentifier("餐食照片-餐次")
                            TextField("备注 · 如吃了一半、两人分食", text: $note, axis: .vertical)
                                .lineLimit(2...5).accessibilityIdentifier("餐食照片-备注")
                            DisclosureGroup("日期与保存说明") {
                                Text("日期按记录时的当地时区保存。旅行后不会移动到另一天。菜名、份量和营养均可留空。")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                        }.cardSurface()
                    } else {
                        Text("保存后追加到这一餐，不修改原始记录和已填营养。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    Label("离线保存 · 不自动上传", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }.padding(20)
            }
            .sprintPage()
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label(isAppending ? "保存追加照片" : "保存这餐", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(SprintPrimaryButtonStyle())
                    .disabled(images.isEmpty || isLoading || isSaving).accessibilityIdentifier("餐食照片-保存")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.background)
            }
            .navigationTitle(isAppending ? "追加餐食照片" : "拍照记餐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("餐食照片-取消")
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                MealCameraCapture { image in
                    showsCamera = false
                    if let image { images.append(image) }
                    else if images.isEmpty { dismiss() }
                }.ignoresSafeArea()
            }
            .task { await openCamera() }
            .onChange(of: selection) { _, items in Task { await loadPhotos(items) } }
            .alert("无法保存照片", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .sprintPage().tint(AppTheme.ink)
        .environment(\.calendar, Calendar.current).environment(\.timeZone, TimeZone.current)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    @MainActor private func openCamera() async {
        guard images.count < maximumPhotos else { return }
        #if DEBUG
        if CloudSyncRuntime.isTesting && CommandLine.arguments.contains("--ui-testing-meal-camera-fixture") {
            // Replaces only the camera hardware boundary in isolated UI tests.
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
            images.append(renderer.image { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            })
            return
        }
        #endif
        guard MealCameraAccess.isAvailable else {
            cameraMessage = "当前没有可用相机，可以从相册添加照片。"
            return
        }
        guard await MealCameraAccess.request() else {
            permissionDenied = true
            cameraMessage = "尚未允许相机访问。可以打开设置，或从相册添加。"
            return
        }
        permissionDenied = false
        cameraMessage = nil
        showsCamera = true
    }

    @MainActor private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoading = true
        defer { selection = []; isLoading = false }
        for item in items where images.count < maximumPhotos {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    errorMessage = "有一张照片无法读取，请重新选择。"
                    continue
                }
                images.append(image)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        guard !isSaving, !isLoading, !images.isEmpty else { return }
        isSaving = true
        do {
            let data = try images.map { image -> Data in
                let scale = min(1, 2048 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let jpeg = normalized.jpegData(compressionQuality: 0.85) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return jpeg
            }
            try onSave(data, date, mealType, note.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

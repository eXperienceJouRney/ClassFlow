import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// 图片仅在此页面的内存中保留；关闭后释放，不存入课表或草稿 JSON。
struct TimetableImageImportView: View {
    let semesterId: UUID
    var onRecognized: (ImportDraft, UIImage?) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    // 每次进入默认使用 OCR；旧版允许 AI 后备的偏好不能变成直接联网的授权。
    @State private var usesAIRecognition = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsFiles = false
    @State private var imageData: Data?
    @State private var preview: UIImage?
    @State private var fileName = "课表截图"
    @State private var isLoading = false
    @State private var isRecognizing = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var recognizer: LocalFirstTimetableImageRecognizer?
    @State private var needsAIConfiguration = false
    @State private var showsAISettings = false
    @State private var classOptions: [TimetableImageClassOption] = []
    @State private var selectedClassID: String?
    @State private var hasInspectedClasses = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    Button("从文件选择", systemImage: "folder") { showsFiles = true }
                } header: {
                    Text("选择一张课表图片")
                } footer: {
                    Text("支持 PNG、JPEG、HEIC 等图片，最大 20 MB。请保留完整星期、课节、班级和课程内容，使用方向端正的清晰截图。多班级课表需先选择班级。")
                }
                .disabled(isLoading || isRecognizing)

                Section {
                    Toggle("使用 AI 识别", isOn: $usesAIRecognition)
                } footer: {
                    Text(usesAIRecognition
                        ? "直接使用已配置的个人API识别图片，不经过OCR。结果需要核对并确认提交。"
                        : "默认使用OCR识别，图片不会发送至AI服务。")
                }
                .disabled(isLoading || isRecognizing)

                if let preview {
                    Section("所选图片") {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel("待识别的课表图片")
                        Text(fileName).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !classOptions.isEmpty {
                    Section {
                        Picker("导入班级", selection: $selectedClassID) {
                            Text("请选择班级").tag(String?.none)
                            ForEach(classOptions) { option in
                                Text(option.name).tag(String?.some(option.id))
                            }
                        }
                        .disabled(isRecognizing)
                    } header: {
                        Text("检测到 \(classOptions.count) 个班级")
                    } footer: {
                        Text("只提取所选班级及其共用课程；无法对应班级的分组会保留在核对页，默认不勾选。")
                    }
                }

                Section {
                    if isLoading || isRecognizing {
                        HStack {
                            ProgressView()
                            Text(isLoading ? "正在读取图片…" : "正在识别课程…")
                        }
                    } else {
                        Button(classOptions.isEmpty ? "识别并预览课程" : "预览所选班级课程", systemImage: "text.viewfinder") { recognize() }
                            .disabled(imageData == nil || (!classOptions.isEmpty && selectedClassID == nil))
                    }
                    if needsAIConfiguration {
                        Button("AI 识别配置", systemImage: "gearshape") { showsAISettings = true }
                    }
                }
            }
            .navigationTitle("图片导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recognitionTask?.cancel()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(isRecognizing)
            .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
                loadFile(result)
            }
            .task(id: selectedPhoto) { await loadPhoto() }
            .onChange(of: usesAIRecognition) { _, _ in resetRecognition() }
            .sheet(isPresented: $showsAISettings, onDismiss: {
                resetRecognition()
            }) {
                NavigationStack { AIImageImportSettingsView() }
            }
            .onDisappear { recognitionTask?.cancel() }
            .errorAlert($errorMessage)
        }
    }

    private func loadPhoto() async {
        guard let selectedPhoto else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw AppError.importParseFailed(reason: "无法读取所选照片，请重试或从文件选择")
            }
            try Task.checkCancellation()
            try setImage(data, name: "课表照片")
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? AppError)?.message ?? "无法读取所选照片；若照片保存在 iCloud，请先下载后重试"
        }
    }

    private func loadFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= VisionTimetableImageRecognizer.maximumImageBytes else {
                throw AppError.importParseFailed(reason: "图片超过 20 MB，请裁剪或压缩后重试")
            }
            try setImage(Data(contentsOf: url), name: url.lastPathComponent)
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            errorMessage = (error as? AppError)?.message ?? "无法读取所选图片，请重新选择"
        }
    }

    private func setImage(_ data: Data, name: String) throws {
        guard data.count <= VisionTimetableImageRecognizer.maximumImageBytes else {
            throw AppError.importParseFailed(reason: "图片超过 20 MB，请裁剪或压缩后重试")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
              ] as CFDictionary) else {
            throw AppError.importParseFailed(reason: "无法读取图片，请选择 PNG、JPEG 或 HEIC 格式")
        }
        imageData = data
        preview = UIImage(cgImage: thumbnail)
        fileName = name
        resetRecognition()
        errorMessage = nil
    }

    private func recognize() {
        guard let imageData, !isRecognizing else { return }
        isRecognizing = true
        recognitionTask = Task {
            defer { isRecognizing = false }
            do {
                if recognizer == nil { recognizer = makeRecognizer() }
                guard let recognizer else { return }
                if !hasInspectedClasses {
                    classOptions = try await recognizer.classOptions(imageData: imageData)
                    try Task.checkCancellation()
                    hasInspectedClasses = true
                    if !classOptions.isEmpty { return }
                }
                let selected = classOptions.first { $0.id == selectedClassID }
                let activeRecognizer = SelectedLocalFirstTimetableImageRecognizer(recognizer: recognizer, selectedClassID: selectedClassID)
                let draft = try await store.createImportDraft(
                    fromImageData: imageData,
                    fileName: selected.map { fileName + " · " + $0.name } ?? fileName,
                    semesterId: semesterId,
                    recognizer: activeRecognizer
                )
                onRecognized(draft, preview)
                dismiss()
            } catch is CancellationError {
                return
            } catch let selection as TimetableClassSelectionNeeded {
                classOptions = selection.options
                selectedClassID = nil
                hasInspectedClasses = true
            } catch let error as AIImageImportConfigurationNeeded {
                needsAIConfiguration = true
                errorMessage = error.message
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func resetRecognition() {
        classOptions = []
        selectedClassID = nil
        hasInspectedClasses = false
        recognizer = nil
        needsAIConfiguration = false
        errorMessage = nil
    }

    private func makeRecognizer() -> LocalFirstTimetableImageRecognizer {
        guard usesAIRecognition else {
            return LocalFirstTimetableImageRecognizer(mode: .localOnly, ai: nil)
        }
        let ai: AITimetableImageRecognizer?
        if let personalKey = AIImageImportSettings.personalAPIKey {
            ai = try? AITimetableImageRecognizer(personal: AIImageImportSettings.personalConfiguration, apiKey: personalKey)
        } else { ai = nil }
        return LocalFirstTimetableImageRecognizer(mode: .aiOnly, ai: ai)
    }
}

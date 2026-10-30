import Foundation

enum TimetableImageRecognitionMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, localOnly, aiOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动"
        case .localOnly: "仅本地"
        case .aiOnly: "仅 AI"
        }
    }
}

struct TimetableClassSelectionNeeded: Error, Sendable {
    let options: [TimetableImageClassOption]
}

/// 支持本地或 AI 直识别；automatic 仅供原有自动后备流程使用。取消不触发后备请求。
actor LocalFirstTimetableImageRecognizer: TimetableClassImageRecognizer {
    private let mode: TimetableImageRecognitionMode
    private let local: any TimetableClassImageRecognizer
    private let ai: (any TimetableClassImageRecognizer)?
    private var imageData: Data?
    private var options: [TimetableImageClassOption] = []
    private var inspected = false
    private(set) var usedAI = false
    private(set) var fallbackReason: String?

    init(mode: TimetableImageRecognitionMode = .automatic,
         local: any TimetableClassImageRecognizer = VisionTimetableImageRecognizer(),
         ai: (any TimetableClassImageRecognizer)?) {
        self.mode = mode
        self.local = local
        self.ai = ai
    }

    func classOptions(imageData: Data) async throws -> [TimetableImageClassOption] {
        if self.imageData != imageData {
            self.imageData = imageData
            options = []
            inspected = false
            usedAI = mode == .aiOnly
            fallbackReason = nil
        }
        if inspected { return options }
        do {
            options = try await (usedAI ? requireAI() : local).classOptions(imageData: imageData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard mode == .automatic && !usedAI else { throw error }
            usedAI = true
            fallbackReason = "本地文字识别未完成，已转为 AI 识别。"
            options = try await requireAI().classOptions(imageData: imageData)
        }
        inspected = true
        return options
    }

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognize(imageData: imageData, fileName: fileName, selectedClassID: nil)
    }

    func recognize(imageData: Data, fileName: String, selectedClassID: String?) async throws -> [ImportDraftEntry] {
        _ = try await classOptions(imageData: imageData)
        if usedAI {
            return try await requireAI().recognize(imageData: imageData, fileName: fileName, selectedClassID: selectedClassID)
        }
        // 缺少用户的选班输入不是识别失败，不能借自动切换跳过选择。
        if !options.isEmpty && !options.contains(where: { $0.id == selectedClassID }) {
            throw TimetableClassSelectionNeeded(options: options)
        }
        let localEntries: [ImportDraftEntry]
        do {
            localEntries = try await local.recognize(imageData: imageData, fileName: fileName, selectedClassID: selectedClassID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard mode == .automatic else { throw error }
            return try await recognizeWithAI(imageData, fileName: fileName, selectedClassID: selectedClassID,
                                             reason: "本地未能还原课程，已转为 AI 识别。")
        }
        try Task.checkCancellation()
        let needsAI = await Self.needsAIAssistance(localEntries)
        if mode == .automatic && needsAI {
            return try await recognizeWithAI(imageData, fileName: fileName, selectedClassID: selectedClassID,
                                             reason: "本地结果缺少关键字段，已转为 AI 识别。")
        }
        return localEntries
    }

    static func needsAIAssistance(_ entries: [ImportDraftEntry]) -> Bool {
        let selected = entries.filter(\.isSelected)
        guard !selected.isEmpty else { return entries.isEmpty }
        return selected.contains {
            $0.courseName.isBlank || $0.weekday == nil || ($0.periodPair == nil && $0.customPair == nil)
                || $0.imageReview?.requiresWeekConfirmation == true
        }
    }

    private func requireAI() throws -> any TimetableClassImageRecognizer {
        guard let ai else {
            let message = mode == .aiOnly
                ? "请在 AI 识别配置中填写个人 API Key 后使用 AI 识别，也可关闭「使用 AI 识别」改用 OCR。"
                : "本地识别未完成。请在 AI 识别配置中填写个人 API Key 后重试，也可改用文本导入或手动录入。"
            throw AIImageImportConfigurationNeeded(message: message)
        }
        return ai
    }

    private func recognizeWithAI(_ data: Data, fileName: String, selectedClassID: String?, reason: String) async throws -> [ImportDraftEntry] {
        let previousSelection = options.first { $0.id == selectedClassID }
        let ai = try requireAI()
        usedAI = true
        fallbackReason = reason
        options = try await ai.classOptions(imageData: data)
        if let previousSelection {
            guard let matching = options.first(where: { $0.name == previousSelection.name }) else {
                throw AppError.importParseFailed(reason: "AI 未能确认之前选择的班级，请核对原图后重新识别，避免混入其他班课程")
            }
            return try await ai.recognize(imageData: data, fileName: fileName, selectedClassID: matching.id)
        }
        if !options.isEmpty { throw TimetableClassSelectionNeeded(options: options) }
        return try await ai.recognize(imageData: data, fileName: fileName, selectedClassID: nil)
    }
}

struct SelectedLocalFirstTimetableImageRecognizer: TimetableImageRecognizer {
    let recognizer: LocalFirstTimetableImageRecognizer
    let selectedClassID: String?
    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognizer.recognize(imageData: imageData, fileName: fileName, selectedClassID: selectedClassID)
    }
}

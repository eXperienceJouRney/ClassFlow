import Foundation
import CoreGraphics
import ImageIO

/// 用户自己的 Key 只发送到其配置的个人 API 地址。
actor AITimetableImageRecognizer: TimetableClassImageRecognizer {
    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession
    private let configuration: PersonalTimetableAIConfiguration
    private var cachedImage: Data?
    private var cachedResults: [String: TimetableAIResult] = [:]
    init(personal configuration: PersonalTimetableAIConfiguration, apiKey: String, session: URLSession? = nil) throws {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, apiKey.count <= 2048, apiKey.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else {
            throw AIImageImportConfigurationNeeded(message: "请在 AI 识别配置中填写有效的个人 API Key")
        }
        let configuration = try configuration.validated()
        self.configuration = configuration
        self.endpoint = try configuration.requestURL
        self.apiKey = apiKey
        self.session = Self.makeSession(session)
    }

    private nonisolated static func makeSession(_ session: URLSession?) -> URLSession {
        if let session { return session }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: AIImportSessionDelegate(), delegateQueue: nil)
    }

    func classOptions(imageData: Data) async throws -> [TimetableImageClassOption] {
        let result = try await analyze(imageData, selectedClass: nil)
        return result.classes.map {
            // AI 使用完整班名作为 ID，编号仅供旧版边线解析器使用。
            TimetableImageClassOption(id: $0.id, name: $0.name, code: 0, shortNumber: 0, prefix: "")
        }
    }

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognize(imageData: imageData, fileName: fileName, selectedClassID: nil)
    }

    func recognize(imageData: Data, fileName: String, selectedClassID: String?) async throws -> [ImportDraftEntry] {
        let initial = try await analyze(imageData, selectedClass: nil)
        var result = initial
        if !initial.classes.isEmpty {
            guard let selectedClassID, let selected = initial.classes.first(where: { $0.id == selectedClassID }) else {
                throw AppError.importParseFailed(reason: "检测到班级课表，请先选择要导入的班级")
            }
            result = try await analyze(imageData, selectedClass: selected.name)
            guard result.classes.contains(where: { $0.id == selectedClassID && $0.name == selected.name }) else {
                throw AppError.importParseFailed(reason: "AI 返回的班级与所选班级不一致，请重试")
            }
        } else if selectedClassID != nil {
            throw AppError.importParseFailed(reason: "所选班级不属于这张图片，请重新选择图片和班级")
        }
        let entries = try await result.entries(selectedClassID: selectedClassID, draftId: UUID())
        guard !entries.isEmpty else {
            throw AppError.importParseFailed(reason: "AI 未找到可用课程，请核对图片或改用文本导入")
        }
        return entries
    }

    private func analyze(_ data: Data, selectedClass: String?) async throws -> TimetableAIResult {
        try Task.checkCancellation()
        if cachedImage != data {
            cachedImage = data
            cachedResults = [:]
        }
        let key = selectedClass.map { "class:" + $0 } ?? "inspect"
        if let result = cachedResults[key] { return result }
        guard data.count <= VisionTimetableImageRecognizer.maximumImageBytes else {
            throw AppError.importParseFailed(reason: "图片超过 20 MB，请裁剪或压缩后重试")
        }
        // 转成不带原图 EXIF 的 JPEG，保留小字所需分辨率，兼容 HEIC。
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
              ] as CFDictionary) else {
            throw AppError.importParseFailed(reason: "无法读取图片，请选择清晰的 PNG、JPEG 或 HEIC 图片")
        }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil) else {
            throw AppError.importParseFailed(reason: "无法处理所选图片")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination), jpeg.length <= 8 * 1024 * 1024 else {
            throw AppError.importParseFailed(reason: "图片内容过大，请裁剪无关区域后重试")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = try await PersonalTimetableAPI.request(imageBase64: (jpeg as Data).base64EncodedString(),
                                                                selectedClass: selectedClass, configuration: configuration)
        do {
            let (responseData, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AIImportResponseError.invalid }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw AIImageImportConfigurationNeeded(message: "API Key 无效或没有模型权限，请检查 AI 识别配置")
                }
                let message: String
                switch http.statusCode {
                case 400, 404, 422: message = "请检查 API 地址、接口格式和模型 ID，并确认模型支持图片与所选 JSON 输出格式"
                case 402: message = "API 账户余额不足，请检查账户余额"
                case 413: message = "图片过大，请裁剪无关区域后重试"
                case 429: message = "AI 服务繁忙，请稍后重试"
                case 503: message = "AI 服务暂不可用，请检查 AI 识别配置，或改用文本导入"
                case 504: message = "AI 识别超时，请稍后重试"
                default: message = "AI 识别未完成，请重试或改用文本导入"
                }
                throw AppError.dependencyUnavailable(reason: message)
            }
            guard responseData.count <= 2 * 1024 * 1024 else { throw AIImportResponseError.invalid }
            let result = try await PersonalTimetableAPI.result(from: responseData, configuration: configuration)
            try await result.validate()
            // actor 在请求期间可能重入，旧请求不能覆盖新图片的缓存。
            if cachedImage == data { cachedResults[key] = result }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIImageImportConfigurationNeeded {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AppError.dependencyUnavailable(reason: error.code == .timedOut
                ? "AI 识别超时，请稍后重试" : "无法连接 AI 服务，请检查网络和服务地址，或改用文本导入")
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.importParseFailed(reason: "AI 返回的数据不完整或格式不正确，请重试")
        }
    }
}

final class AIImportSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // 图片与访问令牌只发到明确配置的地址。
        completionHandler(nil)
    }
}

struct ClassSelectedAITimetableImageRecognizer: TimetableImageRecognizer {
    let recognizer: AITimetableImageRecognizer
    let selectedClassID: String?

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry] {
        try await recognizer.recognize(imageData: imageData, fileName: fileName, selectedClassID: selectedClassID)
    }
}

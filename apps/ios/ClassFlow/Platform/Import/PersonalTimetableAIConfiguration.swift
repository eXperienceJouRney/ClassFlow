import Foundation
import CryptoKit

nonisolated enum PersonalTimetableAIService: String, Codable, CaseIterable, Sendable {
    case deepSeek, compatible
    var title: String { self == .deepSeek ? "DeepSeek" : "其他兼容服务" }
}

nonisolated enum PersonalTimetableAIProtocol: String, Codable, CaseIterable, Sendable {
    case responses, chatCompletions
    var title: String { self == .responses ? "Responses" : "Chat Completions" }
    var path: String { self == .responses ? "responses" : "chat/completions" }
}

nonisolated enum PersonalTimetableAIJSONMode: String, Codable, CaseIterable, Sendable {
    case schema, object
    var title: String { self == .schema ? "JSON Schema" : "JSON 对象" }
}

/// 个人服务配置不含密钥；密钥按实际请求地址隔离保存在钥匙串。
nonisolated struct PersonalTimetableAIConfiguration: Codable, Equatable, Sendable {
    var service: PersonalTimetableAIService = .deepSeek
    var baseURL: String = ""
    var model: String = ""
    var apiProtocol: PersonalTimetableAIProtocol = .chatCompletions
    var jsonMode: PersonalTimetableAIJSONMode = .object

    static let deepSeek = Self()
    var effectiveProtocol: PersonalTimetableAIProtocol { service == .deepSeek ? .responses : apiProtocol }
    var effectiveModel: String { service == .deepSeek ? "deepseek-flash" : model.trimmingCharacters(in: .whitespacesAndNewlines) }
    var effectiveJSONMode: PersonalTimetableAIJSONMode { service == .deepSeek ? .schema : jsonMode }

    func validated() throws -> Self {
        if service == .deepSeek { return .deepSeek }
        _ = try requestURL
        guard !effectiveModel.isEmpty, effectiveModel.count <= 256,
              effectiveModel.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AppError.dependencyUnavailable(reason: "请填写服务商提供的图片识别模型 ID")
        }
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = effectiveModel
        return value
    }

    var requestURL: URL {
        get throws {
            if service == .deepSeek { return URL(string: "https://api.deepseek.com/responses")! }
            guard baseURL.count <= 2048 else {
                throw AppError.dependencyUnavailable(reason: "API 地址过长，请检查后重试")
            }
            let url = try AIImageImportSettings.endpoint(from: baseURL)
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let other = apiProtocol == .responses ? "chat/completions" : "responses"
            if path == other || path.hasSuffix("/" + other) {
                throw AppError.dependencyUnavailable(reason: "API 地址与所选接口格式不一致，请检查接口格式")
            }
            if path == apiProtocol.path || path.hasSuffix("/" + apiProtocol.path) { return url }
            return url.appendingPathComponent(apiProtocol.path)
        }
    }

    var credentialAccount: String {
        get throws {
            // 保留旧版 DeepSeek 个人 Key；它不会被迁移到自定义地址。
            if service == .deepSeek { return "deepseek-personal" }
            let digest = SHA256.hash(data: Data(try requestURL.absoluteString.utf8))
            return "personal-api-" + digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}

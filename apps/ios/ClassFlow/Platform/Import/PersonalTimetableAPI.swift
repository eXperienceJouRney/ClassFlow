import Foundation

/// 个人服务共用同一份提示与结果契约；不自动重试或切换提供方。
enum PersonalTimetableAPI {
    static func request(imageBase64: String, selectedClass: String?, configuration: PersonalTimetableAIConfiguration) throws -> Data {
        let configuration = try configuration.validated()
        guard let promptURL = Bundle.main.url(forResource: "TimetableAIPrompt", withExtension: "txt"),
              let schemaURL = Bundle.main.url(forResource: "TimetableAIResponse.schema", withExtension: "json") else {
            throw AppError.dependencyUnavailable(reason: "AI 识别资源缺失，请重新安装应用")
        }
        var prompt = try String(contentsOf: promptURL, encoding: .utf8)
        let schemaData = try Data(contentsOf: schemaURL)
        let schema = try JSONSerialization.jsonObject(with: schemaData)
        if configuration.effectiveJSONMode == .object {
            prompt += "\n输出必须严格符合以下 JSON Schema，包含全部必填字段，不输出 Markdown：\n" + String(decoding: schemaData, as: UTF8.self)
        }
        let selection: [String: Any] = ["selectedClass": selectedClass as Any? ?? NSNull()]
        let selectionText = String(decoding: try JSONSerialization.data(withJSONObject: selection), as: UTF8.self)
        let imageURL = "data:image/jpeg;base64," + imageBase64
        let format: [String: Any] = configuration.effectiveJSONMode == .schema
            ? ["type": "json_schema", "name": "classflow_timetable", "strict": true, "schema": schema]
            : ["type": "json_object"]
        var body: [String: Any]
        switch configuration.effectiveProtocol {
        case .responses:
            body = ["model": configuration.effectiveModel, "store": false, "max_output_tokens": 8192,
                "instructions": prompt,
                "input": [["role": "user", "content": [
                    ["type": "input_text", "text": selectionText],
                    ["type": "input_image", "image_url": imageURL, "detail": "high"]]]],
                "text": ["format": format]]
            if configuration.service == .deepSeek { body["reasoning"] = ["effort": "none"] }
        case .chatCompletions:
            let responseFormat: [String: Any] = configuration.effectiveJSONMode == .schema
                ? ["type": "json_schema", "json_schema": ["name": "classflow_timetable", "strict": true, "schema": schema]]
                : ["type": "json_object"]
            body = ["model": configuration.effectiveModel, "stream": false, "max_tokens": 8192,
                "messages": [["role": "system", "content": prompt],
                    ["role": "user", "content": [
                        ["type": "text", "text": selectionText],
                        ["type": "image_url", "image_url": ["url": imageURL, "detail": "high"]]]]],
                "response_format": responseFormat]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func result(from data: Data, configuration: PersonalTimetableAIConfiguration) throws -> TimetableAIResult {
        let text: String
        switch configuration.effectiveProtocol {
        case .responses:
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.status == "completed" else { throw incomplete() }
            let parts = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
            guard !parts.contains(where: { $0.type == "refusal" }) else { throw refused() }
            text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        case .chatCompletions:
            let response = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard response.choices.count == 1, let choice = response.choices.first else { throw incomplete() }
            guard choice.message.refusal?.isEmpty ?? true else { throw refused() }
            guard choice.finish_reason == "stop", let content = choice.message.content else { throw incomplete() }
            text = content
        }
        let result = try JSONDecoder().decode(TimetableAIResult.self, from: Data(text.utf8))
        try result.validate()
        return result
    }

    private static func incomplete() -> AppError {
        .importParseFailed(reason: "AI 未完整返回结果，请重试或检查模型与接口配置")
    }

    private static func refused() -> AppError {
        .importParseFailed(reason: "AI 未能识别这张图片，请更换图片或改用文本导入")
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            struct Content: Decodable { let type: String; let text: String? }
            let type: String
            let content: [Content]?
        }
        let status: String
        let output: [Item]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String?; let refusal: String? }
            let finish_reason: String?
            let message: Message
        }
        let choices: [Choice]
    }
}

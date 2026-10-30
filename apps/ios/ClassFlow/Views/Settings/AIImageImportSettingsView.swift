import SwiftUI

struct AIImageImportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var personalAPIKey = AIImageImportSettings.personalAPIKey ?? ""
    @State private var personalConfiguration = AIImageImportSettings.personalConfiguration
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("服务商", selection: $personalConfiguration.service) {
                    ForEach(PersonalTimetableAIService.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if personalConfiguration.service == .compatible {
                    TextField("API 根地址，如 https://api.example.com/v1", text: $personalConfiguration.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("个人 API 地址")
                    TextField("支持图片输入的模型 ID", text: $personalConfiguration.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("接口格式", selection: $personalConfiguration.apiProtocol) {
                        ForEach(PersonalTimetableAIProtocol.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("JSON 输出", selection: $personalConfiguration.jsonMode) {
                        ForEach(PersonalTimetableAIJSONMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                SecureField("API Key", text: $personalAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                if let url = try? personalConfiguration.requestURL {
                    LabeledContent("请求地址") { Text(url.absoluteString).font(.caption).textSelection(.enabled) }
                }
            } header: {
                Text("个人 API")
            } footer: {
                Text("可使用支持图片与 JSON 输出的 OpenAI 兼容服务。AI 请求直接发送至所配置的服务，费用由对应 API 账户承担。Key 按请求地址保存在本机钥匙串。更换服务地址后需重新填写 Key；清空 Key 并保存后无法使用 AI 识别。接口格式与模型 ID 请以服务商文档为准。")
            }
            Section {
                Text("用于图片导入。图片导入默认使用OCR方法，显式开启AI识别后使用个人配置的API。结果仍需核对与确认。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI 识别配置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: personalConfiguration.service) { _, service in
            personalAPIKey = ""
            personalConfiguration = service == .deepSeek ? .deepSeek : PersonalTimetableAIConfiguration(service: .compatible)
        }
        .onChange(of: personalConfiguration.baseURL) { _, _ in personalAPIKey = "" }
        .onChange(of: personalConfiguration.apiProtocol) { _, _ in personalAPIKey = "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        try AIImageImportSettings.save(personalAPIKey: personalAPIKey,
                                                      personalConfiguration: personalConfiguration)
                        dismiss()
                    } catch { errorMessage = error.userMessage }
                }
            }
        }
        .errorAlert($errorMessage)
    }
}

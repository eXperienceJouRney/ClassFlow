import Foundation
import Security

enum AIImageImportSettings {
    private static let personalConfigurationKey = "classflow.ai.imageImport.personalConfiguration"
    private static let tokenService = "ClassFlow.ImageImportService"

    nonisolated static func endpoint(from string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw AppError.dependencyUnavailable(reason: "请填写 HTTPS API 地址；本机调试可使用 localhost 的 HTTP 地址")
        }
        return url
    }

    static var personalConfiguration: PersonalTimetableAIConfiguration {
        guard let data = UserDefaults.standard.data(forKey: personalConfigurationKey),
              let value = try? JSONDecoder().decode(PersonalTimetableAIConfiguration.self, from: data) else { return .deepSeek }
        return value
    }
    static var personalAPIKey: String? {
        guard let account = try? personalConfiguration.credentialAccount else { return nil }
        return readToken(account: account)
    }

    private static func readToken(account: String) -> String? {
        var query = tokenQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.normalizedOrNil
    }

    static func save(personalAPIKey: String, personalConfiguration: PersonalTimetableAIConfiguration) throws {
        let personal = personalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuration = personalConfiguration
        guard personal.count <= 2048, personal.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else {
            throw AppError.dependencyUnavailable(reason: "API Key 格式不正确")
        }
        if !personal.isEmpty { configuration = try configuration.validated() }
        let configurationData = try JSONEncoder().encode(configuration)
        if let account = try? configuration.credentialAccount { try storeToken(personal, account: account) }
        // 保存配置时清理旧版共享试用凭据；个人 Key 保持原有存储位置。
        try storeToken("", account: "proxy-access")
        UserDefaults.standard.removeObject(forKey: "classflow.ai.imageImport.endpoint")
        UserDefaults.standard.set(configurationData, forKey: personalConfigurationKey)
    }

    private static func storeToken(_ token: String, account: String) throws {
        let queryBase = tokenQuery(account: account)
        let status: OSStatus
        if token.isEmpty {
            status = SecItemDelete(queryBase as CFDictionary)
        } else {
            let data = Data(token.utf8)
            let updated = SecItemUpdate(queryBase as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updated == errSecItemNotFound {
                var query = queryBase
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(query as CFDictionary, nil)
            } else { status = updated }
        }
        guard status == errSecSuccess || (token.isEmpty && status == errSecItemNotFound) else {
            throw AppError.dependencyUnavailable(reason: "无法保存 API Key，请重试")
        }
    }

    private static func tokenQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: tokenService, kSecAttrAccount as String: account]
    }

}

import Foundation

/// 应用层统一错误类型；每个分支对应一个稳定错误码。
/// `message` 面向用户的提示，不包含内部路径或敏感数据。
enum AppError: Error, Equatable, Sendable {

    case validation(ValidationError)
    case notFound(entity: String)
    case persistenceFailed(reason: String)
    case illegalOperation(reason: String)
    case confirmationRequired(operation: String)
    case importParseFailed(reason: String)
    case importCommitFailed(reason: String)
    case unsupportedFormat(format: String)
    case dependencyUnavailable(reason: String)
    case invalidStateTransition(reason: String)
}

extension AppError {

    /// 稳定错误码，供程序分支与测试断言使用。
    var code: String {
        switch self {
        case .validation: "VALIDATION_FAILED"
        case .notFound: "NOT_FOUND"
        case .persistenceFailed: "PERSISTENCE_FAILED"
        case .illegalOperation: "VALIDATION_FAILED"
        case .confirmationRequired: "DELETE_CONFIRMATION_REQUIRED"
        case .importParseFailed: "IMPORT_PARSE_FAILED"
        case .importCommitFailed: "IMPORT_COMMIT_FAILED"
        case .unsupportedFormat: "UNSUPPORTED_FORMAT"
        case .dependencyUnavailable: "DEPENDENCY_UNAVAILABLE"
        case .invalidStateTransition: "INVALID_STATE_TRANSITION"
        }
    }

    var message: String {
        switch self {
        case let .validation(error):
            error.message
        case let .notFound(entity):
            "「\(entity)」不存在，可能已被删除"
        case let .persistenceFailed(reason):
            "保存失败：\(reason)"
        case let .illegalOperation(reason):
            reason
        case let .confirmationRequired(operation):
            "「\(operation)」需要确认后才会执行"
        case let .importParseFailed(reason):
            "导入内容解析失败：\(reason)"
        case let .importCommitFailed(reason):
            "导入提交失败：\(reason)"
        case let .unsupportedFormat(format):
            "暂不支持的文件格式：\(format)"
        case let .dependencyUnavailable(reason):
            "功能暂不可用：\(reason)"
        case let .invalidStateTransition(reason):
            reason
        }
    }
}

extension Validatable {

    func appValidated() throws {
        if let first = validationErrors.first {
            throw AppError.validation(first)
        }
    }
}

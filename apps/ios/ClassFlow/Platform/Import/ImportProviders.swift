import Foundation

/// 用户选择的导入文件引用。
struct ImportFileReference: Hashable, Sendable {

    let url: URL
    let displayName: String

    init(url: URL, displayName: String? = nil) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
    }
}

/// 系统文件选择能力的适配器接口。
/// 只能读取用户主动选择的文件；不可访问时抛出明确错误，用户提示不得包含本地路径。
protocol ImportFileProvider: Sendable {

    func selectImportFile() async throws -> ImportFileReference
}

/// 首版支持的文件格式。
enum TimetableFileFormat: String, CaseIterable, Hashable, Sendable {

    case plainText = "txt"
    case altText = "text"
    case csv = "csv"
    case markdown = "md"
    case altMarkdown = "markdown"

    init?(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let format = TimetableFileFormat(rawValue: ext) else { return nil }
        self = format
    }

    /// 面向用户展示的支持格式清单。
    static var supportedExtensionsText: String {
        Array(Set(TimetableFileFormat.allCases.map(\.rawValue))).sorted().joined(separator: " / ")
    }

    var isStructuredTable: Bool {
        self == .csv
    }
}

/// 文本文件读取器。
/// 只读取用户主动选择的文件，并将底层错误映射为应用层错误。
struct TextFileImportReader: Sendable {

    func readText(at url: URL) throws -> String {
        guard TimetableFileFormat(fileName: url.lastPathComponent) != nil else {
            throw AppError.unsupportedFormat(format: (url.lastPathComponent as NSString).pathExtension)
        }

        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let text = String(data: data, encoding: .unicode) {
                return text
            }
            throw AppError.importParseFailed(reason: "文件不是可识别的文本编码")
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.dependencyUnavailable(reason: "无法读取所选文件，请重新选择")
        }
    }
}

/// 图片识别适配器接口。
/// 识别结果为候选数据；联网实现必须在发起前向用户明确说明图片发送目的地。
nonisolated protocol TimetableImageRecognizer: Sendable {

    func recognize(imageData: Data, fileName: String) async throws -> [ImportDraftEntry]
}

nonisolated protocol TimetableClassImageRecognizer: TimetableImageRecognizer {
    func classOptions(imageData: Data) async throws -> [TimetableImageClassOption]
    func recognize(imageData: Data, fileName: String, selectedClassID: String?) async throws -> [ImportDraftEntry]
}

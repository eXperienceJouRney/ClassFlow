import Foundation

enum StoreError: Error, Equatable, Sendable {
    case loadFailed(reason: String)
    case saveFailed(reason: String)
}

/// 数据访问抽象：UI 不直接操作底层持久化对象。
protocol AppDataStore {
    func load() throws -> AppData
    func save(_ data: AppData) throws

    /// 补写缺失或旧格式的小组件快照；只应在主 App 启动时调用一次。
    /// 默认实现什么都不做。
    func repairWidgetSnapshotIfNeeded(_ data: AppData)
}

extension AppDataStore {

    func repairWidgetSnapshotIfNeeded(_ data: AppData) {}
}

final class InMemoryDataStore: AppDataStore {

    private var data: AppData

    init(_ data: AppData = .empty) {
        self.data = data
    }

    func load() throws -> AppData {
        data
    }

    func save(_ data: AppData) throws {
        self.data = data
    }
}

final class FileDataStore: AppDataStore {

    let url: URL

    /// 保存后要重排时间线的组件（默认全部）；组件内的交互动作应传空数组，交由系统重排。
    var widgetReloadKinds: [WidgetKind] = WidgetKind.all

    /// 快照文件目录；nil = 优先 App Group 共享容器，不可用时退回数据文件所在目录。
    var widgetSnapshotDirectory: URL?

    private func widgetSnapshotURL() -> URL? {
        if let widgetSnapshotDirectory {
            return widgetSnapshotDirectory.appendingPathComponent(WidgetSnapshotStore.fileName)
        }
        return WidgetSnapshotStore.fileURL(fallbackDirectory: url.deletingLastPathComponent())
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// 数据文件位置：优先 App Group 共享容器，没有资格时退回 App 自己的 Documents。
    static func defaultURL() -> URL {
        let directory = WidgetSnapshotStore.containerURL() ?? fallbackDirectory()
        return directory.appendingPathComponent("classflow.json")
    }

    private static func fallbackDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        let data: AppData
        do {
            let payload = try Data(contentsOf: url)
            data = try decoder.decode(AppData.self, from: payload).migrated()
        } catch {
            throw StoreError.loadFailed(reason: String(describing: error))
        }

        // 快照缺失 / 比数据旧，或者已经隔夜（`today` 不是今天）→ 补写一次。
        let snapshotURL = widgetSnapshotURL()
        if WidgetSnapshotStore.needsRefresh(snapshotURL: snapshotURL, dataURL: url)
            || WidgetSnapshotStore.isStaleDay(at: snapshotURL) {
            refreshWidgetSnapshot(data)
        }

        return data
    }

    func save(_ data: AppData) throws {
        let payload: Data
        do {
            payload = try encoder.encode(data)
        } catch {
            throw StoreError.saveFailed(reason: String(describing: error))
        }

        if let existing = try? Data(contentsOf: url),
           existing == payload {
            // 内容没变时连数据文件都不重写；但快照可能已经隔夜，仍需重算一次。
            let snapshotURL = widgetSnapshotURL()
            if WidgetSnapshotStore.needsRefresh(snapshotURL: snapshotURL, dataURL: url)
                || WidgetSnapshotStore.isStaleDay(at: snapshotURL) {
                refreshWidgetSnapshot(data)
            }
            return
        }

        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            throw StoreError.saveFailed(reason: String(describing: error))
        }

        refreshWidgetSnapshot(data)
    }

    /// 刷新小组件的共享快照；写失败不能影响课表本身。
    private func refreshWidgetSnapshot(_ data: AppData) {
        guard let snapshotURL = widgetSnapshotURL() else { return }
        WidgetSnapshotStore.write(data, to: snapshotURL, reloading: widgetReloadKinds)
    }

    /// 主 App 启动时补写一次缺失或旧格式的小组件快照。
    func repairWidgetSnapshotIfNeeded(_ data: AppData) {
        guard let snapshotURL = widgetSnapshotURL(),
              WidgetSnapshotStore.isLegacy(at: snapshotURL)
        else { return }

        WidgetSnapshotStore.write(data, to: snapshotURL, reloading: widgetReloadKinds)
    }
}

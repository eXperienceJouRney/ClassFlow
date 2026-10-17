# ClassFlow · iOS 客户端

SwiftUI 实现的 ClassFlow 主 App，含 WidgetKit 桌面小组件。

## 目录结构

```text
apps/ios/
├── ClassFlow/                 主 App target（PBXFileSystemSynchronizedRootGroup，新增文件自动进编译）
│   ├── Models/                领域模型与纯计算（仅依赖 Foundation）
│   ├── Services/              状态管理、持久化、路由、小组件快照
│   ├── Views/                 页面级视图，按功能分子目录
│   │   ├── Schedule/          日 / 周 / 月课表
│   │   ├── Courses/           课程与安排编辑
│   │   ├── Tasks/             待办
│   │   ├── Notes/             课程笔记
│   │   ├── Settings/          学期、课节时间、偏好
│   │   ├── Import/            课表导入流程
│   │   ├── Widget/            小组件卡片视图（主 App 与 widget 共用）
│   │   └── Support/           预览数据与展示层辅助
│   ├── Components/            可复用视图与设计常量（`DesignTokens`）
│   └── Platform/Import/       文本课表解析与导入提供者
├── ClassFlowWidget/           WidgetKit 扩展（显式登记文件，非同步组）
├── ClassFlow-Info.plist       主 App Info.plist
└── ClassFlow.xcodeproj
```

## 分层规则

| 层 | 允许依赖 | 不允许 |
|---|---|---|
| `Models/` | Foundation | SwiftUI、持久化、网络 |
| `Services/` | Models、Foundation | SwiftUI 视图类型 |
| `Views/` `Components/` | Services、Models、SwiftUI | 直接读写文件 |

`AppStore` 是唯一的可变状态入口：视图通过 `@Environment(AppStore.self)` 读取，写入统一走 `commit(_:)`，内部由 `AppDataStore` 落盘。视图不直接接触持久化对象。

## 数据流

```text
View ──commit──▶ AppStore ──▶ AppDataStore ──▶ classflow.json（App Group 容器）
                    └──▶ WidgetSnapshotStore ──▶ classflow-widget.json（小组件读）
```

`WidgetSnapshot` 由主 App 预先算好并烘焙成「已排版」结构，小组件只做倒计时与渲染；相对时间文案一律在渲染时现算。

## 小组件 target 的共享文件

`ClassFlowWidget` 不是同步组，参与 widget 编译的文件必须在 `project.pbxproj` 里显式登记。共享来源为：

- `ClassFlow/Models/*.swift`
- `ClassFlow/Services/{AppData,AppDataStore,Inputs,WidgetSnapshotStore}.swift`
- `ClassFlow/Views/Widget/*.swift`

新增共享文件后运行 `python3 Scripts/sync-widget-target.py` 重新生成登记记录（`--check` 只报告不写入）。

## 构建

```bash
xcodebuild -project apps/ios/ClassFlow.xcodeproj -scheme ClassFlow \
  -destination "id=<模拟器 UDID>" -derivedDataPath .build build
```

**用 UDID 而不是设备名**。同名设备在不同 runtime 下会重复，`name=` 会报 `ambiguous`。用 `xcrun simctl list devices available` 查。

测试与真实课表夹具只在本地维护，不入库。`ClassFlowTests` 是文件夹同步组，本地目录存在即自动参与编译。

# ClassFlow · iOS 客户端

SwiftUI 实现的 ClassFlow 主 App，含 WidgetKit 桌面小组件与课程 Live Activity。

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
│   ├── LiveActivity/          Live Activity 数据契约（主 App 与 widget 共用）
│   └── Platform/
│       ├── Import/            文本课表解析与导入提供者
│       └── LiveActivity/      课程 Live Activity 控制器（ActivityKit，仅主 App）
├── ClassFlowWidget/           WidgetKit 扩展（桌面组件 + Live Activity，显式登记文件，非同步组）
├── ClassFlow-Info.plist       主 App Info.plist
└── ClassFlow.xcodeproj
```

## 分层规则

| 层 | 允许依赖 | 不允许 |
|---|---|---|
| `Models/` | Foundation | SwiftUI、持久化、网络 |
| `Services/` | Models、Foundation | SwiftUI 视图类型 |
| `Views/` `Components/` | Services、Models、SwiftUI | 直接读写文件 |
| `LiveActivity/` | ActivityKit、Foundation | SwiftUI、持久化、网络、Models |
| `Platform/` | Models、Services、系统框架（ActivityKit 等） | SwiftUI 视图类型 |

`AppStore` 是唯一的可变状态入口：视图通过 `@Environment(AppStore.self)` 读取，写入统一走 `commit(_:)`，内部由 `AppDataStore` 落盘。视图不直接接触持久化对象。

## 数据流

```text
View ──commit──▶ AppStore ──▶ AppDataStore ──▶ classflow.json（App Group 容器）
                    └──▶ WidgetSnapshotStore ──▶ classflow-widget.json（小组件读）
```

`WidgetSnapshot` 由主 App 预先算好并烘焙成「已排版」结构，小组件只做倒计时与渲染；相对时间文案一律在渲染时现算。
快照里的日期都是绝对时刻：时间线跨过零点重排时，若 `today` 已不是今天，组件会读共享容器里的数据文件就地重算并写回，
主 App 一天没打开也不会一直停在旧日期。

## 小组件 target 的共享文件

`ClassFlowWidget` 不是同步组，参与 widget 编译的文件必须在 `project.pbxproj` 里显式登记。共享来源为：

- `ClassFlow/Models/*.swift`
- `ClassFlow/Services/{AppData,AppDataStore,Inputs,WidgetSnapshotStore}.swift`
- `ClassFlow/Views/Widget/*.swift`
- `ClassFlow/LiveActivity/*.swift`

新增共享文件后运行 `python3 Scripts/sync-widget-target.py` 重新生成登记记录（`--check` 只报告不写入）。

## 课程 Live Activity

`CourseActivityAttributes` 定义一节课的不变信息（课程名、起止时间、地点、`ScheduleEntry.id`），
下一节课放在 `ContentState` 里，因为 ActivityKit 的 attributes 在活动开始后不可更新。
UI 由 `ClassFlowWidget` 里的 `CourseLiveActivity` 承载：锁屏、Dynamic Island 展开 / 紧凑 / 最小化，
统一黑底白字、不使用课程图标。

数据全部来自现有课表，不另建一份课程数据：

- `Timetable.currentSession(at:)` / `nextSession(after:)` 把课节换算成真实的 `ClassSession`
  （课程名、起止 `Date`、地点；作息没配好时返回 nil，不猜时间）。
- App 内没有实时活动卡片或按钮：唯一的入口是设置 › 实时活动 ›「自动显示当前课程」，
  打开后由调度器在正在上课时自动开启，课表页不再有手动启动 / 结束的入口。
- `CourseLiveActivityController` 负责启动 / 收尾：同一时刻只保留一条课程活动，
  重复启动同一节只更新 `ContentState`；启动前、回到前台、系统把活动标成过期时都会对账，
  已下课的活动会被结束，不留过期活动。
- 剩余时间与进度条不靠 App 刷新：界面使用 `Text(timerInterval:)` / `ProgressView(timerInterval:)`
  按系统时间自绘，ActivityKit 只在开始与对账时更新。

### 版面

`CourseLiveActivityComponents.swift` 是纯展示层：只认 `CourseActivityPresentation`，
不引用 ActivityKit，四种形态共用同一套字号 / 间距令牌（`CourseActivityType` / `CourseActivityMetrics`）：

| 形态 | 内容 |
|---|---|
| 紧凑 | 课程名 + 距下课倒计时 |
| 最小化 | 距下课倒计时；已下课时显示「已结束」 |
| 展开 | 课程名、起止时刻与地点、通栏进度条、下一节课 |
| 锁屏 | 课程名 + 剩余时间、时段与地点、进度条、下一节课 |

课程名与地点在 `CourseActivityPresentation` 里统一去掉首尾空白，地点为空串时变成 `nil`：
锁屏、展开态与下一节课行都不会留下孤零零的 `·`。长课名各有上限——锁屏最多两行、
展开态上方区域最多两行并允许缩放、紧凑态一行缩放后截断；右侧的时刻与倒计时用
`.fixedSize()` 固定，不会先被课名挤掉。版面只用文字、进度条与一条分割线，
不使用课程图标、装饰图案或按钮。

展开态的字号与行距都乘 `CourseActivityMetrics.expandedScale`（90%）：
灵动岛展开后的外框由系统固定，内容收一档，每个区域再多让一点内边距
（`expandedInsetHorizontal` / `expandedInsetVertical`），四周留白因此比锁屏更宽。
进度条的粗细不参与缩放——线性 `ProgressView` 的粗细由系统决定，跟着缩反而显粗。

### 验证版面

不需要真机也能先量版面：`Scripts/live-activity-visual-check.swift` 用 `ImageRenderer`
把四种形态（含长课名 / 无地点 / 已下课）渲染成 PNG，再用 Vision OCR 与像素采样核对
文案、上下左右顺序、进度条粗细与截断：

```bash
xcrun swiftc -O -parse-as-library -o /tmp/classflow-live-activity-visual \
  apps/ios/ClassFlow/Models/*.swift apps/ios/ClassFlow/Services/Inputs.swift \
  apps/ios/ClassFlowWidget/CourseLiveActivityComponents.swift \
  Scripts/live-activity-visual-check.swift
/tmp/classflow-live-activity-visual .build
```

截图在 `.build/live-activity-*.png`。画布尺寸是系统容器的近似值，只核对内容排版；
最终样式以 Xcode Preview 或模拟器 / 真机为准。`CourseLiveActivity.swift` 里为锁屏、
展开、紧凑、最小化以及长课名 / 无地点都留了 `#Preview`。

### 自动显示当前课程

设置 › 实时活动 ›「自动显示当前课程」打开后（默认关闭，`AppPreferences.autoStartLiveActivity`）：

- `CourseLiveActivityPlan` 是纯规则：只给**正在上**的课自动开启活动，不提前显示还没开始的课；
  当前没课时把下一次检查定在下一节开始，因此课间、跨天（明天 / 下周）都只醒一次。
- `CourseLiveActivityScheduler` 按规则调用控制器，只在「下课」和「下一节上课」两个边界各醒一次，
  不做按秒轮询。App 启动、回到前台、`AppStore.revision` 变化（课程时间修改、课程取消、
  切换学期）都会重新评估。
- 自动创建的活动在 `ContentState.isAutomatic` 里留了标记：关闭「自动显示当前课程」时
  只收掉这类活动（兼容旧版本里手动开启、当时仍在显示的活动）。
- 用户从锁屏 / 灵动岛划掉活动后，会记住这一节（`CourseLiveActivitySuppression`，
  写入 `UserDefaults`，键含安排 id 与上课时刻），本次课内不再自动重建。
- 系统关闭实时活动时不发起 `Activity.request`，设置页会显示「系统实时活动：已关闭」。

**iOS 系统限制（不要承诺无法保证的行为）**：iOS 只允许 App 在前台（或刚回到前台）时
`Activity.request` 启动实时活动；App 被挂起后，`Task` 定时器不会准点执行，也不能在后台
随意启动活动。因此自动模式的实际保证是：

- App 在前台时，到边界自动开始 / 结束 / 切换；
- App 回到前台时，按当前时间立即校正（正在上课就补上，已下课就收掉）；
- App 长时间完全不打开时，Live Activity 不会准点自动出现，已开始的活动会在 `staleDate`
  （下课时刻）被系统标成过期，并在下次回到前台时清理。

需要「完全准点且无需打开 App」时，必须接入服务端 Push（Live Activity push 的 `start` / `end`
事件），当前版本没有实现。

手动测试：

1. 设置 › 实时活动，打开「自动显示当前课程」；
2. 给今天当前时段建一门课（或让课程即将开始），回到课表页；
3. 正在上课时下拉通知中心 / 锁屏，应已自动出现活动，长按 Dynamic Island 查看展开态；
4. 等到下课时刻（或临时把课程结束时间改到 1 分钟后）：活动自动结束；若紧接着有下一节，
   到下一节开始时会自动切换；
5. 从锁屏 / 灵动岛划掉活动，本次课内不应再自动重建；
6. 把 App 切到后台再回来，活动应与当前课程一致（已下课的被收掉）。

逐状态检查（模拟器 / 真机）：

- **锁屏**：正在上课且已自动开启活动时锁屏（模拟器菜单 `Device › Lock`，快捷键 `⌘L`），应看到课程名、
  `剩余 …`、时段与地点；活动过期后同一位置变成「已结束」。
- **紧凑**：解锁回主屏幕，灵动岛应显示「课程名 + 倒计时」。
- **展开**：按住灵动岛约 1 秒（模拟器里按住鼠标），应显示课程名、起止时刻、地点、
  通栏进度条与下一节；点空白处收起。
- **最小化**：系统只在需要给其他实时活动让位时才切到这个形态，最可靠的检查方式是
  Xcode 里的 `#Preview("灵动岛 · 最小化")`。
- **长课名 / 无地点**：用 `#Preview` 的长课名版本，或临时把课程名改长、清空地点后回到前台让活动校正；
  检查课名折行或截断后，右侧的剩余时间与时刻仍然完整。

`ClassFlowTests/CourseLiveActivityControllerTests.swift` 在 App 宿主里真的请求 / 结束活动，
系统关闭实时活动时会跳过；`CourseLiveActivityPlanTests.swift` 覆盖上课 / 课间 / 跨天 /
取消 / 改时间 / 开关与权限；`CourseLiveActivitySchedulerTests.swift` 用替身覆盖自动启动、
不重建、取消与改时间后的重新评估；`ClassSessionTests.swift` 覆盖当前课程与旧活动识别。

主 App 的 `NSSupportsLiveActivities` 写在 `ClassFlow-Info.plist`。

## 构建

```bash
xcodebuild -project apps/ios/ClassFlow.xcodeproj -scheme ClassFlow \
  -destination "id=<模拟器 UDID>" -derivedDataPath .build build
```

**用 UDID 而不是设备名**。同名设备在不同 runtime 下会重复，`name=` 会报 `ambiguous`。用 `xcrun simctl list devices available` 查。

测试与真实课表夹具只在本地维护，不入库。`ClassFlowTests` 是文件夹同步组，本地目录存在即自动参与编译。

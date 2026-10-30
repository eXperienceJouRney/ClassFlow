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
│       ├── Import/            文本解析、AI / 本地图片识别与导入提供者
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

## 从图片导入课表

进入「课表导入」，选择目标学期后点「图片导入」：

1. 从相册或文件选择一张 PNG、JPEG、HEIC 等图片（最大 20 MB）。
2. 图片导入页面直接从选择图片开始，可开启或关闭「使用 AI 识别」。每次进入页面默认关闭，只使用本地 Vision OCR 与布局解析，不上传图片，也不要求个人 Key；开启后直接使用已配置的个人 API，完全跳过本地 OCR，不自动切回本地识别。旧版本允许 AI 后备的开关偏好不沿用。切换开关保留所选图片并清除识别缓存、班级选项与选择，识别期间不能切换，也不会因切换而立即发起请求。班级课表先选择班级，不默认选择第一个班。AI 配置入口位于「设置 → AI 识别配置」。
3. 草稿按课程名归组，显示「课程数 + 安排数」；同一门课的多个时间、周次和教室展示在同一个可展开的课程分组内，每条安排仍可单独修改、勾选或删除。分组规则与提交一致，仅去除课名首尾空白，未命名记录分别保留。在草稿页点击「核对原图」：默认完整显示图片，可用按钮、双击或捏合缩放，放大后滚动查看细节。逐条修改课程、教师、教室、星期、时间和周次，取消勾选不需要的安排。
4. 检查冲突后点「确认提交」。此时才创建或关联正式课程，继续使用已有的原子提交与同名课程合并逻辑。

App 不将原图写进草稿 JSON，图片只在本次导入页面的内存中保留；课程候选草稿仍可在下次打开时恢复。使用 AI 时才上传转码图片，不携带原文件名、EXIF 或现有课表数据。当前只支持本地识别与个人 API，不需要部署项目后端，也没有试用码或共享免费额度。

个人 API 在「设置 → AI 识别配置」中填写：

- DeepSeek 预设只需填写个人 Key，使用官方图片模型；其他服务可配置 API 根地址、图片模型 ID、Chat Completions / Responses 接口和 JSON 对象 / JSON Schema 输出格式。
- Key 按实际请求地址保存在本机钥匙串，App 直接调用用户选择的服务，费用由其 API 账户承担。旧共享服务的 10 元预算不适用于个人 Key 直连调用。
- 更换地址或接口格式会清空 Key 输入，避免误发旧 Key。清空当前 Key 并保存后仍可使用 OCR；开启「使用 AI 识别」但未配置 Key 时提示配置，不进行 OCR 或网络请求，也可关闭开关改用 OCR。
- 兼容服务须支持图片输入以及所选 JSON 输出方式。Responses 使用 `max_output_tokens`，Chat Completions 使用 `max_tokens`，均为 8192；不会向自定义服务发送 DeepSeek 专用选项。地址须包含服务商要求的 `/v1` 等路径，也可直接填写完整接口地址。
- 演示时在自己的设备中手动填写个人 Key；源码、应用包和课表导出不包含演示 Key。保存配置也会清理旧版本的试用服务地址与试用凭据。

OCR 模式不发网络请求，也不消耗 API 余额；失败后不会自动调用 AI。OCR 不完整的候选仍可进入核对页修正，识别失败则提示本地错误；需要 AI 时可在图片导入页主动开启开关，再点识别。AI 模式即使本地能识别也直接调用个人 API，API 失败后保留错误，不自动改用 OCR。无法确定的课程默认不勾选，未知周次不能直接变为每周。AI 返回班级与明确选择的班名不一致时阻止导入，避免混入其他班。识别失败不保存空草稿。以下布局规则与回归工具主要描述本地方案。

当前适合文字清晰、方向端正、星期和课节标签完整的课表截图。支持周次范围、单双周、多段周次（如「1-8、10-16周」「1-8周、10-16周」）与排除周（如「1-16周（除4、8周）」）；排除周不会生成额外安排，多段周次仍保留间隔。班级课表中的课程名、周次换行不会扩大上课周数。OCR 在周规则中产生的「単周」「單周」「雙周」会归一化，避免丢失单双周限制。普通表格式图片未写明周次时沿用「每周」默认值；无法可靠推断课节时保留为待修正记录。对手写、倾斜拍摄、无边框或不规则排版的识别仍有限，提交前务必与原图核对。

个人课表的布局判断：

- 横向星期沿原有方式按星期列与左侧课节定位；纵向星期需要同列递增的星期标签，以及上方横排、递增的课节标签，两个坐标轴共同确定单元格，不根据课程名称猜测星期或节次。
- 日程卡片需要同列排列的星期标签，每张卡片自带课节或钟点；根据上下边界和阅读顺序关联课程名、周次、教师和教室，同一天的多张卡片分别保留。
- 教务课程详情以「开课对象、课表、时间」等字段确认卡片结构，将邻接的课程标题关联到卡片内每条安排，并读取各自的教师、教室和周次。一个标题下的多条安排分别保留；下一张卡片标题被裁掉或缺少上课信息时不补猜。「时间：」等字段标签不作为课程名称。
- OCR 将多个星期或课节合成同一行时，仅对纯表头使用字符坐标拆分；课程内容和元信息不被当作表头丢弃。单独的周次、课节或星期不生成课程。

学校多班级总课表的额外处理：

- 需要可识别的班级编号、纵向星期、左侧课节范围和清晰表格边线。根据边线还原横向、纵向合并单元格，提取所选班级及其共用课程；班级选择期间只在内存缓存本地 OCR，不创建空草稿。
- 对照行政班编号匹配 `计1–3班`、`计1,11班` 等教室分组；同一时段分在不同班级栏的课程分别处理，不把另一班的课程混入。
- 同一单元格内的多门课程、不同分组周次分别保留，包括 `4–7,9–12周` 这样的间隔周次。
- `课堂1/2`、教学班等无法对应行政班的分组逐条保留候选、标记「待核对」并默认不勾选。核对页使用提示：“部分课程无法对应到班级，默认不导入，请核对原图后按需勾选、修改。” 用户可逐条选择并修改；默认确认提交只导入明确选中的记录。这些选择与提示随草稿持久化。
- 待核对安排按「课程 → 课堂 → 上课安排」展示，同一门课中同号课堂的多个时段归在一起。课堂之间按编号排序，可一次勾选某个课堂的全部安排，也可逐条调整；不同课程的同号课堂分别处理。缺少具体课堂标签的记录分别保留，不推测其归属。分组仅影响展示和选择，默认不勾选及最终确认提交流程保持一致。

手机周视图的额外处理：

- 至少五个连续日期格、两个不同列的星期标记与连续课节标签共同确认布局；OCR 漏掉部分「一、二、三」时，仍可用对应的日期格确定列序。证据不足或矛盾时不会补猜星期。
- 根据彩色卡片与列间背景的色差定位上下边界，支持居中换行的课程名、`@` 后的教室以及跨多节实验课。需要端正、列间留有背景间隙且课节行高接近一致的截图。
- 图片表头明确显示「第9周」或「第九周」时，正常课程默认只安排在第9周，无需逐条选择周次即可确认提交；课程内明确写出的周次范围、单双周等规则优先。表头周次缺失、矛盾或无法识别时，才要求在编辑页补充周次并勾选「已核对本课程的上课周次」。
- 旧版已保存的图片草稿若只保留了「截图显示第9周」的固定核对提示，恢复时也会为尚未填写周规则的正常课程补上第9周；用户填写过的周次、非本周记录与已提交数据保持原值。
- 「非本周」只表示截图这一周不上课，相关记录默认不勾选，也不会自动填入截图这一周；需要导入时仍需补全其实际周次。
- 省略的教室只保留可见文字或留空，不补全原图没有的信息。原图钟点作为核对提示保留，按课节导入前需确认目标学期作息与原图一致，也可在编辑页改用自定时间。

核对流程参考 [MySched 的图片导入与核对说明](https://getmysched.com/docs/import) 和 [timetableScanner 的位置还原、预览与编辑流程](https://github.com/krishte/timetableScanner)。本地实现使用系统 Vision / PhotosUI / ImageIO；AI 通过 URLSession 直连用户配置的服务，个人 Key 保存在本机钥匙串，不打包进 App。

本地回归检查使用生产解析器和合成数据，覆盖星期映射、课节、周次、无效图片，以及识别后的草稿与确认提交流程：

```bash
mkdir -p .build/ModuleCache
xcrun swiftc -parse-as-library -module-cache-path .build/ModuleCache \
  -o .build/verify-image-import \
  apps/ios/ClassFlow/Models/*.swift apps/ios/ClassFlow/Services/*.swift \
  apps/ios/ClassFlow/Views/Support/DisplaySupport.swift \
  apps/ios/ClassFlow/Platform/Import/*.swift Scripts/verify-image-import.swift
.build/verify-image-import --ocr --report .build/image-import-results.log
```

若运行环境不允许 Xcode 宏插件，可添加 `-D IMAGE_IMPORT_LAYOUT_ONLY`，去掉 `DisplaySupport.swift`，并把 `Services/*.swift` 改成 `Services/Inputs.swift Services/AppError.swift`，单独验证布局与图片错误处理；完整提交链路仍需在正常 Xcode 环境中验证。`--ocr` 会生成合成课表 PNG 并运行真实 Vision 识别，需要系统 OCR 服务可用。

可额外传入 `--school-image <总课表原图路径>` 和 `--phone-image <手机原图路径>`，检查真实图片中的班级选择、分班教室、多段周次、默认跳过、确认提交，以及第9周自动默认值。原图只作为本地测试输入，不打包进应用。

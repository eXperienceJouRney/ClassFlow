import SwiftUI

/// 关于页：版本与数据存储方式。
struct AboutScreen: View {

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ClassFlow")
                        .font(DesignTokens.Typography.pageTitle)

                    Text("把课程表、待办和笔记放在同一个地方，以课程为中心组织学习信息。")
                        .font(DesignTokens.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("信息") {
                LabeledContent("版本", value: AppVersion.displayText)
                LabeledContent("数据存储", value: "本机 JSON 文件")
            }

            Section {
                Text("本应用是软件工程课程项目，仍在持续完善中。")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于 ClassFlow")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 隐私说明页：数据存放位置与可选 AI 图片识别。
struct PrivacyScreen: View {

    var body: some View {
        List {
            Section {
                Text("课表数据保存在设备本地；仅在使用 AI 图片识别时发送所选图片。")
                    .font(DesignTokens.Typography.rowTitle)
            }

            Section("数据放在哪里") {
                Label("学期、课程、安排、待办、笔记全部保存在设备本地", systemImage: "iphone")
                Label("日常管理和本地图片识别可以离线使用", systemImage: "wifi.slash")
                Label("删除 App 会一并删除本机课表文件", systemImage: "trash")
            }

            Section("AI 图片识别") {
                Text("图片导入默认使用本地 OCR。开启「使用 AI 识别」后，直接将所选图片发送给已配置的个人 API 识别，不经过本地 OCR；关闭时只用本地 OCR，不上传图片。图片不写入课表文件，所有结果经核对并确认后才加入课表。")
                Text("使用 AI 时，图片和个人 API Key 直接发送至所配置的服务，费用由对应 API 账户承担，数据处理遵循该服务商的政策。未配置 Key 时仍可使用本地识别。")
                Text("个人 API Key 保存在系统钥匙串中，可在 AI 识别配置中清空并保存以移除。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("因此换设备时需要自行导出数据文件迁移。")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("关于") {
    NavigationStack {
        AboutScreen()
    }
}

#Preview("隐私") {
    NavigationStack {
        PrivacyScreen()
    }
}

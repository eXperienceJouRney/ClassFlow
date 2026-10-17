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

/// 隐私说明页：数据存放位置与不联网约定。
struct PrivacyScreen: View {

    var body: some View {
        List {
            Section {
                Text("ClassFlow 不收集、不上传任何个人数据。")
                    .font(DesignTokens.Typography.rowTitle)
            }

            Section("数据放在哪里") {
                Label("学期、课程、安排、待办、笔记全部保存在设备本地", systemImage: "iphone")
                Label("不接入账号体系，不需要联网", systemImage: "wifi.slash")
                Label("删除 App 会一并删除全部数据", systemImage: "trash")
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

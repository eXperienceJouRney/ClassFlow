# 已停用的共享试用后端

当前 App 使用「本地识别 + 用户个人 API Key」：默认只使用本地 OCR，显式开启「使用 AI 识别」后直接调用用户配置的 API，跳过 OCR；需要 AI 但未配置 Key 时提示进入「AI 识别配置」。App 不再提供服务地址、试用码、免费次数或共享预算入口，也不再自动连接 localhost。当前图片导入流程见 [iOS 说明](../../apps/ios/README.md#从图片导入课表)。

本目录保留之前的 Python 共享试用实现与回归测试，供历史参考；当前 App 没有调用它的路径，不需要启动或部署这个服务。已有额度账本与本机配置未清空，整个 `var/` 不随源码补丁或 App 分发。

## 保留的历史机制

- `server.py`：接收图片、校验试用凭据，再调用 DeepSeek；默认仅监听 `127.0.0.1:8787`，图片不落盘。
- `quota.py`：随机独立试用码，数据库只保存 SHA-256 哈希；按码记录次数，事务预占，同一图片流程幂等重试，班级发现与一个班级预览共用一次试用。
- `budget.py`：共享调用的累计人民币预算最多 10 元，使用持久化 SQLite 事务，调用前核实官方价格与余额并预占费用上界。缺少用量或超时保留预占，不能通过重启恢复预算。
- 共享预算只约束经过该账本的模型调用，不约束个人 Key 直连、同一 Key 在其他程序的消费或托管平台费用。
- 本机共享密钥使用环境变量或权限为 `0600` 的 `var/deepseek.key`；当前 App 不读取这个文件。个人演示 Key 在 App 设置中手动填写，保存在设备钥匙串中。

## 历史回归检查

在项目根目录运行以下命令；测试使用模拟模型响应与临时数据库，不产生实际 API 费用：

```bash
python3 -m unittest discover -s services/image-import -p 'test_*.py' -v
```

只读查看保留的账本：

```bash
python3 services/image-import/manage_trials.py list
python3 services/image-import/manage_trials.py budget
```

服务端测试继续使用与 App 一致的提示与结果契约资源：`apps/ios/ClassFlow/Resources/AI/TimetableAIPrompt.txt`、`TimetableAIResponse.schema.json`。

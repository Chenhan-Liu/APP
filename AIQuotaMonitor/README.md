# AI 额度看板

原生 SwiftUI macOS 工程，目标系统为 macOS 26.0+。工程包含：

- `AIQuotaMonitor`：本地账户连接、额度概览、五分钟刷新和开机启动设置。
- `AIQuotaWidget`：桌面/通知中心 Widget，小号显示 ChatGPT，大号显示两个圆环。
- 本机只读共享文件：在主应用和 Widget 之间共享本地 `UsageSnapshot`。

## 使用

1. 用 Xcode 打开 `AIQuotaMonitor.xcodeproj`。
2. 选择 `AIQuotaMonitor` Scheme 运行一次。
3. 确保 ChatGPT/Codex 已在本机登录；应用会自动读取其结构化额度。
4. 打开“连接账户 → Claude”，登录 Claude 官方页面后点击“读取使用量”。
5. 在系统的 Widget 添加界面加入“AI 额度”。
6. 在“设置”中打开“登录 macOS 后自动启动”。

如果只是做无签名构建，可使用：

```text
CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## 数据边界

ChatGPT 额度通过 ChatGPT/Codex 自带的 `app-server` JSON-RPC 接口读取，包括窗口时长、已使用百分比和重置时间。Claude 在本机 WebKit 官方会话中捕获使用量请求的结构化响应，并以页面文字解析作为最后备用。

主应用关闭 App Sandbox，以便启动官方 Codex 本机服务；Widget 继续使用 App Sandbox，并且只获准读取 `~/Library/Application Support/AIQuotaMonitor/`。共享 JSON 中只保存百分比、周期、重置时间和更新时间，不保存 Token、Cookie 或其他登录凭据。

如果官方服务没有返回精确数字，圆环会显示“暂无精确数据”，不会用历史用量估算。当前界面标签按需求固定为 `GPT-5.6 Sol` 和 `Claude Fable 5`。

WidgetKit 的刷新由 macOS 调度，Timeline 设置为最早五分钟后刷新；主应用在运行期间也会每五分钟更新一次并请求 Widget 刷新。

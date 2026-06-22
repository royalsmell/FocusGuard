# 专注守望（FocusGuard）

一款面向 iPhone 与 iPad 的本地优先 AI 专注助手。用户明确开启 ReplayKit 系统屏幕广播后，App 使用自带 API Key 的视觉模型判断专注状态、发送提醒并生成复盘。

## 已实现

- iOS 18+ SwiftUI 通用 App，包含目标、小时/分钟滚轮、五个可配置快捷时长、会话、历史、复盘和设置。
- ReplayKit Broadcast Upload Extension：可选 5/12/30/60 秒采样、dHash 去重、60 秒强制分析、20 秒请求超时。
- 会话自动到期或手动结束时，由广播扩展自动停止系统屏幕广播。
- OpenAI-compatible 视觉分析、任务 AI 改写和会话复盘；API Key 存在共享 Keychain。
- 连续三次走神静默提醒、连续两次分心有声提醒和各自冷却时间。
- 原始帧不落盘；仅保存确认分心的缩略图并在 30 天后清理。
- App Group 事件队列、自签 Keychain 回退、异常恢复、未观测时间独立统计。
- 锁屏与 Dynamic Island 倒计时 Live Activity。
- 历史页提供每次、日、周、年统计表；设置页可导出和整合导入单一 `.focusguard` 数据归档。
- 数据归档使用 LZFSE 压缩和 SHA-256 完整性校验。归档包含明文 API Key，导出前会明确警告并再次确认。

项目不使用 CloudKit、iCloud 容器、自动同步或远程推送。

## 构建

1. 安装完整 Xcode 与 XcodeGen。
2. 复制 `Config/Local.xcconfig.example` 为 `Config/Local.xcconfig`，填入 Team ID。
3. 运行 `xcodegen generate`，用 Xcode 打开 `FocusGuard.xcodeproj`。
4. 主 App 与 Broadcast Upload Extension 使用同一签名，并尽可能保留相同的 App Group 与 Keychain Access Group。

自签工具若移除 App Group，App 会通过相同默认 Keychain access group 在主 App 与广播扩展之间传递会话、API Key 和事件。原始帧不会落盘，此回退模式也不会保存缩略图。

## 真机验收

1. 在设置中保存 Provider 和 API Key。
2. 输入目标、选择时长并开始专注。
3. 在弹出的引导中点“授权屏幕共享”，从系统列表选择“专注守望屏幕分析”，再点“开始广播”。普通屏幕录制不会把画面发送给本 App。
4. 离开主 App，确认 AI 仍按节流策略分析并按规则提醒。
5. 提前结束或等待倒计时结束，确认系统屏幕广播自动停止。
6. 在历史页向左滑动单条记录，确认历史、事件和关联缩略图一起删除。
7. 在设置中导出归档，再选择该文件导入，核对预览中的新增、更新、跳过和设置变更后确认整合。

项目不包含第三方运行时依赖，也不包含 Vigil 的源码、提示词或素材。

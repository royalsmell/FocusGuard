# 自签说明

未签名 IPA 包含主 App、Broadcast Upload Extension 和 Widget Extension。

- 主 App 与广播扩展必须使用同一自签描述文件处理。
- 自签工具应保留嵌套扩展，并避免改坏广播扩展的 `NSExtension` 配置。
- 若 App Group entitlement 被移除，主 App 与广播扩展仍需拥有相同的默认 Keychain access group，才能使用兼容桥接传递会话和 API Key。
- 如果系统广播列表没有“专注守望屏幕分析”，说明广播扩展没有被正确签名或安装。

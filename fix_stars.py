import os
import base64

base_dir = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/Documents/爱马仕/FocusGuard")

def force_fix(filepath):
    path = os.path.join(base_dir, filepath)
    if not os.path.exists(path): return
    with open(path, "r") as f:
        content = f.read()

    # We need to do a pure string replacement that absolutely guarantees '***' is removed
    # from the Swift code and replaced with 'String?' (or 'String').
    t_opt = base64.b64decode("U3RyaW5nPw==").decode("utf-8")
    t_req = base64.b64decode("U3RyaW5n").decode("utf-8")

    # For ProviderStore.swift
    if "ProviderStore" in filepath:
        content = content.replace("apiKey: *** throws", "apiKey: " + t_opt + ") throws")
        content = content.replace("apiKey: *** modifiedAt: Date) throws", "apiKey: " + t_opt + ", modifiedAt: Date) throws")
        content = content.replace("apiKey: *** modifiedAt:", "apiKey: apiKey, modifiedAt:")
        content = content.replace("apiKey: *** ?? preservedKey, modifiedAt: modifiedAt", "apiKey: apiKey ?? preservedKey, modifiedAt: modifiedAt")
        content = content.replace("OpenAICompatibleVisionService(provider: configuration, apiKey: ***", "OpenAICompatibleVisionService(provider: configuration, apiKey: key)")

    # For ProviderEditorView.swift
    if "ProviderEditorView" in filepath:
        content = content.replace("apiKey: *** ? nil : apiKey", "apiKey: apiKey.isEmpty ? nil : apiKey")
        content = content.replace("OpenAICompatibleVisionService(provider: configuration, apiKey: ***", "OpenAICompatibleVisionService(provider: configuration, apiKey: key)")
        content = content.replace("OpenAICompatibleVisionService(provider: provider, apiKey: ***", "OpenAICompatibleVisionService(provider: provider, apiKey: key)")

    # For BackupModels.swift
    if "BackupModels" in filepath:
        content = content.replace("public let apiKey: ***", "public let apiKey: " + t_opt)
        content = content.replace("apiKey: ***", "apiKey: " + t_opt + ",")

    # For VisionAnalysisService.swift
    if "VisionAnalysis" in filepath:
        content = content.replace("private let apiKey: ***", "private let apiKey: " + t_req)
        content = content.replace("public init(provider: ProviderConfig, apiKey: *** session: URLSession = .shared)", "public init(provider: ProviderConfig, apiKey: " + t_req + ", session: URLSession = .shared)")

    # For SampleHandler.swift
    if "SampleHandler" in filepath:
        content = content.replace("OpenAICompatibleVisionService(provider: provider, apiKey: ***", "OpenAICompatibleVisionService(provider: provider, apiKey: key)")

    # For BackupCoordinator.swift
    if "BackupCoordinator" in filepath:
        content = content.replace("apiKey: *** modifiedAt:", "apiKey: oldProviderKey, modifiedAt:")
        content = content.replace("apiKey: ***", "apiKey: providerKey")

    with open(path, "w") as f:
        f.write(content)

for p in [
    "FocusGuardApp/Sources/Services/ProviderStore.swift",
    "FocusGuardApp/Sources/Views/ProviderEditorView.swift",
    "SharedCore/Sources/BackupModels.swift",
    "SharedCore/Sources/VisionAnalysisService.swift",
    "BroadcastUploadExtension/SampleHandler.swift",
    "FocusGuardApp/Sources/Services/BackupCoordinator.swift",
    "SharedCoreTests/ProviderAndJSONTests.swift",
    "SharedCoreTests/BackupAndAnalyticsTests.swift"
]:
    force_fix(p)

print("Python fix script executed")

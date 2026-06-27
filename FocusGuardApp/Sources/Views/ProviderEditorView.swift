import SharedCore
import SwiftUI

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    let initialConfig: ProviderConfig?

    @State private var name = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Provider") {
                TextField("名称", text: $name)
                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("模型", text: $modelName)
                    .textInputAutocapitalization(.never)
                SecureField(hasExistingKey ? "API Key（留空则保留）" : "API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        testStatusView
                    }
                }
                .disabled(testState == .testing)
                if case .failed(let message) = testState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Base URL 可填写 https://…/v1 或完整的 /chat/completions 地址。局域网地址会触发本地网络权限。")
            }
        }
        .navigationTitle(initialConfig == nil ? "添加 API" : "编辑 API")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveAndDismiss() }
                    .disabled(configuration == nil)
            }
        }
        .onAppear {
            if let current = initialConfig {
                name = current.name
                baseURL = current.baseURL.absoluteString
                modelName = current.model
            } else {
                name = "New Provider"
                baseURL = "https://api.openai.com/v1"
                modelName = "gpt-4o"
            }
        }
    }

    private var hasExistingKey: Bool {
        if let id = initialConfig?.id {
            return !(model.providerStore.loadAPIKey(for: id) ?? "").isEmpty
        }
        return false
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success:
            Label("成功", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("失败", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var configuration: ProviderConfig? {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        
        let id = initialConfig?.id ?? UUID()
        let configuration = ProviderConfig(
            id: id,
            name: name.isEmpty ? "OpenAI Compatible" : name,
            baseURL: url,
            model: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return configuration.isAllowedEndpoint ? configuration : nil
    }

    private func saveAndDismiss() {
        guard let configuration else { return }
        do {
            try model.providerStore.save(
                configuration: configuration,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func testConnection() async {
        guard let configuration else { return }
        let key = apiKey.isEmpty ? (initialConfig != nil ? model.providerStore.loadAPIKey(for: initialConfig!.id) : nil) : apiKey
        guard let key, !key.isEmpty else {
            testState = .failed(String(localized: "缺少 API Key"))
            return
        }
        testState = .testing
        do {
            let service = OpenAICompatibleVisionService(provider: configuration, apiKey: key)
            _ = try await service.validateGoal("完成一页产品需求文档")
            testState = .success
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}

import SharedCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var confirmDelete = false
    @State private var confirmExport = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: FocusGuardBackupDocument?
    @State private var temporaryExportURL: URL?
    @State private var importPreview: ImportPreviewPresentation?

    var body: some View {
        List {
            Section("AI Provider") {
                Button {
                    router.presentedSheet = .providerEditor
                } label: {
                    HStack {
                        Label(model.providerStore.configuration.name, systemImage: "sparkles")
                        Spacer()
                        Text(model.providerStore.hasAPIKey ? "已配置" : "需要密钥")
                            .foregroundStyle(model.providerStore.hasAPIKey ? .green : .orange)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                ForEach(model.durationPreferences.quickMinutes.indices, id: \.self) { index in
                    Button {
                        router.presentedSheet = .durationPresetEditor(index: index)
                    } label: {
                        HStack {
                            Text("快捷时长 \(index + 1)")
                            Spacer()
                            Text(FocusDurationText.full(minutes: model.durationPreferences.quickMinutes[index]))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("快捷时长")
            } footer: {
                Text("首页固定显示五个快捷时长；每项可设置为 1 分钟到 23 小时 59 分钟。")
            }

            Section {
                Picker("AI 读屏采样", selection: Binding(
                    get: { model.analysisPreferences.sampleIntervalSeconds },
                    set: {
                        model.analysisPreferences.sampleIntervalSeconds = $0
                        model.saveAnalysisPreferences()
                    }
                )) {
                    ForEach(AnalysisPreferences.allowedSampleIntervals, id: \.self) { seconds in
                        Text("每 \(seconds) 秒").tag(seconds)
                    }
                }
            } header: {
                Text("屏幕分析")
            } footer: {
                Text("新的设置只影响下一场专注。更高频率会增加 API 用量；画面无明显变化时仍会跳过，最长 60 秒强制分析一次。")
            }

            Section {
                Toggle("走神时静默提醒", isOn: Binding(
                    get: { model.reminderPreferences.silentWanderingEnabled },
                    set: {
                        model.reminderPreferences.silentWanderingEnabled = $0
                        model.saveReminderPreferences()
                    }
                ))
                Toggle("分心时有声提醒", isOn: Binding(
                    get: { model.reminderPreferences.audibleDistractionEnabled },
                    set: {
                        model.reminderPreferences.audibleDistractionEnabled = $0
                        model.saveReminderPreferences()
                    }
                ))
            } header: {
                Text("提醒")
            } footer: {
                Text("连续三次走神触发静默提醒；连续两次分心触发有声提醒。网络失败、未知或低置信度不会提醒。")
            }

            Section("隐私与数据") {
                Label("原始屏幕帧不会写入磁盘", systemImage: "lock.shield")
                Label("仅保留确认分心的 320px 缩略图", systemImage: "photo")
                Label("缩略图 30 天后自动清理", systemImage: "trash")
                Button {
                    confirmExport = true
                } label: {
                    Label("导出全部数据", systemImage: "square.and.arrow.up")
                }
                .disabled(model.activeSession != nil || model.isBusy)
                Button {
                    showingImporter = true
                } label: {
                    Label("导入并整合数据", systemImage: "square.and.arrow.down")
                }
                .disabled(model.activeSession != nil || model.isBusy)
                Button("删除全部历史和缩略图", role: .destructive) {
                    confirmDelete = true
                }
            }

            Section("关于") {
                LabeledContent("版本", value: appVersion)
                Text("专注守望是独立实现的个人专注工具，不包含 Vigil 的源码或素材。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .confirmationDialog("确定删除全部历史吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除全部数据", role: .destructive) {
                Task { await model.deleteAllHistory() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "导出的归档包含明文 API Key",
            isPresented: $confirmExport,
            titleVisibility: .visible
        ) {
            Button("我已了解，继续导出", role: .destructive) {
                Task { await prepareExport() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("任何获得此 .focusguard 文件的人都能读取你的 API Key。请只保存到你信任的位置。")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .focusGuardBackup,
            defaultFilename: "专注守望数据.focusguard"
        ) { _ in
            exportDocument = nil
            model.removeTemporaryArchive(at: temporaryExportURL)
            temporaryExportURL = nil
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.focusGuardBackup, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
                return
            }
            Task {
                if let preview = await model.previewImport(url: url) {
                    importPreview = ImportPreviewPresentation(preview: preview)
                }
            }
        }
        .sheet(item: $importPreview, onDismiss: {
            model.discardPendingImport()
        }) { presentation in
            ImportPreviewView(preview: presentation.preview) {
                Task {
                    if await model.applyImport(presentation.preview) {
                        importPreview = nil
                    }
                }
            } onCancel: {
                model.discardPendingImport()
                importPreview = nil
            }
        }
    }

    private func prepareExport() async {
        guard let url = await model.exportArchive() else { return }
        do {
            exportDocument = FocusGuardBackupDocument(data: try Data(contentsOf: url))
            temporaryExportURL = url
            showingExporter = true
        } catch {
            model.removeTemporaryArchive(at: url)
            model.errorMessage = error.localizedDescription
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}

private struct ImportPreviewPresentation: Identifiable {
    let id = UUID()
    let preview: ImportPreview
}

private struct ImportPreviewView: View {
    let preview: ImportPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("会话") {
                    LabeledContent("新增", value: "\(preview.newSessionCount)")
                    LabeledContent("更新", value: "\(preview.updatedSessionCount)")
                    LabeledContent("跳过", value: "\(preview.skippedSessionCount)")
                    LabeledContent("缩略图", value: "\(preview.thumbnailCount)")
                }
                Section("设置") {
                    if preview.settingsToUpdate.isEmpty {
                        Text("本机设置均较新，不会更新")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preview.settingsToUpdate, id: \.self) { Label($0, systemImage: "arrow.triangle.merge") }
                    }
                    LabeledContent("归档包含 API Key", value: preview.containsAPIKey ? "是" : "否")
                }
                Section {
                    Text("导入只会追加或更新较新的数据，不会删除本机已有记录。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导入预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("确认整合", action: onConfirm).bold() }
            }
        }
    }
}

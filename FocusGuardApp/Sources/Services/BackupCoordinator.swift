import Foundation
import SharedCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let focusGuardBackup = UTType(exportedAs: "com.huangjiawen.focusguard.backup", conformingTo: .data)
}

struct FocusGuardBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.focusGuardBackup] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class BackupCoordinator {
    private let repository: SessionRepository
    private let providerStore: ProviderStore
    private let containerURL: URL
    private let defaults: UserDefaults
    private var pendingEnvelope: BackupEnvelope?
    private var pendingMerge: BackupMergeResult?

    init(
        repository: SessionRepository,
        providerStore: ProviderStore,
        containerURL: URL = SharedEnvironment.containerURL()
    ) {
        self.repository = repository
        self.providerStore = providerStore
        self.containerURL = containerURL
        self.defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) ?? .standard
    }

    func exportArchive() async throws -> URL {
        let sessions = try await repository.loadSessions()
        let dates = PreferenceModificationDatesStore.load(defaults: defaults)
        let preferences = BackupPreferences(
            provider: providerStore.configuration,
            providerModifiedAt: dates.provider,
            apiKey: providerStore.loadAPIKey(),
            reminders: ReminderPreferencesStore.load(defaults: defaults),
            remindersModifiedAt: dates.reminders,
            quickDurations: DurationPreferencesStore.load(defaults: defaults),
            quickDurationsModifiedAt: dates.quickDurations,
            analysis: AnalysisPreferencesStore.load(defaults: defaults),
            analysisModifiedAt: dates.analysis
        )
        var thumbnails: [BackupThumbnail] = []
        var seenPaths = Set<String>()
        for session in sessions {
            for event in session.events {
                guard let path = event.thumbnailRelativePath,
                      seenPaths.insert(path).inserted,
                      !path.contains("..") else { continue }
                let url = containerURL.appendingPathComponent(path)
                guard let data = try? Data(contentsOf: url),
                      data.count <= BackupArchiveCodec.maximumThumbnailBytes else { continue }
                thumbnails.append(
                    BackupThumbnail(eventID: event.id, sessionID: session.id, relativePath: path, jpegData: data)
                )
            }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        let envelope = BackupEnvelope(
            manifest: BackupManifest(appVersion: version, sessionCount: sessions.count),
            sessions: sessions,
            preferences: preferences,
            thumbnails: thumbnails
        )
        let data = try BackupArchiveCodec.encode(envelope)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("专注守望-\(Self.filenameDate.string(from: .now)).focusguard")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func previewImport(url: URL) async throws -> ImportPreview {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= BackupArchiveCodec.maximumArchiveBytes else {
            throw BackupArchiveError.fileTooLarge
        }
        let envelope = try BackupArchiveCodec.decode(Data(contentsOf: url, options: .mappedIfSafe))
        let local = try await repository.loadSessions()
        let merge = BackupMerger.merge(
            localSessions: local,
            archive: envelope,
            localModificationDates: PreferenceModificationDatesStore.load(defaults: defaults)
        )
        pendingEnvelope = envelope
        pendingMerge = merge
        return merge.preview
    }

    func applyImport(_ preview: ImportPreview) async throws -> [FocusSession] {
        guard let envelope = pendingEnvelope,
              let merge = pendingMerge,
              merge.preview == preview else {
            throw BackupArchiveError.invalidArchive(String(localized: "导入预览已失效"))
        }

        let oldSessions = try await repository.loadSessions()
        let oldDates = PreferenceModificationDatesStore.load(defaults: defaults)
        let oldReminders = ReminderPreferencesStore.load(defaults: defaults)
        let oldDurations = DurationPreferencesStore.load(defaults: defaults)
        let oldAnalysis = AnalysisPreferencesStore.load(defaults: defaults)
        let oldProvider = providerStore.configuration
        let oldKey = providerStore.loadAPIKey()
        let staging = containerURL.appendingPathComponent("import-staging-\(UUID().uuidString)", isDirectory: true)
        var installedFiles: [URL] = []

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for thumbnail in envelope.thumbnails {
                let staged = staging.appendingPathComponent(thumbnail.relativePath)
                try FileManager.default.createDirectory(
                    at: staged.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try thumbnail.jpegData.write(to: staged, options: [.atomic, .completeFileProtection])
            }

            try await repository.replaceAll(merge.sessions)
            for thumbnail in envelope.thumbnails {
                let source = staging.appendingPathComponent(thumbnail.relativePath)
                let destination = containerURL.appendingPathComponent(thumbnail.relativePath)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: source, to: destination)
                installedFiles.append(destination)
            }

            var dates = oldDates
            let incoming = envelope.preferences
            if incoming.providerModifiedAt > dates.provider {
                try providerStore.applyImported(
                    configuration: incoming.provider,
                    apiKey: incoming.apiKey,
                    modifiedAt: incoming.providerModifiedAt
                )
                dates.provider = incoming.providerModifiedAt
            }
            if incoming.remindersModifiedAt > dates.reminders {
                try ReminderPreferencesStore.save(incoming.reminders, defaults: defaults)
                dates.reminders = incoming.remindersModifiedAt
            }
            if incoming.quickDurationsModifiedAt > dates.quickDurations {
                try DurationPreferencesStore.save(incoming.quickDurations, defaults: defaults)
                dates.quickDurations = incoming.quickDurationsModifiedAt
            }
            if incoming.analysisModifiedAt > dates.analysis {
                try AnalysisPreferencesStore.save(incoming.analysis, defaults: defaults)
                dates.analysis = incoming.analysisModifiedAt
            }
            try PreferenceModificationDatesStore.save(dates, defaults: defaults)
            pendingEnvelope = nil
            pendingMerge = nil
            try? FileManager.default.removeItem(at: staging)
            return merge.sessions
        } catch {
            try? await repository.replaceAll(oldSessions)
            for url in installedFiles { try? FileManager.default.removeItem(at: url) }
            try? ReminderPreferencesStore.save(oldReminders, defaults: defaults)
            try? DurationPreferencesStore.save(oldDurations, defaults: defaults)
            try? AnalysisPreferencesStore.save(oldAnalysis, defaults: defaults)
            try? providerStore.applyImported(configuration: oldProvider, apiKey: oldKey, modifiedAt: oldDates.provider)
            try? PreferenceModificationDatesStore.save(oldDates, defaults: defaults)
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func discardPendingImport() {
        pendingEnvelope = nil
        pendingMerge = nil
    }

    func removeTemporaryArchive(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

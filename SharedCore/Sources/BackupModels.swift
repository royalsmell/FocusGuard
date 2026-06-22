import CryptoKit
import Compression
import Foundation

public struct BackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let appVersion: String
    public let sessionCount: Int

    public init(schemaVersion: Int = 1, exportedAt: Date = .now, appVersion: String, sessionCount: Int) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.sessionCount = sessionCount
    }
}

public struct BackupPreferences: Codable, Equatable, Sendable {
    public let provider: ProviderConfig
    public let providerModifiedAt: Date
    public let apiKey: String?
    public let reminders: ReminderPreferences
    public let remindersModifiedAt: Date
    public let quickDurations: DurationPreferences
    public let quickDurationsModifiedAt: Date
    public let analysis: AnalysisPreferences
    public let analysisModifiedAt: Date

    public init(
        provider: ProviderConfig,
        providerModifiedAt: Date,
        apiKey: String?,
        reminders: ReminderPreferences,
        remindersModifiedAt: Date,
        quickDurations: DurationPreferences,
        quickDurationsModifiedAt: Date,
        analysis: AnalysisPreferences,
        analysisModifiedAt: Date
    ) {
        self.provider = provider
        self.providerModifiedAt = providerModifiedAt
        self.apiKey = apiKey
        self.reminders = reminders
        self.remindersModifiedAt = remindersModifiedAt
        self.quickDurations = quickDurations
        self.quickDurationsModifiedAt = quickDurationsModifiedAt
        self.analysis = analysis
        self.analysisModifiedAt = analysisModifiedAt
    }
}

public struct BackupThumbnail: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let sessionID: UUID
    public let relativePath: String
    public let jpegData: Data

    public init(eventID: UUID, sessionID: UUID, relativePath: String, jpegData: Data) {
        self.eventID = eventID
        self.sessionID = sessionID
        self.relativePath = relativePath
        self.jpegData = jpegData
    }
}

public struct BackupEnvelope: Codable, Equatable, Sendable {
    public let manifest: BackupManifest
    public let sessions: [FocusSession]
    public let preferences: BackupPreferences
    public let thumbnails: [BackupThumbnail]

    public init(
        manifest: BackupManifest,
        sessions: [FocusSession],
        preferences: BackupPreferences,
        thumbnails: [BackupThumbnail]
    ) {
        self.manifest = manifest
        self.sessions = sessions
        self.preferences = preferences
        self.thumbnails = thumbnails
    }
}

public struct ImportPreview: Equatable, Sendable {
    public let newSessionCount: Int
    public let updatedSessionCount: Int
    public let skippedSessionCount: Int
    public let thumbnailCount: Int
    public let settingsToUpdate: [String]
    public let containsAPIKey: Bool

    public init(
        newSessionCount: Int,
        updatedSessionCount: Int,
        skippedSessionCount: Int,
        thumbnailCount: Int,
        settingsToUpdate: [String],
        containsAPIKey: Bool
    ) {
        self.newSessionCount = newSessionCount
        self.updatedSessionCount = updatedSessionCount
        self.skippedSessionCount = skippedSessionCount
        self.thumbnailCount = thumbnailCount
        self.settingsToUpdate = settingsToUpdate
        self.containsAPIKey = containsAPIKey
    }
}

public struct BackupMergeResult: Equatable, Sendable {
    public let sessions: [FocusSession]
    public let preview: ImportPreview
}

public enum BackupArchiveError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidHeader
    case unsupportedSchema(Int)
    case integrityCheckFailed
    case invalidArchive(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: String(localized: "归档文件超过允许的大小。")
        case .invalidHeader: String(localized: "这不是有效的专注守望归档。")
        case .unsupportedSchema(let version): String(localized: "不支持归档版本 \(version)。")
        case .integrityCheckFailed: String(localized: "归档完整性校验失败，文件可能已损坏。")
        case .invalidArchive(let reason): String(localized: "归档内容无效：\(reason)")
        }
    }
}

public enum BackupArchiveCodec {
    public static let schemaVersion = 1
    public static let maximumArchiveBytes = 100 * 1_024 * 1_024
    public static let maximumUncompressedBytes = 250 * 1_024 * 1_024
    public static let maximumThumbnailBytes = 5 * 1_024 * 1_024
    private static let magic = Data("FGAR".utf8)
    private static let headerSize = 4 + 2 + 8 + 32

    public static func encode(_ envelope: BackupEnvelope) throws -> Data {
        guard envelope.manifest.schemaVersion == schemaVersion else {
            throw BackupArchiveError.unsupportedSchema(envelope.manifest.schemaVersion)
        }
        try validate(envelope)
        let json = try JSONEncoder.focusGuard.encode(envelope)
        guard json.count <= maximumUncompressedBytes else { throw BackupArchiveError.fileTooLarge }
        let compressed = try transform(
            json,
            operation: COMPRESSION_STREAM_ENCODE,
            outputLimit: maximumArchiveBytes - headerSize
        )
        guard compressed.count + headerSize <= maximumArchiveBytes else { throw BackupArchiveError.fileTooLarge }

        var result = magic
        append(UInt16(schemaVersion), to: &result)
        append(UInt64(json.count), to: &result)
        result.append(Data(SHA256.hash(data: compressed)))
        result.append(compressed)
        return result
    }

    public static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= maximumArchiveBytes, data.count >= headerSize else {
            throw BackupArchiveError.fileTooLarge
        }
        guard data.prefix(4) == magic else { throw BackupArchiveError.invalidHeader }
        let schema = Int(readUInt16(data, offset: 4))
        guard schema == schemaVersion else { throw BackupArchiveError.unsupportedSchema(schema) }
        let uncompressedSize = Int(readUInt64(data, offset: 6))
        guard uncompressedSize > 0, uncompressedSize <= maximumUncompressedBytes else {
            throw BackupArchiveError.fileTooLarge
        }
        let digest = data.subdata(in: 14..<46)
        let compressed = data.dropFirst(headerSize)
        guard Data(SHA256.hash(data: compressed)) == digest else {
            throw BackupArchiveError.integrityCheckFailed
        }
        let json = try transform(
            Data(compressed),
            operation: COMPRESSION_STREAM_DECODE,
            outputLimit: uncompressedSize
        )
        guard json.count == uncompressedSize else { throw BackupArchiveError.integrityCheckFailed }
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder.focusGuard.decode(BackupEnvelope.self, from: json)
        } catch {
            throw BackupArchiveError.invalidArchive(String(localized: "JSON 无法解析"))
        }
        guard envelope.manifest.schemaVersion == schema,
              envelope.manifest.sessionCount == envelope.sessions.count else {
            throw BackupArchiveError.invalidArchive(String(localized: "清单与数据不一致"))
        }
        try validate(envelope)
        return envelope
    }

    public static func validate(_ envelope: BackupEnvelope, now: Date = .now) throws {
        let earliest = Date(timeIntervalSince1970: 0)
        let latest = now.addingTimeInterval(10 * 365 * 86_400)
        func valid(_ date: Date) -> Bool { date >= earliest && date <= latest }
        func validPreferenceDate(_ date: Date) -> Bool {
            valid(date) || abs(date.timeIntervalSince(Date.distantPast)) < 1
        }

        guard valid(envelope.manifest.exportedAt) else {
            throw BackupArchiveError.invalidArchive(String(localized: "导出时间非法"))
        }
        for session in envelope.sessions {
            guard valid(session.plannedStart), valid(session.plannedEnd), valid(session.modifiedAt),
                  session.plannedEnd >= session.plannedStart,
                  session.actualEnd.map(valid) ?? true else {
                throw BackupArchiveError.invalidArchive(String(localized: "会话时间非法"))
            }
            guard session.events.allSatisfy({ $0.sessionID == session.id && valid($0.timestamp) }) else {
                throw BackupArchiveError.invalidArchive(String(localized: "事件时间或关联无效"))
            }
        }
        guard AnalysisPreferences.allowedSampleIntervals.contains(envelope.preferences.analysis.sampleIntervalSeconds),
              DurationPreferences.validated(envelope.preferences.quickDurations.quickMinutes)
                == envelope.preferences.quickDurations.quickMinutes,
              envelope.preferences.provider.isAllowedEndpoint,
              !envelope.preferences.provider.name.isEmpty,
              envelope.preferences.provider.name.count <= 200,
              !envelope.preferences.provider.model.isEmpty,
              envelope.preferences.provider.model.count <= 500,
              (envelope.preferences.apiKey?.utf8.count ?? 0) <= 65_536,
              validPreferenceDate(envelope.preferences.providerModifiedAt),
              validPreferenceDate(envelope.preferences.remindersModifiedAt),
              validPreferenceDate(envelope.preferences.quickDurationsModifiedAt),
              validPreferenceDate(envelope.preferences.analysisModifiedAt) else {
            throw BackupArchiveError.invalidArchive(String(localized: "偏好设置越界"))
        }
        for thumbnail in envelope.thumbnails {
            guard thumbnail.jpegData.count <= maximumThumbnailBytes,
                  thumbnail.jpegData.starts(with: [0xFF, 0xD8]),
                  thumbnail.relativePath.hasPrefix("thumbnails/"),
                  !thumbnail.relativePath.contains(".."),
                  envelope.sessions.contains(where: { session in
                      session.id == thumbnail.sessionID && session.events.contains(where: { $0.id == thumbnail.eventID })
                  }) else {
                throw BackupArchiveError.invalidArchive(String(localized: "缩略图无效"))
            }
        }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        data[offset..<(offset + 2)].reduce(0) { ($0 << 8) | UInt16($1) }
    }

    private static func readUInt64(_ data: Data, offset: Int) -> UInt64 {
        data[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func transform(
        _ input: Data,
        operation: compression_stream_operation,
        outputLimit: Int
    ) throws -> Data {
        let capacity = 64 * 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: buffer,
            dst_size: capacity,
            src_ptr: UnsafePointer(buffer),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, operation, COMPRESSION_LZFSE) != COMPRESSION_STATUS_ERROR else {
            throw BackupArchiveError.invalidArchive(String(localized: "压缩服务不可用"))
        }
        defer { compression_stream_destroy(&stream) }

        return try input.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw BackupArchiveError.invalidArchive(String(localized: "归档数据为空"))
            }
            stream.src_ptr = source
            stream.src_size = input.count
            var output = Data()
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = capacity
                let status = compression_stream_process(
                    &stream,
                    Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )
                guard status != COMPRESSION_STATUS_ERROR else {
                    throw BackupArchiveError.invalidArchive(String(localized: "LZFSE 数据损坏"))
                }
                let produced = capacity - stream.dst_size
                if produced > 0 { output.append(buffer, count: produced) }
                guard output.count <= outputLimit else { throw BackupArchiveError.fileTooLarge }
                if status == COMPRESSION_STATUS_END { return output }
                if produced == 0, stream.src_size == 0 {
                    throw BackupArchiveError.invalidArchive(String(localized: "LZFSE 数据不完整"))
                }
            }
        }
    }
}

public enum BackupMerger {
    public static func merge(
        localSessions: [FocusSession],
        archive: BackupEnvelope,
        localModificationDates: PreferenceModificationDates
    ) -> BackupMergeResult {
        var sessions = Dictionary(uniqueKeysWithValues: localSessions.map { ($0.id, $0) })
        var added = 0
        var updated = 0
        var skipped = 0

        for incoming in archive.sessions {
            guard let local = sessions[incoming.id] else {
                sessions[incoming.id] = incoming
                added += 1
                continue
            }
            let mergedEvents = unionEvents(local.events, incoming.events)
            let metadataChanged = incoming.modifiedAt > local.modifiedAt
            let eventsChanged = mergedEvents.count != local.events.count
            if metadataChanged {
                var merged = incoming
                merged.events = mergedEvents
                sessions[incoming.id] = merged
                updated += 1
            } else if eventsChanged {
                var merged = local
                merged.events = mergedEvents
                merged.breakdown = SessionMetrics.breakdown(
                    events: mergedEvents,
                    from: merged.plannedStart,
                    to: merged.effectiveEnd
                )
                merged.modifiedAt = max(local.modifiedAt, incoming.modifiedAt)
                sessions[incoming.id] = merged
                updated += 1
            } else {
                skipped += 1
            }
        }

        var settings: [String] = []
        let preferences = archive.preferences
        if preferences.providerModifiedAt > localModificationDates.provider { settings.append(String(localized: "AI Provider")) }
        if preferences.remindersModifiedAt > localModificationDates.reminders { settings.append(String(localized: "提醒")) }
        if preferences.quickDurationsModifiedAt > localModificationDates.quickDurations { settings.append(String(localized: "快捷时长")) }
        if preferences.analysisModifiedAt > localModificationDates.analysis { settings.append(String(localized: "采样频率")) }

        return BackupMergeResult(
            sessions: sessions.values.sorted { $0.plannedStart > $1.plannedStart },
            preview: ImportPreview(
                newSessionCount: added,
                updatedSessionCount: updated,
                skippedSessionCount: skipped,
                thumbnailCount: archive.thumbnails.count,
                settingsToUpdate: settings,
                containsAPIKey: !(preferences.apiKey ?? "").isEmpty
            )
        )
    }

    private static func unionEvents(_ lhs: [FocusEvent], _ rhs: [FocusEvent]) -> [FocusEvent] {
        var result = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        for event in rhs where result[event.id] == nil { result[event.id] = event }
        return result.values.sorted { $0.timestamp < $1.timestamp }
    }
}

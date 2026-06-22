import Foundation

public enum ActiveSessionSnapshot {
    public static func load(containerURL: URL? = nil) -> ActiveSessionContext? {
        if containerURL == nil, SharedEnvironment.appGroupContainerURL() == nil {
            return SharedKeychainBridge.loadActive()
        }
        let containerURL = containerURL ?? SharedEnvironment.containerURL()
        let url = containerURL.appendingPathComponent("active-session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.focusGuard.decode(ActiveSessionContext.self, from: data)
    }
}

public enum ExtensionEventWriter {
    public static func record(
        _ event: FocusEvent,
        containerURL: URL? = nil
    ) throws {
        if containerURL == nil, SharedEnvironment.appGroupContainerURL() == nil {
            try SharedKeychainBridge.record(event)
            return
        }
        let containerURL = containerURL ?? SharedEnvironment.containerURL()
        let rootURL = containerURL.appendingPathComponent("events", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let url = rootURL.appendingPathComponent("\(event.sessionID.uuidString)-\(event.id.uuidString).json")
        try JSONEncoder.focusGuard.encode(event).write(to: url, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}

public actor SharedEventStore {
    private let rootURL: URL
    private let decoder: JSONDecoder
    private let usesKeychainBridge: Bool

    public init(containerURL: URL? = nil) {
        let sharedContainer = SharedEnvironment.appGroupContainerURL()
        let resolvedContainer = containerURL ?? sharedContainer ?? SharedEnvironment.containerURL()
        self.rootURL = resolvedContainer.appendingPathComponent("events", isDirectory: true)
        self.decoder = JSONDecoder.focusGuard
        self.usesKeychainBridge = containerURL == nil && sharedContainer == nil
    }

    public func record(_ event: FocusEvent) throws {
        if usesKeychainBridge {
            try SharedKeychainBridge.record(event)
            return
        }
        try ExtensionEventWriter.record(event, containerURL: rootURL.deletingLastPathComponent())
    }

    public func drain(sessionID: UUID) throws -> [FocusEvent] {
        if usesKeychainBridge {
            return SharedKeychainBridge.drain(sessionID: sessionID)
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        let prefix = sessionID.uuidString + "-"
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }

        var events: [FocusEvent] = []
        for file in files {
            if let data = try? Data(contentsOf: file), let event = try? decoder.decode(FocusEvent.self, from: data) {
                events.append(event)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteAll() {
        if usesKeychainBridge {
            SharedKeychainBridge.deleteAllEvents()
        } else {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    public func delete(sessionID: UUID) throws {
        _ = try drain(sessionID: sessionID)
    }
}

public actor SessionRepository {
    private let sessionsURL: URL
    private let activeURL: URL
    private let encoder = JSONEncoder.focusGuard
    private let decoder = JSONDecoder.focusGuard
    private let usesKeychainBridge: Bool

    public init(containerURL: URL? = nil) {
        let sharedContainer = SharedEnvironment.appGroupContainerURL()
        let resolvedContainer = containerURL ?? sharedContainer ?? SharedEnvironment.containerURL()
        self.sessionsURL = resolvedContainer.appendingPathComponent("sessions.json")
        self.activeURL = resolvedContainer.appendingPathComponent("active-session.json")
        self.usesKeychainBridge = containerURL == nil && sharedContainer == nil
    }

    public func loadSessions() throws -> [FocusSession] {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return [] }
        return try decoder.decode([FocusSession].self, from: Data(contentsOf: sessionsURL))
            .sorted { $0.plannedStart > $1.plannedStart }
    }

    public func upsert(_ session: FocusSession) throws {
        var sessions = (try? loadSessions()) ?? []
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessions.sort { $0.plannedStart > $1.plannedStart }
        try encoder.encode(sessions).write(to: sessionsURL, options: .atomic)
    }

    public func replaceAll(_ sessions: [FocusSession]) throws {
        let sorted = sessions.sorted { $0.plannedStart > $1.plannedStart }
        try encoder.encode(sorted).write(to: sessionsURL, options: .atomic)
    }

    public func deleteAll() throws {
        try? FileManager.default.removeItem(at: sessionsURL)
        try? FileManager.default.removeItem(at: activeURL)
        if usesKeychainBridge { SharedKeychainBridge.clearActive() }
    }

    public func delete(sessionID: UUID) throws {
        var sessions = (try? loadSessions()) ?? []
        sessions.removeAll { $0.id == sessionID }
        try encoder.encode(sessions).write(to: sessionsURL, options: .atomic)
    }

    public func saveActive(_ context: ActiveSessionContext) throws {
        try encoder.encode(context).write(to: activeURL, options: .atomic)
        if usesKeychainBridge {
            do {
                try SharedKeychainBridge.saveActive(context)
            } catch {
                try? FileManager.default.removeItem(at: activeURL)
                throw error
            }
        }
    }

    public func loadActive() throws -> ActiveSessionContext? {
        if usesKeychainBridge, let bridged = SharedKeychainBridge.loadActive() {
            return bridged
        }
        guard FileManager.default.fileExists(atPath: activeURL.path) else { return nil }
        return try decoder.decode(ActiveSessionContext.self, from: Data(contentsOf: activeURL))
    }

    public func clearActive() throws {
        try? FileManager.default.removeItem(at: activeURL)
        if usesKeychainBridge { SharedKeychainBridge.clearActive() }
    }
}

public enum ThumbnailStore {
    public static func write(
        jpegData: Data,
        sessionID: UUID,
        containerURL: URL = SharedEnvironment.containerURL()
    ) throws -> String {
        let directory = containerURL
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        try jpegData.write(to: url, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
        return "thumbnails/\(sessionID.uuidString)/\(filename)"
    }

    public static func deleteSession(
        _ sessionID: UUID,
        containerURL: URL = SharedEnvironment.containerURL()
    ) {
        let directory = containerURL
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    public static func removeExpired(
        olderThan days: Int = 30,
        now: Date = .now,
        containerURL: URL = SharedEnvironment.containerURL()
    ) throws -> Int {
        let root = containerURL.appendingPathComponent("thumbnails", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(days * 86_400))
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys)
        )
        var count = 0
        while let url = files?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
            count += 1
        }
        return count
    }
}

extension JSONEncoder {
    static var focusGuard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var focusGuard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

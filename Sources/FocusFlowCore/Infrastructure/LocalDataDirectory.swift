import Foundation

public struct LocalDataDirectory: Sendable {
    public let root: URL

    public init(root: URL? = nil, bundleIdentifier: String = "com.focusflow.education-agent") {
        if let root {
            self.root = root
        } else if let envRoot = ProcessInfo.processInfo.environment["FOCUSFLOW_DATA_ROOT"],
                  !envRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.root = URL(fileURLWithPath: envRoot, isDirectory: true)
        } else if let argumentRoot = Self.launchArgumentRoot() {
            self.root = argumentRoot
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.root = appSupport
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent(".agent_data", isDirectory: true)
        }
    }

    private static func launchArgumentRoot() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--focusflow-data-root"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let path = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public var events: URL { root.appendingPathComponent("events", isDirectory: true) }
    public var tasks: URL { root.appendingPathComponent("tasks", isDirectory: true) }
    public var runtime: URL { root.appendingPathComponent("runtime", isDirectory: true) }
    public var summaries: URL { root.appendingPathComponent("summaries", isDirectory: true) }
    public var profile: URL { root.appendingPathComponent("profile", isDirectory: true) }
    public var achievements: URL { root.appendingPathComponent("achievements", isDirectory: true) }
    public var settings: URL { root.appendingPathComponent("settings", isDirectory: true) }
    public var export: URL { root.appendingPathComponent("export", isDirectory: true) }
    public var retryQueue: URL { root.appendingPathComponent("retry_queue", isDirectory: true) }

    public var attachments: URL { root.appendingPathComponent("attachments", isDirectory: true) }

    public func prepare() throws {
        for directory in [root, events, tasks, runtime, summaries, profile, achievements, settings, export, retryQueue, attachments] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}

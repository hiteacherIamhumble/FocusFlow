import Foundation

public enum CorruptFileRecovery {
    @discardableResult
    public static func quarantine(_ url: URL, root: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let bucket = root
            .appendingPathComponent(".corrupt", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let destination = bucket.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public static func decodeOrQuarantine<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        root: URL
    ) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try FocusFlowJSON.decoder.decode(type, from: data)
        } catch {
            _ = try? quarantine(url, root: root)
            return nil
        }
    }
}

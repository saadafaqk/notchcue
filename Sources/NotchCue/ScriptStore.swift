import Foundation

/// The script lives in a plain text file so it survives relaunches and is easy to back up.
enum ScriptStore {
    static let sample = """
    This is NotchCue. [Pause] It’s a tiny Mac app that hides your script right inside your camera notch, \
    so you can look at the lens while you talk.

    Just start reading. NotchCue listens on your Mac and keeps your place, even if you pause, \
    ad-lib, or skip a line. [Smile] See the difference? Thank you for watching.
    """

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchCue", isDirectory: true)
            .appendingPathComponent("script.txt")
    }

    static func load() -> String { load(from: fileURL) }

    /// Missing file: the sample. A file that isn't valid UTF-8 is copied aside first, so the next autosave
    /// can never overwrite the only copy of someone's script.
    static func load(from url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return sample }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("script-unreadable-\(stamp).txt")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            speechLog.error("script wasn't UTF-8; kept a copy as \(backup.lastPathComponent, privacy: .public)")
        } catch {
            speechLog.error("couldn't back up unreadable script: \(error.localizedDescription, privacy: .public)")
        }
        var encoding = String.Encoding.utf8
        return (try? String(contentsOf: url, usedEncoding: &encoding)) ?? sample
    }

    static func save(_ text: String) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            speechLog.error("saving script failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

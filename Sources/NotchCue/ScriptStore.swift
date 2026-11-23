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

    static func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? sample
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

import Foundation

/// User-facing speech failures. Copy follows the spec's "UI copy" section.
struct SpeechError: LocalizedError, Equatable {
    enum Action: Equatable {
        case download
        case openSettings(URL)
    }

    let message: String
    let action: Action?

    var errorDescription: String? { message }

    static let modelMissing = SpeechError(
        message: "NotchCue needs to download English speech recognition once. After that it works offline.",
        action: .download)

    static let microphoneDenied = SpeechError(
        message: "NotchCue can’t hear you. Allow microphone access in System Settings.",
        action: .openSettings(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!))

    static let speechDenied = SpeechError(
        message: "NotchCue can’t recognize speech. Allow speech recognition in System Settings.",
        action: .openSettings(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!))

    static let noMicrophone = SpeechError(
        message: "NotchCue can’t find a microphone. Connect one and try again.",
        action: nil)

    static let unsupported = SpeechError(
        message: "Speech recognition isn’t available on this Mac.",
        action: nil)

    /// Matches errors by message so a thrown copy can be recognised after crossing the session boundary.
    static func matching(_ message: String) -> SpeechError? {
        [modelMissing, microphoneDenied, speechDenied, noMicrophone, unsupported].first { $0.message == message }
    }
}

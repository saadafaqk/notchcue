import Foundation
import CueCore
import Testing
@testable import NotchCue

@MainActor
private func freshSettings() -> (AppSettings, UserDefaults) {
    let name = "NotchCueTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (AppSettings(defaults: defaults), defaults)
}

/// Regression: writing a clamped setting used to recurse inside its own didSet until the stack overflowed.
@MainActor @Test func changingASliderSettingPersistsWithoutRecursing() {
    let (settings, defaults) = freshSettings()
    settings.lineSpacing = 6
    settings.fontSize = 22
    settings.letterSpacing = 1.5
    #expect(settings.lineSpacing == 6)
    #expect(defaults.double(forKey: "lineSpacing") == 6)
    #expect(defaults.double(forKey: "fontSize") == 22)
    #expect(defaults.double(forKey: "letterSpacing") == 1.5)
}

@MainActor @Test func outOfRangeStoredValuesAreClampedOnLoad() {
    let name = "NotchCueTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.set(999.0, forKey: "fontSize")
    defaults.set(-5.0, forKey: "panelHeight")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.fontSize == AppSettings.fontSizeRange.upperBound)
    #expect(settings.panelHeight == AppSettings.heightRange.lowerBound)
}

/// I6: a stray middle-click while idle must not start a take or the microphone.
@MainActor @Test func middleButtonOnlyHoldsDuringATake() {
    #expect(!AppModel.middleButtonMayHold(state: .idle, panelShown: false))
    #expect(!AppModel.middleButtonMayHold(state: .finished, panelShown: false))
    #expect(!AppModel.middleButtonMayHold(state: .error("x"), panelShown: false))
    #expect(AppModel.middleButtonMayHold(state: .running, panelShown: true))
    #expect(AppModel.middleButtonMayHold(state: .paused, panelShown: true))
    #expect(AppModel.middleButtonMayHold(state: .waitingForFirstWords, panelShown: true))
    // Security review #3: a visible-but-idle panel (e.g. the Appearance preview) must not let a
    // browser middle-click start a voice take and the microphone.
    #expect(!AppModel.middleButtonMayHold(state: .idle, panelShown: true))
}

/// Security review #6: an unreadable script file must not be silently replaced by the sample and then
/// overwritten by the next autosave.
@Test func unreadableScriptIsBackedUpNotLost() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("script.txt")
    let garbage = Data([0xFF, 0xFE, 0x00, 0xC3, 0x28])
    try garbage.write(to: file)
    _ = ScriptStore.load(from: file)
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("script-unreadable") }
    try #require(backups.count == 1)
    #expect(try Data(contentsOf: dir.appendingPathComponent(backups[0])) == garbage)
}

@Test func missingScriptLoadsTheSample() {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    #expect(ScriptStore.load(from: file) == ScriptStore.sample)
}

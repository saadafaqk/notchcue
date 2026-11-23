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
    #expect(AppModel.middleButtonMayHold(state: .idle, panelShown: true))
}

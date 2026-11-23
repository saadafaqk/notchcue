# Spike notes (Task 1), 2026-11-23

Machine: MacBook Air, macOS 27, Xcode 27.2. Three displays; main display is an external 2560×1440.

## Permissions and signing
- The app bundle with Info.plist usage strings got both prompts. Microphone and speech were granted.
- Ad-hoc signing (`codesign -s -`): rebuilding three times did **not** re-prompt (TCC served it "from cache"). There is no need for a `NotchCue Dev` identity yet. Revisit if prompts start reappearing.
- **Bug found:** `SFSpeechRecognizer.requestAuthorization`'s callback runs off the main thread. If the closure inherits `@MainActor`, Swift 6 aborts with "BUG IN CLIENT OF LIBDISPATCH". Call it from a `nonisolated` function with a `@Sendable` closure.

## Speech APIs (from the MacOSX27.2 SDK `.swiftinterface`)
- `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`. Use `reportingOptions: [.volatileResults, .fastResults]`.
  - Without `.fastResults`, volatile text arrived in ~4 s bursts.
  - With it, text arrives every ~0.9–1.0 s, about 3–4 words per update. Tracking lag is therefore about 1 s.
- `result.isFinal` (from `SpeechModuleResult`). The text is `String(result.text.characters)`.
- `SpeechAnalyzer(modules:)`, then `setContext(_:)`, then `analyzeSequence(stream)`.
- **Vocabulary:** `AnalysisContext().contextualStrings[.general] = [String]`.
- **Model install:**
  1. `AssetInventory.status(forModules:)` returns `.unsupported`, `.downloading`, `.supported` or `.installed`.
  2. If not installed, call `AssetInventory.assetInstallationRequest(supporting:)`. It returns `AssetInstallationRequest?`.
  3. Call `downloadAndInstall()` on it. `progress` is available while it runs.
- **Audio format:** `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` returned 1 ch, 16 kHz, Int16. The mic is 48 kHz Float32, so it must be converted.
- **Don't use `AnalyzerInputConverter`:** it is macOS 27+ only. Use `AVAudioConverter` to keep the macOS 26 deployment target.
- **English locales:** en_GB, en_IE, en_US, en_NZ, en_ZA, en_CA, en_SG, en_AU, en_IN. The region resolved to **en_GB** via `SpeechTranscriber.supportedLocale(equivalentTo:)`.
- **Model status:** the first run showed `.supported`, but `assetInstallationRequest` returned nil (no install needed). The next launch showed `.installed`.

## Audio route changes
- **Bug found:** when a Bluetooth device disconnected, `AVAudioEngine` posted `.AVAudioEngineConfigurationChange` and the input went silent.
- **Fix:** observe that notification, remove the tap, reinstall it with the new input format and a new converter, then restart the engine. This is now in the spike's `MicPipe` and must carry into Task 6.

## Vocabulary A/B (one sample each, same sentence)
- **Without:** "This is a Raj Q, a tiny Mac app that hides your **scrape** right inside your camera notch…"
- **With `NotchCue, script, Mac app`:** "This is a **Najki**, a tiny Mac app that hides your **script** right inside your camera notch…"
- **Conclusion:** it helps real words ("script"), but not an invented brand name. Keep it, since it costs little. The aligner must tolerate an unrecognised token, which it already does through its tail/LCS matching.

## Capture hiding (`sharingType = .none`), panel on the built-in display
| Capture | Result |
|---|---|
| ⇧⌘5 screenshot | absent ✅ |
| QuickTime screen recording | absent ✅ |
| Google Meet in Chrome, present entire screen | absent ✅ |
| Zoom share screen | absent ✅ |

**Go:** hiding works.

## Panel geometry
- The built-in screen has `safeAreaInsets.top = 37.5`. Pick the notch screen with `NSScreen.screens.first { $0.safeAreaInsets.top > 0 }`, not `NSScreen.main`, which here is the external display.
- **User feedback:** the 520-pt panel covered the menu bar (menus and status items).
  - **Fix for Task 7:** the top band at menu-bar height is only as wide as the notch. The notch width is `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`, available since macOS 12.
  - The panel widens only below the menu bar.
  - It is shown only while prompting.

## Hold shortcut (⌃⌥⌘↓)
- `RegisterEventHotKey` returned status 0, so it is unclaimed. Pressed/released timing wasn't exercised yet; it will be verified manually in Task 8, and the `CGEventSource.keyState` failsafe stays in the plan.

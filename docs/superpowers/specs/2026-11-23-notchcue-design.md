# NotchCue — Design Spec

A tiny macOS app that shows your script in a panel hanging from the camera notch and scrolls it **by itself** by listening to you read. Fully offline. No AI, no cloud, no accounts.

Inspired by notchprompter.com. Own name, own UI, no copied code, branding or assets.

## Decisions (confirmed by the user, 2026-11-23)

1. **Hidden from screen sharing and recordings**, on by default. It must be absent from all of these:
   - Chrome screen share (Google Meet, and any tab, window or entire-screen share)
   - Zoom screen share
   - QuickTime and Screenshot recordings
2. **English only.** There is no language picker; recognition uses your region's English (e.g. en-GB), falling back to en-US.
3. **One-time speech-model download is fine.** It happens via a button, and the app is offline after that.
4. **v1 features added:**
   - **A:** vocabulary boost
   - **B:** countdown and start-on-first-words, as two separate toggles
   - **C:** pace meter
   - **D:** polish
   - **J:** dyslexia-friendly font
   - a **hold-to-scroll hotkey**
5. **UI looks and reads like Apple's**: native controls, SF Symbols and a System Settings-style layout. Copy follows Apple's style (Human Interface Guidelines → Writing), with the macOS conventions used in System Settings. See "UI copy" below.

## What it does

1. Paste or type a script in Settings › Script.
2. Press **Start Prompting** (menu or ⌃⌥⌘P). The panel slides down from the notch.
3. If **Count down before starting** is on, the panel shows 3 · 2 · 1.
4. Start talking. The app transcribes on-device and matches your words to the script:
   - text you have read dims
   - the current line sits at a fixed reading line
   - the view scrolls smoothly to keep up
5. If **Start when I say the first words** is on, nothing moves and the timer doesn't run until the script's opening words are recognised. Coughs and "okay, recording" are ignored.
6. Tracking behaviour:
   - If you pause, it waits.
   - If you ad-lib, it holds.
   - If you skip a sentence, it catches up.
   - If you re-read a single word, it doesn't jump back. If you re-read a whole phrase, it does.
7. `[Bracketed cues]` are shown dimmed and italic and are never expected to be spoken.
8. Reaching the end stops listening.

## Hold-to-scroll

- **Control** setting:
  - **Voice** (default): tracks speech.
  - **Hold shortcut**: no microphone at all. The script advances only while you hold ⌃⌥⌘↓, at **Hold speed** (60–260 words per minute, default 140), and stops the moment you release.
- In Voice mode, holding the shortcut still works as a manual nudge. When you release, voice tracking resumes from the new spot.
- Key down and key up both come from Carbon hotkey pressed/released events. No Accessibility or Input Monitoring permission is needed.

## Vocabulary boost

Distinctive words from the script are passed to the recognizer as contextual strings, so names and jargon get recognised correctly. This uses the on-device API only. Up to 100 terms are picked from:
- capitalised words that are not sentence-initial
- words of 8 or more letters
- words containing digits

## Pace

- The bottom-left of the panel shows the current pace (e.g. `152 wpm`) and the time left (e.g. `1:40 left`). Time left is computed from the unread words at your recent pace.
- The pace turns orange when you are more than 15% above **Target pace** (100–200 wpm, default 150).
- Shown when **Show pace** is on, which is the default.

## Offline guarantee

- Speech runs only through Apple's on-device `SpeechAnalyzer` + `SpeechTranscriber`.
- Script matching is deterministic local code. No language models.
- The only network use is the OS-managed speech-model install, which you trigger with a button.

## Panel

- Placement:
  - **Notch** (default)
  - **Top Left** and **Top Right** corners
  - **Floating**, draggable, with its position remembered
- Theme: **Dark** (white on black) or **Light**.
- Font options:
  - **System**
  - **Serif**
  - **Rounded**
  - **Monospaced**
  - **OpenDyslexic**, bundled under the SIL OFL, with its license file shipped in the app
- Polish (D):
  - **Slide animation:** 0.25 s slide down from behind the bezel to show, and back up to hide.
  - **Edge fades:** soft fades at the top and bottom edges.
  - **Progress bar:** 2 pt along the bottom.
  - **Pause when pointer is over prompter** (default on): resumes when the pointer leaves, if it was running.
- An elapsed timer (mm:ss) sits at the bottom-right, behind the **Show timer** toggle.
- The panel is borderless and non-activating. It never takes focus, joins all Spaces and works over full-screen apps. Only the bottom corners are rounded.
- **Hide from screen sharing and recordings** is on by default.
- Sizes:
  - text 12–40 pt
  - width 300–900 px
  - height 80–400 px
- Display: any connected screen, stored by display ID. The panel re-places itself when displays change.

## Controls

Global shortcuts (Carbon, no permissions):

| Action | Shortcut |
|--------|----------|
| Start/Pause | ⌃⌥⌘P |
| Restart from Beginning | ⌃⌥⌘R |
| Show/Hide Prompter | ⌃⌥⌘H |
| Hold to scroll | hold ⌃⌥⌘↓ (⌃⌥Space is the system input-source switch) |

There is also a menu bar icon. No input is needed while reading in Voice mode.

## UI copy (Apple style)

- **Menu items and buttons:** title case, verb first. Add an ellipsis only when the item opens a window that asks for more input:
  - Start Prompting / Pause Prompting
  - Restart from Beginning
  - Show Prompter / Hide Prompter
  - Edit Script…
  - Settings…
  - Quit NotchCue
- **Settings labels:** sentence case and short:
  - Text size
  - Line spacing
  - Hide from screen sharing and recordings
  - Count down before starting
  - Start when I say the first words
- **Explanations:** one plain sentence in secondary grey under the control, like System Settings.
- **Errors:** say what happened, then what to do, then offer one button. For example: "NotchCue can't hear you. Allow microphone access in System Settings." with the button **Open System Settings**.
- No exclamation marks and no jargon ("ASR", "model asset") in the UI.

## Persistence

- The script is stored in `~/Library/Application Support/NotchCue/script.txt`.
- Settings are stored in `UserDefaults`.

## Platform

- macOS 26+ on Apple Silicon. The development machine runs macOS 27 with Xcode 27.2.
- Swift 6, SwiftUI + AppKit, SwiftPM.
- A script wraps the build into a signed `.app`.

## Out of scope for v1

From the feature table:
- **E:** sections with time budgets
- **F:** missed-line report
- **G:** cue actions
- **H:** take statistics
- **I:** multiple scripts

Also out: other languages, mirroring, phone remote, rich text, App Store distribution.

## Known risk

Hiding from Chrome, Zoom and Meet relies on `NSWindow.sharingType = .none`, which is the only public API for this. Some ScreenCaptureKit-based capture on recent macOS versions has reportedly ignored it. The spike (plan Task 1) tests all three apps before anything else is built. If a capture shows the panel, the user is told before work continues.

import AppKit
import CueCore
import SwiftUI

/// System Settings–style window: a sidebar of coloured icons, each page a grouped Form.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.settingsPage) { page in
                Label {
                    Text(page.title)
                } icon: {
                    SidebarIcon(symbol: page.symbol, color: page.color)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            Group {
                switch model.settingsPage {
                case .script: ScriptPage(model: model)
                case .appearance: AppearancePage(model: model, settings: model.settings)
                case .behavior: BehaviorPage(settings: model.settings)
                case .pace: PacePage(settings: model.settings)
                case .shortcuts: ShortcutsPage()
                }
            }
            .navigationTitle(model.settingsPage.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, idealWidth: 740, minHeight: 500, idealHeight: 560)
        .background(CaptureShield(hidden: model.settings.hideFromCapture))
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The white-on-colour rounded-square icons System Settings uses in its sidebar.
private struct SidebarIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Applies the capture setting to the Settings window too: it shows your script, so it mustn't
/// appear in a screen share either.
private struct CaptureShield: NSViewRepresentable {
    let hidden: Bool

    func makeNSView(context: Context) -> ShieldView { ShieldView() }

    func updateNSView(_ view: ShieldView, context: Context) {
        view.hideFromCapture = hidden
    }

    /// Sets the window's sharing type as soon as the view joins it, before the first frame is shown.
    final class ShieldView: NSView {
        var hideFromCapture = true { didSet { apply() } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() { window?.sharingType = hideFromCapture ? .none : .readOnly }
    }
}

private struct ScriptPage: View {
    @Bindable var model: AppModel

    private var wordCount: Int { model.session.script.spoken.count }
    private var readingTime: String {
        let seconds = Double(wordCount) / model.settings.targetPace * 60
        return seconds < 60 ? "under a minute" : "about \(Int((seconds / 60).rounded())) min"
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $model.scriptText)
                    .font(.system(size: 14))
                    // Writing Tools can send text off-device; NotchCue promises your script stays local.
                    .writingToolsBehavior(.disabled)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 300)
                    .padding(.vertical, 4)
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your script")
                    Spacer()
                    Text("\(wordCount) words · \(readingTime) at \(Int(model.settings.targetPace)) wpm")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        model.toggle()
                    } label: {
                        Label(model.isActive ? "Pause" : "Start Prompting",
                              systemImage: model.isActive ? "pause.fill" : "play.fill")
                    }
                    .controlSize(.small)
                    .help("⌃⌥⌘P")
                }
            } footer: {
                Text("Put cues like [Pause] or [Smile] in square brackets. NotchCue shows them but doesn’t wait for you to say them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePage: View {
    let model: AppModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                PanelPreview(settings: settings, scriptText: model.scriptText)
            } footer: {
                Text("The prompter is also showing at the notch while you’re on this page.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Text") {
                Picker("Font", selection: $settings.fontChoice) {
                    ForEach(FontChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Weight", selection: $settings.fontWeight) {
                    ForEach(FontWeightChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                ValueSlider("Text size", value: $settings.fontSize, in: AppSettings.fontSizeRange, step: 1, unit: "pt")
                ValueSlider("Line spacing", value: $settings.lineSpacing, in: AppSettings.lineSpacingRange,
                            step: 1, unit: "pt")
                ValueSlider("Letter spacing", value: $settings.letterSpacing, in: AppSettings.letterSpacingRange,
                            step: 0.5, unit: "pt")
                Picker("Alignment", selection: $settings.textAlignment) {
                    ForEach(TextAlignmentChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Theme", selection: $settings.theme) {
                    ForEach(PanelTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Prompter") {
                Picker("Position", selection: $settings.placement) {
                    ForEach(PlacementMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Display", selection: $settings.targetDisplayID) {
                    Text("Automatic").tag(UInt32(0))
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screen.displayID ?? 0)
                    }
                }
                ValueSlider("Width", value: $settings.panelWidth, in: AppSettings.widthRange, step: 10, unit: "px")
                ValueSlider("Height", value: $settings.panelHeight, in: AppSettings.heightRange, step: 10, unit: "px")
            }
        }
        .formStyle(.grouped)
        // Live preview at the real notch while adjusting the look.
        .onAppear { model.showPreview() }
        .onDisappear { model.endPreview() }
    }
}

private struct BehaviorPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Control", selection: $settings.controlMode) {
                    ForEach(ControlMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.controlMode == .hold {
                    Text("Hold ⌃⌥⌘↓ to move the script. It stops when you let go.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Toggle(isOn: $settings.middleButtonHold) {
                    Text("Hold the mouse wheel button to scroll")
                    Text("Works in any app. In a browser, clicking a link this way still opens it in a new tab.")
                }
                ValueSlider("Hold speed", value: $settings.holdSpeed, in: AppSettings.holdSpeedRange, step: 5, unit: "wpm")
            }
            Section {
                Toggle("Count down before starting", isOn: $settings.countdownEnabled)
                Toggle(isOn: $settings.startOnFirstWords) {
                    Text("Start when I say the first words")
                    Text("The timer starts when NotchCue hears the opening of your script.")
                }
                Toggle("Pause when pointer is over prompter", isOn: $settings.pauseOnHover)
            }
            Section {
                Toggle(isOn: $settings.hideFromCapture) {
                    Text("Hide from screen sharing and recordings")
                    Text("The prompter won’t appear in Zoom, Google Meet, Chrome, or screen recordings.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PacePage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show pace", isOn: $settings.showPace)
                ValueSlider("Target pace", value: $settings.targetPace, in: AppSettings.targetPaceRange, step: 5, unit: "wpm")
                Text("The pace turns orange when you’re more than 15% faster than your target.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show timer", isOn: $settings.showTimer)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsPage: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Start or pause prompting", value: "⌃⌥⌘P")
                LabeledContent("Restart from beginning", value: "⌃⌥⌘R")
                LabeledContent("Show or hide prompter", value: "⌃⌥⌘H")
                LabeledContent("Scroll while held", value: "⌃⌥⌘↓ or mouse wheel button")
            } footer: {
                Text("Shortcuts work in any app.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A labeled slider with its current value shown on the trailing edge, like System Settings.
private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(step < 1 ? String(format: "%.1f %@", value, unit) : "\(Int(value)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

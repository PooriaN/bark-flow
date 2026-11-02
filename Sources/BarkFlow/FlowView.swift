import SwiftUI

// THESIS: speak from any text field, return to the same work with words inserted.
// OWN-WORLD: macOS control-panel clarity, system typography, blue action, flat grouped rows.
// STORY: grant microphone and insertion access, press the shortcut, speak, press again.
// FIRST VIEWPORT: model identity, live recording control, permissions and editable transcript.
// FORM: compact native utility as requested; no marketing surface or decorative dashboard.
struct FlowView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recording: Bool { model.phase == .recording }
    private var tint: Color { model.theme.accent }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 28, weight: .medium)).foregroundStyle(model.theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bark Flow").font(model.theme.displayFont)
                    Text("\(model.selectedModel.displayName) · English · On-device").font(.system(size: 12)).foregroundStyle(model.theme.ink.opacity(0.72))
                }
                Spacer()
                Button { model.cancelShortcutCapture(); model.showSettings.toggle() } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
                    .buttonStyle(.plain).help("Dictation preferences").accessibilityLabel("Dictation preferences")
            }.padding(.bottom, 20)

            HStack {
                Text("Speech model").font(.system(size:12,weight:.medium))
                Spacer()
                Picker("Speech model",selection:Binding(get:{model.selectedModel},set:{model.selectModel($0)})) {
                    ForEach(ModelChoice.allCases) { choice in Text(choice == .plus ? choice.menuName : (choice.availableDirectory == nil ? choice.menuName : choice.displayName + " · Installed")).tag(choice) }
                }.labelsHidden().frame(width:210).disabled(model.busy)
            }
            Text("Plus is included. Bark 3.0 and Pro download on first use (about 200 MB and 1.25 GB).")
                .font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72)).fixedSize(horizontal:false,vertical:true).padding(.bottom,22)

            HStack {
                Text("Theme").font(.system(size:12,weight:.medium))
                Spacer()
                Picker("Theme",selection:$model.theme) {
                    ForEach(FlowTheme.allCases) { theme in Text(theme.name).tag(theme) }
                }.labelsHidden().frame(width:210).disabled(model.busy)
            }.padding(.bottom,22)

            HStack(alignment: .top, spacing: 18) {
                Button { model.toggle(origin:.window) } label: {
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 25, weight: .medium))
                        .frame(width: 66, height: 66)
                        .foregroundStyle(model.theme.dark ? Color(hex:0x211B17) : .white)
                        .background(tint, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain).disabled(!model.canToggle)
                .opacity(model.canToggle ? 1 : 0.55)
                .accessibilityLabel(recording ? "Stop recording and transcribe" : "Start dictation")
                .help(recording ? "Stop and transcribe" : "Start dictation")

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title).font(.system(size: 20, weight: .semibold))
                    Text(model.status).font(.system(size: 13)).foregroundStyle(model.theme.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    if let seconds = model.lastTranscriptionSeconds, model.phase == .ready {
                        Text(String(format:"Transcribed in %.2f seconds",seconds)).font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72))
                    }
                    if model.phase == .loading || model.phase == .arming || model.phase == .processing || model.phase == .inserting {
                        ProgressView().controlSize(.small).accessibilityLabel(model.status)
                    } else if recording {
                        HStack(spacing: 3) {
                            ForEach(0..<24, id: \.self) { index in
                                Capsule().fill(model.theme.accent)
                                    .frame(width: 3, height: max(3, CGFloat(model.level) * CGFloat(8 + (index * 7 % 19))))
                            }
                            Spacer()
                            Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(model.theme.ink.opacity(0.72))
                        }.frame(height: 26).accessibilityLabel("Microphone input level")
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.level)
                    } else {
                        HStack(spacing: 5) {
                            Text(model.shortcuts.start.label).shortcutKey()
                            Text(model.shortcuts.usesSameKey ? "start / stop" : "start").font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72))
                            if !model.shortcuts.usesSameKey {
                                Text(model.shortcuts.stop.label).shortcutKey()
                                Text("stop").font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72))
                            }
                        }.accessibilityElement(children:.ignore).accessibilityLabel("Start: \(model.shortcuts.start.label). Stop: \(model.shortcuts.stop.label).")
                    }
                    if recording || model.phase == .processing {
                        Button("Discard dictation") { model.cancel() }.font(.system(size: 12))
                    }
                    if model.phase == .failed { Button("Try loading again") { model.prepare() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 105, alignment: .top)

            if !model.microphoneAllowed || !model.accessibilityAllowed || model.shortcutError != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.microphoneAllowed {
                        permissionRow("Microphone", detail: "Needed to hear your voice", symbol: "mic", action: "Allow") { model.grantMicrophone() }
                    }
                    if !model.accessibilityAllowed {
                        permissionRow("Text insertion", detail: "Allow Accessibility to type into other apps", symbol: "cursorarrow.rays", action: "Enable") { model.grantInsertion() }
                    }
                    if let error = model.shortcutError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 16)
            }

            if model.showSettings {
                VStack(alignment: .leading, spacing: 12) {
                    ThemePreferences(theme:$model.theme, disabled:model.busy)
                    Divider().padding(.vertical,8)
                    Text("Keyboard shortcuts").font(.system(size:13,weight:.semibold))
                    shortcutRow("Start dictation",role:.start)
                    shortcutRow("Stop and transcribe",role:.stop)
                    Text("Click a shortcut, then press your keys. Use a function key on its own, or combine a key with Option, Control or Command. Stop can also use Esc. Choosing the same shortcut for both makes it a start/stop toggle.")
                        .font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72)).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        Button("Reset shortcuts") { model.resetShortcuts() }.disabled(model.busy || model.editingShortcut != nil)
                        if model.editingShortcut != nil { Button("Cancel") { model.cancelShortcutCapture() } }
                    }
                    Divider().padding(.vertical,4)
                    HStack {
                        Text("Recording limit")
                        Spacer()
                        Picker("Recording limit", selection:$model.recordingLimit) {
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("2 minutes").tag(120)
                            Text("5 minutes").tag(300)
                            Text("10 minutes").tag(600)
                        }.labelsHidden().frame(width:170).disabled(model.busy)
                    }
                    Text("Bark Flow stops and transcribes at the selected limit. Longer recordings take longer to process.")
                        .font(.system(size:11)).foregroundStyle(model.theme.ink.opacity(0.72)).fixedSize(horizontal:false,vertical:true)
                    Toggle("Insert into the active text field", isOn: $model.autoInsert)
                    Toggle("Play start and stop sounds", isOn: $model.sounds)
                    Text("Dictation keeps spoken fillers such as “um”. Audio stays in memory and is cleared after each dictation. Only the latest transcript is kept in this window.")
                        .font(.system(size: 12)).foregroundStyle(model.theme.ink.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                    Link("Model credits & license", destination: URL(string: "https://huggingface.co/ConwayResearch/Underdog-Bark-3.0\(model.selectedModel == .plus ? "-Plus" : model.selectedModel == .pro ? "-Pro" : "")")!)
                        .font(.system(size: 12))
                }.toggleStyle(.switch).controlSize(.small).padding(.top, 20)
            }

            HStack {
                Text("Latest transcript").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Import audio…") { model.importAudio() }.disabled(model.phase != .ready)
                    .font(.system(size: 12)).buttonStyle(.link)
            }.padding(.top, 26).padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.transcript).font(.system(size: 14))
                    .scrollContentBackground(.hidden).padding(8)
                    .accessibilityLabel("Latest transcript, editable")
                if model.transcript.isEmpty {
                    Text("Your words will appear here.").font(.system(size: 14)).foregroundStyle(model.theme.ink.opacity(0.72))
                        .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                }
            }.frame(height: 150)
                .background(model.theme.editor, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))

            HStack(spacing: 12) {
                Label("Local by design", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(model.theme.ink.opacity(0.72))
                Spacer()
                Button("Clear") { model.transcript = "" }.disabled(model.transcript.isEmpty || model.busy)
                Button("Insert text") { model.insertLatest() }.disabled(model.transcript.isEmpty || model.phase != .ready)
                Button("Copy text") { model.copyTranscript() }.buttonStyle(.borderedProminent).disabled(model.transcript.isEmpty)
            }.padding(.top, 14)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 490, idealWidth: 520, minHeight: 510, idealHeight: 690)
        .background(model.theme.surface)
        .foregroundStyle(model.theme.ink)
        .tint(model.theme.accent)
        .environment(\.colorScheme,model.theme.dark ? .dark : .light)
        .onAppear { model.refreshPermissions() }
    }

    private func shortcutRow(_ title: String, role: ShortcutRole) -> some View {
        HStack {
            Text(title).font(.system(size:12))
            Spacer()
            ShortcutRecorder(model:model,role:role).frame(width:170,height:28)
        }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, action: String,
                               perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(model.theme.ink.opacity(0.72)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(model.theme.ink.opacity(0.72))
            }
            Spacer()
            Button(action, action: perform).controlSize(.small)
        }
    }
}

private extension Text {
    func shortcutKey() -> some View {
        font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct RecordingHUD: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.phase == .recording || model.phase == .processing {
            LiveThemeHUD(theme:model.theme,level:model.level,elapsed:model.elapsed,
                         processing:model.phase == .processing,limit:TimeInterval(model.recordingLimit),stop:{ model.finish() })
        }
    }
}

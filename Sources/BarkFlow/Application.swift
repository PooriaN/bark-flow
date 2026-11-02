import AppKit
import SwiftUI
import FluidAudio

final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private let shortcut = GlobalShortcut()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var toggleItem: NSMenuItem!
    private var permissionObserver: NSObjectProtocol?
    private var hud: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        TextInsertion.trackExternalApplications()
        installMainMenu()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Bark Flow", action: #selector(openWindow), keyEquivalent: "").target = self
        toggleItem = menu.addItem(withTitle: "Start dictation", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Bark Flow", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bark Flow")
        statusItem.button?.toolTip = "Bark Flow · \(model.shortcuts.start.label) to dictate"

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bark Flow"
        window.contentView = NSHostingView(rootView: FlowView(model: model))
        window.minSize = NSSize(width: 510, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("BarkFlowMainWindow")
        hud = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 64),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.backgroundColor = .clear
        hud.isOpaque = false
        hud.hasShadow = true
        hud.level = .floating
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.contentView = NSHostingView(rootView: RecordingHUD(model: model))
        model.onChange = { [weak self] in self?.refreshMenu() }
        model.showWindow = { [weak self] in self?.openWindow() }
        shortcut.action = { [weak self] action in self?.model.handleShortcut(action) }
        model.configureShortcuts = { [weak self] bindings in try self?.shortcut.configure(bindings) }
        model.suspendShortcuts = { [weak self] in self?.shortcut.suspend() }
        do { try shortcut.install(); try shortcut.configure(model.shortcuts) } catch { model.shortcutError = error.localizedDescription }
        permissionObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
             object: nil, queue: .main) { [weak self] _ in
                 MainActor.assumeIsolated { self?.model.refreshPermissions() }
             }
        openWindow()
        model.prepare()
    }
    func refreshMenu() {
        let recording = model.phase == .recording
        do { try shortcut.setRecording(recording) } catch {
            model.shortcutError = error.localizedDescription
            model.status = "Stop shortcut unavailable. Click Stop in the listening window to finish."
        }
        toggleItem.title = recording ? "Stop & transcribe    \(model.shortcuts.stop.label)" : "Start dictation    \(model.shortcuts.start.label)"
        toggleItem.isEnabled = model.canToggle
        statusItem.button?.image = NSImage(systemSymbolName: recording ? "record.circle.fill" : "waveform",
                                          accessibilityDescription: recording ? "Bark Flow recording" : "Bark Flow")
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
        statusItem.button?.toolTip = "Bark Flow · \(model.title)"
        if recording || model.phase == .processing {
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                let rect = screen.visibleFrame
                let size = model.theme.hudSize
                hud.setFrame(NSRect(x:rect.midX-size.width/2, y:rect.minY+28,
                                    width:size.width, height:size.height), display:true)
            }
            hud.orderFrontRegardless()
        } else { hud.orderOut(nil) }
    }
    @objc func toggle() { model.toggle() }
    @objc func quit() {
        if model.phase == .recording || model.phase == .processing || model.phase == .arming {
            let alert = NSAlert()
            alert.messageText = "Quit this dictation?"
            alert.informativeText = "The current recording will be discarded."
            alert.addButton(withTitle: "Keep dictating"); alert.addButton(withTitle: "Quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        NSApp.terminate(nil)
    }
    @objc func openWindow() {
        model.refreshPermissions()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) { model.cancelShortcutCapture() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow(); return true
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Bark Flow", action: #selector(quit), keyEquivalent: "q").target = self
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }
}

@main
enum EntryPoint {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--check-access") {
            let probe=AppModel()
            let result: [String:Any] = ["microphone":probe.microphoneAllowed,"insertion":probe.accessibilityAllowed,
                                       "theme":probe.theme.rawValue,"model":probe.selectedModel.rawValue]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),
               let text=String(data:data,encoding:.utf8) { print(text) }
            return
        }
        if let at = args.firstIndex(of:"--render-themes"), args.count > at+1 {
            do { try ThemeSnapshotExport.render(to:URL(fileURLWithPath:args[at+1])) }
            catch { fputs(error.localizedDescription+"\n",stderr);exit(1) }
            return
        }
        if let at = args.firstIndex(of: "--verify-model-download"), args.count > at + 1,
           let model = ModelChoice(rawValue:args[at + 1]), let storeAt = args.firstIndex(of: "--model-store"), args.count > storeAt + 1 {
            Task {
                do {
                    let root = try await ModelDownloads.ensureAvailable(model, store: URL(fileURLWithPath: args[storeAt + 1])) { message in fputs(message + "\n", stderr) }
                    let engine = SpeechEngine()
                    try await engine.prepare(root: root, model:model) { message in fputs(message + "\n", stderr) }
                    if let audio = args.firstIndex(of: "--transcribe"), args.count > audio + 1 {
                        print(try await engine.transcribe(file: URL(fileURLWithPath: args[audio + 1])))
                    }
                    exit(0)
                } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            }
            RunLoop.current.run()
            return
        }
        if let at = args.firstIndex(of: "--transcribe"), args.count > at + 1 {
            Task {
            do {
                let model: ModelChoice
                if let index = args.firstIndex(of:"--model"), args.count > index+1 {
                    guard let chosen = ModelChoice(rawValue:args[index+1]) else { throw FlowError("Choose --model plus, standard, or pro.") }
                    model = chosen
                } else { model = .saved }
                let root: URL
                if let index = args.firstIndex(of: "--model-dir"), args.count > index + 1 {
                    root = URL(fileURLWithPath: args[index + 1])
                } else { root = model.resourceDirectory }
                let engine = SpeechEngine()
                let begin = Date()
                try await engine.prepare(root: root, model:model) { message in fputs(message + "\n", stderr) }
                if args.contains("--benchmark") { fputs("load_and_warm_seconds=\(Date().timeIntervalSince(begin))\n",stderr) }
                let repeats = args.contains("--benchmark") ? 2 : 1
                for repetition in 1...repeats {
                    let start = Date()
                    let text = try await engine.transcribe(file: URL(fileURLWithPath: args[at + 1]), maximumSeconds: args.contains("--benchmark") ? AudioPolicy.maxSeconds : AudioPolicy.importMaxSeconds)
                    print(text)
                    if args.contains("--benchmark") { fputs("run_\(repetition)_seconds=\(Date().timeIntervalSince(start))\n",stderr) }
                }
                exit(0)
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            }
            RunLoop.current.run()
            return
        }
        // Enter AppKit from a synchronous main, leaving the main actor free for UI tasks.
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

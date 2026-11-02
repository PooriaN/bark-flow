import AppKit
import Carbon
import SwiftUI

enum ShortcutAction { case start, stop }
enum ShortcutRole { case start, stop }

struct ShortcutChord: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String
    var label: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        return prefix + keyName
    }
    func matches(_ other: ShortcutChord) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    static let functionKeys: [UInt32:String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
    func validate(for role: ShortcutRole) throws {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard keyCode <= 127, modifiers & ~supported == 0, !keyName.isEmpty else { throw FlowError("That shortcut is not supported. Record another one.") }
        let primary = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & primary != 0 || Self.functionKeys[keyCode] != nil ||
                (role == .stop && keyCode == UInt32(kVK_Escape)) else {
            throw FlowError("Use a function key, or a key with Option, Control or Command. Stop can also use Esc on its own.")
        }
    }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var mask: UInt32 = 0
        if event.modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        modifiers = mask
        let special: [UInt32:String] = [49:"Space",36:"Return",76:"Enter",53:"Esc",48:"Tab",51:"⌫",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"Page Up",121:"Page Down"]
        keyName = special[keyCode] ?? Self.functionKeys[keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(keyCode)"
    }
    init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName
    }
}

struct ShortcutBindings: Codable, Equatable {
    var start: ShortcutChord
    var stop: ShortcutChord
    var usesSameKey: Bool { start.matches(stop) }
    static let defaults = ShortcutBindings(
        start:ShortcutChord(keyCode:UInt32(kVK_Space),modifiers:UInt32(optionKey),keyName:"Space"),
        stop:ShortcutChord(keyCode:UInt32(kVK_Return),modifiers:UInt32(optionKey),keyName:"Return"))
    static var saved: ShortcutBindings {
        guard let data = UserDefaults.standard.data(forKey:"dictationShortcuts"),
              let value = try? JSONDecoder().decode(Self.self,from:data),
              (try? value.start.validate(for:.start)) != nil,
              (try? value.stop.validate(for:.stop)) != nil else { return .defaults }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data,forKey:"dictationShortcuts") } }
}

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let role: ShortcutRole
    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        let active = model.editingShortcut == role
        button.onBegin = { model.beginShortcutCapture(role) }
        button.onCapture = { model.captureShortcut(ShortcutChord(event:$0),role:role) }
        button.onCancel = { model.cancelShortcutCapture() }
        button.captureActive = active
        button.title = active ? "Press keys…" : (role == .start ? model.shortcuts.start.label : model.shortcuts.stop.label)
        button.setAccessibilityLabel(role == .start ? "Change start dictation shortcut" : "Change stop dictation shortcut")
        button.isEnabled = !model.busy
        if active, button.window?.firstResponder !== button {
            DispatchQueue.main.async { if button.captureActive { button.window?.makeFirstResponder(button) } }
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var captureActive = false
    var onBegin: (() -> Void)?
    var onCapture: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame:.zero)
        bezelStyle = .rounded
        target = self; action = #selector(begin)
        font = .systemFont(ofSize:12,weight:.medium)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() { onBegin?() }
    override func keyDown(with event: NSEvent) {
        guard captureActive else { super.keyDown(with:event); return }
        if !event.isARepeat { onCapture?(event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if captureActive { keyDown(with:event); return true }
        return super.performKeyEquivalent(with:event)
    }
    override func resignFirstResponder() -> Bool {
        if captureActive { onCancel?() }
        return super.resignFirstResponder()
    }
}

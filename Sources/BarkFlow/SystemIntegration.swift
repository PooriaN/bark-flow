import AppKit
import Carbon
import ApplicationServices

@MainActor
final class GlobalShortcut {
    private var startKey: EventHotKeyRef?
    private var stopKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: ShortcutBindings?
    private var recording = false
    private var held: Set<UInt32> = []
    var action: ((ShortcutAction) -> Void)?

    func install() throws {
        let events = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = events.withUnsafeBufferPointer { specs in InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,
                                    MemoryLayout<EventHotKeyID>.size,nil,&key) == noErr else { return OSStatus(eventNotHandledErr) }
            guard key.signature == 0x42464C57, key.id == 1 || key.id == 2 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.held.remove(key.id) }
                else if owner.held.insert(key.id).inserted { owner.action?(key.id == 1 ? .start : .stop) }
            }
            return noErr
        }, specs.count, specs.baseAddress, context, &handler) }
        guard result == noErr else { throw FlowError("Could not register the keyboard shortcut.") }
    }
    private func register(_ chord: ShortcutChord, id: UInt32) throws -> EventHotKeyRef {
        var key: EventHotKeyRef?
        let status = RegisterEventHotKey(chord.keyCode,chord.modifiers,EventHotKeyID(signature:0x42464C57,id:id),
                                        GetApplicationEventTarget(),0,&key)
        guard status == noErr, let key else { throw FlowError("\(chord.label) is already in use or reserved by macOS. Choose another shortcut.") }
        return key
    }
    func configure(_ bindings: ShortcutBindings) throws {
        try bindings.start.validate(for:.start); try bindings.stop.validate(for:.stop)
        // New registrations are proved before replacing the working start binding.
        let reuse = current?.start.matches(bindings.start) == true && startKey != nil
        let candidateStart = reuse ? startKey! : try register(bindings.start,id:1)
        do {
            let stopOwnedByPreviousStart = startKey != nil && current?.start.matches(bindings.stop) == true
            if !bindings.usesSameKey && !stopOwnedByPreviousStart {
                let probe = try register(bindings.stop,id:2)
                UnregisterEventHotKey(probe)
            }
        } catch {
            if !reuse { UnregisterEventHotKey(candidateStart) }
            throw error
        }
        if !reuse, let startKey { UnregisterEventHotKey(startKey); held.remove(1) }
        if let stopKey { UnregisterEventHotKey(stopKey) }
        self.startKey = candidateStart; stopKey = nil; current = bindings
        if recording && !bindings.usesSameKey { stopKey = try register(bindings.stop,id:2) }
    }
    func setRecording(_ value: Bool) throws {
        guard recording != value else { return }
        recording = value
        if let stopKey { UnregisterEventHotKey(stopKey); self.stopKey = nil; held.remove(2) }
        if value, let current, !current.usesSameKey { stopKey = try register(current.stop,id:2) }
    }
    func suspend() {
        if let startKey { UnregisterEventHotKey(startKey); self.startKey = nil }
        if let stopKey { UnregisterEventHotKey(stopKey); self.stopKey = nil }
        held.removeAll()
    }
    deinit {
        if let startKey { UnregisterEventHotKey(startKey) }
        if let stopKey { UnregisterEventHotKey(stopKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct InsertionTarget {
    let application: NSRunningApplication
    let element: AXUIElement
    let window: AXUIElement?
    let identifier: String?
    let role: String
    let returnFromOwnWindow: Bool
}

enum InsertionOrigin { case shortcut, window }
enum InsertionIssue: Equatable {
    case accessibilityMissing, noEditableField, secureField, focusChanged, modifiersHeld, pasteUnavailable
    var message: String {
        switch self {
        case .accessibilityMissing: "Text insertion is blocked. Enable Bark Flow in System Settings > Privacy & Security > Accessibility. Your text is ready to copy."
        case .noEditableField: "No destination text field was found. Click the field you want, then use your start shortcut, or return here and click Insert text."
        case .secureField: "Automatic insertion is unavailable in password fields. Your text is ready to copy."
        case .focusChanged: "The destination changed while transcribing. Your text is on the clipboard; paste it in the field you want."
        case .modifiersHeld: "Release the shortcut keys before insertion. Your text is on the clipboard; use ⌘V to paste it."
        case .pasteUnavailable: "The paste could not be sent. Your text is on the clipboard; use ⌘V to paste it."
        }
    }
}
enum InsertionCapture { case target(InsertionTarget), failure(InsertionIssue) }
enum InsertionOutcome { case inserted, pasteSent, failed(InsertionIssue) }

// Pure decision seams used by the regression checks. Stable identifiers only
// replace object equality when they belong to the same window and control role.
enum InsertionPolicy {
    static func sameDestination(sameObject: Bool, sameWindow: Bool, originalID: String?, currentID: String?, sameRole: Bool) -> Bool {
        sameObject || (sameWindow && sameRole && originalID?.isEmpty == false && originalID == currentID)
    }
    static func confirmed(before: String?, after: String?, text: String) -> Bool {
        guard let before, let after, before != after, !text.isEmpty else { return false }
        return after.contains(text)
    }
}

@MainActor
enum TextInsertion {
    private static var lastApplication: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?
    static var allowed: Bool { AXIsProcessTrusted() }
    static func trackExternalApplications() {
        rememberFrontmost()
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { notification in
                MainActor.assumeIsolated {
                    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                       app.bundleIdentifier != "com.apple.systempreferences",
                       app.bundleIdentifier != "com.apple.SecurityAgent" { lastApplication = app }
                }
            }
    }
    private static func rememberFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastApplication = app }
    }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,key as CFString,&raw) == .success else { return nil }
        return raw
    }
    private static func axElement(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw,to:AXUIElement.self)
    }
    private static func capture(in app: NSRunningApplication, returning: Bool) -> InsertionCapture {
        guard !app.isTerminated else { return .failure(.noEditableField) }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = axElement(attribute(application,kAXFocusedUIElementAttribute as String)) else { return .failure(.noEditableField) }
        let role = attribute(element,kAXRoleAttribute as String) as? String ?? ""
        let subrole = attribute(element,kAXSubroleAttribute as String) as? String
        guard subrole != kAXSecureTextFieldSubrole as String,
              attribute(element,"AXProtectedContent") as? Bool != true else { return .failure(.secureField) }
        var writable = DarwinBoolean(false)
        let canSelect = AXUIElementIsAttributeSettable(element,kAXSelectedTextAttribute as CFString,&writable) == .success && writable.boolValue
        guard [kAXTextFieldRole as String,kAXTextAreaRole as String,kAXComboBoxRole as String].contains(role) ||
                attribute(element,"AXEditable") as? Bool == true || canSelect else { return .failure(.noEditableField) }
        let identifier = (attribute(element,kAXIdentifierAttribute as String) as? String).flatMap { $0.isEmpty ? nil : $0 } ??
            (attribute(element,"AXDOMIdentifier") as? String).flatMap { $0.isEmpty ? nil : $0 }
        let window = axElement(attribute(element,kAXWindowAttribute as String)) ?? axElement(attribute(application,kAXFocusedWindowAttribute as String))
        return .target(InsertionTarget(application:app,element:element,window:window,identifier:identifier,role:role,returnFromOwnWindow:returning))
    }
    static func capture(origin: InsertionOrigin = .shortcut) -> InsertionCapture {
        guard allowed else { return .failure(.accessibilityMissing) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return .failure(.noEditableField) }
        if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            rememberFrontmost()
            return capture(in:app,returning:false)
        }
        guard origin == .window, let previous = lastApplication else { return .failure(.noEditableField) }
        return capture(in:previous,returning:true)
    }
    private static func matches(_ a: InsertionTarget, _ b: InsertionTarget) -> Bool {
        guard a.application.processIdentifier == b.application.processIdentifier else { return false }
        let sameWindow = a.window.flatMap { aw in b.window.map { CFEqual(aw,$0) } } ?? false
        return InsertionPolicy.sameDestination(sameObject:CFEqual(a.element,b.element),sameWindow:sameWindow,
             originalID:a.identifier,currentID:b.identifier,sameRole:a.role == b.role)
    }
    private static func textValue(_ element: AXUIElement) -> String? {
        guard let value = attribute(element,kAXValueAttribute as String) as? String, value.utf16.count <= 200_000 else { return nil }
        return value
    }
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text,forType:.string)
    }

    static func insert(_ text: String, into target: InsertionTarget) async -> InsertionOutcome {
        guard allowed else { copy(text); return .failed(.accessibilityMissing) }
        if target.returnFromOwnWindow,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            target.application.activate(options:[])
            if let window = target.window { _ = AXUIElementPerformAction(window,kAXRaiseAction as CFString) }
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier { break }
                try? await Task.sleep(for:.milliseconds(50))
            }
        }
        guard case .target(var current) = capture(), matches(target,current) else { copy(text); return .failed(.focusChanged) }
        // A fast model can finish while Control/Option are still physically held.
        // Never turn the paste into another application's modified shortcut.
        let modifiers: CGEventFlags = [.maskCommand,.maskControl,.maskAlternate,.maskShift]
        for _ in 0..<24 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { break }
            try? await Task.sleep(for:.milliseconds(50))
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else { copy(text); return .failed(.modifiersHeld) }
        guard case .target(let rechecked) = capture(), matches(target,rechecked) else { copy(text); return .failed(.focusChanged) }
        current = rechecked
        let before = textValue(current.element)
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { copy(text); return .failed(.pasteUnavailable) }
        board.clearContents()
        guard board.setString(text, forType: .string) else { return .failed(.pasteUnavailable) }
        let ownChange = board.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.application.processIdentifier); up.postToPid(target.application.processIdentifier)
        var confirmed = false
        for _ in 0..<40 {
            try? await Task.sleep(for:.milliseconds(50))
            if InsertionPolicy.confirmed(before:before,after:textValue(current.element),text:text) { confirmed = true; break }
        }
        // Restore only after the destination actually consumed the paste. If its
        // value is unreadable, keep the transcript available for a manual paste.
        if confirmed && board.changeCount == ownChange {
            board.clearContents()
            let restored = saved.map { values in
                let item = NSPasteboardItem()
                values.forEach { item.setData($0.value, forType: $0.key) }
                return item
            }
            if !restored.isEmpty { board.writeObjects(restored) }
        }
        return confirmed ? .inserted : .pasteSent
    }
}

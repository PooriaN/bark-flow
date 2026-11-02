import AppKit
import SwiftUI

/// Explicit offline UI export: no model preparation, capture, shortcuts or insertion.
enum ThemeSnapshotExport {
    @MainActor static func render(to folder: URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let suite="local.barkflow.snapshot.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(preferences:defaults)
        model.phase = .ready;model.microphoneAllowed=true;model.accessibilityAllowed=true
        model.status="Press your start shortcut in any text field."
        model.transcript="This is a synthetic preview. Your dictated words will appear here."
        for theme in FlowTheme.allCases {
            model.theme=theme
            for settings in [false,true] {
                model.showSettings=settings
                let view=FlowView(model:model).frame(width:560,height:settings ? 1220 : 730)
                try save(view,to:folder.appendingPathComponent("\(theme.rawValue)-\(settings ? "settings" : "main").png"))
            }
            for dark in [false,true] {
                let view=VStack(spacing:18) {
                    HStack(spacing:24) {
                        ThemeHUDSurface(theme:theme,level:0,elapsed:37)
                        ThemeHUDSurface(theme:theme,level:0.85,elapsed:37,phase:1.2)
                    }
                    ThemeHUDSurface(theme:theme,level:0,elapsed:37,processing:true)
                }.padding(24).frame(width:760,height:theme == .heartwood ? 400 : 240)
                    .background(dark ? Color(hex:0x242529) : Color(hex:0xE7E7E4))
                try save(view,to:folder.appendingPathComponent("\(theme.rawValue)-hud-\(dark ? "dark" : "light").png"))
            }
        }
        print("Exported 20 native theme views. No models or microphone opened.")
    }
    @MainActor private static func save<V:View>(_ view: V,to file: URL) throws {
        let host=NSHostingView(rootView:view)
        let size=host.fittingSize
        host.frame=NSRect(origin:.zero,size:size)
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:size.width,height:size.height),
                            styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView=host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.08))
        window.displayIfNeeded()
        guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in:host.bounds,to:rep)
        guard let data=rep.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to:file)
        window.orderOut(nil)
    }
}

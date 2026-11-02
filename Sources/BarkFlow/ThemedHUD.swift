import SwiftUI

// Disambiguate the macOS 15 property wrapper from newer SDK State macros.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// Pure rendering surface, shared by the live HUD, settings preview and render checks.
/// A single amplitude drives stylized linework; it does not imply a frequency spectrum.
struct ThemeHUDSurface: View {
    let theme: FlowTheme
    let level: Double
    let elapsed: TimeInterval
    var limit: TimeInterval = 120
    var processing = false
    var phase: Double = 0
    var stop: () -> Void = {}
    @Environment(\.colorSchemeContrast) private var contrast

    private var time: String { String(format:"%d:%02d",Int(max(0,elapsed))/60,Int(max(0,elapsed))%60) }
    private var label: String { processing ? "Transcribing" : "Listening" }
    private var edge: Color { contrast == .increased ? theme.ink : theme.ink.opacity(0.34) }

    var body: some View {
        ZStack(alignment:.topLeading) {
            Canvas { context, size in
                draw(in:&context, size:size)
            }.accessibilityHidden(true).allowsHitTesting(false)
            if theme == .heartwood {
                VStack(spacing:3) {
                    Text(label).font(.system(size:10, weight:.medium))
                    Text(time).font(.custom("Optima",size:25)).monospacedDigit()
                }.frame(width:140,height:62).offset(x:8,y:40)
                stopControl.frame(width:78,height:44).offset(x:39,y:113)
            } else if theme == .downstroke {
                stopControl.frame(width:56,height:48).offset(x:8,y:16)
                VStack(alignment:.leading, spacing:4) {
                    Text(label).font(.system(size:10,weight:.medium))
                    Text(time).font(.system(size:18,design:.serif)).monospacedDigit()
                }.frame(width:84,height:48,alignment:.leading).offset(x:83,y:14)
            } else {
                let x: CGFloat = theme == .minimal ? 180 : (theme == .breakwater ? 210 : 190)
                VStack(alignment:.leading, spacing:4) {
                    Text(label).font(.system(size:10,weight:.medium))
                    Text(time).font(.system(size:16,weight:.medium,design:.rounded)).monospacedDigit()
                }.frame(width:70,height:48,alignment:.leading).offset(x:x-10,y:14)
                stopControl.frame(width:48,height:48).offset(x:theme.hudSize.width-58,y:14)
            }
        }
        .foregroundStyle(theme.ink)
        .frame(width:theme.hudSize.width,height:theme.hudSize.height)
        .environment(\.colorScheme, theme.dark ? .dark : .light)
        .accessibilityElement(children:.contain)
        .accessibilityLabel("\(theme.name), \(label)")
    }

    @ViewBuilder private var stopControl: some View {
        if processing {
            ThemeProcessingIndicator(ink:theme == .downstroke ? Color(hex:0xEFE8D8) : theme.ink)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .accessibilityLabel("Transcribing on your Mac")
        } else {
            Button(action:stop) {
                VStack(spacing:3) {
                    Image(systemName:"stop.fill").font(.system(size:10,weight:.semibold))
                    Text("Stop").font(.system(size:10,weight:.medium))
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    .foregroundStyle(theme.dark ? Color(hex:0x241A13) : Color.white)
                    .background(theme.dark ? Color(hex:0xEFE6D6) : Color(hex:0x21483E),
                                in:RoundedRectangle(cornerRadius:theme == .downstroke ? 4 : 16))
            }.buttonStyle(.plain)
                .help("Stop listening and transcribe")
                .accessibilityLabel("Stop listening and transcribe")
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let amplitude = processing ? 0 : min(1,max(0,level))
        let rim = theme.dark ? Color(hex:0xC6A47E) : edge
        switch theme {
        case .minimal:
            let path = Path(roundedRect:CGRect(x:2,y:4,width:284,height:68),cornerRadius:20)
            ctx.fill(path, with:.color(theme.surface))
            ctx.stroke(path,with:.color(edge),lineWidth:0.75)
            drawWave(in:&ctx, rect:CGRect(x:14,y:14,width:148,height:48),level:amplitude, ink:theme.accent, kind:.minimal)
        case .breakwater:
            var p=Path(); p.move(to:CGPoint(x:8,y:65))
            p.addCurve(to:CGPoint(x:178,y:35),control1:CGPoint(x:65,y:65-45*amplitude),control2:CGPoint(x:135,y:65-50*amplitude))
            p.addCurve(to:CGPoint(x:198,y:8),control1:CGPoint(x:185,y:34),control2:CGPoint(x:176,y:8))
            p.addLine(to:CGPoint(x:300,y:8)); p.addQuadCurve(to:CGPoint(x:314,y:22),control:CGPoint(x:314,y:8))
            p.addLine(to:CGPoint(x:314,y:68)); p.addQuadCurve(to:CGPoint(x:300,y:81),control:CGPoint(x:314,y:81))
            p.addLine(to:CGPoint(x:20,y:81)); p.addQuadCurve(to:CGPoint(x:8,y:65),control:CGPoint(x:6,y:81));p.closeSubpath()
            ctx.fill(p,with:.linearGradient(Gradient(colors:[Color(hex:0x4B3C30),theme.surface]),startPoint:.zero,endPoint:CGPoint(x:30,y:86)))
            ctx.stroke(p,with:.color(rim),lineWidth:contrast == .increased ? 1.6 : 0.8)
        case .downstroke:
            ctx.fill(Path(roundedRect:CGRect(x:2,y:8,width:295,height:64),cornerRadius:5),with:.color(Color(hex:0x171C22)))
            let sheet=Path(roundedRect:CGRect(x:72,y:2,width:230,height:64),cornerRadius:3)
            ctx.fill(sheet,with:.color(theme.surface));ctx.stroke(sheet,with:.color(edge),lineWidth:0.6)
            drawWave(in:&ctx,rect:CGRect(x:169,y:10,width:123,height:48),level:amplitude,ink:Color(hex:0x302E29),kind:.downstroke)
        case .drawnWake:
            var p=Path();p.move(to:CGPoint(x:5,y:43))
            p.addCurve(to:CGPoint(x:279,y:5),control1:CGPoint(x:110,y:43),control2:CGPoint(x:165,y:5))
            p.addCurve(to:CGPoint(x:279,y:75),control1:CGPoint(x:329,y:5),control2:CGPoint(x:329,y:75))
            p.addCurve(to:CGPoint(x:5,y:43),control1:CGPoint(x:184,y:75),control2:CGPoint(x:98,y:43));p.closeSubpath()
            ctx.fill(p,with:.linearGradient(Gradient(colors:[Color(hex:0xF1F6F3),theme.surface]),startPoint:.zero,endPoint:CGPoint(x:0,y:80)))
            ctx.stroke(p,with:.color(Color(hex:0x416B5B)),lineWidth:contrast == .increased ? 1.6 : 0.8)
            var glassContext=ctx;glassContext.clip(to:p)
            drawWave(in:&glassContext,rect:CGRect(x:26,y:19,width:144,height:46),level:amplitude,ink:theme.accent,kind:.drawnWake)
        case .heartwood:
            let circle=Path(ellipseIn:CGRect(x:4,y:2,width:148,height:148))
            let disc = processing ? circle : circle.intersection(Path(CGRect(x:0,y:0,width:156,height:127)))
            ctx.fill(disc,with:.linearGradient(Gradient(colors:[Color(hex:0x3B2B20),theme.surface]),startPoint:.zero,endPoint:CGPoint(x:140,y:150)))
            ctx.stroke(disc,with:.color(rim),lineWidth:0.8)
            for i in 0..<12 {
                let r=CGFloat(43+i*2)
                let ring=Path(ellipseIn:CGRect(x:78-r,y:76-r,width:r*2,height:r*2))
                ctx.stroke(ring,with:.color(theme.ink.opacity(0.13)),lineWidth:0.6)
                let interval=max(1,limit/12)
                let fraction=min(1,max(0,(elapsed-Double(i)*interval)/interval))
                if !processing && fraction>0 {
                    ctx.stroke(ring.trimmedPath(from:0,to:fraction),with:.color(theme.accent),
                               style:StrokeStyle(lineWidth:fraction<1 ? 0.8+amplitude*1.6 : 0.85,lineCap:.round))
                }
            }
        }
    }

    private func drawWave(in ctx: inout GraphicsContext, rect: CGRect, level: Double, ink: Color, kind: FlowTheme) {
        let steps=96
        func point(_ x: Double, _ layer: Double = 0) -> CGPoint {
            let envelope=pow(sin(.pi*x),1.35)
            let carrier=sin(x * .pi * 5.2 - phase + layer)*0.68 + sin(x * .pi * 9.1 + phase*0.47)*0.24
            return CGPoint(x:rect.minX+x*rect.width,y:rect.midY+envelope*carrier*level*rect.height*0.38)
        }
        if kind == .downstroke {
            var p=Path()
            for j in 0...steps {
                let x=Double(j)/Double(steps)
                let thickness=0.5+pow(sin(.pi*x),1.5)*level*18*(0.72+0.28*sin(x*10+phase))
                let q=CGPoint(x:rect.minX+x*rect.width,y:rect.midY-thickness)
                if j==0 { p.move(to:q) } else { p.addLine(to:q) }
            }
            for j in (0...steps).reversed() {
                let x=Double(j)/Double(steps)
                let thickness=0.5+pow(sin(.pi*x),1.5)*level*18*(0.72+0.28*sin(x*10+phase))
                p.addLine(to:CGPoint(x:rect.minX+x*rect.width,y:rect.midY+thickness))
            }
            p.closeSubpath();ctx.fill(p,with:.color(ink))
        } else {
            for layer in 0..<(kind == .minimal ? 3 : 1) {
                var p=Path()
                for j in 0...steps {
                    let q=point(Double(j)/Double(steps),Double(layer)*0.45)
                    if j==0 { p.move(to:q) } else { p.addLine(to:q) }
                }
                ctx.stroke(p,with:.color(ink.opacity(layer==0 ? 1 : 0.25)),
                           style:StrokeStyle(lineWidth:layer==0 ? 1.6 : 0.8,lineCap:.round))
            }
        }
    }
}

struct LiveThemeHUD: View {
    let theme: FlowTheme
    let level: Float
    let elapsed: TimeInterval
    let processing: Bool
    var limit: TimeInterval = 120
    let stop: () -> Void
    var animating = true
    @ViewState<VoiceEnvelope> private var envelope=VoiceEnvelope()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || processing || !animating)) { clock in
            let now=clock.date.timeIntervalSinceReferenceDate
            ThemeHUDSurface(theme:theme,level:reduceMotion ? VoiceEnvelope.normalized(Double(level)) : envelope.value(at:now),
                            elapsed:elapsed,limit:limit,processing:processing,phase:reduceMotion ? 0 : now.truncatingRemainder(dividingBy:60)*2,stop:stop)
        }
        .onAppear { envelope.receive(Double(level),at:Date.timeIntervalSinceReferenceDate) }
        .onChange(of:level) { _, value in envelope.receive(Double(value),at:Date.timeIntervalSinceReferenceDate) }
    }
}

struct ThemePreferences: View {
    @Binding var theme: FlowTheme
    var disabled = false
    @ViewState<Task<Void,Never>?> private var sampleTask: Task<Void,Never>?
    @ViewState<Float> private var sampleLevel: Float = 0
    @ViewState<Bool> private var playing = false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Appearance").font(.system(size:13,weight:.semibold))
                Spacer()
                Picker("Theme",selection:$theme) {
                    ForEach(FlowTheme.allCases) { item in Text(item.name).tag(item) }
                }.frame(width:185).disabled(disabled)
            }
            Text(theme.detail).font(.system(size:12)).foregroundStyle(theme.ink.opacity(0.72))
            ZStack {
                Color.primary.opacity(0.04)
                LiveThemeHUD(theme:theme,level:sampleLevel,elapsed:37,processing:false,stop:stopSample,animating:playing)
            }.frame(height:theme == .heartwood ? 180 : 112)
                .clipShape(RoundedRectangle(cornerRadius:10))
            HStack {
                Text("Preview only. No microphone used.").font(.system(size:11)).foregroundStyle(theme.ink.opacity(0.72))
                Spacer()
                Button(playing ? "Stop sample" : "Play sample") { playing ? stopSample() : playSample() }
            }
            if disabled { Text("You can change themes after this dictation finishes.").font(.system(size:11)).foregroundStyle(theme.ink.opacity(0.72)) }
        }
        .onDisappear(perform:stopSample)
        .onChange(of:theme) { _,_ in stopSample() }
    }
    private func stopSample() { sampleTask?.cancel();sampleTask=nil;playing=false;sampleLevel=0 }
    private func playSample() {
        stopSample();playing=true
        sampleTask=Task { @MainActor in
            for step in 0..<144 {
                guard !Task.isCancelled else { return }
                let t=Double(step)/24
                let burst=pow(max(0,sin(t*3.6)),2)*(0.55+0.35*sin(t*1.8))
                sampleLevel=Float(burst)
                do { try await Task.sleep(for:.milliseconds(42)) } catch { return }
            }
            sampleLevel=0;playing=false;sampleTask=nil
        }
    }
}

private struct ThemeProcessingIndicator: View {
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:1/20,paused:reduceMotion)) { clock in
            Circle().trim(from:0.08,to:0.8).stroke(ink,style:StrokeStyle(lineWidth:1.8,lineCap:.round))
                .frame(width:15,height:15)
                .rotationEffect(.degrees(reduceMotion ? 0 : clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:2)*180))
        }.accessibilityHidden(true)
    }
}

import AppKit
import Combine
import QuartzCore
import SwiftUI

// The clock face: a translucent disc, hour/minute ticks, optional numerals,
// three hands and a hub. Colors come from the selected theme and adapt to
// light/dark; the disc keeps it legible on any wallpaper.
//
// It is built from Core Animation layers rather than a SwiftUI `Canvas` in a
// `TimelineView`. Re-rendering a SwiftUI `Canvas` every tick leaks: each frame
// leaves a dispatch timer (plus its block and two small allocations) behind
// inside SwiftUI's renderer, about one per second while the clock is on screen.
// Over days of uptime that adds up to hundreds of thousands of timers and
// hundreds of MB, and the CPU cost of each tick climbs with them. `.drawingGroup()` and
// `Canvas(rendersAsynchronously:)` leak the same way.
//
// So nothing here re-renders per tick. The dial (disc, rim, ticks, numerals) is
// drawn once into a layer and redrawn only when its look changes: size, theme,
// numerals, light/dark. The hands are shape layers that are only rotated:
//  - ticking: a one-second timer, aligned to the whole second, sets three
//    rotation transforms;
//  - sweeping: the second hand runs as a Core Animation rotation capped at
//    30 fps, animated by the system's render server with no work in this
//    process between frames. The one-second timer still moves the hour and
//    minute hands, and re-syncs the sweep to the wall clock once a minute.
//
// When the clock can't actually be seen (display asleep, screen saver up, or
// the window fully occluded) the timer and the sweep stop and the face holds a
// single static frame. AppDelegate drives `settings.renderActive`.
final class ClockView: NSView, CALayerDelegate {

    private let settings: ClockSettings
    private var settingsObservation: AnyCancellable?

    private let dialLayer = CALayer()
    private let hourHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let secondHand = CAShapeLayer()
    private let hubLayer = CAShapeLayer()
    private let hubDotLayer = CAShapeLayer()

    private var palette: ClockPalette?
    private var dialKey: DialKey?
    private var motion: Motion?
    private var tickTimer: Timer?

    private static let sweepKey = "sweep"

    init(settings: ClockSettings) {
        self.settings = settings
        super.init(frame: .zero)

        // Layer-hosting: assigning the layer before `wantsLayer` means this view
        // owns its sublayer tree and AppKit leaves it alone.
        layer = CALayer()
        wantsLayer = true

        dialLayer.delegate = self
        for sublayer in allLayers {
            layer?.addSublayer(sublayer)
        }
        for hand in [hourHand, minuteHand, secondHand] {
            hand.fillColor = nil
            hand.lineCap = .round
        }

        // objectWillChange fires before the new value is stored, so look at the
        // settings on the next pass of the main queue, once it has landed.
        settingsObservation = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsDidChange() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        tickTimer?.invalidate()
    }

    private var allLayers: [CALayer] {
        [dialLayer, hourHand, minuteHand, secondHand, hubLayer, hubDotLayer]
    }

    // Drag the clock by grabbing anywhere on the face.
    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: - Reacting to changes

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutFace()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        settingsDidChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        settingsDidChange()
    }

    private func settingsDidChange() {
        applyLook()
        applyMotion()
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        withoutAnimation {
            for sublayer in allLayers { sublayer.contentsScale = scale }
        }
        dialLayer.setNeedsDisplay()
    }

    // MARK: - Look: colors and the dial

    private struct DialKey: Equatable {
        let dark: Bool
        let theme: ClockTheme
        let showNumerals: Bool
    }

    private func applyLook() {
        let key = DialKey(dark: isDark,
                          theme: settings.previewTheme ?? settings.theme,
                          showNumerals: settings.showNumerals)
        guard key != dialKey else { return }
        dialKey = key

        let palette = ClockPalette(dark: key.dark, theme: key.theme)
        self.palette = palette
        withoutAnimation {
            hourHand.strokeColor = palette.hourHand
            minuteHand.strokeColor = palette.minuteHand
            secondHand.strokeColor = palette.secondHand
            hubLayer.fillColor = palette.hub
            hubDotLayer.fillColor = palette.secondHand
        }
        dialLayer.setNeedsDisplay()
    }

    private func layoutFace() {
        let geometry = FaceGeometry(bounds: bounds)
        let center = geometry.center
        let radius = geometry.radius

        withoutAnimation {
            layer?.frame = bounds
            dialLayer.frame = bounds

            // Each hand is drawn pointing at 12 o'clock and rotated about the
            // center. Placing it by bounds + position (not frame) keeps that
            // valid while a rotation transform is applied.
            func shape(_ hand: CAShapeLayer, length: CGFloat, tail: CGFloat, width: CGFloat) {
                hand.bounds = bounds
                hand.position = center
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x, y: center.y - tail))     // short counterweight tail
                path.addLine(to: CGPoint(x: center.x, y: center.y + length)) // tip
                hand.path = path
                hand.lineWidth = width
            }
            shape(hourHand, length: radius * 0.52, tail: radius * 0.12,
                  width: max(3.0, radius * 0.045))
            shape(minuteHand, length: radius * 0.76, tail: radius * 0.14,
                  width: max(2.4, radius * 0.032))
            shape(secondHand, length: radius * 0.84, tail: radius * 0.20,
                  width: max(1.0, radius * 0.014))

            // Center hub, capped with a small second-hand-colored dot.
            func disc(_ layer: CAShapeLayer, radius r: CGFloat) {
                layer.frame = bounds
                layer.path = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                      width: r * 2, height: r * 2),
                                    transform: nil)
            }
            disc(hubLayer, radius: max(2.5, radius * 0.045))
            disc(hubDotLayer, radius: max(1.0, radius * 0.018))
        }
        dialLayer.setNeedsDisplay()
    }

    // CALayerDelegate: draws the static dial. Runs only when the dial layer is
    // marked for display (size, look or backing scale changed), never per tick.
    func draw(_ layer: CALayer, in ctx: CGContext) {
        guard layer === dialLayer, let palette else { return }
        let geometry = FaceGeometry(bounds: layer.bounds)
        let center = geometry.center
        let radius = geometry.radius

        // Translucent backing disc + rim.
        ctx.setFillColor(palette.face)
        ctx.fillEllipse(in: geometry.faceRect)
        ctx.setStrokeColor(palette.ring)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: geometry.faceRect.insetBy(dx: 0.75, dy: 0.75))

        // 60 minute ticks; every 5th is a longer/heavier hour tick.
        ctx.setLineCap(.round)
        for i in 0..<60 {
            let isHour = (i % 5 == 0)
            let angle = Double(i) / 60.0 * 2 * .pi
            ctx.move(to: point(center, radius * (isHour ? 0.82 : 0.89), angle))
            ctx.addLine(to: point(center, radius * 0.96, angle))
            ctx.setStrokeColor(isHour ? palette.hourTick : palette.minuteTick)
            ctx.setLineWidth(isHour ? 2.4 : 1.0)
            ctx.strokePath()
        }

        // Optional hour numerals, set just inside the tick ring.
        if dialKey?.showNumerals == true {
            let fontSize = radius * 0.17
            let base = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            let font = base.fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(cgColor: palette.numeral) ?? NSColor.labelColor,
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            for n in 1...12 {
                let label = NSAttributedString(string: "\(n)", attributes: attributes)
                let size = label.size()
                let pos = point(center, radius * 0.68, Double(n) / 12.0 * 2 * .pi)
                label.draw(at: CGPoint(x: pos.x - size.width / 2, y: pos.y - size.height / 2))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Motion: the tick timer and the sweep

    private struct Motion: Equatable {
        let active: Bool
        let sweep: Bool
    }

    private func applyMotion() {
        let wanted = Motion(active: settings.renderActive && window != nil,
                            sweep: settings.sweepSeconds)
        guard wanted != motion else { return }
        motion = wanted

        stopMotion()
        showTime(Date())
        guard wanted.active else { return }   // hidden: hold one static frame

        if wanted.sweep { startSweep(at: Date()) }

        // Fire on each whole second, so a ticking second hand lands on the beat.
        // .common keeps it running while the settings slider is being dragged.
        let now = Date().timeIntervalSinceReferenceDate
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: now.rounded(.down) + 1),
                          interval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopMotion() {
        tickTimer?.invalidate()
        tickTimer = nil
        secondHand.removeAnimation(forKey: Self.sweepKey)
    }

    private func tick() {
        let now = Date()
        showTime(now)
        // The sweep runs on media time, which can drift from the wall clock;
        // re-anchor it at the top of every minute.
        if motion?.sweep == true,
           Calendar.current.component(.second, from: now) == 0 {
            startSweep(at: now)
        }
    }

    // Sets the three hands' model rotations. While sweeping, the second hand's
    // animation overrides its model value on screen; setting it anyway means it
    // is already right whenever the sweep stops.
    private func showTime(_ date: Date) {
        let sweep = settings.sweepSeconds
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double(comps.minute ?? 0)
        let hour   = Double((comps.hour ?? 0) % 12)
        // Seconds-into-the-minute is timezone-independent (offsets are whole minutes).
        let continuousSecond = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let second = sweep ? continuousSecond : Double(comps.second ?? 0)

        let secondAngle = second / 60.0 * 2 * .pi
        let minuteAngle = (minute + second / 60.0) / 60.0 * 2 * .pi
        let hourAngle   = (hour + minute / 60.0) / 12.0 * 2 * .pi

        // Angles run clockwise from 12; layer rotation runs counterclockwise.
        withoutAnimation {
            hourHand.setAffineTransform(CGAffineTransform(rotationAngle: -hourAngle))
            minuteHand.setAffineTransform(CGAffineTransform(rotationAngle: -minuteAngle))
            secondHand.setAffineTransform(CGAffineTransform(rotationAngle: -secondAngle))
        }
    }

    private func startSweep(at date: Date) {
        let second = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let start = -second / 60.0 * 2 * .pi
        let sweep = CABasicAnimation(keyPath: "transform.rotation.z")
        sweep.fromValue = start
        sweep.toValue = start - 2 * .pi
        sweep.duration = 60
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        sweep.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        secondHand.add(sweep, forKey: Self.sweepKey)
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

// MARK: - Geometry

private struct FaceGeometry {
    let center: CGPoint
    let radius: CGFloat
    let faceRect: CGRect

    init(bounds: CGRect) {
        let inset: CGFloat = 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        center = CGPoint(x: rect.midX, y: rect.midY)
        radius = max(0, min(rect.width, rect.height) / 2)
        faceRect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
    }
}

// Point on a circle, with the angle measured clockwise from 12 o'clock, in
// layer coordinates (y grows upward).
private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + radius * CGFloat(sin(angle)),
            y: center.y + radius * CGFloat(cos(angle)))
}

// MARK: - Colors

private struct ClockPalette {
    let face: CGColor
    let ring: CGColor
    let hourTick: CGColor
    let minuteTick: CGColor
    let numeral: CGColor
    let hourHand: CGColor
    let minuteHand: CGColor
    let secondHand: CGColor
    let hub: CGColor

    init(dark: Bool, theme: ClockTheme) {
        let scheme: ColorScheme = dark ? .dark : .light
        func cg(_ color: Color) -> CGColor { NSColor(color).cgColor }
        if dark {
            face       = cg(Color.black.opacity(0.34))
            ring       = cg(Color.white.opacity(0.30))
            hourTick   = cg(Color.white.opacity(0.92))
            minuteTick = cg(Color.white.opacity(0.45))
            numeral    = cg(Color.white.opacity(0.92))
        } else {
            face       = cg(Color.white.opacity(0.62))
            ring       = cg(Color.black.opacity(0.22))
            hourTick   = cg(Color.black.opacity(0.88))
            minuteTick = cg(Color.black.opacity(0.42))
            numeral    = cg(Color.black.opacity(0.85))
        }
        hourHand   = cg(theme.handColor(scheme))
        minuteHand = cg(theme.handColor(scheme))
        secondHand = cg(theme.secondColor(scheme))
        hub        = cg(theme.handColor(scheme))
    }
}

import SwiftUI

// The clock face: a translucent disc, hour/minute ticks, optional numerals,
// three hands and a hub. Redrawn on a TimelineView — once per second (ticking
// second hand) or ~30 fps when the sweeping second hand is enabled. Colors come
// from the selected theme and adapt to light/dark; the disc keeps it legible on
// any wallpaper.
//
// When the clock can't actually be seen (display asleep, screen saver up, or the
// window fully occluded) the periodic schedule is dropped for a single static
// frame. A `.periodic` TimelineView does *not* auto-pause off-screen the way
// `.animation` does, so without this gate it would redraw ~30 fps into a buffer
// nobody sees, forever. AppDelegate drives `settings.renderActive`.
struct ClockView: View {
    @ObservedObject var settings: ClockSettings
    @Environment(\.colorScheme) private var scheme

    // A fixed schedule anchor. Using a stable reference date — rather than
    // `.now`, which is recomputed on every `body` pass and churns the schedule
    // rebuild — keeps the periodic timeline from re-anchoring on each redraw.
    private static let anchor = Date(timeIntervalSinceReferenceDate: 0)

    var body: some View {
        let palette = ClockPalette(scheme: scheme, theme: settings.previewTheme ?? settings.theme)
        let sweep = settings.sweepSeconds
        let showNumerals = settings.showNumerals
        let interval = sweep ? 1.0 / 30.0 : 1.0

        if settings.renderActive {
            TimelineView(.periodic(from: Self.anchor, by: interval)) { timeline in
                Canvas { context, size in
                    drawClock(in: context, size: size, date: timeline.date,
                              palette: palette, sweep: sweep, showNumerals: showNumerals)
                }
            }
        } else {
            // Hidden: one static frame, no periodic wake-ups until we're visible
            // again (AppDelegate flips renderActive back on).
            Canvas { context, size in
                drawClock(in: context, size: size, date: Date(),
                          palette: palette, sweep: sweep, showNumerals: showNumerals)
            }
        }
    }
}

// MARK: - Colors

private struct ClockPalette {
    let face: Color
    let ring: Color
    let hourTick: Color
    let minuteTick: Color
    let numeral: Color
    let hourHand: Color
    let minuteHand: Color
    let secondHand: Color
    let hub: Color

    init(scheme: ColorScheme, theme: ClockTheme) {
        if scheme == .dark {
            face       = Color.black.opacity(0.34)
            ring       = Color.white.opacity(0.30)
            hourTick   = Color.white.opacity(0.92)
            minuteTick = Color.white.opacity(0.45)
            numeral    = Color.white.opacity(0.92)
        } else {
            face       = Color.white.opacity(0.62)
            ring       = Color.black.opacity(0.22)
            hourTick   = Color.black.opacity(0.88)
            minuteTick = Color.black.opacity(0.42)
            numeral    = Color.black.opacity(0.85)
        }
        hourHand   = theme.handColor(scheme)
        minuteHand = theme.handColor(scheme)
        secondHand = theme.secondColor(scheme)
        hub        = theme.handColor(scheme)
    }
}

// MARK: - Drawing

// Point on a circle, with the angle measured clockwise from 12 o'clock.
private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + radius * CGFloat(sin(angle)),
            y: center.y - radius * CGFloat(cos(angle)))
}

private func drawHand(_ ctx: GraphicsContext, center: CGPoint, angle: Double,
                      length: CGFloat, tail: CGFloat, width: CGFloat, color: Color) {
    var path = Path()
    path.move(to: point(center, tail, angle + .pi))   // short counterweight tail
    path.addLine(to: point(center, length, angle))    // tip
    ctx.stroke(path, with: .color(color),
               style: StrokeStyle(lineWidth: width, lineCap: .round))
}

private func drawClock(in ctx: GraphicsContext, size: CGSize, date: Date,
                       palette: ClockPalette, sweep: Bool, showNumerals: Bool) {
    let inset: CGFloat = 2
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2

    // Translucent backing disc + rim.
    let faceRect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
    ctx.fill(Path(ellipseIn: faceRect), with: .color(palette.face))
    ctx.stroke(Path(ellipseIn: faceRect.insetBy(dx: 0.75, dy: 0.75)),
               with: .color(palette.ring), lineWidth: 1.5)

    // 60 minute ticks; every 5th is a longer/heavier hour tick.
    for i in 0..<60 {
        let isHour = (i % 5 == 0)
        let angle = Double(i) / 60.0 * 2 * .pi
        let outer = radius * 0.96
        let inner = radius * (isHour ? 0.82 : 0.89)
        var path = Path()
        path.move(to: point(center, inner, angle))
        path.addLine(to: point(center, outer, angle))
        ctx.stroke(path,
                   with: .color(isHour ? palette.hourTick : palette.minuteTick),
                   style: StrokeStyle(lineWidth: isHour ? 2.4 : 1.0, lineCap: .round))
    }

    // Optional hour numerals, set just inside the tick ring.
    if showNumerals {
        let fontSize = radius * 0.17
        for n in 1...12 {
            let angle = Double(n) / 12.0 * 2 * .pi
            let pos = point(center, radius * 0.68, angle)
            var text = ctx.resolve(
                Text("\(n)").font(.system(size: fontSize, weight: .medium, design: .rounded)))
            text.shading = .color(palette.numeral)
            ctx.draw(text, at: pos, anchor: .center)
        }
    }

    // Time → angles. The second hand uses a continuous (sub-second) value when
    // sweeping, and the whole-second value when ticking.
    let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    let minute = Double(comps.minute ?? 0)
    let hour   = Double((comps.hour ?? 0) % 12)
    // Seconds-into-the-minute is timezone-independent (offsets are whole minutes).
    let continuousSecond = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
    let second = sweep ? continuousSecond : Double(comps.second ?? 0)

    let secondAngle = second / 60.0 * 2 * .pi
    let minuteAngle = (minute + second / 60.0) / 60.0 * 2 * .pi
    let hourAngle   = (hour + minute / 60.0) / 12.0 * 2 * .pi

    drawHand(ctx, center: center, angle: hourAngle,
             length: radius * 0.52, tail: radius * 0.12,
             width: max(3.0, radius * 0.045), color: palette.hourHand)
    drawHand(ctx, center: center, angle: minuteAngle,
             length: radius * 0.76, tail: radius * 0.14,
             width: max(2.4, radius * 0.032), color: palette.minuteHand)
    drawHand(ctx, center: center, angle: secondAngle,
             length: radius * 0.84, tail: radius * 0.20,
             width: max(1.0, radius * 0.014), color: palette.secondHand)

    // Center hub, capped with a small second-hand-colored dot.
    let hubR = max(2.5, radius * 0.045)
    ctx.fill(Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR,
                                    width: hubR * 2, height: hubR * 2)),
             with: .color(palette.hub))
    let dotR = max(1.0, radius * 0.018)
    ctx.fill(Path(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR,
                                    width: dotR * 2, height: dotR * 2)),
             with: .color(palette.secondHand))
}

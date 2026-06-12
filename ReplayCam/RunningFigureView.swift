import SwiftUI

/// Animated stick figure that cycles through walking keyframes.
struct RunningFigureView: View {
    @State private var phase: Double = 0

    // 8 keyframes: each is [shoulder, elbow, wrist, hip, knee, ankle] for left & right limbs
    // Values are (x, y) offsets from body centre in a -1…1 normalised space
    // Joints order per arm/leg: shoulder/hip → elbow/knee → wrist/ankle
    private let frameCount = 8

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let cycle = (t * 1.8).truncatingRemainder(dividingBy: 1.0)
                draw(ctx: ctx, size: size, phase: cycle)
            }
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, phase: Double) {
        let cx = size.width  / 2
        let cy = size.height / 2
        let s  = size.height * 0.36   // unit scale

        // Body proportions
        let headR  = s * 0.18
        let headY  = cy - s * 0.72    // top
        let neckY  = headY + headR * 2
        let shouldY = neckY + s * 0.08
        let hipY   = shouldY + s * 0.42
        let groundY = hipY + s * 0.75

        let strokeW: CGFloat = 3.5
        let color = Color.purple.opacity(0.9)

        // Head
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - headR, y: headY,
                                          width: headR*2, height: headR*2)),
                   with: .color(color), lineWidth: strokeW)

        // Spine
        line(ctx, from: CGPoint(x: cx, y: neckY), to: CGPoint(x: cx, y: hipY),
             color: color, w: strokeW)

        // --- Arms ---
        // Pendulum angles: left arm swings forward when right leg is forward
        let armAmp  = 0.55    // radians amplitude
        let legAmp  = 0.65

        let leftArmAngle  =  sin(phase * .pi * 2) * armAmp   // forward swing
        let rightArmAngle = -leftArmAngle

        let leftLegAngle  = -sin(phase * .pi * 2) * legAmp
        let rightLegAngle = -leftLegAngle

        let upperArmLen = s * 0.30
        let foreArmLen  = s * 0.28
        let thighLen    = s * 0.38
        let shinLen     = s * 0.37

        // Elbow bend: arms bend more during mid-swing
        let elbowBend: Double = 0.6 + 0.3 * abs(sin(phase * .pi * 2))

        func armPts(angle: Double, side: Double) -> (CGPoint, CGPoint, CGPoint) {
            let shoulder = CGPoint(x: cx + side * s * 0.10, y: shouldY)
            let elbowX = shoulder.x + CGFloat(sin(angle)) * upperArmLen
            let elbowY = shoulder.y + CGFloat(cos(angle)) * upperArmLen
            let wristAngle = angle + elbowBend * side
            let wristX = elbowX + CGFloat(sin(wristAngle)) * foreArmLen
            let wristY = elbowY + CGFloat(cos(wristAngle)) * foreArmLen
            return (shoulder, CGPoint(x: elbowX, y: elbowY), CGPoint(x: wristX, y: wristY))
        }

        // Knee bend: only bends when leg is swinging back
        func legPts(angle: Double, side: Double) -> (CGPoint, CGPoint, CGPoint) {
            let hip = CGPoint(x: cx + side * s * 0.10, y: hipY)
            let kneeX = hip.x + CGFloat(sin(angle)) * thighLen
            let kneeY = hip.y + CGFloat(cos(angle)) * thighLen
            // Knee always bends forward slightly for realism
            let kneeBend: Double = 0.25 + max(0, -angle * side) * 0.55
            let ankleAngle = angle + kneeBend
            let ankleX = kneeX + CGFloat(sin(ankleAngle)) * shinLen
            let ankleY = kneeY + CGFloat(cos(ankleAngle)) * shinLen
            return (hip, CGPoint(x: kneeX, y: kneeY), CGPoint(x: ankleX, y: ankleY))
        }

        // Draw limb: three-segment chain
        func drawLimb(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) {
            line(ctx, from: a, to: b, color: color, w: strokeW)
            line(ctx, from: b, to: c, color: color, w: strokeW)
            // Joint dots
            for pt in [b] {
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x-2.5, y: pt.y-2.5, width: 5, height: 5)),
                         with: .color(color))
            }
        }

        let (lShoulder, lElbow, lWrist) = armPts(angle: leftArmAngle,  side: -1)
        let (rShoulder, rElbow, rWrist) = armPts(angle: rightArmAngle, side:  1)
        let (lHip,  lKnee,  lAnkle)    = legPts(angle: leftLegAngle,  side: -1)
        let (rHip,  rKnee,  rAnkle)    = legPts(angle: rightLegAngle, side:  1)

        drawLimb(lShoulder, lElbow, lWrist)
        drawLimb(rShoulder, rElbow, rWrist)
        drawLimb(lHip,  lKnee,  lAnkle)
        drawLimb(rHip,  rKnee,  rAnkle)

        // Ground dots (scan line effect)
        for i in 0..<3 {
            let dx = CGFloat(i - 1) * s * 0.55
            let dotX = cx + dx - CGFloat(phase) * s * 0.8
            let wrappedX = dotX.truncatingRemainder(dividingBy: size.width + s)
            let finalX = wrappedX < -s * 0.5 ? wrappedX + size.width + s : wrappedX
            ctx.fill(Path(ellipseIn: CGRect(x: finalX-2, y: groundY-2, width: 4, height: 4)),
                     with: .color(.white.opacity(0.15)))
        }
    }

    private func line(_ ctx: GraphicsContext,
                      from a: CGPoint, to b: CGPoint,
                      color: Color, w: CGFloat) {
        var p = Path()
        p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(color), lineWidth: w)
    }
}

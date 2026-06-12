import SwiftUI

/// Pose-scan animation: skeleton keypoints light up sequentially with a sweep line.
struct RunningFigureView: View {
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                draw(ctx: ctx, size: size, t: t)
            }
        }
    }

    // Joint positions in normalized coords (0–1), origin top-left
    // Approximate human skeleton proportions
    private let joints: [(CGFloat, CGFloat)] = [
        (0.50, 0.08),  // 0 head
        (0.50, 0.22),  // 1 neck
        (0.35, 0.25),  // 2 left shoulder
        (0.65, 0.25),  // 3 right shoulder
        (0.28, 0.42),  // 4 left elbow
        (0.72, 0.42),  // 5 right elbow
        (0.23, 0.58),  // 6 left wrist
        (0.77, 0.58),  // 7 right wrist
        (0.40, 0.55),  // 8 left hip
        (0.60, 0.55),  // 9 right hip
        (0.37, 0.73),  // 10 left knee
        (0.63, 0.73),  // 11 right knee
        (0.35, 0.92),  // 12 left ankle
        (0.65, 0.92),  // 13 right ankle
    ]

    private let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (1, 3),
        (2, 4), (4, 6),
        (3, 5), (5, 7),
        (2, 8), (3, 9), (8, 9),
        (8, 10), (10, 12),
        (9, 11), (11, 13),
    ]

    private func draw(ctx: GraphicsContext, size: CGSize, t: Double) {
        let period: Double = 2.2
        let cycle = t.truncatingRemainder(dividingBy: period) / period  // 0–1

        // Sweep line Y in normalized coords: scans top → bottom → top
        let sweepNorm = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2   // 0→1→0
        let sweepY = sweepNorm * size.height

        func pt(_ idx: Int) -> CGPoint {
            CGPoint(x: joints[idx].0 * size.width,
                    y: joints[idx].1 * size.height)
        }

        // Draw edges — dim base
        for (a, b) in edges {
            let pa = pt(a), pb = pt(b)
            // Brightness: segments near sweep line glow
            let midY = (pa.y + pb.y) / 2
            let dist = abs(midY - sweepY)
            let glow = max(0, 1 - dist / (size.height * 0.25))
            let alpha = 0.15 + 0.55 * glow

            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            ctx.stroke(path,
                       with: .color(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(alpha)),
                       lineWidth: 1.5)
        }

        // Draw joints
        for (i, _) in joints.enumerated() {
            let p = pt(i)
            let dist = abs(p.y - sweepY)
            let glow = max(0, 1 - dist / (size.height * 0.20))
            let r: CGFloat = i == 0 ? 6 : 4   // head bigger

            // Outer glow
            if glow > 0.1 {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: p.x - r*2, y: p.y - r*2, width: r*4, height: r*4)),
                    with: .color(Color.purple.opacity(0.18 * glow))
                )
            }
            // Core dot
            let dotAlpha = 0.25 + 0.75 * glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)),
                with: .color(Color(red: 0.75, green: 0.55, blue: 1.0).opacity(dotAlpha))
            )
        }

        // Sweep line
        let lineAlpha = 0.45 * (0.6 + 0.4 * sin(t * .pi * 3))
        var sweepPath = Path()
        sweepPath.move(to: CGPoint(x: 0, y: sweepY))
        sweepPath.addLine(to: CGPoint(x: size.width, y: sweepY))
        ctx.stroke(sweepPath,
                   with: .color(Color(red: 0.7, green: 0.5, blue: 1.0).opacity(lineAlpha)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
}

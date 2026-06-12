import SwiftUI
import simd

// MARK: - Skeleton overlay

struct PoseOverlayView: View {
    let poses: [PoseResult]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let draw = drawingRect(in: geo.size)
            Canvas { ctx, _ in
                for pose in poses {
                    drawSkeleton(pose, ctx: ctx, rect: draw)
                }
            }
        }
    }

    // MARK: - Coordinate mapping

    private func drawingRect(in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scaleX = viewSize.width  / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale  = min(scaleX, scaleY)
        let w = imageSize.width  * scale
        let h = imageSize.height * scale
        return CGRect(x: (viewSize.width  - w) / 2,
                      y: (viewSize.height - h) / 2,
                      width: w, height: h)
    }

    private func point(_ kp: Keypoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + kp.x * rect.width,
                y: rect.minY + kp.y * rect.height)
    }

    // MARK: - Depth helpers (iOS 17+ 3D mode)

    /// Normalise a z value (metres, negative = further away in camera space)
    /// to 0…1 where 1 = closest. Returns nil when no 3D data available.
    private func depthFactor(for pose: PoseResult) -> ((Keypoint) -> CGFloat?) {
        let worldPositions = pose.keypoints.compactMap(\.worldPos)
        guard !worldPositions.isEmpty else { return { _ in nil } }

        // z is negative in camera space — more negative = further away
        let zValues = worldPositions.map { $0.z }
        let zMin = zValues.min()!   // most negative = furthest
        let zMax = zValues.max()!   // least negative = closest
        let range = zMax - zMin

        return { kp in
            guard let w = kp.worldPos else { return nil }
            guard range > 0.01 else { return 0.5 }
            return CGFloat((w.z - zMin) / range)   // 0 = far, 1 = near
        }
    }

    // MARK: - Drawing

    private func drawSkeleton(_ pose: PoseResult, ctx: GraphicsContext, rect: CGRect) {
        let kps = pose.keypoints
        let depth = depthFactor(for: pose)

        // Skeleton lines
        for (a, b) in skeletonEdges {
            let ka = kps[a.rawValue]
            let kb = kps[b.rawValue]
            guard ka.confidence >= 0.25, kb.confidence >= 0.25 else { continue }

            let da = depth(ka)
            let db = depth(kb)
            let avgDepth = (da.flatMap { d in db.map { (d + $0) / 2 } }) ?? nil

            var path = Path()
            path.move(to: point(ka, in: rect))
            path.addLine(to: point(kb, in: rect))

            let baseColor = lineColor(a, b)
            let lineWidth = avgDepth.map { 1.5 + $0 * 2.5 } ?? 2.5
            let opacity   = avgDepth.map { 0.5 + $0 * 0.5 } ?? 1.0
            ctx.stroke(path,
                       with: .color(baseColor.opacity(opacity)),
                       lineWidth: lineWidth)
        }

        // Keypoint dots
        for kp in kps {
            guard kp.confidence >= 0.25 else { continue }
            let p = point(kp, in: rect)
            let d = depth(kp)
            let radius = d.map { 3.0 + $0 * 4.0 } ?? 4.0
            let dot = CGRect(x: p.x - radius, y: p.y - radius,
                             width: radius * 2, height: radius * 2)
            let opacity = d.map { 0.55 + $0 * 0.45 } ?? 1.0
            ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(opacity)))
            ctx.stroke(Path(ellipseIn: dot.insetBy(dx: -1, dy: -1)),
                       with: .color(.black.opacity(opacity * 0.4)), lineWidth: 1)
        }
    }

    private func lineColor(_ a: CocoKeypoint, _ b: CocoKeypoint) -> Color {
        let left:  Set<CocoKeypoint> = [.leftEye, .leftEar, .leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle]
        let right: Set<CocoKeypoint> = [.rightEye, .rightEar, .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle]
        if left.contains(a)  || left.contains(b)  { return Color(red: 0.2, green: 0.8, blue: 1.0) }
        if right.contains(a) || right.contains(b) { return Color(red: 1.0, green: 0.5, blue: 0.1) }
        return .yellow
    }
}

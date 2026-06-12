import SwiftUI
import simd

struct TopDownPoseView: View {
    let pose: PoseResult

    var body: some View {
        Canvas { ctx, size in
            guard has3D else {
                ctx.draw(
                    Text("No 3D").font(.caption2).foregroundColor(.white.opacity(0.3)),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
                return
            }
            guard let layout = Layout(pose: pose, size: size) else { return }
            drawGrid(ctx: ctx, layout: layout)
            drawSkeleton(ctx: ctx, layout: layout)
            drawHead(ctx: ctx, layout: layout)
            drawFacingArrow(ctx: ctx, layout: layout)
            drawLabel(ctx: ctx, size: size)
        }
        .frame(width: 130, height: 140)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var has3D: Bool { pose.keypoints.contains { $0.worldPos != nil } }

    // MARK: - Layout

    /// X軸：直接用 2D 影像 x（和影片畫面左右完全一致）
    /// Z軸（深度）：用 Vision 3D worldPos.z
    private struct Layout {
        let size: CGSize
        let center: CGPoint
        let xScale: CGFloat     // view pixels per 2D normalised unit
        let zScale: CGFloat     // view pixels per world metre (depth)
        let cx2d: Float         // body centre 2D x
        let cz: Float           // body centre world z

        init?(pose: PoseResult, size: CGSize) {
            self.size = size
            self.center = CGPoint(x: size.width / 2, y: size.height * 0.52)

            let kps = pose.keypoints
            let ls = kps[CocoKeypoint.leftShoulder.rawValue]
            let rs = kps[CocoKeypoint.rightShoulder.rawValue]
            let lh = kps[CocoKeypoint.leftHip.rawValue]
            let rh = kps[CocoKeypoint.rightHip.rawValue]

            guard ls.confidence > 0.2, rs.confidence > 0.2 else { return nil }

            // X scale: apparent shoulder span in 2D → 28% of view width
            let apparentSpan = abs(Float(ls.x) - Float(rs.x))
            guard apparentSpan > 0.01 else { return nil }
            self.xScale = CGFloat(size.width) * 0.28 / CGFloat(apparentSpan)

            // Body centre X in 2D
            self.cx2d = (Float(ls.x) + Float(rs.x)) / 2

            // Body centre Z in world space (average torso joints)
            var sumZ: Float = 0, n: Float = 0
            for w in [ls.worldPos, rs.worldPos, lh.worldPos, rh.worldPos].compactMap({ $0 }) {
                sumZ += w.z; n += 1
            }
            guard n > 0 else { return nil }
            self.cz = sumZ / n

            // Z scale: world shoulder width → 28% of view height
            if let lsW = ls.worldPos, let rsW = rs.worldPos {
                let trueW = simd_length(SIMD2<Float>(lsW.x - rsW.x, lsW.z - rsW.z))
                self.zScale = trueW > 0.05 ? CGFloat(size.height) * 0.28 / CGFloat(trueW) : 60
            } else {
                self.zScale = 60
            }
        }

        /// Convert a keypoint to top-down view point.
        /// X: from 2D image position (matches video frame orientation exactly).
        /// Y: from 3D world z (depth — positive z away from camera = top of view).
        func toView(_ kp: Keypoint) -> CGPoint? {
            guard kp.confidence > 0.1 else { return nil }
            let vx = center.x + CGFloat(Float(kp.x) - cx2d) * xScale
            let vy: CGFloat
            if let w = kp.worldPos {
                vy = center.y + CGFloat(-(w.z - cz)) * zScale
            } else {
                vy = center.y
            }
            return CGPoint(x: vx, y: vy)
        }
    }

    // MARK: - Grid

    private func drawGrid(ctx: GraphicsContext, layout: Layout) {
        let size = layout.size
        for m: CGFloat in [-1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5] {
            let y = layout.center.y + m * layout.zScale
            guard y > 4, y < size.height - 4 else { continue }
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(m == 0 ? 0.25 : 0.10)),
                       lineWidth: m == 0 ? 1 : 0.5)
        }
        var vp = Path()
        vp.move(to: CGPoint(x: layout.center.x, y: 0))
        vp.addLine(to: CGPoint(x: layout.center.x, y: size.height))
        ctx.stroke(vp, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
    }

    // MARK: - Skeleton

    private func drawSkeleton(ctx: GraphicsContext, layout: Layout) {
        let kps = pose.keypoints
        for (a, b) in skeletonEdges {
            let ka = kps[a.rawValue], kb = kps[b.rawValue]
            guard let ptA = layout.toView(ka), let ptB = layout.toView(kb) else { continue }
            var path = Path()
            path.move(to: ptA); path.addLine(to: ptB)
            ctx.stroke(path, with: .color(edgeColor(a, b)), lineWidth: 2)
        }
        for (idx, kp) in kps.enumerated() {
            guard let p = layout.toView(kp) else { continue }
            let isAnkle = idx == CocoKeypoint.leftAnkle.rawValue
                       || idx == CocoKeypoint.rightAnkle.rawValue
            let r: CGFloat = isAnkle ? 4 : 2.5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                     with: .color(.white.opacity(isAnkle ? 1 : 0.8)))
        }
    }

    // MARK: - Head

    private func drawHead(ctx: GraphicsContext, layout: Layout) {
        let kps = pose.keypoints
        let nose = kps[CocoKeypoint.nose.rawValue]
        let ls   = kps[CocoKeypoint.leftShoulder.rawValue]
        let rs   = kps[CocoKeypoint.rightShoulder.rawValue]
        guard let p = layout.toView(nose) else { return }
        let span = abs(Float(ls.x) - Float(rs.x))
        let r = max(5, CGFloat(span) * layout.xScale * 0.35)
        let rect = CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)
        ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.15)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
    }

    // MARK: - Facing arrow
    // Direction from 2D shoulder vector + 3D z-diff for depth component

    private func drawFacingArrow(ctx: GraphicsContext, layout: Layout) {
        let kps = pose.keypoints
        let ls = kps[CocoKeypoint.leftShoulder.rawValue]
        let rs = kps[CocoKeypoint.rightShoulder.rawValue]
        guard ls.confidence > 0.2, rs.confidence > 0.2 else { return }

        // X component: perpendicular to 2D shoulder line (in view X)
        // Shoulder vector in view X: ls.x > rs.x when facing camera → sv_x > 0
        // Forward (perpendicular, pointing toward camera) → same view x-centre
        // Use z-diff for the depth (Y) component of the arrow
        let lsW = ls.worldPos
        let rsW = rs.worldPos
        let zDiff = (rsW?.z ?? 0) - (lsW?.z ?? 0)   // positive when rs further (turning left)
        let xDiff = Float(ls.x) - Float(rs.x)         // positive when facing camera

        // Forward in view space: (lateral = 0 when straight-on, depth = toward camera = positive vy)
        var nx = CGFloat(-zDiff) * layout.zScale / 14  // lateral from depth difference
        var ny = CGFloat(xDiff) * layout.xScale / 14   // depth component (facing toward camera = positive vy)
        let len = sqrt(nx*nx + ny*ny)
        guard len > 0.5 else { return }
        nx /= len; ny /= len

        let arrowLen: CGFloat = 14
        let base = layout.center
        let tip = CGPoint(x: base.x + nx * arrowLen, y: base.y + ny * arrowLen)
        var shaft = Path()
        shaft.move(to: base); shaft.addLine(to: tip)
        ctx.stroke(shaft, with: .color(.yellow.opacity(0.85)), lineWidth: 2)

        let px = -ny * 5, py = nx * 5
        let bx = tip.x - nx * 7, by = tip.y - ny * 7
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: bx+px, y: by+py))
        head.addLine(to: CGPoint(x: bx-px, y: by-py))
        head.closeSubpath()
        ctx.fill(head, with: .color(.yellow.opacity(0.85)))
    }

    // MARK: - Label

    private func drawLabel(ctx: GraphicsContext, size: CGSize) {
        ctx.draw(
            Text("TOP VIEW")
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: size.width / 2, y: size.height - 8)
        )
    }

    // MARK: - Colour

    private func edgeColor(_ a: CocoKeypoint, _ b: CocoKeypoint) -> Color {
        let left:  Set<CocoKeypoint> = [.leftShoulder,.leftElbow,.leftWrist,.leftHip,.leftKnee,.leftAnkle]
        let right: Set<CocoKeypoint> = [.rightShoulder,.rightElbow,.rightWrist,.rightHip,.rightKnee,.rightAnkle]
        if left.contains(a)  || left.contains(b)  { return Color(red:0.2,green:0.8,blue:1.0).opacity(0.9) }
        if right.contains(a) || right.contains(b) { return Color(red:1.0,green:0.5,blue:0.1).opacity(0.9) }
        return Color.yellow.opacity(0.6)
    }
}

import AVFoundation
import UIKit
import simd

// MARK: - Result models

struct JointAngle: Identifiable {
    let id = UUID()
    let name: String
    let degrees: Double
    let isValid: Bool
}

struct FrameAnalysis {
    let time: Double
    let poses: [PoseResult]
    let angles: [JointAngle]
    let imageSize: CGSize
}

// MARK: - Analyzer

actor VideoAnalyzer {
    private let detector = PoseDetector()
    private let sampleFPS: Double = 10   // analyze 10 frames per second

    func analyze(url: URL, progress: @escaping @Sendable (Double) -> Void) async -> [FrameAnalysis] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = duration.seconds
        guard totalSeconds > 0 else { return [] }

        // Read camera intrinsics embedded by VideoExporter (ReplayCam recordings only)
        let embeddedIntrinsics = await loadIntrinsics(from: asset)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.05, preferredTimescale: 600)

        let frameCount = max(2, Int(totalSeconds * sampleFPS))
        var results: [FrameAnalysis] = []
        results.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let t = totalSeconds * Double(i) / Double(frameCount - 1)
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)

            await progress(Double(i) / Double(frameCount))

            guard let cgImage = try? gen.copyCGImage(at: cmTime, actualTime: nil) else { continue }
            let uiImage = UIImage(cgImage: cgImage)
            guard let pb = uiImage.toPixelBuffer() else { continue }

            let frameSize = CGSize(width: CVPixelBufferGetWidth(pb),
                                   height: CVPixelBufferGetHeight(pb))
            let poses = detector.detect(pixelBuffer: pb, intrinsics: embeddedIntrinsics)
            let angles = poses.first.map { computeAngles($0) } ?? []
            results.append(FrameAnalysis(time: t, poses: poses, angles: angles, imageSize: frameSize))
        }

        await progress(1.0)
        return results.sorted { $0.time < $1.time }
    }

    // MARK: - Intrinsics from metadata

    private func loadIntrinsics(from asset: AVURLAsset) async -> Data? {
        guard let items = try? await asset.load(.metadata) else { return nil }
        let key = VideoExporter.intrinsicsMetadataKey
        guard let item = items.first(where: { ($0.key as? String) == key }),
              let base64 = try? await item.load(.stringValue) else { return nil }
        return Data(base64Encoded: base64)
    }

    // MARK: - Angle calculation

    private func computeAngles(_ pose: PoseResult) -> [JointAngle] {
        let kps = pose.keypoints
        func angle(_ a: CocoKeypoint, _ b: CocoKeypoint, _ c: CocoKeypoint, name: String) -> JointAngle {
            let ka = kps[a.rawValue], kb = kps[b.rawValue], kc = kps[c.rawValue]
            let valid = ka.confidence > 0.3 && kb.confidence > 0.3 && kc.confidence > 0.3
            let deg = valid ? angleDeg(ka, kb, kc) : 0
            return JointAngle(name: name, degrees: deg, isValid: valid)
        }
        return [
            angle(.leftShoulder,  .leftElbow,  .leftWrist,  name: "左肘"),
            angle(.rightShoulder, .rightElbow, .rightWrist, name: "右肘"),
            angle(.leftHip,       .leftKnee,   .leftAnkle,  name: "左膝"),
            angle(.rightHip,      .rightKnee,  .rightAnkle, name: "右膝"),
            angle(.leftShoulder,  .leftHip,    .leftKnee,   name: "左髖"),
            angle(.rightShoulder, .rightHip,   .rightKnee,  name: "右髖"),
            angle(.leftElbow,     .leftShoulder, .leftHip,  name: "左肩"),
            angle(.rightElbow,    .rightShoulder, .rightHip, name: "右肩"),
        ]
    }

    private func angleDeg(_ a: Keypoint, _ b: Keypoint, _ c: Keypoint) -> Double {
        // Use 3D world coords when available (more accurate, not affected by viewing angle)
        if let wa = a.worldPos, let wb = b.worldPos, let wc = c.worldPos {
            let v1 = wa - wb
            let v2 = wc - wb
            let mag = simd_length(v1) * simd_length(v2)
            guard mag > 0 else { return 0 }
            let cosA = (simd_dot(v1, v2) / mag).clamped(to: -1...1)
            return acos(Double(cosA)) * 180 / .pi
        }
        // 2D fallback
        let v1x = a.x - b.x, v1y = a.y - b.y
        let v2x = c.x - b.x, v2y = c.y - b.y
        let dot  = v1x * v2x + v1y * v2y
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        guard mag1 > 0, mag2 > 0 else { return 0 }
        let cosA = max(-1, min(1, Double(dot / (mag1 * mag2))))
        return acos(cosA) * 180 / .pi
    }
}

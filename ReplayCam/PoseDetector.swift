import Vision
import UIKit

// MARK: - Data model

struct Keypoint {
    let x: CGFloat          // normalized 0–1, origin top-left (for display)
    let y: CGFloat
    let confidence: Float
    var worldPos: SIMD3<Float>? = nil  // 3D world position in metres (iOS 17+)
}

struct PoseResult {
    let boundingBox: CGRect   // normalized 0–1, origin top-left
    let confidence: Float
    let keypoints: [Keypoint] // 17 COCO keypoints
}

// COCO 17 keypoint indices
enum CocoKeypoint: Int, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

// Skeleton connections to draw
let skeletonEdges: [(CocoKeypoint, CocoKeypoint)] = [
    (.nose,          .leftEye),    (.nose,         .rightEye),
    (.leftEye,       .leftEar),    (.rightEye,     .rightEar),
    (.leftShoulder,  .rightShoulder),
    (.leftShoulder,  .leftElbow),  (.rightShoulder, .rightElbow),
    (.leftElbow,     .leftWrist),  (.rightElbow,    .rightWrist),
    (.leftShoulder,  .leftHip),    (.rightShoulder, .rightHip),
    (.leftHip,       .rightHip),
    (.leftHip,       .leftKnee),   (.rightHip,      .rightKnee),
    (.leftKnee,      .leftAnkle),  (.rightKnee,     .rightAnkle),
]

// MARK: - Joint maps

private let jointMap2D: [(VNHumanBodyPoseObservation.JointName, CocoKeypoint)] = [
    (.nose,          .nose),
    (.leftShoulder,  .leftShoulder),  (.rightShoulder, .rightShoulder),
    (.leftElbow,     .leftElbow),     (.rightElbow,    .rightElbow),
    (.leftWrist,     .leftWrist),     (.rightWrist,    .rightWrist),
    (.leftHip,       .leftHip),       (.rightHip,      .rightHip),
    (.leftKnee,      .leftKnee),      (.rightKnee,     .rightKnee),
    (.leftAnkle,     .leftAnkle),     (.rightAnkle,    .rightAnkle),
]

@available(iOS 17.0, *)
private let jointMap3D: [(VNHumanBodyPose3DObservation.JointName, CocoKeypoint)] = [
    (.centerHead,    .nose),
    (.leftShoulder,  .leftShoulder),  (.rightShoulder, .rightShoulder),
    (.leftElbow,     .leftElbow),     (.rightElbow,    .rightElbow),
    (.leftWrist,     .leftWrist),     (.rightWrist,    .rightWrist),
    (.leftHip,       .leftHip),       (.rightHip,      .rightHip),
    (.leftKnee,      .leftKnee),      (.rightKnee,     .rightKnee),
    (.leftAnkle,     .leftAnkle),     (.rightAnkle,    .rightAnkle),
]

// MARK: - Detector

final class PoseDetector: Sendable {

    private let request2D = VNDetectHumanBodyPoseRequest()

    nonisolated init() {}

    // MARK: - Public

    /// `intrinsics`: Data containing matrix_float3x3 from CMSampleBuffer (live camera).
    /// Pass nil for video frames — intrinsics will be approximated from image size.
    func detect(pixelBuffer: CVPixelBuffer, intrinsics: Data? = nil) -> [PoseResult] {
        let options = handlerOptions(pixelBuffer: pixelBuffer, intrinsics: intrinsics)

        // Always use 2D for accurate skeleton positions
        var results = detect2D(pixelBuffer: pixelBuffer, options: options)

        // On iOS 17+, enrich with 3D world positions for angle calculation
        if #available(iOS 17.0, *) {
            let world = detect3DWorldPositions(pixelBuffer: pixelBuffer, options: options)
            results = merge(results2D: results, world3D: world)
        }

        return results
    }

    // MARK: - Handler options (intrinsics)

    private func handlerOptions(pixelBuffer: CVPixelBuffer, intrinsics: Data?) -> [VNImageOption: Any] {
        if let data = intrinsics {
            // Live camera: use hardware-provided intrinsics
            return [.cameraIntrinsics: data]
        }
        // Video frame: approximate intrinsics from image dimensions
        // iPhone typical horizontal FOV ≈ 65°; fx ≈ w / (2 * tan(32.5°))
        let w = Float(CVPixelBufferGetWidth(pixelBuffer))
        let h = Float(CVPixelBufferGetHeight(pixelBuffer))
        let fx = w / (2 * tan(32.5 * .pi / 180))
        let fy = fx
        // matrix_float3x3 in column-major: [col0, col1, col2]
        var m = matrix_float3x3(0)
        m.columns.0 = SIMD3<Float>(fx,   0,   0)
        m.columns.1 = SIMD3<Float>(0,    fy,  0)
        m.columns.2 = SIMD3<Float>(w/2,  h/2, 1)
        let data = withUnsafeBytes(of: m) { Data($0) }
        return [.cameraIntrinsics: data]
    }

    // MARK: - 2D (accurate skeleton positions)

    private func detect2D(pixelBuffer: CVPixelBuffer,
                          options: [VNImageOption: Any]) -> [PoseResult] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up, options: options)
        try? handler.perform([request2D])
        guard let observations = request2D.results else { return [] }

        return observations.compactMap { obs in
            guard let points = try? obs.recognizedPoints(.all) else { return nil }
            var kps = Array(repeating: Keypoint(x: 0, y: 0, confidence: 0), count: 17)
            for (joint, coco) in jointMap2D {
                guard let pt = points[joint], pt.confidence > 0.1 else { continue }
                kps[coco.rawValue] = Keypoint(x: pt.location.x,
                                              y: 1 - pt.location.y,
                                              confidence: pt.confidence)
            }
            return boundedResult(keypoints: kps, confidence: obs.confidence)
        }
    }

    // MARK: - 3D world positions (iOS 17+ only, for angle calculation)

    @available(iOS 17.0, *)
    private func detect3DWorldPositions(pixelBuffer: CVPixelBuffer,
                                        options: [VNImageOption: Any]) -> [SIMD3<Float>?] {
        let req = VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up, options: options)
        try? handler.perform([req])
        guard let obs = req.results?.first else {
            return Array(repeating: nil, count: 17)
        }

        var world = Array(repeating: Optional<SIMD3<Float>>.none, count: 17)
        for (joint, coco) in jointMap3D {
            // cameraRelativePosition gives position in camera space, so body rotation
            // is reflected correctly in XZ — unlike pt.position which is body-local.
            guard let matrix = try? obs.cameraRelativePosition(joint) else { continue }
            let t = matrix.columns.3
            world[coco.rawValue] = SIMD3<Float>(t.x, t.y, t.z)
        }
        return world
    }

    // MARK: - Merge 2D positions + 3D world coords

    @available(iOS 17.0, *)
    private func merge(results2D: [PoseResult],
                       world3D: [SIMD3<Float>?]) -> [PoseResult] {
        results2D.map { pose in
            let enriched = pose.keypoints.enumerated().map { idx, kp in
                Keypoint(x: kp.x, y: kp.y,
                         confidence: kp.confidence,
                         worldPos: world3D[idx])
            }
            return PoseResult(boundingBox: pose.boundingBox,
                              confidence: pose.confidence,
                              keypoints: enriched)
        }
    }

    // MARK: - Shared

    private func boundedResult(keypoints kps: [Keypoint],
                               confidence: VNConfidence) -> PoseResult? {
        let valid = kps.filter { $0.confidence > 0.1 }
        guard !valid.isEmpty else { return nil }
        let minX = valid.map(\.x).min()!
        let minY = valid.map(\.y).min()!
        let maxX = valid.map(\.x).max()!
        let maxY = valid.map(\.y).max()!
        return PoseResult(
            boundingBox: CGRect(x: minX, y: minY,
                                width: maxX - minX, height: maxY - minY),
            confidence: confidence,
            keypoints: kps
        )
    }
}

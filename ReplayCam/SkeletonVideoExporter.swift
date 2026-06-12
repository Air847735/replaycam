import AVFoundation
import CoreGraphics
import Photos
import UIKit

enum SkeletonVideoExporter {

    static func export(url: URL, analyses: [FrameAnalysis],
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let videoSize = naturalSize.applying(preferredTransform)
        let outputSize = CGSize(width: abs(videoSize.width), height: abs(videoSize.height))

        // Reader
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ExportError.readerSetupFailed }
        reader.add(readerOutput)

        // Writer
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skeleton_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )
        guard writer.canAdd(writerInput) else { throw ExportError.writerSetupFailed }
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = duration.seconds

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writerInput.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                while writerInput.isReadyForMoreMediaData {
                    guard reader.status == .reading,
                          let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                cont.resume()
                            } else {
                                cont.resume(throwing: writer.error ?? ExportError.writeFailed)
                            }
                        }
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let t = pts.seconds
                    if totalSeconds > 0 { progress(t / totalSeconds) }

                    // Find nearest analysis frame
                    let analysis = analyses.min(by: { abs($0.time - t) < abs($1.time - t) })

                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                    // Composite skeleton onto frame
                    if let analysis, let pose = analysis.poses.first,
                       let composited = drawSkeleton(pose, onto: imageBuffer,
                                                     imageSize: analysis.imageSize,
                                                     outputSize: outputSize) {
                        adaptor.append(composited, withPresentationTime: pts)
                    } else {
                        adaptor.append(imageBuffer, withPresentationTime: pts)
                    }
                }
            }
        }

        guard writer.status == .completed else {
            throw writer.error ?? ExportError.writeFailed
        }
        return outURL
    }

    // MARK: - Draw skeleton onto a pixel buffer

    private static func drawSkeleton(_ pose: PoseResult,
                                     onto srcBuffer: CVImageBuffer,
                                     imageSize: CGSize,
                                     outputSize: CGSize) -> CVPixelBuffer? {
        // Create output pixel buffer
        var outBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault,
                                  Int(outputSize.width), Int(outputSize.height),
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                                  &outBuffer) == kCVReturnSuccess,
              let outBuffer else { return nil }

        CVPixelBufferLockBaseAddress(srcBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(outBuffer, [])
            CVPixelBufferUnlockBaseAddress(srcBuffer, .readOnly)
        }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(outBuffer),
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(outBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Draw source frame
        let ciImage = CIImage(cvPixelBuffer: srcBuffer)
        let ciCtx = CIContext()
        if let cgImg = ciCtx.createCGImage(ciImage, from: ciImage.extent) {
            ctx.draw(cgImg, in: CGRect(origin: .zero, size: outputSize))
        }

        // Flip coordinate system (CoreGraphics origin is bottom-left, video is top-left)
        ctx.translateBy(x: 0, y: outputSize.height)
        ctx.scaleBy(x: 1, y: -1)

        let kps = pose.keypoints
        let scaleX = outputSize.width
        let scaleY = outputSize.height

        func pt(_ kp: Keypoint) -> CGPoint {
            CGPoint(x: kp.x * scaleX, y: kp.y * scaleY)
        }

        // Draw edges
        for (a, b) in skeletonEdges {
            let ka = kps[a.rawValue], kb = kps[b.rawValue]
            guard ka.confidence >= 0.25, kb.confidence >= 0.25 else { continue }
            let left: Set<CocoKeypoint> = [.leftEye, .leftEar, .leftShoulder, .leftElbow,
                                           .leftWrist, .leftHip, .leftKnee, .leftAnkle]
            let right: Set<CocoKeypoint> = [.rightEye, .rightEar, .rightShoulder, .rightElbow,
                                            .rightWrist, .rightHip, .rightKnee, .rightAnkle]
            let color: CGColor
            if left.contains(a) || left.contains(b) {
                color = UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.9).cgColor
            } else if right.contains(a) || right.contains(b) {
                color = UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.9).cgColor
            } else {
                color = UIColor.yellow.withAlphaComponent(0.9).cgColor
            }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(4)
            ctx.move(to: pt(ka))
            ctx.addLine(to: pt(kb))
            ctx.strokePath()
        }

        // Draw joints
        for kp in kps {
            guard kp.confidence >= 0.25 else { continue }
            let p = pt(kp)
            let r: CGFloat = 5
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2))
        }

        return outBuffer
    }

    // MARK: - Save to photo library

    static func saveToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.noPhotoPermission
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    enum ExportError: LocalizedError {
        case noVideoTrack, readerSetupFailed, writerSetupFailed, writeFailed, noPhotoPermission
        var errorDescription: String? {
            switch self {
            case .noVideoTrack:       return "找不到影片軌道"
            case .readerSetupFailed:  return "無法建立影片讀取器"
            case .writerSetupFailed:  return "無法建立影片寫入器"
            case .writeFailed:        return "影片寫入失敗"
            case .noPhotoPermission:  return "需要相簿權限才能儲存"
            }
        }
    }
}

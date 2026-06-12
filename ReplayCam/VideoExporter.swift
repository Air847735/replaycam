import AVFoundation
import Photos
import UIKit

enum VideoExporter {
    private static let portraitSize  = CGSize(width: 1080, height: 1920)
    private static let landscapeSize = CGSize(width: 1920, height: 1080)

    static let intrinsicsMetadataKey = "com.replaycam.cameraIntrinsics"

    static func export(frames: [TimestampedFrame], fps: Int32 = 30,
                       intrinsics: Data? = nil) async throws -> URL {
        let firstSize = UIImage(data: frames[0].jpegData)?.size ?? CGSize(width: 1080, height: 1920)
        let exportSize = firstSize.width > firstSize.height ? landscapeSize : portraitSize

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        nonisolated(unsafe) let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(exportSize.width),
            AVVideoHeightKey: Int(exportSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]
        ])
        videoInput.expectsMediaDataInRealTime = false

        nonisolated(unsafe) let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(exportSize.width),
                kCVPixelBufferHeightKey as String: Int(exportSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        // Embed camera intrinsics in video metadata so VideoAnalyzer can use them
        if let data = intrinsics {
            let item = AVMutableMetadataItem()
            item.keySpace = AVMetadataKeySpace.quickTimeMetadata
            item.key      = Self.intrinsicsMetadataKey as NSString
            item.value    = data.base64EncodedString() as NSString
            writer.metadata = [item]
        }

        guard writer.canAdd(videoInput) else { throw ExportError.cannotAddInput }
        writer.add(videoInput)
        guard writer.startWriting() else { throw writer.error ?? ExportError.startFailed }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var index = 0
            var done  = false
            videoInput.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                while videoInput.isReadyForMoreMediaData {
                    guard index < frames.count else {
                        guard !done else { return }
                        done = true
                        videoInput.markAsFinished()
                        cont.resume()
                        return
                    }
                    let frame = frames[index]
                    let time  = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                    index += 1
                    autoreleasepool {
                        guard let image = UIImage(data: frame.jpegData)?.resizedExact(to: exportSize),
                              let pb    = image.toPixelBuffer() else { return }
                        adaptor.append(pb, withPresentationTime: time)
                    }
                }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? ExportError.exportFailed
        }
        return url
    }

    static func moveToClipsDirectory(from tempURL: URL) throws -> URL {
        let dir = ClipStore.clipsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(tempURL.lastPathComponent)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    static func saveToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.noPhotoLibraryPermission
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    enum ExportError: LocalizedError {
        case cannotAddInput, startFailed, exportFailed, noPhotoLibraryPermission
        var errorDescription: String? {
            switch self {
            case .cannotAddInput:          return "無法建立影片輸入"
            case .startFailed:             return "無法開始寫入"
            case .exportFailed:            return "影片匯出失敗"
            case .noPhotoLibraryPermission: return "需要相簿權限才能儲存"
            }
        }
    }
}

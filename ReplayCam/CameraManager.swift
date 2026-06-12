import AVFoundation
import Combine
import UIKit

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var realtimeImage: UIImage?
    @Published var delayedImage: UIImage?
    @Published var isRunning = false
    @Published var isSaving = false
    @Published var bufferFrameCount = 0
    @Published var bufferDuration: TimeInterval = 0
    @Published var errorMessage = ""
    @Published var showSuccess = false

    private let frameBuffer = FrameBuffer()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated(unsafe) private var lastRealtimeUpdate: TimeInterval = 0
    nonisolated(unsafe) private var lastDelayedUpdate: TimeInterval = 0
    nonisolated(unsafe) var delaySeconds: Double = 3.0
    nonisolated(unsafe) private var videoConnection: AVCaptureConnection?
    nonisolated(unsafe) private var frameCount = 0
    nonisolated(unsafe) var targetFPS: Int32 = 30
    nonisolated(unsafe) var cameraPosition: AVCaptureDevice.Position = .back

    @Published var currentPosition: AVCaptureDevice.Position = .back

    // Pose detection
    @Published var poseResults: [PoseResult] = []
    @Published var poseFrameSize: CGSize = .zero
    nonisolated(unsafe) var poseEnabled: Bool = false
    nonisolated(unsafe) private var latestIntrinsics: Data? = nil
    private let poseDetector = PoseDetector()

    private static let jpegQualityKey = CIImageRepresentationOption(
        rawValue: kCGImageDestinationLossyCompressionQuality as String
    )

    private let realtimeInterval: TimeInterval = 1.0 / 15.0
    private let delayedInterval:  TimeInterval = 1.0 / 25.0
    private let decodeQueue  = DispatchQueue(label: "com.replaycam.decode",  qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "com.replaycam.session", qos: .userInitiated)
    private let frameQueue   = DispatchQueue(label: "com.replaycam.frames",  qos: .userInteractive)
    private var captureSession: AVCaptureSession?
    private var bufferTimer: AnyCancellable?
    private var orientationObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?

    // MARK: - Public API

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    setupCamera()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { setupCamera() } else { errorMessage = "需要相機權限才能使用" }
            }
        case .denied:        errorMessage = "請到設定中開啟相機權限"
        case .restricted:    errorMessage = "相機權限受限"
        @unknown default:    break
        }
    }

    func setDelay(_ seconds: Double) {
        delaySeconds = seconds
        if seconds > frameBuffer.duration { delayedImage = nil }
    }

    func saveRecentFrames(duration: TimeInterval) {
        guard !isSaving else { return }
        let now = Date().timeIntervalSince1970
        let frames = frameBuffer.frames(since: now - duration)
        guard !frames.isEmpty else { return }

        isSaving = true
        let capturedIntrinsics = latestIntrinsics
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let tempURL = try await VideoExporter.export(
                    frames: frames,
                    fps: self?.targetFPS ?? 30,
                    intrinsics: capturedIntrinsics
                )
                let _ = try VideoExporter.moveToClipsDirectory(from: tempURL)
                await MainActor.run {
                    ClipStore.shared.refresh()
                    self?.isSaving = false
                    self?.showSuccess = true
                }
            } catch {
                print("❌ 儲存失敗: \(error.localizedDescription)")
                await MainActor.run { self?.isSaving = false }
            }
        }
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = newPosition
        captureSession?.stopRunning()
        captureSession = nil
        frameBuffer.trimToLastSeconds(0)
        setupCamera()
        Task { @MainActor in currentPosition = newPosition }
    }

    func applyFPSSetting(_ fps: Int) {
        targetFPS = Int32(fps)
        switch fps {
        case 120:
            frameBuffer.maxDuration = 20.0
            frameBuffer.earlyPurgeThreshold = 2400
        case 60:
            frameBuffer.maxDuration = 30.0
            frameBuffer.earlyPurgeThreshold = 1800
        default:
            frameBuffer.maxDuration = 35.0
            frameBuffer.earlyPurgeThreshold = 1200
        }
    }

    // MARK: - Private

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high

            let position = self.cameraPosition
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                let input  = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                Task { @MainActor in self.errorMessage = "找不到相機" }
                return
            }
            session.addInput(input)

            let fps = self.targetFPS
            if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
                let supportedFormat = device.formats.last { format in
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
                }
                try? device.lockForConfiguration()
                if let format = supportedFormat, fps > 30 { device.activeFormat = format }
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: fps)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: fps)
                device.unlockForConfiguration()
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.frameQueue)

            guard session.canAddOutput(output) else {
                Task { @MainActor in self.errorMessage = "無法建立影片輸出" }
                return
            }
            session.addOutput(output)

            if let conn = output.connection(with: .video) {
                self.videoConnection = conn
                // Enable intrinsics delivery on the connection (for 3D pose accuracy)
                if conn.isCameraIntrinsicMatrixDeliverySupported {
                    conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = self.avOrientation(for: UIDevice.current.orientation)
                }
            }

            session.commitConfiguration()
            self.captureSession = session
            session.startRunning()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRunning = true
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                self.orientationObserver = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    guard let self, let conn = self.videoConnection else { return }
                    let o = UIDevice.current.orientation
                    if o.isValidInterfaceOrientation { conn.videoOrientation = self.avOrientation(for: o) }
                }
                self.bufferTimer = Timer.publish(every: 0.5, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        self.bufferFrameCount = self.frameBuffer.count
                        self.bufferDuration   = self.frameBuffer.duration
                    }
                self.memoryObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    self?.frameBuffer.trimToLastSeconds(15)
                    self?.ciContext.clearCaches()
                }
            }
        }
    }

    private func avOrientation(for o: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .landscapeLeft:      return .landscapeRight
        case .landscapeRight:     return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default:                  return .portrait
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Extract camera intrinsics from sample buffer (available when enabled on output)
        if let intrinsicData = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data {
            latestIntrinsics = intrinsicData
        }

        let now = Date().timeIntervalSince1970
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let jpeg = ciContext.jpegRepresentation(
            of: ciImage, colorSpace: colorSpace,
            options: [Self.jpegQualityKey: 0.45]
        ) else { return }
        frameBuffer.append(TimestampedFrame(jpegData: jpeg, timestamp: now))

        frameCount += 1
        if frameCount % 300 == 0 { ciContext.clearCaches() }

        if now - lastRealtimeUpdate >= realtimeInterval {
            lastRealtimeUpdate = now
            autoreleasepool {
                let extent = ciImage.extent
                let scale = 600.0 / max(extent.width, extent.height)
                let small = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let cg = ciContext.createCGImage(small, from: small.extent) {
                    let thumb = UIImage(cgImage: cg)
                    Task { @MainActor [weak self] in self?.realtimeImage = thumb }
                }
            }
        }

        if now - lastDelayedUpdate >= delayedInterval {
            lastDelayedUpdate = now
            let target = now - delaySeconds
            if let frame = frameBuffer.findFrame(nearTimestamp: target) {
                let runPose = poseEnabled
                decodeQueue.async { [weak self] in
                    guard let self else { return }
                    autoreleasepool {
                        guard let delayed = UIImage(data: frame.jpegData)?.resizedFit(maxDimension: 960) else { return }
                        Task { @MainActor in self.delayedImage = delayed }

                        if runPose,
                           let src = UIImage(data: frame.jpegData),
                           let pb = src.toPixelBuffer() {
                            let sz = CGSize(width: CVPixelBufferGetWidth(pb),
                                           height: CVPixelBufferGetHeight(pb))
                            let intrinsics = self.latestIntrinsics
                            let results = self.poseDetector.detect(pixelBuffer: pb,
                                                                   intrinsics: intrinsics)
                            Task { @MainActor in
                                self.poseResults   = results
                                self.poseFrameSize = sz
                            }
                        }
                    }
                }
            }
        }
    }
}

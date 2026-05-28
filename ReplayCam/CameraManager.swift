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

    // These are written/read from the serial frameQueue inside nonisolated captureOutput.
    // FrameBuffer is NSLock-backed. CIContext is thread-safe by design.
    // Timestamp vars are only touched from frameQueue (serial), so there is no contention.
    // delaySeconds is written from MainActor and read from frameQueue; a Double read-write
    // race is benign here (worst case: one frame uses a stale delay value).
    nonisolated(unsafe) private let frameBuffer = FrameBuffer()
    nonisolated(unsafe) private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated(unsafe) private var lastRealtimeUpdate: TimeInterval = 0
    nonisolated(unsafe) private var lastDelayedUpdate: TimeInterval = 0
    nonisolated(unsafe) var delaySeconds: Double = 3.0
    // Written once from sessionQueue during setup, read from main thread — safe in practice.
    nonisolated(unsafe) private var videoConnection: AVCaptureConnection?

    private let realtimeInterval: TimeInterval = 1.0 / 15.0
    private let delayedInterval: TimeInterval = 1.0 / 25.0
    private let sessionQueue = DispatchQueue(label: "com.replaycam.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "com.replaycam.frames", qos: .userInteractive)
    private var captureSession: AVCaptureSession?
    private var bufferTimer: AnyCancellable?
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Public API

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { setupCamera() } else { errorMessage = "需要相機權限才能使用" }
            }
        case .denied:
            errorMessage = "請到設定中開啟相機權限"
        case .restricted:
            errorMessage = "相機權限受限"
        @unknown default:
            break
        }
    }

    func setDelay(_ seconds: Double) {
        delaySeconds = seconds
    }

    func saveRecentFrames(duration: TimeInterval) {
        guard !isSaving else { return }
        let now = Date().timeIntervalSince1970
        let frames = frameBuffer.frames(since: now - duration)
        guard !frames.isEmpty else { return }

        isSaving = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = try await VideoExporter.export(frames: frames)
                try await VideoExporter.saveToPhotoLibrary(url: url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { self?.isSaving = false; self?.showSuccess = true }
            } catch {
                print("❌ 儲存失敗: \(error.localizedDescription)")
                await MainActor.run { self?.isSaving = false }
            }
        }
    }

    // MARK: - Private

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                Task { @MainActor in self.errorMessage = "找不到後置相機" }
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.frameQueue)

            guard session.canAddOutput(output) else {
                Task { @MainActor in self.errorMessage = "無法建立影片輸出" }
                return
            }
            session.addOutput(output)

            if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
                self.videoConnection = conn
                conn.videoOrientation = self.avOrientation(for: UIDevice.current.orientation)
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
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self, let conn = self.videoConnection else { return }
                    let o = UIDevice.current.orientation
                    if o.isValidInterfaceOrientation {
                        conn.videoOrientation = self.avOrientation(for: o)
                    }
                }
                self.bufferTimer = Timer.publish(every: 0.5, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        self.bufferFrameCount = self.frameBuffer.count
                        self.bufferDuration = self.frameBuffer.duration
                    }
            }
        }
    }

    private func avOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft:       return .landscapeRight
        case .landscapeRight:      return .landscapeLeft
        case .portraitUpsideDown:  return .portraitUpsideDown
        default:                   return .portrait
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
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = Date().timeIntervalSince1970
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let fullImage = UIImage(cgImage: cgImage)

        guard let jpeg = fullImage.jpegData(compressionQuality: 0.6) else { return }
        frameBuffer.append(TimestampedFrame(jpegData: jpeg, timestamp: now))

        if now - lastRealtimeUpdate >= realtimeInterval {
            lastRealtimeUpdate = now
            let thumb = fullImage.resized(to: CGSize(width: 200, height: 150))
            Task { @MainActor [weak self] in self?.realtimeImage = thumb }
        }

        if now - lastDelayedUpdate >= delayedInterval {
            lastDelayedUpdate = now
            let target = now - delaySeconds
            if let frame = frameBuffer.findFrame(nearTimestamp: target),
               let delayed = UIImage(data: frame.jpegData)?
                .resizedFit(maxDimension: 1080) {
                Task { @MainActor [weak self] in self?.delayedImage = delayed }
            }
        }
    }
}

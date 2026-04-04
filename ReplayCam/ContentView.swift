/*
import SwiftUI
import AVFoundation
import Combine
import Photos

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedDelay: Double = 3.0
    
    let delayOptions = [1.0, 3.0, 5.0, 10.0, 15.0]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // 主畫面 - 延遲畫面
                Group {
                    if let delayedImage = cameraManager.delayedImage {
                        Image(uiImage: delayedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .ignoresSafeArea()
                
                // UI 控制層
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        // 即時畫面
                        VStack(spacing: 8) {
                            Group {
                                if let realtimeImage = cameraManager.realtimeImage {
                                    Image(uiImage: realtimeImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.gray
                                }
                            }
                            .frame(width: 200, height: 150)
                            .clipped()
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.yellow, lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 10)
                            
                            Text("即時畫面")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        .padding(20)
                        .zIndex(100)
                    }
                    
                    // 控制面板
                    HStack(spacing: 20) {
                        Menu {
                            ForEach(delayOptions, id: \.self) { delay in
                                Button(action: {
                                    selectedDelay = delay
                                    cameraManager.setDelay(delay)
                                }) {
                                    HStack {
                                        Text("\(Int(delay)) 秒")
                                        if delay == selectedDelay {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                Text("延遲: \(Int(selectedDelay))秒")
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .opacity(cameraManager.isRecording ? 0.5 : 1.0)
                        }
                        .disabled(cameraManager.isRecording)
                        
                        Button(action: {
                            if cameraManager.isRecording {
                                cameraManager.stopRecording()
                            } else {
                                cameraManager.startRecording()
                            }
                        }) {
                            HStack {
                                Image(systemName: cameraManager.isRecording ? "stop.circle.fill" : "record.circle")
                                Text(cameraManager.isRecording ? "停止錄影" : "開始錄影")
                            }
                            .padding()
                            .background(cameraManager.isRecording ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RT: \(cameraManager.realtimeImage != nil ? "✓" : "✗") DL: \(cameraManager.delayedImage != nil ? "✓" : "✗")")
                            if cameraManager.isRecording {
                                Text("錄影: \(String(format: "%.1f", cameraManager.recordingDuration))s (\(cameraManager.frameCounter)幀)")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    }
                    .padding(.bottom, 30)
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            cameraManager.setDelay(selectedDelay)
            cameraManager.checkPermissions()
            cameraManager.startCamera()
        }
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var realtimeImage: UIImage?
    @Published var delayedImage: UIImage?
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var frameCounter: Int = 0
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let frameQueue = DispatchQueue(label: "camera.frame.queue")
    
    private var frameBuffer: [TimestampedFrame] = []
    private var delaySeconds: Double = 3.0
    private var frameCount = 0
    
    // 錄影相關
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: Date?
    private var isWriting = false
    private var recordingTimer: Timer?
    private var lastFrameTime: CMTime = .zero
    
    struct TimestampedFrame {
        let image: UIImage
        let timestamp: TimeInterval
    }
    
    func setDelay(_ seconds: Double) {
        delaySeconds = seconds
        print("設定延遲: \(seconds)秒")
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCamera()
                }
            }
        default:
            break
        }
    }
    
    func startCamera() {
        if captureSession == nil {
            setupCamera()
        } else {
            sessionQueue.async {
                self.captureSession?.startRunning()
            }
        }
        isRunning = true
    }
    
    func stopCamera() {
        sessionQueue.async {
            self.captureSession?.stopRunning()
        }
        isRunning = false
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        print("\n=== 開始錄影 ===")
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        frameCounter = 0
        lastFrameTime = .zero
        
        DispatchQueue.main.async {
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
        
        setupVideoWriter()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        print("\n=== 停止錄影 ===")
        print("總錄製幀數: \(frameCounter)")
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        finishRecording()
    }
    
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.frameQueue)
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            // 設定影片方向
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            session.commitConfiguration()
            
            self.captureSession = session
            self.videoOutput = output
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
            
            session.startRunning()
        }
    }
    
    private func setupVideoWriter() {
        let outputFileName = "replay_\(Date().timeIntervalSince1970).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        print("📹 設定 VideoWriter: \(outputFileName)")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // 使用直向比例 (9:16)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1080,  // 直向寬度
                AVVideoHeightKey: 1920  // 直向高度
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = false
            
            // 設定影片為直向
            videoInput?.transform = CGAffineTransform(rotationAngle: 0)
            
            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 1080,  // 直向寬度
                kCVPixelBufferHeightKey as String: 1920  // 直向高度
            ]
            
            guard let videoInput = videoInput else {
                print("❌ videoInput 是 nil")
                return
            }
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            guard assetWriter?.canAdd(videoInput) == true else {
                print("❌ 無法加入 VideoInput")
                return
            }
            
            assetWriter?.add(videoInput)
            
            guard assetWriter?.startWriting() == true else {
                print("❌ startWriting 失敗")
                if let error = assetWriter?.error {
                    print("❌ 錯誤: \(error.localizedDescription)")
                }
                return
            }
            
            assetWriter?.startSession(atSourceTime: .zero)
            isWriting = true
            print("✅ VideoWriter 準備完成 (1080x1920 直向)\n")
            
        } catch {
            print("❌ Exception: \(error.localizedDescription)")
        }
    }
    
    private func finishRecording() {
        guard let assetWriter = assetWriter, isWriting else {
            print("❌ 沒有進行中的錄影")
            return
        }
        
        isWriting = false
        videoInput?.markAsFinished()
        
        assetWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            
            if assetWriter.status == .completed {
                let outputURL = assetWriter.outputURL
                print("✅ 錄影完成: \(outputURL.lastPathComponent)")
                self.saveVideoToPhotoLibrary(url: outputURL)
            } else if assetWriter.status == .failed {
                print("❌ 錄影失敗: \(assetWriter.error?.localizedDescription ?? "未知")")
            } else {
                print("❌ 錄影狀態異常: \(assetWriter.status.rawValue)")
            }
            
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
        }
    }
    
    private func saveVideoToPhotoLibrary(url: URL) {
        print("💾 請求相簿權限...")
        PHPhotoLibrary.requestAuthorization { status in
            print("📱 相簿權限: \(status.rawValue)")
            guard status == .authorized else {
                print("❌ 沒有相簿權限")
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if success {
                    print("✅ 影片已儲存到相簿")
                } else {
                    print("❌ 儲存失敗: \(error?.localizedDescription ?? "未知")")
                }
                
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        let currentTime = Date().timeIntervalSince1970
        
        frameCount += 1
        
        if frameCount % 30 == 0 {
            print("📷 已處理 \(frameCount) 幀")
        }
        
        // 更新即時畫面
        DispatchQueue.main.async { [weak self] in
            self?.realtimeImage = image
        }
        
        // 加入緩衝區
        let frame = TimestampedFrame(image: image, timestamp: currentTime)
        frameBuffer.append(frame)
        
        // 清理過舊的幀
        let cutoffTime = currentTime - (delaySeconds + 3.0)
        frameBuffer.removeAll { $0.timestamp < cutoffTime }
        
        // 尋找延遲畫面
        let targetTime = currentTime - delaySeconds
        var closestFrame: TimestampedFrame?
        var minDiff = Double.infinity
        
        for frame in frameBuffer {
            let diff = abs(frame.timestamp - targetTime)
            if diff < minDiff {
                minDiff = diff
                closestFrame = frame
            }
        }
        
        // 更新延遲畫面並錄影
        if let frame = closestFrame, minDiff < 0.2 {
            DispatchQueue.main.async { [weak self] in
                self?.delayedImage = frame.image
            }
            
            if isRecording, isWriting {
                writeFrame(image: frame.image)
            }
        }
    }
    
    private func writeFrame(image: UIImage) {
        guard isWriting,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              let videoInput = videoInput else {
            return
        }
        
        guard videoInput.isReadyForMoreMediaData else {
            return
        }
        
        // 使用直向尺寸 1080x1920
        guard let pixelBuffer = image.pixelBuffer(width: 1080, height: 1920) else {
            print("❌ PixelBuffer 轉換失敗")
            return
        }
        
        // 使用遞增的時間戳
        let frameDuration = CMTime(value: 1, timescale: 30)
        let presentationTime = CMTimeAdd(lastFrameTime, frameDuration)
        
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameCounter += 1
            lastFrameTime = presentationTime
        } else {
            print("❌ append 失敗 - 幀 #\(frameCounter + 1)")
            if let error = assetWriter?.error {
                print("   錯誤: \(error.localizedDescription)")
                print("   狀態: \(assetWriter?.status.rawValue ?? -1)")
            }
        }
    }
}

extension UIImage {
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        return buffer
    }
}
*/
import SwiftUI
import AVFoundation
import Combine
import Photos

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedDelay: Double = 3.0
    @State private var showSaveOptions = false
    
    let delayOptions = [1.0, 3.0, 5.0, 10.0, 15.0, 30.0]
    let saveOptions = [5.0, 10.0, 15.0, 30.0]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 主畫面 - 延遲畫面
                Group {
                    if let delayedImage = cameraManager.delayedImage {
                        Image(uiImage: delayedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                            .overlay(
                                VStack {
                                    if cameraManager.isRunning {
                                        ProgressView()
                                            .scaleEffect(2)
                                            .tint(.white)
                                        Text("載入中...")
                                            .foregroundColor(.white)
                                            .padding(.top)
                                    } else {
                                        Text("相機未啟動")
                                            .foregroundColor(.white)
                                        Text(cameraManager.errorMessage)
                                            .foregroundColor(.red)
                                            .font(.caption)
                                            .padding()
                                    }
                                }
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .ignoresSafeArea()
                
                // UI 控制層
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        // 即時畫面
                        VStack(spacing: 8) {
                            Group {
                                if let realtimeImage = cameraManager.realtimeImage {
                                    Image(uiImage: realtimeImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.gray
                                        .overlay(
                                            ProgressView()
                                                .tint(.white)
                                        )
                                }
                            }
                            .frame(width: 200, height: 150)
                            .clipped()
                            .background(Color.black)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.yellow, lineWidth: 3)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 10)
                            
                            Text("即時畫面")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        .padding(20)
                    }
                    
                    // 控制面板
                    VStack(spacing: 15) {
                        // 第一排：控制項
                        HStack(spacing: 20) {
                            Menu {
                                ForEach(delayOptions, id: \.self) { delay in
                                    Button(action: {
                                        selectedDelay = delay
                                        cameraManager.setDelay(delay)
                                    }) {
                                        HStack {
                                            Text("\(Int(delay)) 秒")
                                            if delay == selectedDelay {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("延遲: \(Int(selectedDelay))秒")
                                }
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("緩衝: \(String(format: "%.1f", cameraManager.bufferDuration))秒")
                                Text("幀數: \(cameraManager.bufferFrameCount)")
                                if cameraManager.isSaving {
                                    Text("儲存中...")
                                        .foregroundColor(.green)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        }
                        
                        // 第二排：儲存按鈕（獨立一排）
                        Button(action: {
                            print("🔘 按鈕被點擊！")
                            print("📊 bufferFrameCount: \(cameraManager.bufferFrameCount)")
                            print("📊 bufferDuration: \(cameraManager.bufferDuration)")
                            showSaveOptions = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                                Text("儲存影片 (\(cameraManager.bufferFrameCount)幀)")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Group {
                                    if cameraManager.isSaving {
                                        Color.orange
                                    } else if cameraManager.bufferFrameCount < 10 {
                                        Color.gray
                                    } else {
                                        Color.blue
                                    }
                                }
                            )
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                        }
                        .disabled(cameraManager.isSaving || cameraManager.bufferFrameCount < 10)
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            print("🟢 ContentView appeared")
            cameraManager.setDelay(selectedDelay)
            cameraManager.checkPermissions()
        }
        .confirmationDialog("選擇要儲存的長度", isPresented: $showSaveOptions, titleVisibility: .visible) {
            ForEach(saveOptions, id: \.self) { duration in
                Button("最近 \(Int(duration)) 秒") {
                    print("⏺️ 選擇儲存 \(Int(duration)) 秒")
                    cameraManager.saveRecentFrames(duration: duration)
                }
            }
            Button("取消", role: .cancel) {
                print("❌ 取消儲存")
            }
        } message: {
            Text("選擇要儲存的影片長度")
        }
        .alert("儲存成功", isPresented: $cameraManager.showSuccess) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("影片已成功儲存到相簿")
        }
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var realtimeImage: UIImage?
    @Published var delayedImage: UIImage?
    @Published var isRunning = false
    @Published var isSaving = false
    @Published var bufferDuration: TimeInterval = 0
    @Published var bufferFrameCount: Int = 0
    @Published var errorMessage = ""
    @Published var showSuccess = false
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let frameQueue = DispatchQueue(label: "camera.frame.queue", qos: .userInteractive)
    
    // 使用 JPEG 壓縮節省記憶體
    private var frameBuffer: [TimestampedFrame] = []
    private var delaySeconds: Double = 3.0
    private var frameCount = 0
    private let maxBufferDuration: Double = 30.0
    
    private var updateTimer: Timer?
    
    // UI 更新節流
    private var lastRealtimeUpdate: TimeInterval = 0
    private var lastDelayedUpdate: TimeInterval = 0
    private let realtimeUpdateInterval: TimeInterval = 1.0 / 15.0
    private let delayedUpdateInterval: TimeInterval = 1.0 / 25.0
    
    struct TimestampedFrame {
        let jpegData: Data
        let timestamp: TimeInterval
    }
    
    func setDelay(_ seconds: Double) {
        delaySeconds = seconds
        print("🕐 設定延遲: \(seconds)秒")
    }
    
    func checkPermissions() {
        print("🔍 檢查相機權限...")
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("📸 目前權限狀態: \(status.rawValue)")
        
        switch status {
        case .authorized:
            print("✅ 已授權，啟動相機")
            setupCamera()
        case .notDetermined:
            print("❓ 未決定，請求權限")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print("📸 權限結果: \(granted)")
                if granted {
                    self?.setupCamera()
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "需要相機權限才能使用"
                    }
                }
            }
        case .denied:
            print("❌ 權限被拒絕")
            DispatchQueue.main.async {
                self.errorMessage = "請到設定中開啟相機權限"
            }
        case .restricted:
            print("❌ 權限受限")
            DispatchQueue.main.async {
                self.errorMessage = "相機權限受限"
            }
        @unknown default:
            print("❌ 未知權限狀態")
            DispatchQueue.main.async {
                self.errorMessage = "未知的權限狀態"
            }
        }
    }
    
    func startCamera() {
        print("🎥 嘗試啟動相機...")
        if captureSession == nil {
            setupCamera()
        } else {
            sessionQueue.async {
                if !(self.captureSession?.isRunning ?? false) {
                    print("▶️ 啟動現有 session")
                    self.captureSession?.startRunning()
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isRunning = true
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateBufferInfo()
            }
        }
    }
    
    func stopCamera() {
        print("⏹️ 停止相機")
        sessionQueue.async {
            self.captureSession?.stopRunning()
        }
        isRunning = false
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateBufferInfo() {
        guard !frameBuffer.isEmpty else {
            bufferDuration = 0
            bufferFrameCount = 0
            return
        }
        
        let now = Date().timeIntervalSince1970
        let oldestTime = frameBuffer.first?.timestamp ?? now
        bufferDuration = now - oldestTime
        bufferFrameCount = frameBuffer.count
    }
    
    func saveRecentFrames(duration: TimeInterval) {
        print("\n🎬 === 開始儲存流程 ===")
        print("📊 isSaving: \(isSaving)")
        print("📊 frameBuffer.count: \(frameBuffer.count)")
        
        guard !isSaving else {
            print("❌ 已經在儲存中")
            return
        }
        
        guard !frameBuffer.isEmpty else {
            print("❌ 緩衝區為空")
            return
        }
        
        DispatchQueue.main.async {
            self.isSaving = true
        }
        
        let now = Date().timeIntervalSince1970
        let startTime = now - duration
        
        let framesToSave = frameBuffer.filter { $0.timestamp >= startTime }
        
        print("📊 需要儲存的幀數: \(framesToSave.count)")
        
        guard !framesToSave.isEmpty else {
            print("❌ 沒有足夠的幀可以儲存")
            DispatchQueue.main.async {
                self.isSaving = false
            }
            return
        }
        
        print("✅ 開始匯出影片...")
        print("   目標時長: \(duration) 秒")
        print("   實際幀數: \(framesToSave.count)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.exportVideo(frames: framesToSave, duration: duration)
        }
    }
    
    private func exportVideo(frames: [TimestampedFrame], duration: TimeInterval) {
        let outputFileName = "replay_\(Date().timeIntervalSince1970).mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        print("📁 輸出路徑: \(outputURL.path)")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1080,
                AVVideoHeightKey: 1920,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 5_000_000
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = false
            
            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 1080,
                kCVPixelBufferHeightKey as String: 1920,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            guard assetWriter.canAdd(videoInput) else {
                print("❌ 無法加入 VideoInput")
                self.finishSaving()
                return
            }
            
            assetWriter.add(videoInput)
            
            guard assetWriter.startWriting() else {
                print("❌ startWriting 失敗")
                self.finishSaving()
                return
            }
            
            assetWriter.startSession(atSourceTime: .zero)
            print("✅ AssetWriter 已啟動")
            
            let frameRate: Int32 = 30
            let frameDuration = CMTime(value: 1, timescale: frameRate)
            
            var currentFrameTime = CMTime.zero
            var successCount = 0
            
            for (index, frame) in frames.enumerated() {
                autoreleasepool {
                    while !videoInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    
                    guard let image = UIImage(data: frame.jpegData) else {
                        currentFrameTime = CMTimeAdd(currentFrameTime, frameDuration)
                        return
                    }
                    
                    let resizedImage = image.resizedExact(to: CGSize(width: 1080, height: 1920))
                    
                    guard let pixelBuffer = resizedImage.toPixelBuffer() else {
                        currentFrameTime = CMTimeAdd(currentFrameTime, frameDuration)
                        return
                    }
                    
                    if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: currentFrameTime) {
                        successCount += 1
                    }
                    
                    currentFrameTime = CMTimeAdd(currentFrameTime, frameDuration)
                    
                    if index % 50 == 0 {
                        let progress = Double(index) / Double(frames.count) * 100
                        print("📹 進度: \(Int(progress))%")
                    }
                }
            }
            
            print("✅ 寫入完成 - 成功: \(successCount)/\(frames.count) 幀")
            
            videoInput.markAsFinished()
            
            assetWriter.finishWriting { [weak self] in
                guard let self = self else { return }
                
                if assetWriter.status == .completed {
                    print("✅ 影片匯出完成")
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        self.saveVideoToPhotoLibrary(url: outputURL)
                    } else {
                        print("❌ 檔案不存在")
                        self.finishSaving()
                    }
                } else {
                    print("❌ 匯出失敗")
                    self.finishSaving()
                }
            }
            
        } catch {
            print("❌ Exception: \(error.localizedDescription)")
            self.finishSaving()
        }
    }
    
    private func finishSaving() {
        DispatchQueue.main.async {
            self.isSaving = false
        }
    }
    
    private func setupCamera() {
        print("🔧 設定相機...")
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
                print("✅ 使用 high preset")
            }
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("❌ 找不到後置相機")
                DispatchQueue.main.async {
                    self.errorMessage = "找不到後置相機"
                }
                return
            }
            print("✅ 找到相機")
            
            guard let input = try? AVCaptureDeviceInput(device: camera) else {
                print("❌ 無法建立相機輸入")
                DispatchQueue.main.async {
                    self.errorMessage = "無法建立相機輸入"
                }
                return
            }
            
            if session.canAddInput(input) {
                session.addInput(input)
                print("✅ 相機輸入已加入")
            } else {
                print("❌ 無法加入相機輸入")
                return
            }
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.frameQueue)
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("✅ 影片輸出已加入")
            } else {
                print("❌ 無法加入影片輸出")
                return
            }
            
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                    print("✅ 設定為直向")
                }
            }
            
            session.commitConfiguration()
            print("✅ Session 設定完成")
            
            self.captureSession = session
            self.videoOutput = output
            
            print("▶️ 啟動 session...")
            session.startRunning()
            
            DispatchQueue.main.async {
                self.isRunning = true
                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.updateBufferInfo()
                }
                print("✅ 相機已啟動")
            }
        }
    }
    
    private func saveVideoToPhotoLibrary(url: URL) {
        print("💾 請求相簿權限...")
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            guard status == .authorized else {
                print("❌ 沒有相簿權限")
                self.finishSaving()
                return
            }
            
            print("✅ 有相簿權限，開始儲存...")
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if success {
                    print("✅ 影片已儲存到相簿")
                    DispatchQueue.main.async {
                        self.showSuccess = true
                    }
                } else {
                    print("❌ 儲存失敗: \(error?.localizedDescription ?? "未知")")
                }
                
                try? FileManager.default.removeItem(at: url)
                self.finishSaving()
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let currentTime = Date().timeIntervalSince1970
        frameCount += 1
        
        if frameCount == 1 {
            print("🎉 收到第一幀！")
        }
        
        // 每 100 幀輸出狀態
        if frameCount % 100 == 0 {
            print("📊 緩衝區 - 幀數: \(frameBuffer.count), 時長: \(String(format: "%.1f", bufferDuration))秒")
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        
        guard let jpegData = image.jpegData(compressionQuality: 0.6) else {
            return
        }
        
        let frame = TimestampedFrame(
            jpegData: jpegData,
            timestamp: currentTime
        )
        
        frameBuffer.append(frame)
        
        let cutoffTime = currentTime - maxBufferDuration
        frameBuffer.removeAll { $0.timestamp < cutoffTime }
        
        if currentTime - lastRealtimeUpdate >= realtimeUpdateInterval {
            lastRealtimeUpdate = currentTime
            
            let resizedImage = image.resized(to: CGSize(width: 200, height: 150))
            DispatchQueue.main.async { [weak self] in
                self?.realtimeImage = resizedImage
            }
        }
        
        if currentTime - lastDelayedUpdate >= delayedUpdateInterval {
            lastDelayedUpdate = currentTime
            
            let targetTime = currentTime - delaySeconds
            var closestFrame: TimestampedFrame?
            var minDiff = Double.infinity
            
            for frame in frameBuffer {
                let diff = abs(frame.timestamp - targetTime)
                if diff < minDiff {
                    minDiff = diff
                    closestFrame = frame
                }
            }
            
            if let frame = closestFrame, minDiff < 0.5 {
                if let delayImage = UIImage(data: frame.jpegData) {
                    let resized = delayImage.resized(to: CGSize(width: 540, height: 960))
                    DispatchQueue.main.async { [weak self] in
                        self?.delayedImage = resized
                    }
                }
            }
        }
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    func resizedExact(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self.size.height)
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        return buffer
    }
}

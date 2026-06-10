import AVFoundation

/// Plays audio from an AudioBuffer with a configurable delay.
/// Pulls samples every ~100ms and schedules them on AVAudioPlayerNode.
final class AudioDelayPlayer {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var timer: Timer?
    private var lastScheduledEnd: TimeInterval = 0

    var delaySeconds: TimeInterval = 3.0
    private(set) var isRunning = false

    // MARK: - Lifecycle

    func start(format: AVAudioFormat) {
        self.format = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            player.play()
            isRunning = true
        } catch {
            print("AudioDelayPlayer start error: \(error)")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        isRunning = false
        lastScheduledEnd = 0
    }

    // MARK: - Scheduling

    /// Call this periodically (e.g. every 100ms) to feed delayed audio to the player.
    func tick(audioBuffer: AudioBuffer) {
        guard isRunning, let format else { return }

        let now = Date().timeIntervalSince1970
        let windowEnd   = now - delaySeconds
        let windowStart = max(lastScheduledEnd, windowEnd - 0.2)

        guard windowEnd > windowStart else { return }

        let samples = audioBuffer.samples(from: windowStart, to: windowEnd)
        lastScheduledEnd = windowEnd

        for sample in samples {
            guard let pcm = toPCMBuffer(sample: sample, format: format) else { continue }
            player.scheduleBuffer(pcm, completionHandler: nil)
        }
    }

    // MARK: - Conversion

    private func toPCMBuffer(sample: CMSampleBuffer,
                              format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(sample)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(frameCount)

        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        var length = 0
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                    lengthAtOffsetOut: nil,
                                    totalLengthOut: &length,
                                    dataPointerOut: &dataPointer)
        guard let src = dataPointer else { return nil }

        if let dst = pcm.int16ChannelData {
            let byteCount = min(length, Int(frameCount) * 2 * Int(format.channelCount))
            memcpy(dst[0], src, byteCount)
        } else if let dst = pcm.floatChannelData {
            let byteCount = min(length, Int(frameCount) * 4 * Int(format.channelCount))
            memcpy(dst[0], src, byteCount)
        }

        return pcm
    }
}

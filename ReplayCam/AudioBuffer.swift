import AVFoundation
import Foundation

/// Thread-safe rolling buffer for audio CMSampleBuffers.
/// Mirrors the design of FrameBuffer but stores audio samples.
final class AudioBuffer: @unchecked Sendable {

    private struct Entry {
        let sample: CMSampleBuffer
        let timestamp: TimeInterval
    }

    private var entries: [Entry] = []
    private let lock = NSLock()
    var maxDuration: TimeInterval = 35.0

    // MARK: - Append

    func append(_ sample: CMSampleBuffer) {
        let ts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard ts.isFinite else { return }

        lock.withLock {
            entries.append(Entry(sample: sample, timestamp: ts))
            if entries.count % 100 == 0 {
                let cutoff = (entries.last?.timestamp ?? 0) - maxDuration
                purge(before: cutoff)
            }
        }
    }

    // MARK: - Fetch for delayed playback

    /// Returns samples whose timestamp falls in [start, end].
    func samples(from start: TimeInterval, to end: TimeInterval) -> [CMSampleBuffer] {
        lock.withLock {
            entries
                .filter { $0.timestamp >= start && $0.timestamp <= end }
                .map(\.sample)
        }
    }

    /// All samples at or after startTime (for export).
    func samples(since startTime: TimeInterval) -> [CMSampleBuffer] {
        lock.withLock {
            entries
                .filter { $0.timestamp >= startTime }
                .map(\.sample)
        }
    }

    func clear() {
        lock.withLock { entries.removeAll(keepingCapacity: true) }
    }

    // MARK: - Private

    private func purge(before cutoff: TimeInterval) {
        let idx = entries.partition { $0.timestamp >= cutoff }
        entries.removeFirst(idx)
    }
}

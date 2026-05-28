import Foundation

/// Thread-safe rolling frame buffer backed by NSLock.
final class FrameBuffer: @unchecked Sendable {
    private var frames: [TimestampedFrame] = []
    private let lock = NSLock()
    private let maxDuration: TimeInterval = 35.0

    var count: Int {
        lock.withLock { frames.count }
    }

    var duration: TimeInterval {
        lock.withLock {
            guard let first = frames.first else { return 0 }
            return Date().timeIntervalSince1970 - first.timestamp
        }
    }

    func append(_ frame: TimestampedFrame) {
        let cutoff = frame.timestamp - maxDuration
        lock.withLock {
            frames.append(frame)
            if frames.count > 1200 {
                frames.removeAll { $0.timestamp < cutoff }
            }
        }
    }

    func findFrame(nearTimestamp target: TimeInterval, tolerance: TimeInterval = 0.5) -> TimestampedFrame? {
        lock.withLock {
            guard let best = frames.min(by: { abs($0.timestamp - target) < abs($1.timestamp - target) }) else { return nil }
            return abs(best.timestamp - target) < tolerance ? best : nil
        }
    }

    func frames(since startTime: TimeInterval) -> [TimestampedFrame] {
        lock.withLock { frames.filter { $0.timestamp >= startTime } }
    }
}

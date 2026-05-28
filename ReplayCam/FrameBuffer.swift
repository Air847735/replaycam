import Foundation

/// Thread-safe rolling frame buffer backed by NSLock.
final class FrameBuffer: @unchecked Sendable {
    private var frames: [TimestampedFrame] = []
    private let lock = NSLock()
    private let maxDuration: TimeInterval = 35.0
    private var appendCount = 0

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
        lock.withLock {
            frames.append(frame)
            appendCount += 1
            // Purge old frames ~once per second (every 30 appends) or when count is very high.
            // Frames are time-ordered, so binary-search for cutoff is safe.
            if appendCount % 30 == 0 || frames.count > 1200 {
                let cutoff = frame.timestamp - maxDuration
                if let idx = frames.firstIndex(where: { $0.timestamp >= cutoff }), idx > 0 {
                    frames.removeFirst(idx)
                } else if frames.first.map({ $0.timestamp < cutoff }) == true {
                    frames.removeAll()
                }
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

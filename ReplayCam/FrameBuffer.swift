import Foundation

/// Thread-safe rolling frame buffer backed by NSLock.
/// Frames are always appended in chronological order, enabling binary search.
final class FrameBuffer: @unchecked Sendable {

    private var frames: [TimestampedFrame] = []
    private let lock = NSLock()
    var maxDuration: TimeInterval = 35.0   // adjusted externally based on fps
    var earlyPurgeThreshold: Int = 1200   // adjusted externally based on fps
    private var appendCount = 0

    // MARK: - Public read-only properties

    var count: Int {
        lock.withLock { frames.count }
    }

    var duration: TimeInterval {
        lock.withLock {
            guard let first = frames.first else { return 0 }
            return Date().timeIntervalSince1970 - first.timestamp
        }
    }

    // MARK: - Append + purge

    func append(_ frame: TimestampedFrame) {
        lock.withLock {
            frames.append(frame)
            appendCount += 1

            // Purge once per second (~30 frames) or when the array is very large.
            if appendCount % 30 == 0 || frames.count > earlyPurgeThreshold {
                purgeOldFrames(before: frame.timestamp - maxDuration)
            }
        }
    }

    /// Drop all frames older than `cutoff`. Called inside the lock.
    private func purgeOldFrames(before cutoff: TimeInterval) {
        // Binary-search for the first frame that is still within the window.
        let idx = lowerBound(for: cutoff)
        guard idx > 0 else { return }
        if idx >= frames.count {
            frames.removeAll(keepingCapacity: true)
        } else {
            // replaceSubrange is O(n) too, but we avoid creating a new Array copy.
            frames.removeSubrange(0..<idx)
        }
    }

    // MARK: - Lookup

    /// Find the frame whose timestamp is closest to `target`.
    /// Uses binary search — O(log n) instead of the previous O(n) linear scan.
    func findFrame(nearTimestamp target: TimeInterval,
                   tolerance: TimeInterval = 0.5) -> TimestampedFrame? {
        lock.withLock {
            guard !frames.isEmpty else { return nil }

            let idx = lowerBound(for: target)   // first index where timestamp >= target

            // Candidates: the frame just before and the frame at idx
            let candidates: [TimestampedFrame]
            switch idx {
            case 0:             candidates = [frames[0]]
            case frames.count:  candidates = [frames[frames.count - 1]]
            default:            candidates = [frames[idx - 1], frames[idx]]
            }

            guard let best = candidates.min(by: {
                abs($0.timestamp - target) < abs($1.timestamp - target)
            }) else { return nil }

            return abs(best.timestamp - target) <= tolerance ? best : nil
        }
    }

    /// All frames at or after `startTime` (for video export).
    func frames(since startTime: TimeInterval) -> [TimestampedFrame] {
        lock.withLock {
            let idx = lowerBound(for: startTime)
            guard idx < frames.count else { return [] }
            return Array(frames[idx...])
        }
    }

    // MARK: - Memory pressure

    /// Trim the buffer to the most recent `keepSeconds` seconds.
    /// Call this when the system reports low memory.
    func trimToLastSeconds(_ keepSeconds: TimeInterval) {
        lock.withLock {
            let cutoff = Date().timeIntervalSince1970 - keepSeconds
            purgeOldFrames(before: cutoff)
        }
    }

    // MARK: - Binary search helper (called inside lock)

    /// Index of the first element whose timestamp is >= `target`.
    /// Assumes `frames` is sorted ascending by timestamp.
    private func lowerBound(for target: TimeInterval) -> Int {
        var lo = 0, hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].timestamp < target { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

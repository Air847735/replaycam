import Foundation

struct TimestampedFrame: Sendable {
    let jpegData: Data
    let timestamp: TimeInterval
}

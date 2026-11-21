import Foundation

/// Whole milliseconds since a clock reading.
public func milliseconds(since start: ContinuousClock.Instant) -> Int {
    milliseconds(of: ContinuousClock.now - start)
}

public func milliseconds(of duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
}

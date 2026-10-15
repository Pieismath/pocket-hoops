import CoreGraphics
import Foundation

/// Reads a swipe the way the player means it.
///
/// Fingers (and mice) slow down just before they lift, so the speed over the final instant
/// understates how hard someone flicked. We take the stroke's *peak* speed (over ≥30 ms, so one
/// jittery touch sample can't spike it) and its overall *direction* (from the lowest point of the
/// stroke to the release), which is what the player aimed.
enum Flick {
    struct Sample {
        let t: TimeInterval
        /// View coordinates (points, y grows downward).
        let p: CGPoint
    }

    /// The flick's velocity in points/second with y pointing *up* the screen, or nil if the touch
    /// wasn't an upward flick.
    static func velocity(_ samples: [Sample]) -> (x: Double, y: Double)? {
        guard let last = samples.last, samples.count >= 2 else { return nil }
        let recent = samples.filter { last.t - $0.t <= 0.35 }
        guard recent.count >= 2 else { return nil }

        // Peak speed over windows of at least 30 ms.
        var peak = 0.0
        for i in 1..<recent.count {
            let b = recent[i]
            guard let a = recent[..<i].last(where: { b.t - $0.t >= 0.03 }) ?? recent.first, b.t > a.t else { continue }
            let dx = Double(b.p.x - a.p.x), up = Double(a.p.y - b.p.y)
            guard up > 0 else { continue }
            peak = max(peak, (dx * dx + up * up).squareRoot() / (b.t - a.t))
        }
        guard peak > 0, peak.isFinite else { return nil }

        // Direction: the fast part of the stroke — the slow start and any twitch as the finger
        // lifts off don't count.
        var segments: [(dx: Double, up: Double, speed: Double)] = []
        for i in 1..<recent.count {
            let a = recent[i - 1], b = recent[i]
            let dt = max(1e-4, b.t - a.t)
            let dx = Double(b.p.x - a.p.x), up = Double(a.p.y - b.p.y)
            segments.append((dx, up, (dx * dx + up * up).squareRoot() / dt))
        }
        let fastest = segments.map(\.speed).max() ?? 0
        var dx = 0.0, up = 0.0
        for s in segments where s.speed >= fastest * 0.5 {
            dx += s.dx
            up += s.up
        }
        let len = (dx * dx + up * up).squareRoot()
        guard up > 0, len > 0 else { return nil }
        return (dx / len * peak, up / len * peak)
    }
}

/// Learns how hard this player usually flicks, so their normal flick lands in the middle of the
/// hoop whether they play with a thumb on a phone or a mouse in the simulator. It moves slowly and
/// ignores wild flicks, so flicking noticeably softer or harder than usual still misses.
struct FlickCalibration: Equatable {
    static let defaultReference = 1300.0
    static let range = 700.0...3200.0
    /// Fraction of the way the reference moves toward each new flick (in log space).
    static let rate = 0.3

    private(set) var reference: Double

    init(reference: Double = FlickCalibration.defaultReference) {
        self.reference = min(FlickCalibration.range.upperBound, max(FlickCalibration.range.lowerBound, reference))
    }

    mutating func record(_ speed: Double) {
        guard speed.isFinite, speed > 0 else { return }
        let ratio = speed / reference
        guard ratio > 0.45, ratio < 2.2 else { return } // a mis-swipe, not how they normally flick
        let moved = exp(log(reference) + log(ratio) * FlickCalibration.rate)
        reference = min(FlickCalibration.range.upperBound, max(FlickCalibration.range.lowerBound, moved))
    }

    private static let key = "pockethoops.flickReference"

    static func load(_ defaults: UserDefaults = .standard) -> FlickCalibration {
        let saved = defaults.double(forKey: key)
        return FlickCalibration(reference: saved > 0 ? saved : defaultReference)
    }

    func save(_ defaults: UserDefaults = .standard) { defaults.set(reference, forKey: FlickCalibration.key) }
}

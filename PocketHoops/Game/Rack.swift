import Foundation

/// The ball rack under the "PLAYER" strip. Returning balls drop in, then roll down to the low
/// point of the trough (where the shooter reaches in), bumping into each other and spinning as
/// they go. Units are machine-canvas pixels (x along the trough, `drop` = height above resting).
final class Rack {
    struct RackBall: Identifiable {
        let id: Int
        var x: Double
        var vx = 0.0
        /// Height above the resting position; balls fall in from behind the strip.
        var drop = 0.0
        var vdrop = 0.0
        /// Rolling angle (radians) — picks the ball's rotation frame.
        var spin = 0.0
        var landed = false
    }

    let minX: Double
    let maxX: Double
    /// Lowest point of the trough; balls gather here.
    let lowX: Double
    /// Centre-to-centre distance at which two rack balls touch (they overlap a little, like the art).
    let spacing: Double
    let radius: Double
    private(set) var balls: [RackBall] = []
    private var nextID = 1

    /// Gravity for balls falling in, and the trough's slope toward `lowX` (pixels/s²).
    var fallGravity = 900.0
    var slopeAccel = 140.0
    var friction = 2.2

    init(minX: Double, maxX: Double, lowX: Double, spacing: Double = 11, radius: Double = 7) {
        self.minX = minX
        self.maxX = maxX
        self.lowX = lowX
        self.spacing = spacing
        self.radius = radius
    }

    var count: Int { balls.count }

    /// Drops a ball in at `x` from `height` pixels above the trough.
    @discardableResult
    func add(at x: Double, height: Double = 0, vx: Double = 0) -> Int {
        let b = RackBall(id: nextID, x: min(maxX, max(minX, x)), vx: vx, drop: height, vdrop: 0,
                         spin: Double.random(in: 0..<(2 * .pi)), landed: height <= 0)
        nextID += 1
        balls.append(b)
        return b.id
    }

    /// Takes the ball closest to `x` (the shooter reaching in), or nil if the rack is empty.
    func take(nearest x: Double) -> RackBall? {
        guard let i = balls.indices.min(by: { abs(balls[$0].x - x) < abs(balls[$1].x - x) }) else { return nil }
        return balls.remove(at: i)
    }

    /// Advances the rack. Returns the ids of balls that landed this step (for a clack sound).
    @discardableResult
    func step(_ dt: Double) -> [Int] {
        guard dt > 0 else { return [] }
        var landed: [Int] = []
        let h = min(dt, 1.0 / 30)
        for i in balls.indices {
            var b = balls[i]
            if b.drop > 0 || b.vdrop > 0 {
                b.vdrop -= fallGravity * h
                b.drop += b.vdrop * h
                if b.drop <= 0 {
                    b.drop = 0
                    if b.vdrop < -60 {
                        b.vdrop = -b.vdrop * 0.28 // small bounce
                    } else {
                        b.vdrop = 0
                    }
                    if !b.landed { b.landed = true; landed.append(b.id) }
                }
            }
            balls[i] = b
        }
        // Balls roll down to the low point and stack up against each other there: in order along
        // the trough, each one heads for its own resting slot, so they settle side by side.
        balls.sort { $0.x < $1.x }
        let n = balls.count
        let gap = n > 1 ? min(spacing, (maxX - minX) / Double(n - 1)) : spacing
        let first = min(max(minX, lowX - gap * Double(n - 1) / 2), maxX - gap * Double(max(0, n - 1)))
        for i in balls.indices {
            var b = balls[i]
            let slot = first + gap * Double(i)
            let dx = slot - b.x
            // Gravity down the slope, never more than the slope allows; rolling friction.
            let a = (dx > 0 ? 1 : -1) * min(slopeAccel, abs(dx) * 60)
            // Free rolling is lightly damped; a ball nudging into its resting spot rocks and settles.
            let damping = abs(dx) < 3 ? 10 : friction
            b.vx += (a - damping * b.vx) * h
            if abs(dx) < 0.05 && abs(b.vx) < 1 { b.vx = 0; b.x = slot }
            let before = b.x
            b.x = min(maxX, max(minX, b.x + b.vx * h))
            b.spin += (b.x - before) / radius
            balls[i] = b
        }
        // Never let two balls pass through each other while they roll.
        for _ in 0..<4 {
            for i in 0..<max(0, n - 1) where balls[i + 1].x - balls[i].x < gap - 0.01 {
                let push = (gap - (balls[i + 1].x - balls[i].x)) / 2
                balls[i].x -= push
                balls[i + 1].x += push
                let v = (balls[i].vx + balls[i + 1].vx) / 2
                balls[i].vx = v
                balls[i + 1].vx = v
            }
        }
        return landed
    }

    /// True once every ball has landed and stopped rolling.
    var isSettled: Bool { balls.allSatisfy { $0.drop == 0 && $0.vdrop == 0 && abs($0.vx) < 2 } }
}

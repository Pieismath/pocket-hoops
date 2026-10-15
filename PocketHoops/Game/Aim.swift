import CoreGraphics
import Foundation

/// Turns a finger flick into a launch velocity. Flick speed sets the distance, flick
/// direction (followed on screen up to the rim's height) sets the line.
enum Aim {
    /// Flick speed (points/second) that lands a ball dead centre, before the game has learned how
    /// this player flicks (see `FlickCalibration`).
    static var referenceSpeed: Double { FlickCalibration.defaultReference }
    /// How much a flick that's off the reference speed changes the distance (lower = more forgiving).
    /// Long misses get a steeper curve because the backboard already rescues slightly-long shots.
    static let shortSensitivity = 0.75
    static let longSensitivity = 2.0
    /// Flicks within this fraction of the reference speed all land dead centre, so a
    /// comfortable flick feels reliable; outside it, distance ramps up.
    static let comfortZone = 0.08
    /// How far the lateral aim is pulled toward the hoop (0 = none, 1 = always straight).
    static let aimAssist = 0.3
    /// Steep enough that the ball drops into the hoop at ~64°, so only genuinely short or long
    /// shots find the rim.
    static let launchAngle = 76.0 * .pi / 180
    /// Past the make window (where the back rim stops catching long shots) over-hits get long
    /// fast, so a flick that's clearly too hard bangs off the backboard and rebounds back out
    /// instead of dropping off the glass into the hoop; only a narrow band of "slightly too
    /// hard" flicks banks in.
    static let overhitKnee = 0.13
    static let overhitSensitivity = 14.0
    /// The farthest a flick can aim, as a multiple of the distance to the rim. Every flick past
    /// this is the same hard shot off the backboard (the glass, ceiling net and speed clamp keep
    /// it in the machine until it rebounds back out over the front into the tray).
    static let maxDepth = 3.0
    /// Radians of launch angle lost per unit of over-hit depth.
    static let overhitFlattening = 28.0 * .pi / 180
    /// Air (metres) an over-hit keeps between the ball and the top of the rim as it goes over it.
    static let rimClearance = 0.03

    static func shot(viewVelocity v: (x: Double, y: Double), from x0: Double, court c: Court,
                     projection proj: Projection, reference: Double = referenceSpeed)
        -> (velocity: Vec3, depth: Double, lateral: Double) {
        let start = Vec3(x: x0, y: c.launchY, z: c.launchZ)
        let speed = sqrt(v.x * v.x + v.y * v.y)
        let power = max(0.35, min(2.2, speed / max(1, reference)))
        let off = power - 1
        let eased = off > 0 ? max(0, off - comfortZone) : min(0, off + comfortZone)
        let long = eased * longSensitivity + max(0, eased - overhitKnee) * overhitSensitivity
        let depth = min(maxDepth, 1 + (eased < 0 ? eased * shortSensitivity : long))
        let from = proj.project(start)
        let rim = proj.project(c.rimCenter)
        let t = Double(rim.y - from.y) / max(1, abs(v.y))
        let screenX = Double(from.x) + v.x * t
        let ppm = proj.pixelsPerMetre(at: c.rimCenter)
        var tx = (screenX - Double(rim.x)) / ppm + c.hoopX
        if !tx.isFinite { tx = c.hoopX }
        tx = max(-c.laneHalfWidth, min(c.laneHalfWidth, tx))
        tx = tx * (1 - aimAssist) + c.hoopX * aimAssist
        let target = Vec3(x: tx, y: c.launchY + (c.rimY - c.launchY) * depth, z: c.rimZ)
        // Over-hit flicks also come out flatter, so they smack the backboard and rebound past the
        // rim instead of dropping down it — but never so flat that they reach the rim below its
        // height and fly under it: they always go over the front of the rim.
        var angle = launchAngle - max(0, depth - 1) * overhitFlattening
        if depth > 1 { angle = max(angle, clearingAngle(from: start, to: target, court: c)) }
        var vel = Simulation.launchVelocity(from: start, to: target, angle: angle, gravity: c.gravity)
            ?? Vec3(x: 0, y: 3, z: 5)
        if !vel.isFinite { vel = Vec3(x: 0, y: 3, z: 5) }
        let launchSpeed = vel.length
        if launchSpeed > c.maxLaunchSpeed { vel = vel * (c.maxLaunchSpeed / launchSpeed) }
        return (vel, depth, tx - c.hoopX)
    }

    /// The flattest launch angle (radians, at most `launchAngle`) whose arc from `start` down to
    /// `target` passes over the front half of the rim with the whole ball above the rim tube.
    /// 0 when the arc doesn't pass over the rim at all (a wide shot).
    static func clearingAngle(from start: Vec3, to target: Vec3, court c: Court) -> Double {
        let dx = target.x - start.x, dy = target.y - start.y
        let d = (dx * dx + dy * dy).squareRoot()
        let h = target.z - start.z
        guard d > 1e-6 else { return launchAngle }
        let band = c.ballRadius + c.rimTube + rimClearance
        var needed = -Double.infinity // tan of the launch angle
        let steps = 160
        for i in 1..<steps {
            let s = d * Double(i) / Double(steps)
            let px = start.x + dx / d * s - c.hoopX, py = start.y + dy / d * s - c.rimY
            // Past the middle of the rim it's a back-rim or backboard shot: the physics decides.
            if py > 0 { break }
            let off = (px * px + py * py).squareRoot() - c.rimRadius
            guard abs(off) < band else { continue }
            // Height the ball's centre needs here, and the angle that puts it there: an arc
            // through `target` is z(s) = z0 + s²·h/d² + tanθ · s(1 − s/d).
            let z = c.rimZ + (band * band - off * off).squareRoot()
            needed = max(needed, (z - start.z - s * s * h / (d * d)) / (s * (1 - s / d)))
        }
        return needed.isFinite ? min(launchAngle, atan(needed)) : 0
    }
}

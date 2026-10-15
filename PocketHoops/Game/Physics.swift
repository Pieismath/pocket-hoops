import Foundation

/// Geometry of the arcade cabinet (metres) plus the few knobs game modes turn (hoop offset for the
/// moving hoop, wind, rim size, gravity). The dimensions are fitted to the reference art
/// (`GIFLayout`), so a ball at the rim's world position is drawn exactly on the rim's pixels.
struct Court {
    /// Half the lane's width, measured to where a ball *sprite* touches the side rails.
    var laneHalfWidth = 0.44
    /// Front edge of the lane; the machine's front panel drops from here to the ground.
    var frontY = -0.35
    var rimY = 0.4219
    var rimZ = 1.2824
    var rimRadius = 0.235
    var rimTube = 0.018
    var boardGap = 0.15
    var boardHalfWidth = 0.44
    var boardBottom = 0.3
    var boardTop = 2.35
    /// The cabinet is enclosed (glass sides, backboard, a net overhead), so nothing can leave it.
    var ceiling = 2.7
    var ballRadius = 0.12
    var gravity = 13.0
    /// The lane is a ramp rising from the front edge up to the foot of the backboard,
    /// so missed balls roll back to the rack under gravity.
    var rampRise = 0.3
    /// The shooter stands in front of the machine and releases from above their head.
    var launchY = -0.6
    var launchZ = 0.2707
    /// No launch is ever faster than this (m/s) — a wild flick can't fling a ball out of the world.
    var maxLaunchSpeed = 8.5
    /// Horizontal offset of the rim (moving-hoop stages).
    var hoopX = 0.0
    /// Constant sideways acceleration (daily-challenge modifier).
    var wind = 0.0

    var boardY: Double { rimY + rimRadius + boardGap }
    /// Slope of the ramp (rise per metre along the lane).
    var rampSlope: Double { rampRise / (boardY - frontY) }
    /// Height of the lane surface at depth `y` (0 at the front edge).
    func floorZ(_ y: Double) -> Double { max(0, min(rampRise, (y - frontY) * rampSlope)) }
    var rimCenter: Vec3 { Vec3(x: hoopX, y: rimY, z: rimZ) }
    /// The funnel of net below the rim: balls in here have scored and get slowed.
    var netDepth: Double { 0.3 }
    /// The net tapers from the rim's radius down to this at its bottom opening.
    var netBottomRadius: Double { rimRadius * 0.6 }

    /// The ball tray in front of the machine: a ball that comes back out over the front edge has
    /// landed in it once it's drawn at the tray's resting line (art row 114, 18 px below the
    /// lane's front edge) — however far toward the shooter it flew.
    func inTray(_ p: Vec3) -> Bool {
        p.y < frontY && (p.y - frontY) * Projection.ky + p.z * Projection.kz < -18
    }

    /// Anything outside this box (or with a non-finite position) is recovered to the rack.
    func inBounds(_ p: Vec3) -> Bool {
        abs(p.x) < laneHalfWidth + 0.3 && p.y > frontY - 1.6 && p.y < boardY + 0.3 && p.z > -2.5 && p.z < ceiling + 0.5
    }
}

enum BallPhase: Equatable { case flying, returning }

final class Ball: Identifiable {
    let id: Int
    var pos: Vec3
    var vel: Vec3
    var phase: BallPhase = .flying
    /// Rotation about the x axis, for picking a spin frame (backspin).
    var spin: Double = 0
    var spinRate: Double = -14
    var age: Double = 0
    var scored = false
    var resolved = false
    var touchedRim = false
    var touchedBoard = false
    var inNet = false
    /// Set by the game when this shot was launched while "on fire".
    var onFire = false
    /// Found somewhere impossible (out of bounds / not a number): goes straight back to the rack.
    var lost = false

    init(id: Int, pos: Vec3, vel: Vec3) {
        self.id = id
        self.pos = pos
        self.vel = vel
    }
}

enum PhysicsEvent: Equatable {
    case rim(ballID: Int, strength: Double)
    case board(ballID: Int, strength: Double)
    case wall(ballID: Int, strength: Double)
    case floor(ballID: Int, strength: Double)
    case score(ballID: Int, swish: Bool, bank: Bool)
    case miss(ballID: Int, airball: Bool)
    /// The ball left play and goes back to the rack. `x` is where it was (metres); `lost` means it
    /// was recovered (out of bounds, invalid, or wedged) rather than rolling back normally.
    case returned(ballID: Int, x: Double, lost: Bool)
}

/// Deterministic fixed-step ball simulation. No SpriteKit in here, so it's unit-testable.
final class Simulation {
    var court: Court
    private(set) var balls: [Ball] = []
    private var nextID = 1
    private let substep = 1.0 / 240.0
    private var accumulator = 0.0

    init(court: Court = Court()) {
        self.court = court
    }

    /// Adds a ball. The velocity is clamped to `court.maxLaunchSpeed` and must be finite.
    @discardableResult
    func launch(from pos: Vec3, velocity: Vec3) -> Ball {
        var v = velocity.isFinite ? velocity : Vec3(x: 0, y: 2, z: 5)
        let speed = v.length
        if speed > court.maxLaunchSpeed { v = v * (court.maxLaunchSpeed / speed) }
        let b = Ball(id: nextID, pos: pos, vel: v)
        nextID += 1
        balls.append(b)
        return b
    }

    func removeAll() { balls.removeAll() }

    /// Advances by `dt` seconds (any size) and returns everything that happened.
    func step(_ dt: Double) -> [PhysicsEvent] {
        var events: [PhysicsEvent] = []
        guard dt.isFinite, dt > 0 else { return events }
        accumulator += min(dt, 0.1)
        while accumulator >= substep {
            accumulator -= substep
            // Split the step further for fast balls so none moves more than a quarter of its
            // radius per collision check — nothing can tunnel through the board or the rim.
            let fastest = balls.map { $0.vel.length }.max() ?? 0
            let pieces = max(1, min(64, Int((fastest * substep / (0.25 * court.ballRadius)).rounded(.up))))
            for _ in 0..<pieces { tick(substep / Double(pieces), &events) }
        }
        return events
    }

    // MARK: - Internals

    private func tick(_ h: Double, _ events: inout [PhysicsEvent]) {
        let c = court
        let r = c.ballRadius
        for b in balls {
            // Anything corrupted or outside the machine is recovered, not pushed around.
            if !b.pos.isFinite || !b.vel.isFinite || !c.inBounds(b.pos) { b.lost = true; continue }
            b.age += h
            let prev = b.pos

            // Integrate.
            b.vel.z -= c.gravity * h
            b.vel.x += c.wind * h * (b.phase == .flying ? 1 : 0)
            b.pos += b.vel * h
            b.spin += b.spinRate * h

            // Net: once through the rim, the ball is funnelled and slowed.
            let rimC = c.rimCenter
            let dh = Vec3(x: b.pos.x - rimC.x, y: b.pos.y - rimC.y, z: 0)
            let below = rimC.z - b.pos.z
            if b.scored && below > -0.02 && below < c.netDepth + r {
                b.inNet = true
                let pull = 9.0 * h
                b.pos.x -= dh.x * pull
                b.pos.y -= dh.y * pull
                b.vel.x *= (1 - 6 * h)
                b.vel.y *= (1 - 6 * h)
                b.vel.z *= (1 - 5 * h)
            } else {
                b.inNet = false
            }

            // Scoring: centre crosses the rim plane downward inside the ring.
            if !b.scored && !b.resolved && prev.z > rimC.z && b.pos.z <= rimC.z && b.vel.z < 0 {
                let hd = Vec3(x: b.pos.x - rimC.x, y: b.pos.y - rimC.y, z: 0).horizontalLength
                if hd < c.rimRadius {
                    b.scored = true
                    b.resolved = true
                    events.append(.score(ballID: b.id, swish: !b.touchedRim && !b.touchedBoard,
                                         bank: b.touchedBoard))
                }
            }

            collideRim(b, c, h, &events)
            collideNet(b, c, &events)
            collideWalls(b, c, h, &events)
            unwedgeFromRim(b, c)
            collideFloor(b, c, &events)

            // A shot that is well below the rim without scoring is a miss.
            if !b.resolved && b.pos.z < rimC.z - 0.4 && b.vel.z < 0 {
                b.resolved = true
                events.append(.miss(ballID: b.id, airball: !b.touchedRim && !b.touchedBoard))
            }
            if b.resolved { b.phase = .returning }
        }

        // A ball on its way back out over the front of the machine is past the shooter's new shots:
        // it neither knocks them off line nor gets knocked away itself.
        collideBalls(balls.filter { !$0.lost && !($0.pos.y < c.frontY - c.ballRadius && $0.vel.y < 0) }, &events)

        // Balls that roll back to the rack go home; anything lost, invalid or wedged is recovered.
        balls.removeAll { b in
            // Rolling off the front of the lane — on the ramp, not flying back over its edge (a
            // hard rebound does that, and drops into the tray in front of the machine instead).
            let rolledBack = b.pos.y < c.frontY + 0.12 && b.pos.y > c.frontY - 0.05 && b.vel.y < 0 && b.age > 0.3
                && b.pos.z < c.floorZ(b.pos.y) + c.ballRadius + 0.1
            let dropped = c.inTray(b.pos) // fell (or flew back) out in front of the machine
            let invalid = b.lost || !b.pos.isFinite || !b.vel.isFinite || !c.inBounds(b.pos)
            let wedged = b.age > 7
            guard rolledBack || dropped || invalid || wedged else { return false }
            if !b.resolved { events.append(.miss(ballID: b.id, airball: false)) }
            let x = b.pos.x.isFinite ? max(-c.laneHalfWidth, min(c.laneHalfWidth, b.pos.x)) : 0
            events.append(.returned(ballID: b.id, x: x, lost: invalid || wedged))
            return true
        }
    }

    /// Friction from a contact: a knock (`speedIn`, m/s into the surface) scrubs off a fixed
    /// share of the sliding speed; a ball merely resting or rolling on the surface gets a gentle
    /// drag over time instead — so it rolls off the rim, or out of the gap between the rim and
    /// the backboard, rather than sticking there.
    private func friction(knock: Double, speedIn: Double, _ h: Double) -> Double {
        speedIn > 0.4 ? knock : 1 - 1.5 * h
    }

    private func collideRim(_ b: Ball, _ c: Court, _ h: Double, _ events: inout [PhysicsEvent]) {
        let rc = c.rimCenter
        let q = b.pos - rc
        let hl = q.horizontalLength
        let dir = hl > 1e-6 ? Vec3(x: q.x / hl, y: q.y / hl, z: 0) : Vec3(x: 1, y: 0, z: 0)
        let nearest = rc + dir * c.rimRadius
        let d = b.pos - nearest
        let dist = d.length
        let minDist = c.ballRadius + c.rimTube
        guard dist < minDist, dist > 1e-6 else { return }
        let n = d * (1 / dist)
        b.pos += n * (minDist - dist)
        let vn = b.vel.dot(n)
        if vn < 0 {
            let restitution = 0.5
            b.vel -= n * ((1 + restitution) * vn)
            // A little friction on the tangential part.
            let vnAfter = b.vel.dot(n)
            let tangential = b.vel - n * vnAfter
            b.vel = n * vnAfter + tangential * friction(knock: 0.9, speedIn: -vn, h)
            // A ball balanced dead centre on the back (or front) of the rim would sit there
            // forever, perfectly symmetric; a real one never is, and rolls off to one side.
            if -vn <= 0.4 && abs(q.x) < 1e-3 { b.vel.x += (b.id % 2 == 0 ? 0.5 : -0.5) * h }
            if -vn > 0.4 { events.append(.rim(ballID: b.id, strength: min(1, -vn / 5))) }
            b.touchedRim = true
            b.spinRate = -b.spinRate * 0.6
        }
    }

    /// The glass or the backboard can undo the rim's sideways push on a ball wedged between them
    /// (say, one pressed into the corner by another ball landing on it), which would let it sink
    /// through the rim. There's no room for it beside the rim there, so it rides up onto the rim
    /// instead — or, if it's underneath, stays under it.
    private func unwedgeFromRim(_ b: Ball, _ c: Court) {
        let q = b.pos - c.rimCenter
        let off = q.horizontalLength - c.rimRadius
        let minDist = c.ballRadius + c.rimTube
        guard abs(off) < minDist, off * off + q.z * q.z < (minDist - 0.005) * (minDist - 0.005) else { return }
        let side = q.z >= 0 ? 1.0 : -1.0
        b.pos.z = c.rimZ + side * (minDist * minDist - off * off).squareRoot()
        if b.vel.z * side < 0 { b.vel.z = 0 }
    }

    /// The net hangs from the rim as a cone (the rim's radius at the top, `netBottomRadius` at
    /// `netDepth` below). Only a ball that came down through the ring gets inside it; to every
    /// other ball the net — sides and bottom opening alike — is solid, so nothing can slip in
    /// under the rim and come out looking like it went through it.
    private func collideNet(_ b: Ball, _ c: Court, _ events: inout [PhysicsEvent]) {
        guard !b.scored else { return }
        let rc = c.rimCenter
        let r = c.ballRadius
        let top = rc.z, bottom = rc.z - c.netDepth
        guard b.pos.z < top, b.pos.z > bottom - r else { return }
        let hx = b.pos.x - rc.x, hy = b.pos.y - rc.y
        let rho = (hx * hx + hy * hy).squareRoot()
        guard rho < c.rimRadius + r else { return }

        let side = c.netBottomRadius + (c.rimRadius - c.netBottomRadius) * (b.pos.z - bottom) / c.netDepth
        if b.pos.z > bottom && rho < side {
            // Inside, but without crossing the rim plane under its own steam: another ball
            // knocked it down through the ring. It went in.
            b.scored = true
            if !b.resolved {
                b.resolved = true
                events.append(.score(ballID: b.id, swish: !b.touchedRim && !b.touchedBoard, bank: b.touchedBoard))
            }
            return
        }

        // Nearest point of the net's outline in the ball's (radius, height) plane: the sloping
        // side from the rim down to the bottom opening, then across the opening to the middle.
        func nearest(_ p0: (Double, Double), _ p1: (Double, Double)) -> (Double, Double) {
            let dr = p1.0 - p0.0, dz = p1.1 - p0.1
            let t = max(0, min(1, ((rho - p0.0) * dr + (b.pos.z - p0.1) * dz) / (dr * dr + dz * dz)))
            return (p0.0 + dr * t, p0.1 + dz * t)
        }
        let edge = (c.netBottomRadius, bottom)
        let onSide = nearest((c.rimRadius, top), edge), onBottom = nearest(edge, (0, bottom))
        let dSide = hypot(rho - onSide.0, b.pos.z - onSide.1), dBottom = hypot(rho - onBottom.0, b.pos.z - onBottom.1)
        let (p, dist) = dSide <= dBottom ? (onSide, dSide) : (onBottom, dBottom)
        guard dist < r, dist > 1e-9 else { return }
        let out = rho > 1e-9 ? (hx / rho, hy / rho) : (0.0, -1.0)
        let nr = (rho - p.0) / dist
        let n = Vec3(x: out.0 * nr, y: out.1 * nr, z: (b.pos.z - p.1) / dist)
        b.pos += n * (r - dist)
        let vn = b.vel.dot(n)
        guard vn < 0 else { return }
        // Netting gives: it soaks up most of the ball's speed into it and drags on the rest.
        b.vel -= n * (1.2 * vn)
        let vnAfter = b.vel.dot(n)
        b.vel = n * vnAfter + (b.vel - n * vnAfter) * 0.8
    }

    private func collideWalls(_ b: Ball, _ c: Court, _ h: Double, _ events: inout [PhysicsEvent]) {
        let r = c.ballRadius
        // Back plane: the backboard fills it, all the way up to the ceiling net. Walls are hard
        // limits — a ball squeezed against one (say, by the rim) is put back even if it's already
        // moving away — and only a ball moving into a wall bounces.
        if b.pos.y + r > c.boardY && b.vel.y <= 0 { b.pos.y = c.boardY - r }
        if b.pos.y + r > c.boardY && b.vel.y > 0 {
            b.pos.y = c.boardY - r
            let onBoard = b.pos.z > c.boardBottom - r * 0.5 && b.pos.z < c.boardTop + r * 0.5
            let s = b.vel.y
            b.vel.y = -b.vel.y * (onBoard ? 0.6 : 0.4)
            let f = friction(knock: 0.92, speedIn: s, h)
            b.vel.x *= f
            b.vel.z *= f
            if onBoard {
                if !b.resolved { b.touchedBoard = true }
                if s > 0.3 { events.append(.board(ballID: b.id, strength: min(1, s / 6))) }
            } else if s > 0.3 {
                events.append(.wall(ballID: b.id, strength: min(1, s / 6)))
            }
        }
        // Front panel of the machine (only reachable by weak shots from below lane level).
        if b.pos.z < 0 && b.pos.y < c.frontY && b.pos.y + r > c.frontY && b.vel.y > 0 {
            b.pos.y = c.frontY - r
            b.vel.y = -b.vel.y * 0.4
            events.append(.wall(ballID: b.id, strength: 0.4))
        }
        // Side walls (glass).
        for side in [-1.0, 1.0] {
            let limit = c.laneHalfWidth - r
            if b.pos.x * side > limit && b.vel.x * side <= 0 { b.pos.x = limit * side }
            if b.pos.x * side > limit && b.vel.x * side > 0 {
                b.pos.x = limit * side
                let s = abs(b.vel.x)
                b.vel.x = -b.vel.x * 0.55
                if s > 0.5 { events.append(.wall(ballID: b.id, strength: min(1, s / 6))) }
            }
        }
        // Ceiling net.
        if b.pos.z + r > c.ceiling && b.vel.z <= 0 { b.pos.z = c.ceiling - r }
        if b.pos.z + r > c.ceiling && b.vel.z > 0 {
            b.pos.z = c.ceiling - r
            b.vel.z = -b.vel.z * 0.35
            events.append(.wall(ballID: b.id, strength: 0.2))
        }
    }

    private func collideFloor(_ b: Ball, _ c: Court, _ events: inout [PhysicsEvent]) {
        let r = c.ballRadius
        guard b.pos.y >= c.frontY - r * 0.5 else { return }
        // Distance from the ramp plane z = slope·(y - frontY), along its normal.
        let k = c.rampSlope
        let norm = sqrt(1 + k * k)
        let n = Vec3(x: 0, y: -k / norm, z: 1 / norm)
        let dist = (b.pos.z - c.floorZ(b.pos.y)) / norm
        guard dist < r else { return }
        b.pos += n * (r - dist)
        let vn = b.vel.dot(n)
        guard vn < 0 else { return }
        let s = -vn
        if s > 0.6 {
            b.vel -= n * (1.45 * vn)
            events.append(.floor(ballID: b.id, strength: min(1, s / 7)))
            b.vel.x *= 0.85
        } else {
            b.vel -= n * vn // settle onto the ramp and roll down it
        }
        if !b.resolved {
            b.resolved = true
            events.append(.miss(ballID: b.id, airball: !b.touchedRim && !b.touchedBoard))
        }
    }

    private func collideBalls(_ balls: [Ball], _ events: inout [PhysicsEvent]) {
        guard balls.count > 1 else { return }
        let d2 = court.ballRadius * 2
        for i in 0..<balls.count {
            for j in (i + 1)..<balls.count {
                let a = balls[i], b = balls[j]
                let delta = b.pos - a.pos
                let dist = delta.length
                guard dist < d2, dist > 1e-6 else { continue }
                let n = delta * (1 / dist)
                let push = (d2 - dist) / 2
                a.pos -= n * push
                b.pos += n * push
                let rel = (b.vel - a.vel).dot(n)
                if rel < 0 {
                    let imp = n * (-(1 + 0.7) * rel / 2)
                    a.vel -= imp
                    b.vel += imp
                }
            }
        }
    }

    // MARK: - Aiming

    /// Launch velocity that carries a ball from `from` through `to` with launch angle `angle` (radians).
    static func launchVelocity(from: Vec3, to: Vec3, angle: Double, gravity: Double) -> Vec3? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let d = sqrt(dx * dx + dy * dy)
        let h = to.z - from.z
        let denom = 2 * pow(cos(angle), 2) * (d * tan(angle) - h)
        guard d > 1e-6, denom > 0 else { return nil }
        let v = sqrt(gravity * d * d / denom)
        let vh = v * cos(angle)
        return Vec3(x: vh * dx / d, y: vh * dy / d, z: v * sin(angle))
    }
}

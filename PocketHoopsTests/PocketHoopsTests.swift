import XCTest
@testable import PocketHoops

final class PhysicsTests: XCTestCase {
    /// Runs one ball to completion and returns what happened to it.
    private func outcome(_ court: Court, from x0: Double, to target: Vec3) -> (scored: Bool, swish: Bool, events: [PhysicsEvent]) {
        let sim = Simulation(court: court)
        let v = Simulation.launchVelocity(from: Vec3(x: x0, y: court.launchY, z: court.launchZ), to: target,
                                          angle: Aim.launchAngle, gravity: court.gravity)!
        sim.launch(from: Vec3(x: x0, y: court.launchY, z: court.launchZ), velocity: v)
        var all: [PhysicsEvent] = []
        for _ in 0..<(60 * 8) {
            all += sim.step(1.0 / 60)
            if sim.balls.isEmpty { break }
        }
        var scored = false, swish = false
        for e in all { if case let .score(_, s, _) = e { scored = true; swish = s } }
        return (scored, swish, all)
    }

    func testDeadCentreShotIsASwishFromAnywhere() {
        let c = Court()
        for x0 in [-0.3, -0.15, 0, 0.15, 0.3] {
            let r = outcome(c, from: x0, to: c.rimCenter)
            XCTAssertTrue(r.scored, "x0=\(x0)")
            XCTAssertTrue(r.swish, "x0=\(x0)")
        }
    }

    func testShortAndLongShotsMiss() {
        let c = Court()
        let short = outcome(c, from: 0, to: Vec3(x: 0, y: c.rimY - 0.5, z: c.rimZ))
        XCTAssertFalse(short.scored)
        XCTAssertTrue(short.events.contains { if case .miss = $0 { return true }; return false })
        // (The machine is narrow, so a wide shot can bank in off the glass; short-and-wide can't.)
        let wide = outcome(c, from: 0, to: Vec3(x: 0.3, y: c.rimY - 0.3, z: c.rimZ))
        XCTAssertFalse(wide.scored)
    }

    func testEveryBallComesBackToTheTray() {
        let c = Court()
        for dy in [-0.6, -0.2, 0, 0.15, 0.4, 1.0] {
            let r = outcome(c, from: 0.1, to: Vec3(x: 0, y: c.rimY + dy, z: c.rimZ))
            XCTAssertTrue(r.events.contains { if case .returned = $0 { return true }; return false }, "dy=\(dy)")
            let resolutions = r.events.filter {
                switch $0 { case .score, .miss: return true; default: return false }
            }
            XCTAssertEqual(resolutions.count, 1, "each shot resolves exactly once (dy=\(dy))")
        }
    }

    func testRimOutsAndBanksHappen() {
        // Sweep depth: somewhere between swish and airball the ball must touch rim or board.
        let c = Court()
        var sawRim = false, sawBankMake = false
        for i in 0..<60 {
            let dy = -0.35 + Double(i) * 0.012
            let r = outcome(c, from: 0, to: Vec3(x: 0.03, y: c.rimY + dy, z: c.rimZ))
            for e in r.events {
                if case .rim = e { sawRim = true }
                if case let .score(_, _, bank) = e, bank { sawBankMake = true }
            }
        }
        XCTAssertTrue(sawRim)
        XCTAssertTrue(sawBankMake)
    }

    /// The reported bug: a very hard flick made the ball vanish. Now every flick — any speed, any
    /// direction — must keep the ball inside the machine and bring it back to the rack.
    func testWildFlicksNeverLoseTheBall() {
        let c = Court()
        let proj = Projection.machine(at: .zero)
        for speed in [300.0, 1_500, 4_000, 20_000, 1_000_000] {
            for angle in [-70.0, -30, 0, 30, 70] {
                let a = angle * .pi / 180
                let (v, _, _) = Aim.shot(viewVelocity: (speed * sin(a), speed * cos(a)), from: 0.1, court: c, projection: proj)
                XCTAssertLessThanOrEqual(v.length, c.maxLaunchSpeed + 1e-9)
                let sim = Simulation(court: c)
                sim.launch(from: Vec3(x: 0.1, y: c.launchY, z: c.launchZ), velocity: v)
                var returned = false
                for _ in 0..<(60 * 10) {
                    for e in sim.step(1.0 / 60) {
                        if case let .returned(_, x, lost) = e {
                            returned = true
                            XCTAssertFalse(lost, "speed \(speed) angle \(angle): should roll back, not need rescuing")
                            XCTAssertTrue(x.isFinite)
                        }
                    }
                    for b in sim.balls {
                        XCTAssertTrue(b.pos.isFinite && b.vel.isFinite)
                        XCTAssertLessThanOrEqual(b.pos.y, c.boardY - c.ballRadius + 1e-6, "went through the backboard")
                        XCTAssertLessThanOrEqual(b.pos.z, c.ceiling - c.ballRadius + 1e-6, "went through the ceiling net")
                        XCTAssertLessThanOrEqual(abs(b.pos.x), c.laneHalfWidth - c.ballRadius + 1e-6, "went through the glass")
                    }
                    if returned { break }
                }
                XCTAssertTrue(returned, "speed \(speed) angle \(angle): ball never came back")
            }
        }
    }

    func testAbsurdVelocityIsClampedAndCannotTunnel() {
        let c = Court()
        let sim = Simulation(court: c)
        let b = sim.launch(from: Vec3(x: 0, y: 0, z: 1), velocity: Vec3(x: 0, y: 500, z: 0))
        XCTAssertLessThanOrEqual(b.vel.length, c.maxLaunchSpeed + 1e-9)
        for _ in 0..<120 {
            _ = sim.step(1.0 / 60)
            if let live = sim.balls.first { XCTAssertLessThanOrEqual(live.pos.y, c.boardY - c.ballRadius + 1e-6) }
        }
    }

    func testCorruptedBallIsRecoveredToTheRackNotDeleted() {
        let sim = Simulation(court: Court())
        let b = sim.launch(from: Vec3(x: 0, y: 0, z: 1), velocity: Vec3(x: 0, y: 2, z: 3))
        b.pos = Vec3(x: .nan, y: 1, z: 1)
        let events = sim.step(1.0 / 60)
        XCTAssertTrue(events.contains { if case .returned(_, _, true) = $0 { return true }; return false })
        XCTAssertTrue(sim.balls.isEmpty)
        let far = sim.launch(from: Vec3(x: 0, y: 0, z: 1), velocity: .zero)
        far.pos = Vec3(x: 9, y: 1, z: 1)
        XCTAssertTrue(sim.step(1.0 / 60).contains { if case .returned(_, _, true) = $0 { return true }; return false })
    }

    /// Where the net's side is at `below` metres under the rim plane (radius from the rim's axis).
    private func netRadius(_ c: Court, below: Double) -> Double {
        c.rimRadius - (c.rimRadius - c.netBottomRadius) * below / c.netDepth
    }

    /// The reported bug: a too-hard flick flew under the rim, through the net, and came out looking
    /// like it had gone through the hoop. However hard the flick — from anywhere, at any angle, with
    /// the hoop anywhere — the ball must never be inside the rim tube, never be under the rim inside
    /// the net unless it came down through the ring, and always come back.
    func testHardFlicksNeverGoUnderOrThroughTheRim() {
        let proj = Projection.machine(at: .zero)
        for hoopX in [0.0, -0.17, 0.17] {
            var c = Court()
            c.hoopX = hoopX
            for power in [1.1, 1.25, 1.4, 2.0, 5.0, 50.0] {
                for angle in [-12.0, 0, 12] {
                    for x0 in [-0.3, 0, 0.3] {
                        let label = "power \(power)× angle \(angle) from \(x0) hoop \(hoopX)"
                        let s = power * Aim.referenceSpeed, a = angle * .pi / 180
                        let (v, _, _) = Aim.shot(viewVelocity: (s * sin(a), s * cos(a)), from: x0, court: c, projection: proj)
                        let sim = Simulation(court: c)
                        let b = sim.launch(from: Vec3(x: x0, y: c.launchY, z: c.launchZ), velocity: v)
                        var returned = false
                        for _ in 0..<(120 * 8) {
                            if sim.step(1.0 / 120).contains(where: { if case .returned = $0 { return true }; return false }) {
                                returned = true
                                break
                            }
                            let q = b.pos - c.rimCenter
                            let rho = q.horizontalLength
                            let toTube = ((rho - c.rimRadius) * (rho - c.rimRadius) + q.z * q.z).squareRoot()
                            XCTAssertGreaterThan(toTube, c.ballRadius + c.rimTube - 0.01, "\(label): ball went into the rim")
                            if !b.scored && q.z < 0 && q.z > -c.netDepth {
                                XCTAssertGreaterThan(rho, netRadius(c, below: -q.z), "\(label): under the rim, inside the net")
                            }
                        }
                        XCTAssertTrue(returned, "\(label): ball never came back")
                    }
                }
            }
        }
    }

    /// The net is solid to a ball that didn't come down through the ring: thrown at it from the
    /// front below the rim, from the side, or up into its bottom opening, it bounces off.
    func testNetStopsBallsThatDidNotGoThroughTheRing() {
        let c = Court()
        let throwsAtNet: [(from: Vec3, velocity: Vec3)] = [
            (Vec3(x: 0, y: c.rimY - 0.7, z: c.rimZ - 0.22), Vec3(x: 0, y: 6, z: 0.5)),
            (Vec3(x: -(c.laneHalfWidth - c.ballRadius), y: c.rimY, z: c.rimZ - 0.1), Vec3(x: 4, y: 0, z: 0.5)),
            (Vec3(x: 0.02, y: c.rimY, z: c.rimZ - c.netDepth - 0.4), Vec3(x: 0, y: 0, z: 4)),
        ]
        for (i, t) in throwsAtNet.enumerated() {
            let sim = Simulation(court: c)
            let b = sim.launch(from: t.from, velocity: t.velocity)
            for _ in 0..<(120 * 3) {
                let events = sim.step(1.0 / 120)
                XCTAssertFalse(events.contains { if case .score = $0 { return true }; return false }, "throw \(i) scored")
                guard sim.balls.contains(where: { $0 === b }) else { break }
                let q = b.pos - c.rimCenter
                if q.z < 0 && q.z > -c.netDepth {
                    XCTAssertGreaterThan(q.horizontalLength, netRadius(c, below: -q.z), "throw \(i) got inside the net")
                }
            }
        }
    }

    /// A ball knocked down through the ring by another one (so it never crossed the rim plane
    /// under its own steam) still counts.
    func testBallKnockedThroughTheRingStillCounts() {
        let c = Court()
        let sim = Simulation(court: c)
        let a = sim.launch(from: Vec3(x: c.hoopX, y: c.rimY, z: c.rimZ + 0.005), velocity: .zero)
        sim.launch(from: Vec3(x: c.hoopX, y: c.rimY, z: c.rimZ + 0.205), velocity: Vec3(x: 0, y: 0, z: -3))
        var events: [PhysicsEvent] = []
        for _ in 0..<120 { events += sim.step(1.0 / 120) }
        XCTAssertTrue(events.contains(.score(ballID: a.id, swish: true, bank: false)))
    }

    /// A hard rebound flies back out over the front of the lane in the air. It must keep flying —
    /// not be taken out of play mid-air (it used to vanish there) — until it comes down to the tray.
    func testReboundOverTheFrontIsNotRemovedMidAir() {
        let c = Court()
        let sim = Simulation(court: c)
        let b = sim.launch(from: Vec3(x: 0, y: c.boardY - c.ballRadius - 0.01, z: 2.0), velocity: Vec3(x: 0, y: -2.2, z: 1.8))
        var handedBackAt: Vec3?
        for _ in 0..<(120 * 3) {
            if sim.step(1.0 / 120).contains(where: { if case .returned(_, _, false) = $0 { return true }; return false }) {
                handedBackAt = b.pos
                break
            }
        }
        XCTAssertNotNil(handedBackAt)
        XCTAssertTrue(handedBackAt.map(c.inTray) ?? false, "taken out of play before reaching the tray: \(String(describing: handedBackAt))")
    }

    /// A ball on its way back out over the shooter doesn't knock their next shot off line (or get
    /// knocked out of the world itself).
    func testReboundAndNewShotPassEachOther() {
        let c = Court()
        let sim = Simulation(court: c)
        // They'd overlap by ~11 cm about 0.05 s in.
        let back = sim.launch(from: Vec3(x: 0, y: c.launchY, z: 0.6), velocity: Vec3(x: 0, y: -1.0, z: 0))
        let shotVelocity = Vec3(x: 0, y: 1.4, z: 5.8)
        let shot = sim.launch(from: Vec3(x: 0, y: c.launchY, z: c.launchZ), velocity: shotVelocity)
        for _ in 0..<12 { _ = sim.step(1.0 / 120) }
        XCTAssertEqual(back.vel.y, -1.0, accuracy: 1e-9)
        XCTAssertEqual(shot.vel.y, shotVelocity.y, accuracy: 1e-9)
    }

    /// With the hoop sliding toward the side glass, a ball sitting in the corner between the rim,
    /// the backboard and the glass, with another ball stacked on it, gets squeezed: the glass and
    /// board undo the rim's sideways push. It must ride on the rim, not sink into it.
    func testBallSqueezedInTheCornerRidesOnTheRim() {
        var c = Court()
        c.hoopX = 0.17 * sin(0.4)
        let sim = Simulation(court: c)
        let x = c.laneHalfWidth - c.ballRadius, y = c.boardY - c.ballRadius
        let minDist = c.ballRadius + c.rimTube
        let off = ((x - c.hoopX) * (x - c.hoopX) + (y - c.rimY) * (y - c.rimY)).squareRoot() - c.rimRadius
        let low = sim.launch(from: Vec3(x: x, y: y, z: c.rimZ + (minDist * minDist - off * off).squareRoot()), velocity: .zero)
        sim.launch(from: low.pos + Vec3(x: -0.03, y: -0.03, z: 0.24), velocity: .zero)
        var t = 0.4 / 1.1, deepest = 0.0
        for _ in 0..<(120 * 3) {
            sim.court.hoopX = 0.17 * sin(t * 1.1)
            _ = sim.step(1.0 / 120)
            t += 1.0 / 120
            guard sim.balls.contains(where: { $0 === low }) else { break }
            let q = low.pos - sim.court.rimCenter
            let o = q.horizontalLength - c.rimRadius
            deepest = max(deepest, minDist - (o * o + q.z * q.z).squareRoot())
        }
        XCTAssertLessThan(deepest, 0.01)
    }

    /// A ball that lands in the gap between the back of the rim and the backboard rolls out of it
    /// rather than sitting there — even one balanced dead centre.
    func testBallDoesNotStickBetweenTheRimAndBackboard() {
        let c = Court()
        for dx in [0.0, 0.03] {
            let sim = Simulation(court: c)
            let b = sim.launch(from: Vec3(x: dx, y: c.boardY - c.ballRadius, z: c.rimZ + 0.14), velocity: .zero)
            var rolledOut = false
            for _ in 0..<(120 * 3) {
                _ = sim.step(1.0 / 120)
                if b.pos.z < c.rimZ - 0.1 || !sim.balls.contains(where: { $0 === b }) {
                    rolledOut = true
                    break
                }
            }
            XCTAssertTrue(rolledOut, "dx \(dx): still stuck behind the rim after 3 s")
        }
    }
}

final class RackTests: XCTestCase {
    func testBallsDropInRollDownAndSettleWithoutOverlapping() {
        let rack = Rack(minX: 23, maxX: 56, lowX: 39.5)
        for (x, h) in [(25.0, 10.0), (54.0, 8.0), (40.0, 12.0), (30.0, 9.0), (50.0, 11.0)] { rack.add(at: x, height: h) }
        var landed = 0
        for _ in 0..<(60 * 4) { landed += rack.step(1.0 / 60).count }
        XCTAssertEqual(landed, 5, "every ball drops in and lands once")
        XCTAssertEqual(rack.count, 5)
        XCTAssertTrue(rack.isSettled)
        let xs = rack.balls.map(\.x).sorted()
        // A full rack packs its balls closer (overlapping, like the jumble in the reference art).
        let packed = min(rack.spacing, (rack.maxX - rack.minX) / Double(xs.count - 1))
        for (a, b) in zip(xs, xs.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, packed - 0.6) }
        XCTAssertTrue(xs.allSatisfy { $0 >= rack.minX && $0 <= rack.maxX })
        // Gathered around the low point, not left where they fell.
        XCTAssertLessThan(abs(xs.reduce(0, +) / Double(xs.count) - rack.lowX), 3)
    }

    func testTakingABallLetsTheOthersRollIn() {
        let rack = Rack(minX: 23, maxX: 56, lowX: 39.5)
        for x in [28.0, 39.5, 51.0] { rack.add(at: x) }
        for _ in 0..<120 { rack.step(1.0 / 60) }
        let taken = rack.take(nearest: 39.5)
        XCTAssertNotNil(taken)
        XCTAssertLessThan(abs(taken!.x - 39.5), 6)
        let before = rack.balls.map(\.spin)
        for _ in 0..<120 { rack.step(1.0 / 60) }
        let xs = rack.balls.map(\.x).sorted()
        XCTAssertLessThan(xs[1] - xs[0], rack.spacing + 1, "the gap closes as they roll down")
        XCTAssertNotEqual(rack.balls.map(\.spin), before, "rolling turns the balls")
    }
}

final class AimTests: XCTestCase {
    private func makeRate(speeds: [Double], angleDeg: Double = 0, x0: Double = 0) -> [Double: Bool] {
        let c = Court()
        let proj = Projection.machine(at: .zero)
        var out: [Double: Bool] = [:]
        for s in speeds {
            let a = angleDeg * .pi / 180
            let (v, _, _) = Aim.shot(viewVelocity: (s * sin(a), s * cos(a)), from: x0, court: c, projection: proj)
            let sim = Simulation(court: c)
            sim.launch(from: Vec3(x: x0, y: c.launchY, z: c.launchZ), velocity: v)
            var scored = false
            for _ in 0..<480 {
                for e in sim.step(1.0 / 60) { if case .score = e { scored = true } }
                if sim.balls.isEmpty { break }
            }
            out[s] = scored
        }
        return out
    }

    func testReferenceFlickScoresAndWindowIsForgiving() {
        // Speeds relative to the reference (the player's calibrated normal flick).
        let ref = Aim.referenceSpeed
        let speeds = stride(from: 0.5, through: 1.8, by: 0.025).map { ($0 * ref).rounded() }
        let r = makeRate(speeds: speeds)
        XCTAssertEqual(r[ref], true)
        let made = speeds.filter { r[$0] == true }
        print("MAKE WINDOW", made.map { Int($0) }, "reference", Int(ref))
        // A person's flicks vary ±15% or so; the window should cover at least that.
        XCTAssertTrue(speeds.filter { abs($0 / ref - 1) <= 0.15 }.allSatisfy { r[$0] == true })
        XCTAssertFalse(r[(0.6 * ref).rounded()]!, "a much softer flick than usual falls short")
        XCTAssertFalse(r[(1.6 * ref).rounded()]!, "a much harder flick than usual goes long")
    }

    func testFlickDirectionSteers() {
        // From the left side, a straight-up flick misses left of the rim but a flick angled at the hoop scores.
        let straight = makeRate(speeds: [Aim.referenceSpeed], angleDeg: 0, x0: -0.3)
        let angled = makeRate(speeds: [Aim.referenceSpeed], angleDeg: 13, x0: -0.3)
        XCTAssertEqual(straight[Aim.referenceSpeed], false)
        XCTAssertEqual(angled[Aim.referenceSpeed], true)
    }

    /// A clearly too-hard flick goes over the front of the rim (not under it), hits the backboard
    /// above the rim and rebounds back out.
    func testTooHardFlicksGoOverTheRimAndReboundOut() {
        let c = Court()
        let proj = Projection.machine(at: .zero)
        for power in [1.4, 2.0, 5.0] {
            let (v, _, _) = Aim.shot(viewVelocity: (0, power * Aim.referenceSpeed), from: 0, court: c, projection: proj)
            let sim = Simulation(court: c)
            let b = sim.launch(from: Vec3(x: 0, y: c.launchY, z: c.launchZ), velocity: v)
            var scored = false
            var overFrontRim: Double?
            for _ in 0..<(120 * 6) {
                for e in sim.step(1.0 / 120) { if case .score = e { scored = true } }
                if overFrontRim == nil && b.pos.y >= c.rimY - c.rimRadius { overFrontRim = b.pos.z }
                if !sim.balls.contains(where: { $0 === b }) { break }
            }
            XCTAssertGreaterThan(overFrontRim ?? 0, c.rimZ + c.rimTube + c.ballRadius, "\(power)×: under the rim")
            XCTAssertTrue(b.touchedBoard, "\(power)×")
            XCTAssertFalse(b.touchedRim, "\(power)×")
            XCTAssertFalse(scored, "\(power)×")
        }
    }
}

final class RimLayerTests: XCTestCase {
    /// The reported "went through the rim": a ball that rolled off the *outside* of the rim was
    /// drawn behind the front of the ring and the net, i.e. inside the hoop.
    func testBallsAreDrawnOnTheSideOfTheRimTheyAreReallyOn() {
        let c = Court()
        func layer(_ x: Double, _ y: Double, _ z: Double, scored: Bool = false) -> GameScene.RimLayer {
            let b = Ball(id: 1, pos: c.rimCenter + Vec3(x: x, y: y, z: z), vel: .zero)
            b.scored = scored
            return GameScene.rimLayer(of: b, court: c)
        }
        let out = (c.rimRadius + 0.13) / 2.0.squareRoot()
        XCTAssertEqual(layer(-out, -out, -0.05), .inFront, "fell off the front-left, outside: in front of the ring")
        XCTAssertEqual(layer(out, -out, -0.2), .inFront, "fell off the front-right, outside: in front of the ring")
        XCTAssertEqual(layer(-out, out, -0.05), .behindRing, "fell off the back, outside: behind the ring")
        XCTAssertEqual(layer(0.05, 0.02, -0.05, scored: true), .throughHoop, "dropping through the hoop")
        XCTAssertEqual(layer(0.1, -0.1, -0.02), .throughHoop, "inside the ring, going down")
        XCTAssertEqual(layer(0, -c.rimRadius, 0.13), .inFront, "sitting on top of the front rim")
    }
}

final class FlickTests: XCTestCase {
    /// A stroke that speeds up to `peak` pt/s and then slows to a crawl before lifting,
    /// like a real finger (or the simulator's eased swipes), sampled at 120 Hz.
    private func stroke(peak: Double, angleDeg: Double = 0, hookAtEnd: Double = 0) -> [Flick.Sample] {
        var out: [Flick.Sample] = []
        var p = CGPoint(x: 200, y: 800)
        let a = angleDeg * .pi / 180
        let n = 24
        for i in 0...n {
            let t = Double(i) / 120
            let phase = Double(i) / Double(n)
            let speed = peak * sin(.pi * phase)          // up, then back down to ~0 at release
            var dx = speed * sin(a) / 120, dy = speed * cos(a) / 120
            if phase > 0.85 { dx += hookAtEnd / 120 }     // a sideways twitch as the finger lifts
            if i > 0 { p = CGPoint(x: p.x + dx, y: p.y - dy) }
            out.append(Flick.Sample(t: t, p: p))
        }
        return out
    }

    func testReadsThePeakNotTheSlowRelease() {
        let v = Flick.velocity(stroke(peak: 2000))!
        let speed = (v.x * v.x + v.y * v.y).squareRoot()
        XCTAssertGreaterThan(speed, 1700, "the old last-120 ms average read this flick far too slow")
        XCTAssertLessThan(speed, 2100)
        XCTAssertLessThan(abs(v.x), 1)
    }

    func testDirectionComesFromTheWholeStroke() {
        let v = Flick.velocity(stroke(peak: 1800, angleDeg: 10, hookAtEnd: -300))!
        let angle = atan2(v.x, v.y) * 180 / .pi
        XCTAssertEqual(angle, 10, accuracy: 3, "a twitch as the finger lifts doesn't change the aim")
    }

    func testSidewaysDragIsNotAShot() {
        let drag = (0...20).map { Flick.Sample(t: Double($0) / 120, p: CGPoint(x: 100 + Double($0) * 8, y: 800)) }
        XCTAssertNil(Flick.velocity(drag))
    }

    func testCalibrationFollowsThePlayerButIgnoresWildFlicks() {
        var c = FlickCalibration()
        for _ in 0..<12 { c.record(1000) }
        XCTAssertEqual(c.reference, 1000, accuracy: 60, "a player who always flicks at 1000 gets centred shots")
        let before = c.reference
        c.record(5000)
        XCTAssertEqual(c.reference, before, "one mis-swipe doesn't skew it")
        for _ in 0..<60 { c.record(300) }
        XCTAssertGreaterThanOrEqual(c.reference, FlickCalibration.range.lowerBound)
    }
}

final class RulesTests: XCTestCase {
    func testFireDoublesPointsAndMissPutsItOut() {
        var k = Scorekeeper()
        XCTAssertEqual(k.make(swish: false, bank: false, frenzy: false).points, 2)
        XCTAssertEqual(k.make(swish: false, bank: false, frenzy: false).points, 2)
        let third = k.make(swish: false, bank: false, frenzy: false)
        XCTAssertTrue(third.lit)
        XCTAssertEqual(third.points, 2, "the lighting shot itself isn't doubled")
        XCTAssertEqual(k.make(swish: true, bank: false, frenzy: true).points, 8, "(3 + swish 1) × 2")
        XCTAssertTrue(k.miss())
        XCTAssertFalse(k.onFire)
        XCTAssertEqual(k.make(swish: false, bank: false, frenzy: false).points, 2)
        XCTAssertEqual(k.fires, 1)
        XCTAssertEqual(k.bestStreak, 4)
    }

    func testArcadeStageTwoOnlyIfTargetMet() {
        var s = GameSession(config: .make(.arcade))
        _ = s.update(39)
        XCTAssertTrue(s.frenzy)
        let e = s.update(2)
        XCTAssertEqual(e.last, .over)

        var s2 = GameSession(config: .make(.arcade))
        while s2.keeper.score < s2.config.stageTargets[0] { _ = s2.registerMake(swish: false, bank: false) }
        let e2 = s2.update(41)
        XCTAssertTrue(e2.contains(.stage(2, bonus: 20)))
        XCTAssertFalse(s2.isOver)
        XCTAssertGreaterThan(s2.hoopMotion.amplitude, 0, "stage 2 hoop moves")
    }

    /// Stage 2 takes twice the score it used to (40 → 80) and stage 3 three times (100 → 300), both
    /// running totals checked at the buzzer; the clock and the bonus time are as they were.
    func testArcadeStagesNeedTwiceAndThreeTimesTheOldScores() {
        let arcade = ModeConfig.make(.arcade)
        XCTAssertEqual(arcade.stageTargets, [40 * 2, 100 * 3])
        XCTAssertEqual(arcade.stageBonusTime, [20, 15])
        XCTAssertEqual(arcade.timeLimit, 40)

        /// An Arcade game that has made baskets (without swishes, so on fire: 2+2+2, then 4 each)
        /// until it has at least `points`.
        func game(scoring points: Int) -> GameSession {
            var s = GameSession(config: .make(.arcade))
            while s.keeper.score < points { _ = s.registerMake(swish: false, bank: false) }
            return s
        }
        var before = game(scoring: 74)
        XCTAssertEqual(before.keeper.score, 74, "what used to be plenty for stage 2")
        XCTAssertEqual(before.update(41).last, .over)
        var short = game(scoring: 78)
        XCTAssertEqual(short.keeper.score, 78)
        XCTAssertEqual(short.update(41).last, .over)

        var s = game(scoring: 80)
        XCTAssertEqual(s.keeper.score, 82)
        XCTAssertEqual(s.update(41), [.stage(2, bonus: 20)])
        XCTAssertEqual(s.targetForCurrentStage, 300)
        var shortOfThree = s
        while shortOfThree.keeper.score < 298 { _ = shortOfThree.registerMake(swish: false, bank: false) }
        XCTAssertEqual(shortOfThree.keeper.score, 298)
        XCTAssertEqual(shortOfThree.update(21).last, .over, "100, and even 298, no longer reaches stage 3")
        while s.keeper.score < 300 { _ = s.registerMake(swish: false, bank: false) }
        XCTAssertEqual(s.keeper.score, 302)
        XCTAssertEqual(s.update(21), [.stage(3, bonus: 15)])
        XCTAssertNil(s.targetForCurrentStage, "stage 3 is the last")
    }

    func testSuddenDeathLivesAndLevels() {
        var s = GameSession(config: .make(.streak))
        for _ in 0..<5 { _ = s.registerMake(swish: false, bank: false) }
        XCTAssertEqual(s.level, 2)
        XCTAssertEqual(s.keeper.score, 5, "one point per basket")
        _ = s.registerMiss(); _ = s.registerMiss()
        XCTAssertFalse(s.isOver)
        let last = s.registerMiss()
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(last.events.last, .over)
    }

    func testVersusSwapsPlayers() {
        var s = GameSession(config: .make(.versus))
        _ = s.registerMake(swish: false, bank: false)
        XCTAssertEqual(s.update(31), [.playerSwap(2)])
        XCTAssertEqual(s.keeper.score, 0)
        _ = s.update(31)
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.playerScores, [2, 0])
    }

    /// Each player's results card shows their own shots, not the other player's or a mix: the hand-off
    /// keeps P1's numbers, and a shot of P2's that drops after the final buzzer counts for P2.
    func testVersusKeepsEachPlayersOwnStats() {
        var s = GameSession(config: .make(.versus))
        s.keeper.shot(); _ = s.registerMake(swish: true, bank: false) // P1: a swish, 3
        s.keeper.shot(); _ = s.registerMiss()
        XCTAssertEqual(s.update(31), [.playerSwap(2)])
        for _ in 0..<3 { s.keeper.shot(); _ = s.registerMake(swish: false, bank: false) } // 2+2+2, then on fire
        s.keeper.shot(); _ = s.registerMake(swish: false, bank: true) // on fire: 4
        s.keeper.shot() // still in the air at the buzzer…
        XCTAssertEqual(s.update(31), [.over])
        _ = s.registerMake(swish: false, bank: false) // …and drops: 4
        XCTAssertEqual(s.players, [
            PlayerStats(score: 3, makes: 1, attempts: 2, swishes: 1, banks: 0, fires: 0, bestStreak: 1),
            PlayerStats(score: 14, makes: 5, attempts: 5, swishes: 0, banks: 1, fires: 1, bestStreak: 5),
        ])
        XCTAssertEqual(s.playerScores, [3, 14], "the buzzer beater decides the winner too")
        XCTAssertEqual(s.players.map(\.accuracyPercent), [50, 100])
        let lines = s.players.map { ResultsView.lines($0).map(\.value) }
        XCTAssertEqual(lines, [["1/2", "50%", "1", "0", "1", "0X"], ["5/5", "100%", "0", "1", "5", "1X"]])
        XCTAssertEqual(ResultsView.lines(s.players[0]).map(\.label),
                       ["MADE", "ACCURACY", "SWISHES", "BANK SHOTS", "BEST STREAK", "ON FIRE"],
                       "every stat a one-player card shows")
        XCTAssertTrue(GameSession(config: .make(.arcade)).players.isEmpty)
    }

    func testDailyIsDeterministicAndNeverClashes() {
        let cal = Calendar(identifier: .gregorian)
        var d = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        for _ in 0..<365 {
            let a = Daily.modifiers(for: d), b = Daily.modifiers(for: d)
            XCTAssertEqual(a, b)
            XCTAssertEqual(a.count, 2)
            XCTAssertFalse(Set(a) == [.tinyRim, .bigRim] || Set(a) == [.moon, .heavy])
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
    }
}

@MainActor
final class ProgressTests: XCTestCase {
    private func fresh() -> PlayerProgress {
        // One scratch suite, emptied around every test, so test runs don't pile up saves in the
        // app's preferences.
        let suite = "pockethoops.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return PlayerProgress(defaults: defaults)
    }

    func testRecordingPaysTicketsBestsAndMissions() {
        let p = fresh()
        let now = Date()
        let r = GameResult(mode: .daily, score: 30, makes: 12, attempts: 20, swishes: 4, banks: 1, fires: 1, bestStreak: 5)
        let pay = p.record(r, now: now)
        XCTAssertTrue(pay.newBest)
        XCTAssertEqual(pay.dailyStreak, 1)
        XCTAssertTrue(pay.completedMissions.contains { $0.kind == .playDaily })
        // 30 points on the Daily = 7 tickets, + 7 for the first Daily of a 1-day streak, + the
        // small new-best bonus, + whatever missions it finished (at least "play the Daily": 10).
        XCTAssertEqual(PlayerProgress.tickets(for: r), 7)
        XCTAssertEqual(pay.bestBonus, PlayerProgress.newBestBonus)
        XCTAssertEqual(pay.tickets, 7 + 7 + pay.bestBonus + pay.completedMissions.map(\.reward).reduce(0, +))
        XCTAssertGreaterThanOrEqual(pay.tickets, 7 + 7 + 2 + 10)
        XCTAssertEqual(p.data.tickets, pay.tickets)
        // Second daily the same day: no streak bump, no repeat mission reward.
        let pay2 = p.record(r, now: now)
        XCTAssertNil(pay2.dailyStreak)
        XCTAssertFalse(pay2.completedMissions.contains { $0.kind == .playDaily })
        // Tomorrow continues the streak.
        let pay3 = p.record(r, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(pay3.dailyStreak, 2)
    }

    /// Tickets are about half as easy to earn as they were (2–2.15× harder) in every mode, and for
    /// the daily streak bonus and missions too; only beating a best adds a small extra.
    func testTicketsPayAboutHalfWhatTheyDid() {
        func oldTickets(_ r: GameResult) -> Int {
            switch r.mode {
            case .arcade: return max(1, r.score / 3)
            case .streak: return max(1, r.makes * 2)
            case .daily: return max(1, r.score / 2)
            case .versus: return max(1, (r.playerScores.max() ?? r.score) / 4)
            case .practice: return r.makes / 5
            }
        }
        for mode in GameMode.allCases {
            var old = 0, new = 0
            for points in stride(from: 20, through: 150, by: 10) {
                let r = GameResult(mode: mode, score: points, makes: points / 2, attempts: points, swishes: 0,
                                   banks: 0, fires: 0, bestStreak: 0,
                                   players: mode == .versus ? [PlayerStats(score: points), PlayerStats()] : [])
                old += oldTickets(r)
                new += PlayerProgress.tickets(for: r)
            }
            let harder = Double(old) / Double(new)
            XCTAssertGreaterThanOrEqual(harder, 1.95, "\(mode)")
            XCTAssertLessThanOrEqual(harder, 2.2, "\(mode)")
        }
        let oldMissions = 20 + 30 + 40 + 40 + 35 + 45 + 50 + 25
        let newMissions = ([PlayerProgress.dailyMission] + PlayerProgress.missionPool).map(\.reward).reduce(0, +)
        XCTAssertEqual(Double(oldMissions) / Double(newMissions), 2.05, accuracy: 0.1)
        let oldDaily = (1...6).map { 10 + 5 * $0 }.reduce(0, +)
        let newDaily = (1...6).map { PlayerProgress.dailyBonus(dayStreak: $0) }.reduce(0, +)
        XCTAssertEqual(Double(oldDaily) / Double(newDaily), 2.05, accuracy: 0.1)
        XCTAssertLessThanOrEqual(PlayerProgress.newBestBonus, 3, "the best bonus stays small")
    }

    /// Missions handed out before the reward cut (stored in the save) pay the new amounts.
    func testStoredMissionsPayTheCurrentRewards() {
        let suite = "pockethoops.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        PlayerProgress(defaults: defaults).update { d in for i in d.missions.indices { d.missions[i].reward = 99 } }
        let reloaded = PlayerProgress(defaults: defaults)
        let table = [PlayerProgress.dailyMission] + PlayerProgress.missionPool
        XCTAssertFalse(reloaded.data.missions.isEmpty)
        for m in reloaded.data.missions {
            XCTAssertEqual(m.reward, table.first { $0.kind == m.kind }?.reward, "\(m.kind)")
        }
    }

    func testPrizeCounter() {
        let p = fresh()
        XCTAssertFalse(p.buySkin(BallSkin.gold))
        p.update { $0.tickets = 600 }
        XCTAssertFalse(p.buySkin(BallSkin.gold), "tickets alone aren't enough: it needs 2000 baskets and a 150 game")
        XCTAssertEqual(p.data.tickets, 600)
        p.update { $0.totalMakes = 2000; $0.best[GameMode.arcade.rawValue] = 150 }
        XCTAssertTrue(p.buySkin(BallSkin.gold))
        XCTAssertEqual(p.data.tickets, 100)
        XCTAssertEqual(p.data.skin, "gold")
        XCTAssertFalse(p.buySkin(BallSkin.gold), "can't buy twice")
    }
}

@MainActor
final class ShopTests: XCTestCase {
    private func fresh() -> PlayerProgress {
        let suite = "pockethoops.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return PlayerProgress(defaults: defaults)
    }

    /// A save written before characters and accessories existed still loads, keeping every ticket,
    /// stat and purchase (a missing field must never reset the save).
    func testOldSavesLoadWithEverythingKept() throws {
        let old = """
        {"tickets":897,"ownedSkins":["classic","street","tennis"],"ownedThemes":["classic","neon"],"skin":"tennis",
         "theme":"neon","best":{"arcade":120},"games":40,"totalMakes":900,"totalAttempts":1300,"totalSwishes":300,
         "longestStreak":14,"missionsDay":"","missions":[],"dailyDay":"","dailyBest":0,"lastDailyPlayed":"",
         "dayStreak":2,"sound":true,"haptics":false,"seenTutorial":true,"someFutureField":5}
        """
        let d = try JSONDecoder().decode(SaveData.self, from: Data(old.utf8))
        XCTAssertEqual(d.tickets, 897)
        XCTAssertEqual(d.ownedSkins, ["classic", "street", "tennis"])
        XCTAssertEqual(d.ownedThemes, ["classic", "neon"])
        XCTAssertEqual(d.skin, "tennis")
        XCTAssertEqual(d.theme, "neon")
        XCTAssertEqual(d.best["arcade"], 120)
        XCTAssertEqual(d.games, 40)
        XCTAssertFalse(d.haptics)
        XCTAssertEqual(d.avatar, Avatar.rookie.id)
        XCTAssertEqual(d.ownedAvatars, [Avatar.rookie.id])
        XCTAssertTrue(d.ownedAccessories.isEmpty)
        XCTAssertEqual(d.boardID, "", "nobody is on the world board until they join")
        XCTAssertEqual(d.boardName, "")
        var changed = d
        changed.ownedAccessories = ["beanie"]
        changed.outfit = ["hat": "beanie"]
        changed.ownedAvatars.insert("maya")
        changed.avatar = "maya"
        changed.boardID = UUID().uuidString.lowercased()
        changed.boardName = "JENN"
        XCTAssertEqual(try JSONDecoder().decode(SaveData.self, from: JSONEncoder().encode(changed)), changed)
    }

    func testRequirementsGateBuyingAndShowProgress() {
        let p = fresh()
        let r = Requirement.baskets(250)
        p.update { $0.totalMakes = 112; $0.tickets = 1_000 }
        XCTAssertEqual(r.text + ": " + p.data.progress(r), "MAKE 250 BASKETS: 112/250")
        let beanie = Accessory.byID("beanie")!  // 80 tickets, play 5 games
        p.update { $0.games = 4 }
        XCTAssertFalse(p.buyAccessory(beanie), "requirement not met yet")
        XCTAssertEqual(p.data.tickets, 1_000)
        p.update { $0.games = 5 }
        XCTAssertTrue(p.buyAccessory(beanie))
        XCTAssertEqual(p.data.tickets, 920)
        XCTAssertEqual(p.outfit.items[.hat], "beanie", "bought = worn")
        let dre = Avatar.byID("dre")  // 400 tickets, 15 games
        XCTAssertFalse(p.buyAvatar(dre))
        p.update { $0.games = 15; $0.tickets = 399 }
        XCTAssertFalse(p.buyAvatar(dre), "one ticket short")
        p.update { $0.tickets = 400 }
        XCTAssertTrue(p.buyAvatar(dre))
        XCTAssertEqual(p.data.avatar, "dre")
        XCTAssertEqual(p.data.tickets, 0)
    }

    /// Anything already owned stays owned and can be equipped any time, requirements or not.
    func testOwnedItemsStayOwnedAndEquipForFree() {
        let p = fresh()
        p.update {
            $0.ownedSkins.insert("gold"); $0.ownedThemes.insert("midnight")
            $0.ownedAccessories = ["crown", "hoodie"]; $0.ownedAvatars.insert("robo"); $0.ownedAvatars.insert("maya")
        }
        XCTAssertFalse(p.data.met(BallSkin.gold.unlock), "no progress at all")
        p.wear(Accessory.byID("crown")!)
        p.wear(Accessory.byID("hoodie")!)
        p.wear(Accessory.byID("beanie")!)  // not owned: ignored
        XCTAssertEqual(p.outfit.items, [.hat: "crown", .jacket: "hoodie"])
        XCTAssertEqual(p.data.tickets, 0)
        // Switching characters keeps the accessories: a costume just doesn't show them.
        p.choose(Avatar.byID("robo"))
        XCTAssertEqual(p.outfit.avatar, "robo")
        XCTAssertTrue(p.outfit.worn.isEmpty)
        p.choose(Avatar.byID("maya"))
        XCTAssertEqual(p.outfit.worn, [.hat: "crown", .jacket: "hoodie"])
        p.takeOff(.hat)
        XCTAssertEqual(p.outfit.worn, [.jacket: "hoodie"])
        p.choose(Avatar.byID("legend"))  // not owned
        XCTAssertEqual(p.data.avatar, "maya")
    }

    /// Every character draws in every pose with each accessory it can wear, the accessory really
    /// changes the picture, and no skin placeholder colour is ever left showing.
    func testEveryOutfitDrawsInEveryPose() {
        let placeholders = Set(OutfitArt.shared.skinKeys.map(OutfitArt.colour))
        for v in Avatar.all {
            for pose in KidPose.allCases {
                let bare = GIFArt.kidCanvas(pose, outfit: Outfit(avatar: v.id))
                XCTAssertEqual(bare.width, OutfitArt.shared.cell[0])
                for a in Accessory.all where pose == .idle || a.category == .hat {
                    let dressed = GIFArt.kidCanvas(pose, outfit: Outfit(avatar: v.id).with(a))
                    XCTAssertFalse(dressed.pixels.contains { placeholders.contains($0) }, "\(v.id) \(a.id) \(pose)")
                    if pose == .idle {
                        XCTAssertEqual(dressed.pixels != bare.pixels, v.wears.contains(a.category), "\(v.id) wearing \(a.id)")
                    }
                }
            }
            XCTAssertNotNil(GIFArt.kid(.jump, skin: .gold, outfit: Outfit(avatar: v.id)))
        }
    }

    func testCatalogMatchesTheArtAndStaysSane() {
        let art = OutfitArt.shared
        for a in Accessory.all {
            XCTAssertNotNil(GIFArt.url("outfit_acc_\(a.id)", "png"), a.id)
        }
        for v in Avatar.all where v != .rookie {
            XCTAssertNotNil(GIFArt.url("outfit_avatar_\(v.id)", "png"), v.id)
        }
        for v in Avatar.all { XCTAssertEqual(art.avatars[v.id]?.skin.count, 3, v.id) }
        XCTAssertEqual(art.poses.sorted(), KidPose.allCases.map(\.rawValue).sorted())
        for ids in [Accessory.all.map(\.id), Avatar.all.map(\.id), BallSkin.all.map(\.id), CabinetTheme.all.map(\.id)] {
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate id")
        }
        for c in AccessoryCategory.allCases { XCTAssertGreaterThanOrEqual(Accessory.of(c).count, 5, c.title) }
        let unlocks = Accessory.all.map { ($0.price, $0.unlock) } + Avatar.all.map { ($0.price, $0.unlock) }
            + BallSkin.all.map { ($0.price, $0.unlock) } + CabinetTheme.all.map { ($0.price, $0.unlock) }
        for (price, unlock) in unlocks {
            XCTAssertLessThanOrEqual(unlock.requirements.count, 2)
            // Cheap things: little or nothing to do first. Pricey things: real playing.
            if price <= 60 { XCTAssertTrue(unlock.requirements.allSatisfy { $0.stat == .games && $0.target <= 5 }) }
            if price >= 300 { XCTAssertFalse(unlock.requirements.isEmpty, "\(price)") }
        }
        XCTAssertTrue(Avatar.all.filter { $0 != .rookie }.allSatisfy { $0.price >= 400 }, "characters cost more")
    }
}

/// Stands in for the leaderboard server: records each request and answers with `reply`.
final class BoardStub: URLProtocol {
    static var seen: [URLRequest] = []
    static var reply: (status: Int, body: String) = (200, "")

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BoardStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var r = request
        if r.httpBody == nil, let stream = r.httpBodyStream {
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            stream.open()
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
            r.httpBody = body
        }
        BoardStub.seen.append(r)
        let response = HTTPURLResponse(url: request.url!, statusCode: BoardStub.reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(BoardStub.reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class BoardTests: XCTestCase {
    private let suite = "pockethoops.tests"

    private func scratch() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: "pockethoops.tests") }
        return defaults
    }

    /// Exactly what the server's arcade_leaderboard function sends (copied from a local run).
    private let reply = """
        {"total" : 2, "top" : [{"rank" : 1, "name" : "ACE", "outfit" : "robo:", "score" : 420, "you" : false}], \
        "you" : {"rank" : 2, "name" : "JAY", "outfit" : "kid:crown", "score" : 224, "you" : true}}
        """

    func testMayaIsNowJennWithTheSameArtPriceAndUnlock() {
        let jenn = Avatar.byID("maya")
        XCTAssertEqual(jenn.name, "Jenn")
        XCTAssertEqual(jenn.price, 400)
        XCTAssertEqual(jenn.unlock, .needs(.baskets(500)))
        XCTAssertEqual(jenn.wears, Set(AccessoryCategory.allCases))
        XCTAssertFalse(Avatar.all.contains { $0.name.uppercased().contains("MAYA") })
        XCTAssertNotNil(OutfitArt.shared.avatars["maya"], "her art is the same file as before")
        #if DEBUG
        XCTAssertEqual(Outfit(debug: "jenn,beanie").avatar, "maya")
        XCTAssertEqual(Outfit(debug: "maya,beanie").avatar, "maya")
        #endif
    }

    func testOutfitCodeRoundTripsAndSkipsWhatItDoesNotKnow() throws {
        XCTAssertEqual(Outfit(avatar: "maya", items: [.hat: "beanie", .jacket: "hoodie"]).code, "maya:beanie,hoodie")
        XCTAssertEqual(Outfit(avatar: "robo", items: [.hat: "crown"]).code, "robo:", "a costume shows no accessories")
        XCTAssertEqual(Outfit().code, "kid:")
        let server = try NSRegularExpression(pattern: "^[a-z0-9]{1,16}:[a-z0-9,]{0,120}$")
        for v in Avatar.all {
            for a in Accessory.all {
                var look = Outfit(avatar: v.id, items: [a.category: a.id])
                if a.category != .shoes { look.items[.shoes] = "goldkicks" }
                let back = Outfit(code: look.code)
                XCTAssertEqual(back.avatar, look.avatar)
                XCTAssertEqual(back.worn, look.worn, look.code)
                XCTAssertNotNil(server.firstMatch(in: look.code, range: NSRange(look.code.startIndex..., in: look.code)), look.code)
            }
        }
        let future = Outfit(code: "dragon:jetpack,beanie")
        XCTAssertEqual(future.avatar, Avatar.rookie.id)
        XCTAssertEqual(future.worn, [.hat: "beanie"])
        XCTAssertEqual(Outfit(code: "").avatar, Avatar.rookie.id)
    }

    func testBoardNamesKeepToWhatTheFontAndTheServerTake() throws {
        XCTAssertEqual(BoardName.clean("jason"), "JASON")
        XCTAssertEqual(BoardName.clean("  j@s0n!!  "), "JS0N ", "a space can be typed at the end")
        XCTAssertEqual(BoardName.final("  j@s0n!!  "), "JS0N")
        XCTAssertEqual(BoardName.final("big   dog"), "BIG DOG")
        XCTAssertEqual(BoardName.final("abcdefghijklmnop"), "ABCDEFGHIJ")
        XCTAssertEqual(BoardName.final("zoë"), "ZO")
        XCTAssertNil(BoardName.final("  !!  "))
        XCTAssertNil(BoardName.final("🏀🏀"))
        let server = try NSRegularExpression(pattern: "^[A-Z0-9]([A-Z0-9 ]{0,8}[A-Z0-9])?$")
        for raw in ["a", "ab cd", "x y z", "abcdefghi j", "  hi  there  ", "0123456789012", "Jenn"] {
            let name = try XCTUnwrap(BoardName.final(raw))
            XCTAssertNotNil(server.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), name)
            for ch in name { XCTAssertNotNil(PixelFont.glyphs[ch], "\(ch) in \(name)") }
        }
    }

    func testJoiningMakesOneIDAndANewNameKeepsIt() throws {
        let p = PlayerProgress(defaults: scratch())
        XCTAssertNil(p.boardPlayer)
        XCTAssertFalse(p.joinBoard(name: " !! "))
        XCTAssertNil(p.boardPlayer, "no usable name, no joining")
        XCTAssertTrue(p.joinBoard(name: "jason"))
        let first = try XCTUnwrap(p.boardPlayer)
        XCTAssertEqual(first.name, "JASON")
        XCTAssertTrue(p.joinBoard(name: "jay d"))
        XCTAssertEqual(p.boardPlayer?.id, first.id, "a new name keeps the player's place on the board")
        XCTAssertEqual(p.boardPlayer?.name, "JAY D")
        XCTAssertEqual(PlayerProgress(defaults: UserDefaults(suiteName: suite)!).boardPlayer?.id, first.id, "saved")
    }

    /// Every line of the board fits the narrowest phone (iPhone SE: 375 pt, less the screen's 18 pt
    /// margins, less a panel's 15 pt padding inside a panel). A line that's too wide pushes the whole
    /// screen off the sides.
    func testLeaderboardLinesFitTheNarrowestPhone() {
        func width(_ s: String, _ px: CGFloat) -> CGFloat { CGFloat(PixelFont.width(of: s) + 1) * px }
        let screen: CGFloat = 375 - 36, panel = screen - 30
        let change = width("CHANGE NAME", 1.5)
        for status in ["UPDATING...", "OFFLINE · LAST UPDATE", "UPDATED JUST NOW", "UPDATED 999 MIN AGO"] {
            XCTAssertLessThanOrEqual(width(status, 1.5) + 8 + change, screen, status)
        }
        XCTAssertLessThanOrEqual(width("BEST ARCADE SCORES · 99999 PLAYERS", 1.5), screen)
        XCTAssertLessThanOrEqual(width("JOIN THE WORLD BOARD", 2), panel)
        XCTAssertLessThanOrEqual(width("CHANGE YOUR NAME", 2), panel)
        for line in ["YOUR ARCADE BEST 2999 GOES ON IT", "THEN PLAY ARCADE TO GET A SCORE", "PLAY ARCADE TO GET ON THE BOARD",
                     "YOUR SCORE GOES UP NEXT UPDATE", "TAP TO TYPE A NAME"] {
            XCTAssertLessThanOrEqual(width(line, 1.5), panel, line)
        }
        XCTAssertLessThanOrEqual(width("WWWWWWWWWW", 2.5), panel, "the longest name, as typed")
        // A row: rank, character, name, score and the gaps and padding between them.
        let row = width("#99999", 2) + 8 + 26 * 1.2 + 8 + width("WWWWWWWWWW", 2) + 4 + width("2999", 2.5) + 20
        XCTAssertLessThanOrEqual(row, screen)
    }

    func testBoardReadsTheServersReply() throws {
        let page = try JSONDecoder().decode(BoardPage.self, from: Data(reply.utf8))
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.top, [BoardEntry(rank: 1, name: "ACE", outfit: "robo:", score: 420, you: false)])
        XCTAssertEqual(page.you, BoardEntry(rank: 2, name: "JAY", outfit: "kid:crown", score: 224, you: true))
        let empty = try JSONDecoder().decode(BoardPage.self, from: Data(#"{"total" : 0, "top" : [], "you" : null}"#.utf8))
        XCTAssertNil(empty.you)
        XCTAssertTrue(empty.top.isEmpty)
    }

    func testBoardCallsTheServerFunctionsWithTheirArguments() async throws {
        let base = URL(string: "https://example.supabase.co/rest/v1")!
        let legacy = BoardAPI(base: base, key: "aaa.bbb.ccc", session: BoardStub.session)
        BoardStub.seen = []
        BoardStub.reply = (204, "")
        let id = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        try await legacy.submit(player: id, name: "JAY", outfit: "maya:beanie", score: 224)
        let submit = try XCTUnwrap(BoardStub.seen.last)
        XCTAssertEqual(submit.url?.absoluteString, "https://example.supabase.co/rest/v1/rpc/submit_arcade_score")
        XCTAssertEqual(submit.httpMethod, "POST")
        XCTAssertEqual(submit.value(forHTTPHeaderField: "apikey"), "aaa.bbb.ccc")
        XCTAssertEqual(submit.value(forHTTPHeaderField: "Authorization"), "Bearer aaa.bbb.ccc", "an anon JWT goes in both")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(submit.httpBody)) as? [String: Any])
        XCTAssertEqual(sent["p_player"] as? String, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(sent["p_name"] as? String, "JAY")
        XCTAssertEqual(sent["p_outfit"] as? String, "maya:beanie")
        XCTAssertEqual(sent["p_score"] as? Int, 224)

        let publishable = BoardAPI(base: base, key: "sb_publishable_abc", session: BoardStub.session)
        BoardStub.reply = (200, reply)
        let page = try await publishable.load(player: nil)
        XCTAssertEqual(page.total, 2)
        let load = try XCTUnwrap(BoardStub.seen.last)
        XCTAssertEqual(load.url?.lastPathComponent, "arcade_leaderboard")
        XCTAssertNil(load.value(forHTTPHeaderField: "Authorization"), "a publishable key only goes in apikey")
        let args = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(load.httpBody)) as? [String: Any])
        XCTAssertNil(args["p_player"], "a player who hasn't joined leaves it out")
        XCTAssertEqual(args["p_limit"] as? Int, 50)

        BoardStub.reply = (400, #"{"code":"23514"}"#)
        do {
            try await publishable.submit(player: id, name: "JAY", outfit: "kid:", score: 99_999)
            XCTFail("the server turned it away")
        } catch let BoardError.server(status, _) {
            XCTAssertEqual(status, 400)
        }
    }

    /// The board is kept between launches and still shows when the server can't be reached; the
    /// player's best only goes up once they've joined.
    func testBoardSendsTheBestOnlyAfterJoiningAndKeepsTheLastPage() async throws {
        let defaults = scratch()
        let p = PlayerProgress(defaults: defaults)
        p.update { $0.best[GameMode.arcade.rawValue] = 224 }
        let api = BoardAPI(base: URL(string: "https://example.supabase.co/rest/v1")!, key: "sb_publishable_abc",
                           session: BoardStub.session)
        BoardStub.seen = []
        BoardStub.reply = (200, reply)
        let board = WorldBoard(api: api, defaults: defaults)
        await board.refresh(p)
        XCTAssertEqual(BoardStub.seen.map { $0.url?.lastPathComponent }, ["arcade_leaderboard"], "not joined: nothing sent")
        XCTAssertEqual(board.status, .live)
        XCTAssertEqual(board.page?.total, 2)

        p.joinBoard(name: "Jay")
        BoardStub.seen = []
        await board.refresh(p)
        XCTAssertEqual(BoardStub.seen.map { $0.url?.lastPathComponent }, ["submit_arcade_score", "arcade_leaderboard"])

        BoardStub.reply = (503, "")
        let later = WorldBoard(api: api, defaults: defaults)
        XCTAssertEqual(later.page?.you?.name, "JAY", "the last board is there straight away on the next launch")
        await later.refresh(p)
        XCTAssertEqual(later.status, .offline)
        XCTAssertEqual(later.page?.total, 2, "and stays up while offline")

        let off = WorldBoard(api: nil, defaults: defaults)
        await off.refresh(p)
        XCTAssertEqual(off.status, .off)
        XCTAssertNil(off.page)
    }
}

final class ArtTests: XCTestCase {
    func testFontCoversEveryUIString() {
        let strings = GameMode.allCases.flatMap { [$0.title, $0.blurb] } + Modifier.allCases.map(\.label)
            + MissionKind.allCases.map { $0.text(10) } + BallSkin.all.map { $0.name.uppercased() }
            + CabinetTheme.all.map { $0.name.uppercased() }
            + Accessory.all.map { $0.name.uppercased() } + Avatar.all.map { $0.name.uppercased() }
            + Avatar.all.map(\.wearsNote) + AccessoryCategory.allCases.map(\.title)
            + [Requirement.games(5), .baskets(250), .score(150), .swishes(300), .streak(20)].flatMap { [$0.text + ": 112/250", "🔒 112/250 " + $0.unit] }
            + ["PRIZE COUNTER", "BALLS", "CABINETS", "PLAYER", "CHARACTERS", "EQUIP", "TAKE OFF", "BUY 🎟 100", "NEED 🎟 100",
               "🔒 LOCKED", "OWNED", "NOT WORN BY BRUNO BEAR", "UNLOCKED!"]
            + ["SWISH!", "BANK!", "ON FIRE!", "FIRE'S OUT", "3 PT FRENZY!", "BUZZER BEATER!", "★ NEW BEST! ★",
               "✓ NEW BEST +2", "🎟 100", "✓ EQUIPPED", "♥♥♥", "0123456789%/+-:"]
            + ["PLAYER 1 WINS!", "PLAYER 2 WINS!", "TIE GAME!", "PLAYER 1", "PLAYER 2"]
            + ["LEADERBOARD", "🏆 LEADERBOARD", "BEST ARCADE SCORES · 812 PLAYERS", "THE WORLD BOARD ISN'T SWITCHED ON YET",
               "YOUR ARCADE BEST: 224", "NO SCORES YET", "BE THE FIRST ONE ON THE BOARD", "LOADING...",
               "CAN'T REACH THE WORLD BOARD", "CHECK YOUR CONNECTION", "TRY AGAIN", "#1234", "YOUR SCORE GOES UP NEXT UPDATE",
               "PLAY ARCADE TO GET ON THE BOARD", "CHANGE NAME", "UPDATING...", "OFFLINE · LAST UPDATE",
               "UPDATED JUST NOW", "UPDATED 12 MIN AGO", "CHANGE YOUR NAME", "JOIN THE WORLD BOARD",
               "YOUR ARCADE BEST 1224 GOES ON IT", "THEN PLAY ARCADE TO GET A SCORE", "TAP TO TYPE A NAME", "CANCEL",
               "SAVE", "JOIN"]
            + ResultsView.lines(PlayerStats()).map(\.label)
        for s in strings {
            for ch in s {
                XCTAssertNotNil(PixelFont.glyphs[Character(String(ch).uppercased())], "missing glyph '\(ch)' in \(s)")
            }
        }
        let hud = ["TARGET 80 = BONUS", "STAGE 2 · TARGET 300", "FINAL STAGE", "LEVEL 3", "P1 SCORED 12", "PLAYER 1",
                   "DAILY: MOVER+WIND+TINY RIM", "PRACTICE", "SCORE:0000   HI:0136   INSERT COIN", "READY?", "GO!", "GO P2!",
                   "3PT FRENZY!", "STAGE 2!", "+20 SEC", "MOVING HOOP", "TIME!", "GAME OVER", "ON FIRE!", "FIRE'S OUT",
                   "AIRBALL", "SWISH!", "BANK!", "BUZZER BEATER!", "NICE!", "AIM LEFT", "AIM RIGHT", "HARDER", "SOFTER",
                   "SO CLOSE!", "♥♥♥", "--%", "50%", "SWIPE UP!", "1 LEFT", "+2", "0123456789"]
        for s in hud {
            for ch in s { XCTAssertNotNil(PixelFont.tinyGlyphs[Character(String(ch).uppercased())], "tiny font missing '\(ch)' in \(s)") }
        }
        for (ch, g) in PixelFont.tinyGlyphs {
            XCTAssertEqual(g.count, 5, "\(ch)")
            XCTAssertTrue(g.allSatisfy { $0.count == 3 }, "\(ch)")
        }
        for (ch, g) in PixelFont.glyphs {
            XCTAssertEqual(g.count, 7, "\(ch)")
            XCTAssertTrue(g.allSatisfy { $0.count == 5 }, "\(ch)")
        }
    }

    /// The rim is one ring drawn as two layers (behind and in front of a ball in the hoop). Upscaled
    /// separately, each layer rounded its corners off where it meets the other, and the board showed
    /// through the seams. Now the ring is solid wherever the ring upscaled in one piece is, in every
    /// colourway, and nothing else in the rim or the net moved.
    func testRimRingIsSolidAllTheWayRound() {
        for state in ["rest", "swish"] {
            let names = (back: "rim_back_\(state)", front: "rim_front_\(state)")
            let nativeBack = PixelCanvas(image: GIFArt.image(names.back))
            let nativeFront = PixelCanvas(image: GIFArt.image(names.front))
            let whole = PixelCanvas(width: nativeBack.width, height: nativeBack.height)
            for y in 0..<whole.height {
                for x in 0..<whole.width { whole[x, y] = nativeFront[x, y].a > 0 ? nativeFront[x, y] : nativeBack[x, y] }
            }
            let ring = whole.scale2x()
            for theme in CabinetTheme.all {
                let back = GIFArt.rimCanvas(names.back), front = GIFArt.rimCanvas(names.front)
                theme.recolor(back)
                theme.recolor(front)
                var holes: [String] = []
                for y in 0..<back.height {
                    for x in 0..<back.width where GIFArt.rimColours.contains(ring[x, y]) && front[x, y].a == 0 && back[x, y].a == 0 {
                        holes.append("\(x),\(y)")
                    }
                }
                XCTAssertEqual(holes, [], "board shows through the \(state) rim in \(theme.name)")
            }
            for (name, native) in [(names.back, nativeBack), (names.front, nativeFront)] {
                let fixed = GIFArt.rimCanvas(name), plain = native.scale2x()
                var changed = 0
                for y in 0..<fixed.height {
                    for x in 0..<fixed.width where fixed[x, y] != plain[x, y] {
                        changed += 1
                        XCTAssertTrue(GIFArt.rimColours.contains(native[x / 2, y / 2]), "\(name) \(x),\(y) isn't the ring")
                        XCTAssertGreaterThan(fixed[x, y].a, 0)
                    }
                }
                XCTAssertGreaterThan(changed, 0, "\(name): the seam had gaps to fill")
                XCTAssertLessThan(changed, 40, "\(name): only the seams change")
            }
        }
    }

    func testGIFSpritesLoadForEveryThemeSkinAndPose() {
        let layout = GIFLayout.shared
        XCTAssertEqual(layout.machineCanvas, [60, 0, 80, 142])
        for t in CabinetTheme.all {
            for name in ["machine", "panel", "lip", "rim_back_rest", "rim_front_rest", "rim_back_swish", "rim_front_swish"] {
                XCTAssertGreaterThan(GIFArt.machine(name, theme: t).size().width, 0, "\(name) \(t.id)")
            }
        }
        for s in BallSkin.all {
            for i in 0..<GIFArt.ballFrames {
                // 14 art pixels, drawn from a Scale2x texture with 2 texels per pixel.
                XCTAssertEqual(GIFArt.size(of: GIFArt.ball(i, skin: s)), CGSize(width: 14, height: 14))
                XCTAssertEqual(GIFArt.ball(i, skin: s).size(), CGSize(width: 28, height: 28))
            }
            for pose in KidPose.allCases { XCTAssertGreaterThan(GIFArt.kid(pose, skin: s).size().height, 0) }
        }
        for i in 0..<4 { XCTAssertGreaterThan(GIFArt.sparkle(i).size().width, 0) }
    }

    func testBallIsTheArtsThreeColoursAndSkinsSwapThem() {
        let classic = PixelCanvas(image: GIFArt.ball(0, skin: .classic).cgImage())
        let colours = Set(classic.pixels.filter { $0.a > 0 }.map { RGBA($0.r, $0.g, $0.b) })
        XCTAssertEqual(colours, [RGBA(hex: 0x000000), BallSkin.artRed, BallSkin.artWhite])
        let gold = PixelCanvas(image: GIFArt.ball(0, skin: .gold).cgImage())
        let goldColours = Set(gold.pixels.filter { $0.a > 0 }.map { RGBA($0.r, $0.g, $0.b) })
        XCTAssertEqual(goldColours, [RGBA(hex: 0x000000), BallSkin.gold.primary, BallSkin.gold.secondary])
    }

    func testScale2xOnlyRoundsCornersAndAddsNoColours() {
        // A 2×2 checker and an L-shape: flat areas stay flat, a lone corner gets rounded.
        let c = PixelCanvas(width: 3, height: 3)
        let red = RGBA(hex: 0xD42C2C)
        for (x, y) in [(0, 0), (1, 0), (2, 0), (0, 1), (0, 2)] { c.set(x, y, red) }
        let big = c.scale2x()
        XCTAssertEqual(big.width, 6)
        XCTAssertEqual(Set(big.pixels), [red, .clear])
        XCTAssertEqual(big[0, 0], red)            // solid interior unchanged
        XCTAssertEqual(big[5, 5], .clear)         // empty stays empty
        XCTAssertEqual(big[2, 2], red, "the inside corner of the L is filled in, rounding the step")
        XCTAssertEqual(big[3, 3], .clear, "…but only the quarter that touches both arms")
    }

    func testThemesRecolourTheCabinet() {
        let classic = PixelCanvas(image: GIFArt.machine("machine", theme: .classic).cgImage())
        let neon = PixelCanvas(image: GIFArt.machine("machine", theme: .neon).cgImage())
        XCTAssertTrue(classic.pixels.contains(RGBA(hex: 0x1463AD)), "the reference blue")
        XCTAssertFalse(neon.pixels.contains(RGBA(hex: 0x1463AD)))
        XCTAssertEqual(classic.pixels.filter { $0.a > 0 }.count, neon.pixels.filter { $0.a > 0 }.count, "same shape")
    }
}

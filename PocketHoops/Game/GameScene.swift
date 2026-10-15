import SpriteKit

/// The playable machine, drawn with sprites cut from the reference GIF (see `GIFArt`). Scene units
/// are the GIF's art pixels, shown at an integer number of device pixels each so they stay crisp.
/// Also runs in "attract mode" behind the main menu, where a CPU shoots.
final class GameScene: SKScene {
    enum State { case attract, ready, playing, swap, ending, over }

    // Configuration
    let config: ModeConfig
    let skin: BallSkin
    let theme: CabinetTheme
    /// What the shooter is wearing.
    let outfit: Outfit
    let attract: Bool
    var onFinish: ((GameResult) -> Void)?
    /// Shown on the sign in attract mode.
    var attractHiScore = 0
    var onStateChange: ((State) -> Void)?

    // Model
    private(set) var session: GameSession
    private let sim: Simulation
    private var proj: Projection!
    private(set) var state: State = .ready { didSet { onStateChange?(state) } }
    private var readyTimer = 1.4
    private var endTimer = 0.0
    private var lastTime: TimeInterval?
    private let rackSize: Int
    private var rack: Rack!
    private var shotsTaken = 0
    private var intents: [Int: (depth: Double, lateral: Double)] = [:]
    private var attractTimer = 1.0
    private var attractRNG = SystemRandomNumberGenerator()
    private var nextLostSide = 1.0

    // Layout
    private let layout = GIFLayout.shared
    /// Where the machine (and the clock above it) is fitted, in scene pixels.
    private let area: CGRect
    /// Bottom-left of the machine canvas, in scene pixels.
    private var canvas = CGPoint.zero
    /// Room reserved above the machine for the clock and info line.
    static let hudHeight: CGFloat = 24
    static let machineSize = CGSize(width: 80, height: 142)

    // Nodes
    private let world = SKNode()
    private let machine = SKSpriteNode()
    private let rimBack = SKSpriteNode()
    private let rimFront = SKSpriteNode()
    private let panel = SKSpriteNode()
    private let lip = SKSpriteNode()
    private let kid = SKSpriteNode()
    private let sparkles = SKSpriteNode()
    private var lamps: [SKSpriteNode] = []
    private var ballNodes: [Int: SKSpriteNode] = [:]
    private var squashUntil: [Int: TimeInterval] = [:]
    private var rackNodes: [Int: SKSpriteNode] = [:]
    private let signCrop = SKCropNode()
    private let signLabel = PixelLabel("", scale: 0.5, shadow: RGBA(hex: 0x23424A))
    private var signWindow = CGRect.zero
    private var marquee = 0.0
    private let timeLabel = PixelLabel("", scale: 1.5, outline: .black)
    private let infoLabel = PixelLabel("", scale: 0.5, outline: .black)
    private let playerLabel = PixelLabel("PLAYER:", scale: 0.5, shadow: RGBA(hex: 0x7A1111))
    private var streakPips: [SKSpriteNode] = []
    private let banner = PixelLabel("", scale: 1, outline: .black)
    private let hint = PixelLabel("SWIPE UP!", scale: 0.5, outline: .black)

    // The shooter
    private var pose: KidPose = .hold
    private var poseTimer = 0.0
    /// Holding a ball (from `reach` until it leaves their hands).
    private var holding = true
    /// Horizontal offset from the art's position, in scene pixels (smoothed toward `kidTarget`).
    private var kidOffset = 0.0
    private var kidTarget = 0.0
    static let kidRange = 12.0
    private var pendingShot: (velocity: Vec3, x: Double, intent: (Double, Double))?

    // Touch tracking
    private var touching = false
    private var samples: [Flick.Sample] = []
    /// Once the upward stroke starts the kid stays put, so the ball leaves from where it was aimed.
    private var strokeStarted = false
    private var calibration = FlickCalibration.load()

    /// `area` is where the machine is fitted, in scene pixels (see `SceneLayout`).
    init(size: CGSize, area: CGRect, config: ModeConfig, skin: BallSkin, theme: CabinetTheme, outfit: Outfit = .standard,
         attract: Bool = false) {
        self.area = area
        self.config = config
        self.outfit = outfit
        self.skin = skin
        self.theme = theme
        self.attract = attract
        session = GameSession(config: config)
        var court = Court()
        court.rimRadius *= config.rimScale
        court.gravity *= config.gravityScale
        court.wind = config.wind
        sim = Simulation(court: court)
        // A full rack is a jumble of 7 balls, like the reference art (sudden death keeps just 3).
        rackSize = config.mode == .streak ? 3 : 8
        super.init(size: size)
        scaleMode = .aspectFill
        backgroundColor = theme.background.uiColor
        state = attract ? .attract : .ready
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        guard world.parent == nil else { return }
        view.ignoresSiblingOrder = true
        addChild(world)
        buildMachine()
        buildHUD()
        refreshHUD()
        renderKid()
        renderRack()
    }

    private func buildMachine() {
        let blockHeight = GameScene.machineSize.height + (attract ? 0 : GameScene.hudHeight)
        canvas = CGPoint(x: (area.midX - GameScene.machineSize.width / 2).rounded(.down),
                         y: (area.midY - blockHeight / 2).rounded(.down))
        proj = Projection.machine(at: canvas, court: sim.court, layout: layout)

        func layer(_ node: SKSpriteNode, _ name: String, z: CGFloat, at offset: CGPoint = .zero) {
            node.texture = GIFArt.machine(name, theme: theme)
            node.size = GIFArt.size(of: node.texture!)
            node.anchorPoint = .zero
            node.position = CGPoint(x: canvas.x + offset.x, y: canvas.y + offset.y)
            node.zPosition = z
            world.addChild(node)
        }
        layer(machine, "machine", z: 0)
        let rim = layout.canvasRect(layout.rimBox)
        layer(rimBack, "rim_back_rest", z: 1, at: rim.origin)
        layer(rimFront, "rim_front_rest", z: 30, at: rim.origin)
        layer(panel, "panel", z: 6)
        layer(lip, "lip", z: 6)

        // The player lamps on the strip (the lit one shows whose turn it is).
        for l in layout.lamps {
            let lamp = SKSpriteNode(color: RGBA(hex: 0xFF7D14).uiColor, size: CGSize(width: 1, height: 2))
            lamp.anchorPoint = .zero
            lamp.position = CGPoint(x: canvas.x + CGFloat(l[0] + 1 - layout.canvasX),
                                    y: canvas.y + CGFloat(layout.canvasY(ofArtRow: Double(l[1] + 3))))
            lamp.zPosition = 7
            world.addChild(lamp)
            lamps.append(lamp)
        }

        // The rack: balls rest with their centres on art row 114, between the strip and the lip.
        let trough = layout.canvasRect(layout.trough)
        rack = Rack(minX: Double(trough.minX) + 7, maxX: Double(trough.maxX) - 7, lowX: Double(trough.midX))
        let start = rackSize - 1
        for i in 0..<start {
            let t = start > 1 ? Double(i) / Double(start - 1) : 0.5
            rack.add(at: rack.lowX + (t - 0.5) * 2 * min(22, Double(start) * 5.5))
        }
        for _ in 0..<60 { rack.step(1.0 / 60) }

        kid.anchorPoint = .zero
        kid.zPosition = 34
        world.addChild(kid)

        sparkles.texture = GIFArt.sparkle(0)
        sparkles.size = GIFArt.size(of: sparkles.texture!)
        sparkles.anchorPoint = .zero
        sparkles.position = CGPoint(x: canvas.x + CGFloat(layout.sparkleCanvas[0] - layout.canvasX),
                                    y: canvas.y + CGFloat(layout.canvasHeight - layout.sparkleCanvas[3]))
        sparkles.zPosition = 150
        sparkles.isHidden = true
        world.addChild(sparkles)
    }

    private func buildHUD() {
        // Live score in the sign's LCD window (art columns 86–111, rows 9–13).
        signWindow = CGRect(x: canvas.x + CGFloat(layout.canvasX(ofArtColumn: 86)),
                            y: canvas.y + CGFloat(layout.canvasY(ofArtRow: 14)), width: 26, height: 5)
        let mask = SKSpriteNode(color: .white, size: signWindow.size)
        mask.anchorPoint = .zero
        mask.position = signWindow.origin
        signCrop.maskNode = mask
        signCrop.zPosition = 7
        signLabel.textColor = theme.led.lighter(0.3)
        signLabel.anchorPoint = .zero
        signCrop.addChild(signLabel)
        world.addChild(signCrop)

        // "PLAYER:" on the strip, in a cleaner font at double resolution (the art's own lettering
        // is 3 pixels tall). Vertically centred on the strip's red band (art rows 101–105).
        if let t = layout.playerText {
            playerLabel.anchorPoint = .zero
            playerLabel.position = CGPoint(x: canvas.x + CGFloat(t[0] - layout.canvasX),
                                           y: canvas.y + CGFloat(layout.canvasY(ofArtRow: Double(t[3]))) + 1)
            playerLabel.zPosition = 7
            world.addChild(playerLabel)
        }

        let top = canvas.y + GameScene.machineSize.height
        infoLabel.anchorPoint = CGPoint(x: 0.5, y: 0)
        infoLabel.position = CGPoint(x: canvas.x + 40, y: top + 1.5)
        timeLabel.anchorPoint = CGPoint(x: 0.5, y: 0)
        timeLabel.position = CGPoint(x: canvas.x + 40, y: top + 8)
        for n in [infoLabel, timeLabel] {
            n.zPosition = 101
            n.isHidden = attract
            world.addChild(n)
        }
        for i in 0..<Scorekeeper.fireAt {
            let pip = SKSpriteNode(color: .black, size: CGSize(width: 3, height: 3))
            pip.anchorPoint = .zero
            pip.position = CGPoint(x: canvas.x + 64 + CGFloat(i) * 5, y: top + 13)
            pip.zPosition = 101
            pip.isHidden = attract
            world.addChild(pip)
            streakPips.append(pip)
        }

        banner.zPosition = 200
        banner.position = CGPoint(x: canvas.x + 40, y: proj.sy(0.2, 0.6).rounded())
        banner.alpha = 0
        world.addChild(banner)

        hint.zPosition = 200
        hint.position = CGPoint(x: canvas.x + 40, y: (proj.sy(sim.court.frontY, 0) + 6).rounded())
        hint.alpha = 0
        world.addChild(hint)
        if !attract {
            hint.run(.sequence([.wait(forDuration: readyTimer), .repeatForever(.sequence([
                .fadeAlpha(to: 1, duration: 0.25), .wait(forDuration: 0.5), .fadeAlpha(to: 0.2, duration: 0.25),
            ]))]), withKey: "blink")
            flashBanner(config.mode == .versus ? "PLAYER 1" : "READY?", color: .white, hold: 1.0)
        }
    }

    // MARK: - HUD

    private func refreshHUD() {
        let k = session.keeper
        if attract {
            let hi = String(format: "%04d", min(9999, attractHiScore))
            setSign("SCORE:0000   HI:\(hi)   INSERT COIN   ", scrolling: true)
            lamps.forEach { $0.isHidden = true }
            return
        }
        let shown = config.mode == .streak || config.mode == .practice ? k.makes : k.score
        setSign(String(format: "%04d", min(9999, shown)), scrolling: false)

        let green = RGBA(hex: 0x7CFF6B)
        switch config.mode {
        case .streak:
            timeLabel.set(String(repeating: "♥", count: max(0, session.lives)))
            timeLabel.textColor = RGBA(hex: 0xFF4A4A)
            info("LEVEL \(session.level)")
        case .practice:
            timeLabel.set(k.attempts == 0 ? "--%" : "\(Int((k.accuracy * 100).rounded()))%")
            timeLabel.textColor = .white
            info("PRACTICE")
        default:
            refreshTimeOnly()
            switch config.mode {
            case .arcade:
                if let t = session.targetForCurrentStage {
                    info(session.stage == 1 ? "TARGET \(t) = BONUS" : "STAGE \(session.stage) · TARGET \(t)",
                         color: k.score >= t ? green : .white)
                } else {
                    info("FINAL STAGE", color: theme.led)
                }
            case .versus:
                if session.player == 2, let p1 = session.playerScores.first { info("P1 SCORED \(p1)") }
                else { info("PLAYER 1") }
            case .daily:
                info("DAILY: " + config.modifiers.map(\.shortLabel).joined(separator: "+"), color: theme.led)
            default:
                break
            }
        }
        let active = config.mode == .versus ? session.player - 1 : 0
        for (i, lamp) in lamps.enumerated() { lamp.isHidden = i != active }
        let lit = min(k.streak, Scorekeeper.fireAt)
        for (i, pip) in streakPips.enumerated() {
            pip.color = k.onFire ? UIColor(red: 1, green: 0.55 + CGFloat(i) * 0.12, blue: 0.1, alpha: 1)
                : (i < lit ? RGBA(hex: 0xF1C103).uiColor : UIColor.black.withAlphaComponent(0.45))
        }
    }

    private func info(_ text: String, color: RGBA = .white) {
        infoLabel.set(text)
        infoLabel.textColor = color
    }

    private func setSign(_ text: String, scrolling: Bool) {
        signLabel.set(text)
        if !scrolling {
            signLabel.removeAction(forKey: "marquee")
            let w = CGFloat(PixelFont.width(of: text)) * signLabel.pixelScale
            signLabel.position = CGPoint(x: signWindow.minX + (((signWindow.width - w) / 2) * 2).rounded(.down) / 2,
                                         y: signWindow.minY + 0.5)
        }
    }

    private func refreshTimeOnly() {
        guard session.isTimed, !attract else { return }
        timeLabel.set(String(format: "%02d", Int(ceil(session.timeLeft))))
        timeLabel.textColor = session.frenzy ? RGBA(hex: 0xFF4A4A) : .white
    }

    private func flashBanner(_ text: String, color: RGBA, hold: Double = 0.7) {
        banner.removeAllActions()
        banner.textColor = color
        banner.set(text)
        let fits = CGFloat(PixelFont.width(of: text)) <= GameScene.machineSize.width - 8
        let s: CGFloat = fits ? 1 : 0.5
        banner.pixelScale = s
        banner.setScale(s * 1.25)
        banner.alpha = 1
        banner.run(.sequence([
            .scale(to: s, duration: 0.1),
            .wait(forDuration: hold),
            .fadeOut(withDuration: 0.25),
        ]))
    }

    private func popText(_ text: String, at p: CGPoint, color: RGBA, scale: CGFloat = 1, delay: Double = 0) {
        let n = PixelLabel(text, color: color, scale: scale * 0.5, outline: .black)
        n.position = p.halfSnapped
        n.zPosition = 150
        n.alpha = 0
        world.addChild(n)
        n.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.02),
            .group([.moveBy(x: 0, y: 10, duration: 0.8), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ]))
    }

    private func shake(_ amount: CGFloat = 1) {
        world.removeAction(forKey: "shake")
        var seq: [SKAction] = []
        for i in 0..<6 {
            let a = amount * CGFloat(6 - i) / 6
            seq.append(.move(to: CGPoint(x: CGFloat.random(in: -a...a).rounded(), y: CGFloat.random(in: -a...a).rounded()),
                             duration: 0.03))
        }
        seq.append(.move(to: .zero, duration: 0.03))
        world.run(.sequence(seq), withKey: "shake")
    }

    /// The reference art's score celebration: gold sparkles twinkling beside the machine.
    private func playSparkles() {
        sparkles.removeAllActions()
        sparkles.isHidden = false
        var seq: [SKAction] = []
        for i in 0..<4 {
            seq.append(.setTexture(GIFArt.sparkle(i)))
            seq.append(.wait(forDuration: 0.1))
        }
        seq.append(.hide())
        sparkles.run(.sequence(seq))
    }

    private func swishNet() {
        rimBack.removeAllActions()
        rimFront.removeAllActions()
        let back = [GIFArt.machine("rim_back_swish", theme: theme), GIFArt.machine("rim_back_rest", theme: theme)]
        let front = [GIFArt.machine("rim_front_swish", theme: theme), GIFArt.machine("rim_front_rest", theme: theme)]
        rimBack.run(.sequence([.setTexture(back[0]), .wait(forDuration: 0.2), .setTexture(back[1])]))
        rimFront.run(.sequence([.setTexture(front[0]), .wait(forDuration: 0.2), .setTexture(front[1])]))
    }

    private static let dot: SKTexture = {
        let t = SKTexture(cgImage: PixelCanvas(width: 1, height: 1, fill: .white).makeImage()!)
        t.filteringMode = .nearest
        return t
    }()

    private func fireTrail() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = GameScene.dot
        e.particleBirthRate = 90
        e.particleLifetime = 0.3
        e.particleLifetimeRange = 0.12
        e.particleSpeed = 6
        e.particleSpeedRange = 5
        e.emissionAngleRange = .pi * 2
        e.particleAlphaSpeed = -3
        e.particleScale = 1
        e.particleScaleSpeed = -1.5
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor(red: 1, green: 0.95, blue: 0.4, alpha: 1), UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 1),
                             UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)],
            times: [0, 0.4, 1])
        e.targetNode = world
        e.zPosition = -1
        return e
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(0.05, currentTime - $0) } ?? 1.0 / 60
        lastTime = currentTime
        step(dt)
    }

    /// Pauses/resumes without the clock jumping.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastTime = nil
    }

    private func step(_ dt: Double) {
        switch state {
        case .attract:
            runAttract(dt)
        case .ready:
            readyTimer -= dt
            if readyTimer <= 0 {
                state = .playing
                flashBanner("GO!", color: RGBA(hex: 0x7CFF6B), hold: 0.4)
                sfx(.stage, volume: 0.7)
            }
        case .playing:
            for e in session.update(dt) { handle(e) }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "autoplay") { runAutoplay(dt) }
            #endif
        case .swap, .over:
            break
        case .ending:
            endTimer -= dt
            if endTimer <= 0 || sim.balls.allSatisfy(\.resolved) { finish() }
        }

        // Moving hoop: the rim slides along the backboard.
        let hx = state == .attract ? 0 : session.hoopX(at: session.elapsed)
        sim.court.hoopX = hx
        let shift = CGFloat(proj.kx * hx).rounded()
        let rimOrigin = layout.canvasRect(layout.rimBox).origin
        rimBack.position.x = canvas.x + rimOrigin.x + shift
        rimFront.position.x = rimBack.position.x

        for e in sim.step(dt) { handle(e) }
        for _ in rack.step(dt) { sfx(.bounce, volume: 0.25) }
        updateKid(dt)
        renderBalls()
        renderRack()
        renderKid()
        if state == .playing { refreshTimeOnly() }
        if attract { scrollSign(dt) }
    }

    private func scrollSign(_ dt: Double) {
        marquee += dt * 14
        let w = Double(PixelFont.width(of: signLabel.text)) * Double(signLabel.pixelScale) + 4
        if marquee > w { marquee -= w }
        signLabel.position = CGPoint(x: signWindow.maxX - CGFloat((marquee * 2).rounded(.down) / 2), y: signWindow.minY + 0.5)
    }

    private func finish() {
        guard state != .over else { return }
        state = .over
        let k = session.keeper
        let result = GameResult(mode: config.mode, score: k.score, makes: k.makes, attempts: k.attempts,
                                swishes: k.swishes, banks: k.banks, fires: k.fires, bestStreak: k.bestStreak,
                                stage: session.stage, players: session.players)
        onFinish?(result)
    }

    /// Practice has no clock; the menu's END button calls this.
    func endNow() {
        session.end()
        state = .ending
        endTimer = 0
    }

    /// Second player taps to start their turn.
    func beginNextPlayer() {
        guard state == .swap else { return }
        state = .ready
        readyTimer = 1.0
        flashBanner("GO P\(session.player)!", color: .white, hold: 0.6)
    }

    // MARK: - Events

    private func handle(_ e: SessionEvent) {
        switch e {
        case .frenzy:
            flashBanner("3PT FRENZY!", color: RGBA(hex: 0xFF4A4A), hold: 0.8)
            sfx(.stage)
            Haptics.success()
        case .countdown:
            sfx(.tick)
        case let .stage(n, bonus):
            flashBanner("STAGE \(n)!", color: RGBA(hex: 0x7CFF6B), hold: 1.0)
            popText("+\(Int(bonus)) SEC", at: CGPoint(x: canvas.x + 40, y: proj.sy(0.2, 0.2)), color: .white)
            if n >= 2 { popText("MOVING HOOP", at: CGPoint(x: canvas.x + 40, y: proj.sy(0.2, -0.1)), color: theme.led, delay: 0.3) }
            playSparkles()
            sfx(.stage)
            Haptics.success()
            refreshHUD()
        case let .levelUp(n):
            popText("LEVEL \(n)", at: CGPoint(x: canvas.x + 40, y: proj.sy(0.2, 0.3)), color: theme.led, scale: 2)
            sfx(.stage, volume: 0.7)
            refreshHUD()
        case let .lifeLost(n):
            sfx(.lifeLost)
            Haptics.error()
            shake(1)
            if n > 0 { popText("\(n) LEFT", at: CGPoint(x: canvas.x + 40, y: proj.sy(0.2, 0.2)), color: RGBA(hex: 0xFF4A4A)) }
            refreshHUD()
        case let .playerSwap(n):
            sfx(.buzzer, volume: 0.8)
            sim.removeAll()
            for (_, node) in ballNodes { node.removeFromParent() }
            ballNodes.removeAll()
            resetRack()
            state = .swap // the hand-off card is drawn by GameView
            banner.removeAllActions()
            banner.alpha = 0
            _ = n
            refreshHUD()
        case .over:
            state = .ending
            endTimer = config.mode == .streak ? 0.8 : 1.6
            if session.isTimed {
                sfx(.buzzer)
                flashBanner("TIME!", color: RGBA(hex: 0xFF4A4A), hold: 1.2)
            } else {
                flashBanner("GAME OVER", color: RGBA(hex: 0xFF4A4A), hold: 1.2)
            }
            Haptics.error()
            refreshHUD()
        }
    }

    private func handle(_ e: PhysicsEvent) {
        switch e {
        case let .rim(id, s):
            sfx(.rim, volume: Float(0.3 + s * 0.7))
            if !attract { Haptics.rim(s) }
            if s > 0.35 { squashUntil[id] = CACurrentMediaTime() + 0.07 }
        case let .board(_, s):
            sfx(.board, volume: Float(0.3 + s * 0.7))
        case let .wall(_, s):
            sfx(.board, volume: Float(0.15 + s * 0.3))
        case let .floor(_, s):
            sfx(.bounce, volume: Float(0.2 + s * 0.6))
        case let .score(id, swish, bank):
            scored(id: id, swish: swish, bank: bank)
        case let .miss(id, airball):
            missed(id: id, airball: airball)
        case let .returned(id, x, lost):
            ballReturned(id: id, x: x, lost: lost)
        }
    }

    /// A ball left play: it rolls (or is dropped) back into the rack — never just deleted.
    private func ballReturned(id: Int, x: Double, lost: Bool) {
        let node = ballNodes.removeValue(forKey: id)
        node?.removeFromParent()
        squashUntil[id] = nil
        intents[id] = nil
        guard state != .swap else { return }
        let inRack = rack.count + (holding ? 1 : 0) + sim.balls.count
        guard inRack < rackSize else { return }
        if lost {
            // Recovered from somewhere odd: feed it in from the end of the rack.
            nextLostSide = -nextLostSide
            rack.add(at: nextLostSide > 0 ? rack.maxX : rack.minX, height: 10, vx: -nextLostSide * 30)
        } else if let p = node?.position, p.y < canvas.y + CGFloat(layout.canvasY(ofArtRow: 109)) {
            // It came flying back out over the front of the machine and fell into the tray:
            // it lands right where it is and rolls into the pile.
            let restY = canvas.y + CGFloat(layout.canvasY(ofArtRow: 114))
            rack.add(at: Double(p.x - canvas.x), height: Double(max(0, p.y - restY)))
        } else {
            // It rolled off the lane under the strip and comes out of the return chute at the
            // nearer end of the rack, then rolls down along the trough into the pile.
            let left = x < 0
            rack.add(at: left ? rack.minX : rack.maxX, height: 6, vx: left ? 70 : -70)
        }
    }

    private var rimScreen: CGPoint { proj.project(sim.court.rimCenter) }

    private func scored(id: Int, swish: Bool, bank: Bool) {
        swishNet()
        sfx(.swish, volume: swish ? 1 : 0.7)
        if attract { return }
        guard state == .playing || state == .ending else { return }
        let buzzerBeater = state == .ending && session.isTimed
        let (m, events) = session.registerMake(swish: swish, bank: bank)
        sfx(.score, volume: 0.6)
        Haptics.score()
        playSparkles()
        let at = rimScreen + CGPoint(x: 0, y: 12)
        let color = session.keeper.onFire && !m.lit ? RGBA(hex: 0xFF8A1F) : RGBA(hex: 0xF1C103)
        popText("+\(m.points)", at: at, color: color, scale: 2)
        for (i, l) in m.labels.enumerated() {
            popText(l, at: at + CGPoint(x: 0, y: -12 - CGFloat(i) * 7), color: .white, delay: 0.08 * Double(i + 1))
        }
        if buzzerBeater { popText("BUZZER BEATER!", at: at + CGPoint(x: 0, y: 14), color: RGBA(hex: 0x7CFF6B)) }
        if m.lit {
            flashBanner("ON FIRE!", color: RGBA(hex: 0xFF8A1F), hold: 0.8)
            sfx(.fire)
            Haptics.success()
            shake(1)
        }
        if config.showGuide { popText("NICE!", at: at + CGPoint(x: 0, y: -24), color: RGBA(hex: 0x7CFF6B)) }
        for e in events { handle(e) }
        refreshHUD()
    }

    private func missed(id: Int, airball: Bool) {
        guard !attract, state == .playing || state == .ending else { return }
        if session.isOver && config.mode == .streak { return }
        let (putOut, events) = session.registerMiss()
        let at = rimScreen + CGPoint(x: 0, y: 12)
        if putOut {
            popText("FIRE'S OUT", at: at, color: RGBA(hex: 0xFF8A1F))
            sfx(.fizzle)
        } else if airball {
            popText("AIRBALL", at: at, color: RGBA(hex: 0xC8C8D8))
        }
        if config.showGuide, let intent = intents[id] {
            popText(coachTip(intent), at: at + CGPoint(x: 0, y: -8), color: .white, delay: 0.1)
        }
        for e in events { handle(e) }
        refreshHUD()
    }

    private func coachTip(_ i: (depth: Double, lateral: Double)) -> String {
        if abs(i.lateral) > sim.court.rimRadius * 0.7 { return i.lateral < 0 ? "AIM RIGHT" : "AIM LEFT" }
        if i.depth < 0.97 { return "HARDER" }
        if i.depth > 1.04 { return "SOFTER" }
        return "SO CLOSE!"
    }

    // MARK: - Rendering

    private func ballFrame(_ spin: Double) -> Int {
        Int((spin / (2 * .pi) * Double(GIFArt.ballFrames)).rounded(.down))
    }

    private func renderBalls() {
        let c = sim.court
        let now = CACurrentMediaTime()
        for b in sim.balls {
            let node: SKSpriteNode
            if let n = ballNodes[b.id] {
                node = n
            } else {
                node = SKSpriteNode()
                if b.onFire { node.addChild(fireTrail()) }
                world.addChild(node)
                ballNodes[b.id] = node
            }
            let squash = (squashUntil[b.id] ?? 0) > now
            node.texture = GIFArt.ball(ballFrame(b.spin), skin: skin, squash: squash)
            node.size = GIFArt.size(of: node.texture!)
            node.position = proj.project(b.pos).halfSnapped
            // Rolling back near the front: slips under the panel's top edge into the rack.
            let underPanel = b.pos.y > c.frontY - 0.02 && b.age > 0.35 && b.pos.z < c.floorZ(b.pos.y) + 0.35
            switch GameScene.rimLayer(of: b, court: c) {
            case .throughHoop: node.zPosition = 10
            case .behindRing: node.zPosition = 0.5
            case .inFront: node.zPosition = underPanel ? 4 : 40 + CGFloat(max(0, 10 - proj.depth(b.pos))) * 0.5
            }
        }
    }

    /// Where a ball is drawn against the rim's two layers: the back of the ring (z 1) and the
    /// front of the ring + net (z 30).
    enum RimLayer { case inFront, throughHoop, behindRing }

    /// Below the top of the rim a ball is layered by where it really is: going down through the
    /// hoop (or in the net) it sits between the back and front of the ring; one that fell off the
    /// rim on the *outside* stays in front of the ring on the near side, or goes behind all of it
    /// on the far side. (Drawing those inside the ring made a ball that rolled off the rim look
    /// like it went through it.)
    static func rimLayer(of b: Ball, court c: Court) -> RimLayer {
        let q = b.pos - c.rimCenter
        guard b.pos.z < c.rimZ + c.ballRadius * 0.3, abs(q.x) < c.rimRadius + c.ballRadius else { return .inFront }
        if b.scored || q.horizontalLength < c.rimRadius { return .throughHoop }
        return q.y > 0 ? .behindRing : .inFront
    }

    private func renderRack() {
        let restY = canvas.y + CGFloat(layout.canvasY(ofArtRow: 114))
        var live = Set<Int>()
        for b in rack.balls {
            live.insert(b.id)
            let node: SKSpriteNode
            if let n = rackNodes[b.id] {
                node = n
            } else {
                node = SKSpriteNode()
                node.zPosition = 5
                world.addChild(node)
                rackNodes[b.id] = node
            }
            node.texture = GIFArt.ball(ballFrame(b.spin), skin: skin)
            node.size = GIFArt.size(of: node.texture!)
            // Resting balls sit a pixel higher or lower than their neighbours: a pile, not a row.
            let settle = CGFloat([0, 1, -1, 1, 0, -1, 1][b.id % 7])
            node.position = CGPoint(x: canvas.x + CGFloat(b.x), y: restY + CGFloat(b.drop) + settle).halfSnapped
            node.zPosition = 5 + CGFloat(b.id % 7) * 0.01
        }
        for (id, node) in rackNodes where !live.contains(id) {
            node.removeFromParent()
            rackNodes[id] = nil
        }
    }

    private func resetRack() {
        while rack.take(nearest: rack.lowX) != nil {}
        for i in 0..<(rackSize - 1) { rack.add(at: rack.lowX + Double(i - (rackSize - 1) / 2) * 6) }
        holding = true
        setPose(.hold, for: 0)
    }

    // MARK: - The shooter

    private func setPose(_ p: KidPose, for seconds: Double) {
        pose = p
        poseTimer = seconds
    }

    /// The reference animation: jump → follow-through ×3 → reach into the rack → lift → hold.
    private func updateKid(_ dt: Double) {
        poseTimer -= dt
        let frame = 0.08
        switch pose {
        case .jump where poseTimer <= 0:
            if let shot = pendingShot { launch(velocity: shot.velocity, from: shot.x, intent: shot.intent) }
            pendingShot = nil
            setPose(.follow1, for: frame)
        case .follow1 where poseTimer <= 0:
            setPose(.follow2, for: frame)
        case .follow2 where poseTimer <= 0:
            setPose(.follow3, for: frame)
        case .follow3 where poseTimer <= 0, .idle:
            if pose == .idle && poseTimer > 0 { break }
            if rack.take(nearest: rack.lowX + kidOffset) != nil {
                holding = true
                setPose(.reach, for: frame)
            } else if pose != .idle {
                setPose(.idle, for: 0)
            }
        case .reach where poseTimer <= 0:
            setPose(.lift, for: frame)
        case .lift where poseTimer <= 0:
            setPose(.hold, for: 0)
        default:
            break
        }
        // Step toward the finger.
        let gap = kidTarget - kidOffset
        kidOffset += gap * min(1, dt * 16)
    }

    private func renderKid() {
        kid.texture = GIFArt.kid(pose, skin: skin, outfit: outfit)
        kid.size = GIFArt.size(of: kid.texture!)
        kid.position = CGPoint(x: canvas.x + CGFloat(layout.kidCanvas[0] - layout.canvasX) + CGFloat((kidOffset * 2).rounded() / 2),
                               y: canvas.y + CGFloat(layout.canvasHeight - layout.kidCanvas[3]))
    }

    /// World x of the ball in the shooter's hands.
    private var kidWorldX: Double { (kidOffset * 2).rounded() / 2 / proj.kx }

    // MARK: - Input

    private var canShoot: Bool { state == .playing && holding && (pose == .hold || pose == .crouch) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        if state == .swap { beginNextPlayer(); return }
        guard state == .playing else { return }
        touching = true
        strokeStarted = false
        samples = [Flick.Sample(t: t.timestamp, p: t.location(in: view))]
        followFinger(t.location(in: self))
        if pose == .hold { setPose(.crouch, for: 0) }
        Haptics.tap()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touching, let t = touches.first else { return }
        samples.append(Flick.Sample(t: t.timestamp, p: t.location(in: view)))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
        // Sliding sideways moves the kid; once the finger heads up the screen, the shot is on.
        if let low = samples.map(\.p.y).max(), low - t.location(in: view).y > 12 { strokeStarted = true }
        if !strokeStarted { followFinger(t.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touching, let t = touches.first else { return }
        touching = false
        samples.append(Flick.Sample(t: t.timestamp, p: t.location(in: view)))
        defer { if pose == .crouch { setPose(.hold, for: 0) } }
        guard let v = Flick.velocity(samples), v.y > 250, v.x.isFinite, v.y.isFinite else { return }
        shoot(viewVelocity: v)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = false
        if pose == .crouch { setPose(.hold, for: 0) }
    }

    /// While the finger is down low (on the panel, around the kid), the kid steps sideways with it.
    private func followFinger(_ loc: CGPoint) {
        guard loc.y < proj.sy(sim.court.frontY, 0) else { return }
        let home = canvas.x + 40
        kidTarget = max(-GameScene.kidRange, min(GameScene.kidRange, Double(loc.x - home)))
    }

    private func shoot(viewVelocity v: (x: Double, y: Double)) {
        guard canShoot else { return }
        // The kid stops where they are: the ball leaves from exactly where the flick was aimed.
        kidTarget = kidOffset
        let x = kidWorldX
        let (vel, depth, lateral) = Aim.shot(viewVelocity: v, from: x, court: sim.court, projection: proj,
                                             reference: calibration.reference)
        calibration.record((v.x * v.x + v.y * v.y).squareRoot())
        calibration.save()
        pendingShot = (vel, x, (depth, lateral))
        setPose(.jump, for: 0.06)
        shotsTaken += 1
        if shotsTaken == 1 { hint.removeAllActions(); hint.run(.fadeOut(withDuration: 0.2)) }
        session.keeper.shot()
        sfx(.shoot)
        Haptics.release()
        refreshHUD()
    }

    /// The ball leaves the shooter's hands at the top of the jump.
    private func launch(velocity: Vec3, from x: Double, intent: (Double, Double)) {
        let c = sim.court
        let b = sim.launch(from: Vec3(x: x, y: c.launchY, z: c.launchZ), velocity: velocity)
        b.onFire = session.keeper.onFire && !attract
        b.spinRate = -10 - velocity.length * 1.2
        intents[b.id] = intent
        holding = false
    }

    private func sfx(_ e: Sound.Effect, volume: Float = 1) {
        if !attract { Sound.shared.play(e, volume: volume) }
    }

    #if DEBUG
    /// Debug `-autoplay YES`: shoots real flicks through the normal input path (for screenshots/soak tests).
    private func runAutoplay(_ dt: Double) {
        attractTimer -= dt
        guard attractTimer <= 0, canShoot else { return }
        attractTimer = Double.random(in: 0.1...0.5)
        kidTarget = Double.random(in: -GameScene.kidRange...GameScene.kidRange)
        kidOffset = kidTarget
        let speed = UserDefaults.standard.double(forKey: "autoplaySpeed")
        let ref = calibration.reference
        let s = speed > 0 ? speed : Double.random(in: (ref * 0.85)...(ref * 1.15))
        let aim = -kidWorldX * 0.6 // lean the flick toward the hoop
        shoot(viewVelocity: (s * sin(aim), s * cos(aim)))
    }
    #endif

    // MARK: - Attract mode

    private func runAttract(_ dt: Double) {
        attractTimer -= dt
        guard attractTimer <= 0, holding, pose == .hold else { return }
        attractTimer = Double.random(in: 0.6...1.3, using: &attractRNG)
        kidTarget = Double.random(in: -8...8, using: &attractRNG)
        kidOffset = kidTarget
        let c = sim.court
        let err = Double.random(in: 0...1, using: &attractRNG) < 0.7 ? 0.04 : 0.14
        let target = Vec3(x: c.hoopX + Double.random(in: -err...err, using: &attractRNG),
                          y: c.rimY + Double.random(in: -err...err, using: &attractRNG), z: c.rimZ)
        if let v = Simulation.launchVelocity(from: Vec3(x: kidWorldX, y: c.launchY, z: c.launchZ), to: target,
                                             angle: Aim.launchAngle, gravity: c.gravity) {
            pendingShot = (v, kidWorldX, (1, 0))
            setPose(.jump, for: 0.06)
        }
    }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}

extension Modifier {
    var shortLabel: String {
        switch self {
        case .movingHoop: return "MOVER"
        case .wind: return "WIND"
        case .tinyRim: return "TINY RIM"
        case .bigRim: return "BIG RIM"
        case .moon: return "MOON"
        case .heavy: return "HEAVY"
        }
    }
}

/// How big one art pixel is on screen, and where the machine goes. One art pixel is always a whole
/// number of device pixels so nearest-neighbour scaling stays perfectly crisp.
struct SceneLayout {
    let pointsPerPixel: CGFloat
    let sceneSize: CGSize
    let area: CGRect

    /// `reserveTop`/`reserveBottom` are points kept clear (beyond the safe area) for other UI.
    static func make(view: CGSize, safeTop: CGFloat, safeBottom: CGFloat, displayScale: CGFloat,
                     reserveTop: CGFloat = 0, reserveBottom: CGFloat = 0, withHUD: Bool) -> SceneLayout {
        let blockW = GameScene.machineSize.width + 4
        let blockH = GameScene.machineSize.height + (withHUD ? GameScene.hudHeight : 0) + 4
        let usable = max(100, view.height - safeTop - safeBottom - reserveTop - reserveBottom)
        let scale = max(1, displayScale)
        let n = max(2, min((view.width * scale / blockW).rounded(.down), (usable * scale / blockH).rounded(.down)))
        let s = n / scale
        let size = CGSize(width: view.width / s, height: view.height / s)
        let area = CGRect(x: 0, y: (safeBottom + reserveBottom) / s, width: size.width, height: usable / s)
        return SceneLayout(pointsPerPixel: s, sceneSize: size, area: area)
    }
}

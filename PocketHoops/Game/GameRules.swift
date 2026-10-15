import Foundation

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case arcade, streak, daily, versus, practice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .arcade: return "ARCADE"
        case .streak: return "SUDDEN DEATH"
        case .daily: return "DAILY"
        case .versus: return "2 PLAYER"
        case .practice: return "PRACTICE"
        }
    }

    var blurb: String {
        switch self {
        case .arcade: return "40 SEC. HIT THE TARGET FOR BONUS TIME"
        case .streak: return "3 LIVES. HOOP GETS HARDER EVERY 5"
        case .daily: return "NEW TWIST EVERY DAY. 30 SEC"
        case .versus: return "PASS THE PHONE. 30 SEC EACH"
        case .practice: return "NO CLOCK. AIM GUIDE ON"
        }
    }
}

/// Daily-challenge twists.
enum Modifier: String, CaseIterable, Codable {
    case movingHoop, wind, tinyRim, bigRim, moon, heavy

    var label: String {
        switch self {
        case .movingHoop: return "MOVING HOOP"
        case .wind: return "CROSSWIND"
        case .tinyRim: return "TINY RIM"
        case .bigRim: return "BIG RIM"
        case .moon: return "MOON GRAVITY"
        case .heavy: return "HEAVY BALL"
        }
    }
}

struct ModeConfig {
    var mode: GameMode
    var timeLimit: Double?
    var lives: Int?
    var hoopAmplitude = 0.0
    var hoopSpeed = 0.0
    var rimScale = 1.0
    var gravityScale = 1.0
    var wind = 0.0
    var showGuide = false
    var modifiers: [Modifier] = []
    /// Arcade stage targets: reaching targets[i] by the buzzer earns stage i+2.
    var stageTargets: [Int] = []
    var stageBonusTime: [Double] = []
    var players = 1

    static func make(_ mode: GameMode, date: Date = Date()) -> ModeConfig {
        switch mode {
        case .arcade:
            // Stage targets are running score totals, checked when the stage's clock runs out.
            return ModeConfig(mode: .arcade, timeLimit: 40, stageTargets: [80, 300], stageBonusTime: [20, 15])
        case .streak:
            return ModeConfig(mode: .streak, lives: 3)
        case .practice:
            return ModeConfig(mode: .practice, showGuide: true)
        case .versus:
            return ModeConfig(mode: .versus, timeLimit: 30, players: 2)
        case .daily:
            var c = ModeConfig(mode: .daily, timeLimit: 30)
            c.modifiers = Daily.modifiers(for: date)
            for m in c.modifiers {
                switch m {
                case .movingHoop: c.hoopAmplitude = 0.2; c.hoopSpeed = 1.3
                case .wind: c.wind = Daily.seed(for: date) % 2 == 0 ? 0.9 : -0.9
                case .tinyRim: c.rimScale = 0.86
                case .bigRim: c.rimScale = 1.2
                case .moon: c.gravityScale = 0.62
                case .heavy: c.gravityScale = 1.3
                }
            }
            return c
        }
    }
}

enum Daily {
    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Stable per-day seed (FNV-1a of the date key), same for every player.
    static func seed(for date: Date) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key(for: date).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    static func modifiers(for date: Date) -> [Modifier] {
        var rng = SeededRNG(seed: seed(for: date))
        var pool = Modifier.allCases
        pool.shuffle(using: &rng)
        var picked = [pool[0]]
        // Never pair opposites.
        let clash: Set<Set<Modifier>> = [[.tinyRim, .bigRim], [.moon, .heavy]]
        if let second = pool.dropFirst().first(where: { !clash.contains([pool[0], $0]) }) { picked.append(second) }
        return picked
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Points, streaks and "on fire" — independent of rendering so it can be tested.
struct Scorekeeper {
    private(set) var score = 0
    private(set) var makes = 0
    private(set) var attempts = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var swishes = 0
    private(set) var banks = 0
    private(set) var fires = 0
    private(set) var onFire = false

    static let fireAt = 3

    struct Make { let points: Int; let lit: Bool; let labels: [String] }

    mutating func shot() { attempts += 1 }

    mutating func make(swish: Bool, bank: Bool, frenzy: Bool, flat: Bool = false) -> Make {
        makes += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        var labels: [String] = []
        var pts = flat ? 1 : (frenzy ? 3 : 2)
        if swish { swishes += 1; labels.append("SWISH!"); if !flat { pts += 1 } }
        if bank { banks += 1; labels.append("BANK!") }
        if onFire && !flat { pts *= 2 }
        var lit = false
        if !onFire && streak >= Scorekeeper.fireAt {
            onFire = true
            fires += 1
            lit = true
        }
        score += pts
        return Make(points: pts, lit: lit, labels: labels)
    }

    /// Returns true if this miss put out a fire.
    mutating func miss() -> Bool {
        let wasOnFire = onFire
        streak = 0
        onFire = false
        return wasOnFire
    }

    var accuracy: Double { attempts == 0 ? 0 : Double(makes) / Double(attempts) }

    var stats: PlayerStats {
        PlayerStats(score: score, makes: makes, attempts: attempts, swishes: swishes, banks: banks,
                    fires: fires, bestStreak: bestStreak)
    }
}

/// One player's numbers from a game: what a results card lists.
struct PlayerStats: Equatable {
    var score = 0
    var makes = 0
    var attempts = 0
    var swishes = 0
    var banks = 0
    var fires = 0
    var bestStreak = 0

    /// Shots made, as a whole percentage.
    var accuracyPercent: Int { attempts == 0 ? 0 : Int((Double(makes) / Double(attempts) * 100).rounded()) }
}

enum SessionEvent: Equatable {
    case frenzy
    case countdown(Int)
    case stage(Int, bonus: Double)
    case levelUp(Int)
    case lifeLost(Int)
    case playerSwap(Int)
    case over
}

/// Clock, stages, lives and hoop movement for one game.
struct GameSession {
    let config: ModeConfig
    private(set) var timeLeft: Double
    private(set) var stage = 1
    private(set) var level = 1
    private(set) var lives: Int
    private(set) var elapsed = 0.0
    private(set) var isOver = false
    private(set) var player = 1
    /// Two-player games: the turns already over, P1 first (the player shooting now is `keeper`).
    private(set) var finishedTurns: [PlayerStats] = []
    var keeper = Scorekeeper()
    private var lastCountdown = 99
    private var frenzyAnnounced = false

    static let frenzyWindow = 10.0

    init(config: ModeConfig) {
        self.config = config
        timeLeft = config.timeLimit ?? 0
        lives = config.lives ?? 0
    }

    var isTimed: Bool { config.timeLimit != nil }
    var frenzy: Bool { isTimed && timeLeft <= GameSession.frenzyWindow && timeLeft > 0 }

    /// Two-player games: each player's own numbers so far, P1 first. The last player's stay live
    /// after the final buzzer, so a shot that drops then still counts for them. Empty in other modes.
    var players: [PlayerStats] { config.mode == .versus ? finishedTurns + [keeper.stats] : [] }
    var playerScores: [Int] { players.map(\.score) }

    /// Hoop amplitude/speed for the current stage or level.
    var hoopMotion: (amplitude: Double, speed: Double) {
        switch config.mode {
        case .arcade:
            return stage == 1 ? (0, 0) : (stage == 2 ? (0.18, 1.1) : (0.28, 1.9))
        case .streak:
            if level <= 1 { return (0, 0) }
            return (min(0.32, 0.08 + 0.05 * Double(level - 2)), min(2.4, 0.8 + 0.25 * Double(level - 2)))
        default:
            return (config.hoopAmplitude, config.hoopSpeed)
        }
    }

    /// The rim can slide this far either way before it would run into the glass.
    static let maxHoopTravel = 0.17

    func hoopX(at t: Double) -> Double {
        let m = hoopMotion
        return min(m.amplitude, GameSession.maxHoopTravel) * sin(t * m.speed)
    }

    mutating func update(_ dt: Double) -> [SessionEvent] {
        guard !isOver else { return [] }
        elapsed += dt
        guard isTimed else { return [] }
        var events: [SessionEvent] = []
        timeLeft = max(0, timeLeft - dt)
        if frenzy && !frenzyAnnounced {
            frenzyAnnounced = true
            events.append(.frenzy)
        }
        let whole = Int(ceil(timeLeft))
        if whole <= 5 && whole > 0 && whole < lastCountdown {
            lastCountdown = whole
            events.append(.countdown(whole))
        }
        if timeLeft <= 0 { events.append(contentsOf: buzzer()) }
        return events
    }

    private mutating func buzzer() -> [SessionEvent] {
        if config.mode == .arcade, stage - 1 < config.stageTargets.count,
           keeper.score >= config.stageTargets[stage - 1] {
            let bonus = config.stageBonusTime[stage - 1]
            stage += 1
            timeLeft = bonus
            frenzyAnnounced = false
            lastCountdown = 99
            return [.stage(stage, bonus: bonus)]
        }
        if config.mode == .versus && player < config.players {
            finishedTurns.append(keeper.stats)
            player += 1
            keeper = Scorekeeper()
            timeLeft = config.timeLimit ?? 30
            frenzyAnnounced = false
            lastCountdown = 99
            return [.playerSwap(player)]
        }
        isOver = true
        return [.over]
    }

    /// Called when a shot resolves.
    mutating func registerMake(swish: Bool, bank: Bool) -> (Scorekeeper.Make, [SessionEvent]) {
        let m = keeper.make(swish: swish, bank: bank, frenzy: frenzy, flat: config.mode == .streak)
        var events: [SessionEvent] = []
        if config.mode == .streak && keeper.makes % 5 == 0 {
            level += 1
            events.append(.levelUp(level))
        }
        return (m, events)
    }

    mutating func registerMiss() -> (putOut: Bool, events: [SessionEvent]) {
        let out = keeper.miss()
        guard config.mode == .streak, !isOver else { return (out, []) }
        lives -= 1
        if lives <= 0 {
            isOver = true
            return (out, [.lifeLost(0), .over])
        }
        return (out, [.lifeLost(lives)])
    }

    /// Ends a practice session on demand.
    mutating func end() { isOver = true }

    var targetForCurrentStage: Int? {
        guard config.mode == .arcade, stage - 1 < config.stageTargets.count else { return nil }
        return config.stageTargets[stage - 1]
    }
}

import Foundation
import SwiftUI

/// What one finished game contributes to progress. In a two-player game the single numbers are the
/// last turn's (P2's), which is what lifetime stats and missions count; `players` has each player's.
struct GameResult: Equatable {
    var mode: GameMode
    var score: Int
    var makes: Int
    var attempts: Int
    var swishes: Int
    var banks: Int
    var fires: Int
    var bestStreak: Int
    var stage: Int = 1
    /// Two-player games: each player's own numbers, P1 first (empty in other modes).
    var players: [PlayerStats] = []

    var playerScores: [Int] { players.map(\.score) }

    var stats: PlayerStats {
        PlayerStats(score: score, makes: makes, attempts: attempts, swishes: swishes, banks: banks,
                    fires: fires, bestStreak: bestStreak)
    }
}

enum MissionKind: String, Codable, CaseIterable {
    case makes, swishes, banks, fires, streak, arcadeScore, playDaily, games

    func text(_ target: Int) -> String {
        switch self {
        case .makes: return "SINK \(target) BASKETS"
        case .swishes: return "HIT \(target) SWISHES"
        case .banks: return "MAKE \(target) BANK SHOTS"
        case .fires: return "GET ON FIRE \(target)X"
        case .streak: return "\(target) IN A ROW"
        case .arcadeScore: return "SCORE \(target) IN ARCADE"
        case .playDaily: return "PLAY THE DAILY"
        case .games: return "PLAY \(target) GAMES"
        }
    }

    /// Single-game bests (not cumulative across games).
    var isBest: Bool { self == .streak || self == .arcadeScore }
}

struct Mission: Codable, Identifiable, Equatable {
    var kind: MissionKind
    var target: Int
    var reward: Int
    var progress = 0
    var claimed = false
    var id: String { kind.rawValue }
    var done: Bool { progress >= target }
    var text: String { kind.text(target) }
}

struct SaveData: Codable, Equatable {
    var tickets = 0
    var ownedSkins: Set<String> = ["classic", "street"]
    var ownedThemes: Set<String> = ["classic"]
    var skin = "classic"
    var theme = "classic"
    var best: [String: Int] = [:]
    var games = 0
    var totalMakes = 0
    var totalAttempts = 0
    var totalSwishes = 0
    var longestStreak = 0
    var missionsDay = ""
    var missions: [Mission] = []
    var dailyDay = ""
    var dailyBest = 0
    var lastDailyPlayed = ""
    var dayStreak = 0
    var sound = true
    var haptics = true
    var seenTutorial = false
    /// The shooter: a character and the accessory worn in each category (category → id).
    var avatar = Avatar.rookie.id
    var ownedAvatars: Set<String> = [Avatar.rookie.id]
    var ownedAccessories: Set<String> = []
    var outfit: [String: String] = [:]
    /// World leaderboard: the random id this device's scores go under and the name the player
    /// picked. Both are empty until they join.
    var boardID = ""
    var boardName = ""

    enum CodingKeys: String, CodingKey {
        case tickets, ownedSkins, ownedThemes, skin, theme, best, games, totalMakes, totalAttempts, totalSwishes,
             longestStreak, missionsDay, missions, dailyDay, dailyBest, lastDailyPlayed, dayStreak, sound, haptics,
             seenTutorial, avatar, ownedAvatars, ownedAccessories, outfit, boardID, boardName
    }
}

extension SaveData {
    /// Every field is optional in a stored save — one written before a field existed (or by a
    /// newer version) still loads, keeping everything the player has earned and bought.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func load<T: Decodable>(_ key: CodingKeys, into value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        load(.tickets, into: &tickets)
        load(.ownedSkins, into: &ownedSkins)
        load(.ownedThemes, into: &ownedThemes)
        load(.skin, into: &skin)
        load(.theme, into: &theme)
        load(.best, into: &best)
        load(.games, into: &games)
        load(.totalMakes, into: &totalMakes)
        load(.totalAttempts, into: &totalAttempts)
        load(.totalSwishes, into: &totalSwishes)
        load(.longestStreak, into: &longestStreak)
        load(.missionsDay, into: &missionsDay)
        load(.missions, into: &missions)
        load(.dailyDay, into: &dailyDay)
        load(.dailyBest, into: &dailyBest)
        load(.lastDailyPlayed, into: &lastDailyPlayed)
        load(.dayStreak, into: &dayStreak)
        load(.sound, into: &sound)
        load(.haptics, into: &haptics)
        load(.seenTutorial, into: &seenTutorial)
        load(.avatar, into: &avatar)
        load(.ownedAvatars, into: &ownedAvatars)
        load(.ownedAccessories, into: &ownedAccessories)
        load(.outfit, into: &outfit)
        load(.boardID, into: &boardID)
        load(.boardName, into: &boardName)
        ownedAvatars.insert(Avatar.rookie.id)
    }
}

@MainActor
final class PlayerProgress: ObservableObject {
    @Published private(set) var data: SaveData
    private let defaults: UserDefaults
    private let storeKey = "pockethoops.save.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: storeKey), let d = try? JSONDecoder().decode(SaveData.self, from: raw) {
            data = d
        } else {
            data = SaveData()
        }
        refreshDay()
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { defaults.set(raw, forKey: storeKey) }
    }

    func update(_ change: (inout SaveData) -> Void) {
        change(&data)
        save()
    }

    // MARK: Day rollover

    func refreshDay(now: Date = Date()) {
        let today = Daily.key(for: now)
        if data.missionsDay != today {
            data.missionsDay = today
            data.missions = PlayerProgress.missions(for: now)
        }
        // Missions already handed out keep their tasks but pay the current rewards.
        let rewards = [PlayerProgress.dailyMission] + PlayerProgress.missionPool
        for i in data.missions.indices {
            if let current = rewards.first(where: { $0.kind == data.missions[i].kind }) { data.missions[i].reward = current.reward }
        }
        if data.dailyDay != today {
            data.dailyDay = today
            data.dailyBest = 0
        }
        save()
    }

    // Mission rewards are half what they were (like every other ticket source), so the prize
    // counter takes more visits to fill.
    /// Every day's missions: "play the Daily", plus two from `missionPool` picked by the date.
    static let dailyMission = Mission(kind: .playDaily, target: 1, reward: 10)
    static let missionPool: [Mission] = [
        Mission(kind: .makes, target: 30, reward: 15),
        Mission(kind: .swishes, target: 6, reward: 20),
        Mission(kind: .banks, target: 3, reward: 20),
        Mission(kind: .fires, target: 2, reward: 17),
        Mission(kind: .streak, target: 8, reward: 22),
        Mission(kind: .arcadeScore, target: 50, reward: 25),
        Mission(kind: .games, target: 3, reward: 12),
    ]

    static func missions(for date: Date) -> [Mission] {
        var rng = SeededRNG(seed: Daily.seed(for: date) ^ 0xA5A5)
        return [dailyMission] + missionPool.shuffled(using: &rng).prefix(2)
    }

    // MARK: Results

    struct Payout: Equatable {
        var tickets: Int
        var newBest: Bool
        var previousBest: Int
        var completedMissions: [Mission]
        var dailyStreak: Int?
        /// Included in `tickets`: the small extra for beating a personal best.
        var bestBonus = 0
    }

    /// Points scored (baskets, in Sudden Death and Practice) per ticket. About half the old rates
    /// (arcade was 3, daily 2, two-player 4, sudden death ½, practice 5), so a run pays about half
    /// the tickets and players come back more often to fill up the prize counter.
    static func pointsPerTicket(_ mode: GameMode) -> Double {
        switch mode {
        case .arcade: return 6.2
        case .daily: return 4.1
        case .versus: return 8.3
        case .streak: return 1
        case .practice: return 10.3
        }
    }

    /// Tickets for the game itself (before bonuses): rounded to the nearest ticket, and never
    /// nothing for a real game (Practice, with no clock, can pay 0).
    static func tickets(for r: GameResult) -> Int {
        let points: Int
        switch r.mode {
        case .arcade, .daily: points = r.score
        case .versus: points = r.playerScores.max() ?? r.score
        case .streak, .practice: points = r.makes
        }
        let t = Int((Double(points) / pointsPerTicket(r.mode)).rounded())
        return r.mode == .practice ? t : max(1, t)
    }

    /// Extra tickets for beating your best (Arcade, Daily, Sudden Death): a small thank-you, not a
    /// reason to play for bests alone.
    static let newBestBonus = 2

    /// The first Daily of the day pays a bonus that grows with the day streak (half what it was).
    static func dailyBonus(dayStreak: Int) -> Int { (10 + 5 * min(dayStreak, 6)) / 2 }

    @discardableResult
    func record(_ r: GameResult, now: Date = Date()) -> Payout {
        refreshDay(now: now)
        let key = r.mode.rawValue
        let previousBest = data.best[key] ?? 0
        let comparable = r.mode == .streak ? r.makes : r.score
        let newBest = r.mode != .practice && r.mode != .versus && comparable > previousBest
        var earned = PlayerProgress.tickets(for: r)
        let bestBonus = newBest ? PlayerProgress.newBestBonus : 0
        earned += bestBonus
        var streakOut: Int?

        data.games += 1
        data.totalMakes += r.makes
        data.totalAttempts += r.attempts
        data.totalSwishes += r.swishes
        data.longestStreak = max(data.longestStreak, r.bestStreak)
        if newBest { data.best[key] = comparable }

        if r.mode == .daily {
            let today = Daily.key(for: now)
            if data.lastDailyPlayed != today {
                let yesterday = Daily.key(for: now.addingTimeInterval(-86_400))
                data.dayStreak = data.lastDailyPlayed == yesterday ? data.dayStreak + 1 : 1
                data.lastDailyPlayed = today
                earned += PlayerProgress.dailyBonus(dayStreak: data.dayStreak) // first daily of the day
                streakOut = data.dayStreak
            }
            data.dailyBest = max(data.dailyBest, r.score)
        }

        var completed: [Mission] = []
        for i in data.missions.indices {
            let wasDone = data.missions[i].done
            let m = data.missions[i]
            let value: Int
            switch m.kind {
            case .makes: value = r.makes
            case .swishes: value = r.swishes
            case .banks: value = r.banks
            case .fires: value = r.fires
            case .streak: value = r.bestStreak
            case .arcadeScore: value = r.mode == .arcade ? r.score : 0
            case .playDaily: value = r.mode == .daily ? 1 : 0
            case .games: value = 1
            }
            data.missions[i].progress = m.kind.isBest ? max(m.progress, value) : m.progress + value
            data.missions[i].progress = min(data.missions[i].progress, m.target)
            if !wasDone && data.missions[i].done && !data.missions[i].claimed {
                data.missions[i].claimed = true
                earned += m.reward
                completed.append(data.missions[i])
            }
        }
        data.tickets += earned
        save()
        return Payout(tickets: earned, newBest: newBest, previousBest: previousBest,
                      completedMissions: completed, dailyStreak: streakOut, bestBonus: bestBonus)
    }

    // MARK: Prize counter

    var skin: BallSkin {
        #if DEBUG
        // Debug `-forceSkin <id>` / `-forceTheme <id>` preview looks without touching the save.
        if let id = UserDefaults.standard.string(forKey: "forceSkin") { return BallSkin.byID(id) }
        #endif
        return BallSkin.byID(data.skin)
    }
    var theme: CabinetTheme {
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "forceTheme") { return CabinetTheme.byID(id) }
        #endif
        return CabinetTheme.byID(data.theme)
    }

    /// The shooter's look: the chosen character wearing the equipped accessories.
    var outfit: Outfit {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "forceOutfit") { return Outfit(debug: s) }
        #endif
        var o = Outfit(avatar: Avatar.byID(data.avatar).id)
        for (key, id) in data.outfit {
            if let c = AccessoryCategory(rawValue: key), let a = Accessory.byID(id), a.category == c { o.items[c] = id }
        }
        return o
    }

    /// Anything for sale needs its progress requirements met *and* enough tickets. (Owning an item
    /// never depends on requirements: whatever the player already has stays theirs.)
    func canBuy(price: Int, unlock: Unlock) -> Bool { data.met(unlock) && data.tickets >= price }

    func buySkin(_ s: BallSkin) -> Bool {
        guard !data.ownedSkins.contains(s.id), canBuy(price: s.price, unlock: s.unlock) else { return false }
        update { $0.tickets -= s.price; $0.ownedSkins.insert(s.id); $0.skin = s.id }
        return true
    }

    func buyTheme(_ t: CabinetTheme) -> Bool {
        guard !data.ownedThemes.contains(t.id), canBuy(price: t.price, unlock: t.unlock) else { return false }
        update { $0.tickets -= t.price; $0.ownedThemes.insert(t.id); $0.theme = t.id }
        return true
    }

    /// Buys and puts on an accessory.
    func buyAccessory(_ a: Accessory) -> Bool {
        guard !data.ownedAccessories.contains(a.id), canBuy(price: a.price, unlock: a.unlock) else { return false }
        update { $0.tickets -= a.price; $0.ownedAccessories.insert(a.id); $0.outfit[a.category.rawValue] = a.id }
        return true
    }

    /// Puts on an owned accessory (free, any time).
    func wear(_ a: Accessory) {
        guard data.ownedAccessories.contains(a.id) else { return }
        update { $0.outfit[a.category.rawValue] = a.id }
    }

    func takeOff(_ c: AccessoryCategory) {
        update { $0.outfit[c.rawValue] = nil }
    }

    /// Buys and switches to a character. Accessories stay equipped: they come back on any
    /// character that can wear them.
    func buyAvatar(_ v: Avatar) -> Bool {
        guard !data.ownedAvatars.contains(v.id), canBuy(price: v.price, unlock: v.unlock) else { return false }
        update { $0.tickets -= v.price; $0.ownedAvatars.insert(v.id); $0.avatar = v.id }
        return true
    }

    func choose(_ v: Avatar) {
        guard data.ownedAvatars.contains(v.id) else { return }
        update { $0.avatar = v.id }
    }

    // MARK: World leaderboard

    var arcadeBest: Int { data.best[GameMode.arcade.rawValue] ?? 0 }

    /// The player's id and name on the world board, once they've joined.
    var boardPlayer: (id: UUID, name: String)? {
        guard !data.boardName.isEmpty, let id = UUID(uuidString: data.boardID) else { return nil }
        return (id, data.boardName)
    }

    /// Joins the world board under `name`, or renames. The id is made once and kept, so a new
    /// name replaces the old one on the board.
    @discardableResult
    func joinBoard(name: String) -> Bool {
        guard let name = BoardName.final(name) else { return false }
        update {
            if UUID(uuidString: $0.boardID) == nil { $0.boardID = UUID().uuidString.lowercased() }
            $0.boardName = name
        }
        return true
    }
}

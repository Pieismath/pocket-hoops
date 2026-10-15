import Foundation

/// Lifetime stats a shop item can ask for (all kept in `SaveData`).
enum Stat: String, CaseIterable {
    case games, baskets, bestScore, swishes, streak
}

/// One progress benchmark an item needs before it can be bought — "make 250 baskets".
struct Requirement: Equatable {
    let stat: Stat
    let target: Int

    static func games(_ n: Int) -> Requirement { Requirement(stat: .games, target: n) }
    static func baskets(_ n: Int) -> Requirement { Requirement(stat: .baskets, target: n) }
    static func score(_ n: Int) -> Requirement { Requirement(stat: .bestScore, target: n) }
    static func swishes(_ n: Int) -> Requirement { Requirement(stat: .swishes, target: n) }
    static func streak(_ n: Int) -> Requirement { Requirement(stat: .streak, target: n) }

    var text: String {
        switch stat {
        case .games: return "PLAY \(target) GAMES"
        case .baskets: return "MAKE \(target) BASKETS"
        case .bestScore: return "SCORE \(target) IN A GAME"
        case .swishes: return "HIT \(target) SWISHES"
        case .streak: return "MAKE \(target) IN A ROW"
        }
    }

    /// What's counted, for a short "112/250 BASKETS".
    var unit: String {
        switch stat {
        case .games: return "GAMES"
        case .baskets: return "BASKETS"
        case .bestScore: return "BEST"
        case .swishes: return "SWISHES"
        case .streak: return "IN A ROW"
        }
    }
}

/// What an item needs besides its ticket price: every one of its requirements met.
struct Unlock: Equatable {
    let requirements: [Requirement]

    static let none = Unlock([])

    init(_ requirements: [Requirement]) { self.requirements = requirements }

    static func needs(_ r: Requirement...) -> Unlock { Unlock(r) }
}

extension SaveData {
    /// A lifetime stat's current value.
    func value(_ s: Stat) -> Int {
        switch s {
        case .games: return games
        case .baskets: return totalMakes
        case .bestScore: return max(best[GameMode.arcade.rawValue] ?? 0, best[GameMode.daily.rawValue] ?? 0)
        case .swishes: return totalSwishes
        case .streak: return longestStreak
        }
    }

    func met(_ r: Requirement) -> Bool { value(r.stat) >= r.target }
    func met(_ u: Unlock) -> Bool { u.requirements.allSatisfy(met) }
    /// "112/250".
    func progress(_ r: Requirement) -> String { "\(min(value(r.stat), r.target))/\(r.target)" }
}

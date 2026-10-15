import Foundation

/// What the shooter can wear. The art for every item is drawn by `scripts/make_outfits.py` onto
/// the reference kid's body parts in all ten poses (GIFArt/outfit_*.png).
enum AccessoryCategory: String, CaseIterable, Identifiable {
    case hat, shirt, jacket, pants, shoes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hat: return "HATS"
        case .shirt: return "SHIRTS"
        case .jacket: return "JACKETS"
        case .pants: return "PANTS"
        case .shoes: return "SHOES"
        }
    }

    /// Body layers, bottom to top. (Then the character's over-clothes hair, then the hat.)
    static let bodyOrder: [AccessoryCategory] = [.pants, .shoes, .shirt, .jacket]
}

struct Accessory: Identifiable, Equatable {
    let id: String
    let name: String
    let category: AccessoryCategory
    let price: Int
    let unlock: Unlock

    init(_ id: String, _ name: String, _ category: AccessoryCategory, _ price: Int, _ unlock: Unlock = .none) {
        self.id = id
        self.name = name
        self.category = category
        self.price = price
        self.unlock = unlock
    }

    static func byID(_ id: String) -> Accessory? { all.first { $0.id == id } }
    static func of(_ c: AccessoryCategory) -> [Accessory] { all.filter { $0.category == c } }

    static let all: [Accessory] = [
        Accessory("sweatband", "Sweatband", .hat, 40),
        Accessory("beanie", "Beanie", .hat, 80, .needs(.games(5))),
        Accessory("bandana", "Bandana", .hat, 120, .needs(.baskets(150))),
        Accessory("cap", "Snapback", .hat, 180, .needs(.baskets(400))),
        Accessory("headphones", "Headphones", .hat, 300, .needs(.games(30), .swishes(300))),
        Accessory("crown", "Crown", .hat, 800, .needs(.baskets(3000), .score(200))),

        Accessory("redtee", "Red Tee", .shirt, 40),
        Accessory("blacktee", "Black Tee", .shirt, 60, .needs(.games(3))),
        Accessory("striped", "Stripes", .shirt, 100, .needs(.baskets(100))),
        Accessory("jersey", "Jersey 23", .shirt, 200, .needs(.streak(12))),
        Accessory("tiedye", "Tie-Dye", .shirt, 300, .needs(.swishes(250))),
        Accessory("goldjersey", "Gold Jersey", .shirt, 700, .needs(.baskets(2500), .score(180))),

        Accessory("hoodie", "Hoodie", .jacket, 150, .needs(.games(10))),
        Accessory("track", "Track Jacket", .jacket, 200, .needs(.baskets(400))),
        Accessory("bomber", "Bomber", .jacket, 250, .needs(.games(25))),
        Accessory("puffer", "Puffer", .jacket, 350, .needs(.baskets(1000))),
        Accessory("varsity", "Varsity", .jacket, 500, .needs(.games(40), .score(150))),
        Accessory("mvp", "MVP Jacket", .jacket, 900, .needs(.baskets(4000), .streak(25))),

        Accessory("blackjeans", "Black Jeans", .pants, 50),
        Accessory("shorts", "Shorts", .pants, 80, .needs(.games(5))),
        Accessory("trackpants", "Track Pants", .pants, 150, .needs(.baskets(300))),
        Accessory("camo", "Camo", .pants, 250, .needs(.games(30))),
        Accessory("galaxy", "Galaxy", .pants, 600, .needs(.swishes(800), .score(150))),

        Accessory("whites", "Fresh Whites", .shoes, 40),
        Accessory("blackkicks", "Black Kicks", .shoes, 80, .needs(.baskets(50))),
        Accessory("retros", "Blue Retros", .shoes, 150, .needs(.games(15))),
        Accessory("neon", "Neon Runners", .shoes, 250, .needs(.baskets(800))),
        Accessory("lava", "Lava Tops", .shoes, 400, .needs(.games(40), .streak(15))),
        Accessory("goldkicks", "Gold Kicks", .shoes, 750, .needs(.baskets(3000), .score(200))),
    ]
}

/// A whole character — a different shooter (hair, skin, their own outfit), or a costume.
struct Avatar: Identifiable, Equatable {
    let id: String
    let name: String
    let price: Int
    let unlock: Unlock
    /// Which accessories can go on top. A costume (robot, bear, statue) wears none; Zorp's
    /// antennae leave no room for a hat.
    let wears: Set<AccessoryCategory>

    static func == (a: Avatar, b: Avatar) -> Bool { a.id == b.id }

    static func byID(_ id: String) -> Avatar { all.first { $0.id == id } ?? rookie }

    private static let everything = Set(AccessoryCategory.allCases)

    static let rookie = Avatar(id: "kid", name: "Rookie", price: 0, unlock: .none, wears: everything)
    static let all: [Avatar] = [
        rookie,
        Avatar(id: "dre", name: "Dre", price: 400, unlock: .needs(.games(15)), wears: everything),
        // Jenn keeps the id "maya" that her art and existing saves use.
        Avatar(id: "maya", name: "Jenn", price: 400, unlock: .needs(.baskets(500)), wears: everything),
        Avatar(id: "rio", name: "Rio", price: 500, unlock: .needs(.games(20), .score(100)), wears: everything),
        Avatar(id: "zorp", name: "Zorp", price: 800, unlock: .needs(.baskets(1500), .swishes(500)),
               wears: [.shirt, .jacket, .pants, .shoes]),
        Avatar(id: "robo", name: "Robo", price: 1000, unlock: .needs(.games(60), .score(180)), wears: []),
        Avatar(id: "bruno", name: "Bruno Bear", price: 1200, unlock: .needs(.baskets(3000), .streak(20)), wears: []),
        Avatar(id: "legend", name: "Legend", price: 2000, unlock: .needs(.baskets(6000), .score(250)), wears: []),
    ]

    /// "WEARS NO ACCESSORIES" / "WEARS CLOTHES, NO HATS" / "" (wears everything).
    var wearsNote: String {
        if wears.isEmpty { return "WEARS NO ACCESSORIES" }
        if wears.count == AccessoryCategory.allCases.count { return "WEARS ANY ACCESSORY" }
        if !wears.contains(.hat) { return "WEARS CLOTHES, NO HATS" }
        return "WEARS SOME ACCESSORIES"
    }
}

/// What the shooter looks like: a character plus the accessory equipped in each category.
struct Outfit: Hashable {
    var avatar: String = Avatar.rookie.id
    var items: [AccessoryCategory: String] = [:]

    static let standard = Outfit()

    /// The accessories actually drawn: the equipped ones this character can wear.
    var worn: [AccessoryCategory: String] {
        let wears = Avatar.byID(avatar).wears
        return items.filter { wears.contains($0.key) && Accessory.byID($0.value) != nil }
    }

    /// Identifies the look for texture caching.
    var key: String {
        avatar + ":" + AccessoryCategory.allCases.compactMap { worn[$0] }.joined(separator: ",")
    }

    func with(_ a: Accessory) -> Outfit {
        var o = self
        o.items[a.category] = a.id
        return o
    }

    func with(avatar id: String) -> Outfit {
        var o = self
        o.avatar = id
        return o
    }
}

extension Outfit {
    /// The look as the world leaderboard stores it: the character and what it visibly wears,
    /// e.g. "maya:beanie,hoodie".
    var code: String {
        avatar + ":" + AccessoryCategory.allCases.compactMap { worn[$0] }.joined(separator: ",")
    }

    /// Reads `code`. An unknown character draws as the Rookie and unknown items are skipped, so an
    /// entry from a newer version of the game still shows.
    init(code: String) {
        self.init()
        let parts = code.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if let id = parts.first, let v = Avatar.all.first(where: { $0.id == id }) { avatar = v.id }
        if parts.count > 1 {
            for id in parts[1].split(separator: ",") {
                if let a = Accessory.byID(String(id)) { items[a.category] = a.id }
            }
        }
    }
}

#if DEBUG
extension Outfit {
    /// Debug `-forceOutfit jenn,beanie,hoodie`: preview a look without touching the save. A
    /// character can be given by id or by name.
    init(debug: String) {
        self.init()
        for token in debug.split(separator: ",").map(String.init) {
            if let v = Avatar.all.first(where: { $0.id == token || $0.name.lowercased() == token }) { avatar = v.id }
            if let a = Accessory.byID(token) { items[a.category] = a.id }
        }
    }
}
#endif

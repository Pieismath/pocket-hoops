import UIKit

/// Unlockable ball skins: palette swaps of the reference art's red-and-white ball
/// (it is drawn in exactly three colours: red, white and a black outline).
struct BallSkin: Identifiable, Equatable {
    let id: String
    let name: String
    let price: Int
    /// Replaces the reference ball's red.
    let primary: RGBA
    /// Replaces the reference ball's white.
    let secondary: RGBA
    /// Progress needed (besides tickets) before it can be bought.
    var unlock: Unlock = .none

    static let artRed = RGBA(hex: 0xD42C2C)
    static let artWhite = RGBA(hex: 0xFFFFFF)

    static func == (a: BallSkin, b: BallSkin) -> Bool { a.id == b.id }

    static let all: [BallSkin] = [classic, street, ice, tennis, melon, eight, smiley, earth, disco, gold]
    static func byID(_ id: String) -> BallSkin { all.first { $0.id == id } ?? classic }

    static let classic = BallSkin(id: "classic", name: "Arcade Red", price: 0, primary: artRed, secondary: artWhite)
    static let street = BallSkin(id: "street", name: "Street", price: 0,
                                 primary: RGBA(hex: 0xE8772E), secondary: RGBA(hex: 0x3A2418))
    static let ice = BallSkin(id: "ice", name: "Freeze", price: 60,
                              primary: RGBA(hex: 0x4FB8E8), secondary: RGBA(hex: 0xF2FBFF), unlock: .needs(.games(3)))
    static let tennis = BallSkin(id: "tennis", name: "Fuzzy", price: 100,
                                 primary: RGBA(hex: 0xC9E83A), secondary: RGBA(hex: 0xF7F7EE), unlock: .needs(.baskets(100)))
    static let melon = BallSkin(id: "melon", name: "Melon", price: 120,
                                primary: RGBA(hex: 0x2E8B3A), secondary: RGBA(hex: 0x9BE36B), unlock: .needs(.games(10)))
    static let eight = BallSkin(id: "eight", name: "Eight Ball", price: 150,
                                primary: RGBA(hex: 0x1C1C26), secondary: RGBA(hex: 0xF4F4F4), unlock: .needs(.baskets(300)))
    static let smiley = BallSkin(id: "smiley", name: "Sunny", price: 200,
                                 primary: RGBA(hex: 0xFFC61A), secondary: RGBA(hex: 0xFFF3B0), unlock: .needs(.swishes(150)))
    static let earth = BallSkin(id: "earth", name: "Planet", price: 250,
                                primary: RGBA(hex: 0x2F74D8), secondary: RGBA(hex: 0x4DB846),
                                unlock: .needs(.games(20), .score(80)))
    static let disco = BallSkin(id: "disco", name: "Disco", price: 300,
                                primary: RGBA(hex: 0xFF4FD8), secondary: RGBA(hex: 0x5AF0FF), unlock: .needs(.baskets(800)))
    static let gold = BallSkin(id: "gold", name: "Solid Gold", price: 500,
                               primary: RGBA(hex: 0xE0A21E), secondary: RGBA(hex: 0xFFF1B8),
                               unlock: .needs(.baskets(2000), .score(150)))

    private var map: [RGBA: RGBA] { [BallSkin.artRed: primary, BallSkin.artWhite: secondary] }

    func recolor(_ c: PixelCanvas) {
        guard self != .classic else { return }
        c.replace(map)
    }

    /// Recolours only the ball inside a kid sprite (`region` = the ball's box in the sprite, y down).
    func recolor(_ c: PixelCanvas, region: [Int]) {
        guard self != .classic else { return }
        c.replace(map, region: region)
    }
}

/// Cabinet colour schemes: the reference art recoloured family by family
/// (blue body, red trim, glass, background); black, white and the coin box are left alone.
struct CabinetTheme: Identifiable, Equatable {
    struct Shift: Equatable {
        var hue: Double      // degrees; nil-like identity when `amount` is 0
        var amount: Double   // 0 = keep the original hue, 1 = use `hue`
        var saturation: Double
        var brightness: Double
        static let none = Shift(hue: 0, amount: 0, saturation: 1, brightness: 1)
    }

    let id: String
    let name: String
    let price: Int
    let background: RGBA
    let body: Shift
    let trim: Shift
    let glass: Shift
    /// LED colour for live text (sign score etc.).
    let led: RGBA
    /// Progress needed (besides tickets) before it can be bought.
    var unlock: Unlock = .none

    static func == (a: CabinetTheme, b: CabinetTheme) -> Bool { a.id == b.id }

    static let all: [CabinetTheme] = [classic, neon, retro, sunset, midnight]
    static func byID(_ id: String) -> CabinetTheme { all.first { $0.id == id } ?? classic }

    /// The reference GIF, untouched.
    static let classic = CabinetTheme(id: "classic", name: "Classic", price: 0, background: RGBA(hex: 0x24ACE5),
                                      body: .none, trim: .none, glass: .none, led: RGBA(hex: 0xBBB38A))
    static let neon = CabinetTheme(id: "neon", name: "Neon Night", price: 150, background: RGBA(hex: 0x1B1036),
                                   body: Shift(hue: 268, amount: 1, saturation: 0.95, brightness: 0.85),
                                   trim: Shift(hue: 318, amount: 1, saturation: 1, brightness: 1.05),
                                   glass: Shift(hue: 185, amount: 1, saturation: 1, brightness: 1),
                                   led: RGBA(hex: 0x5AF0FF), unlock: .needs(.games(10)))
    static let retro = CabinetTheme(id: "retro", name: "Hardwood", price: 200, background: RGBA(hex: 0x2F6B4F),
                                    body: Shift(hue: 28, amount: 1, saturation: 0.75, brightness: 0.95),
                                    trim: Shift(hue: 215, amount: 1, saturation: 0.9, brightness: 0.7),
                                    glass: Shift(hue: 150, amount: 1, saturation: 0.6, brightness: 1),
                                    led: RGBA(hex: 0xFF6040), unlock: .needs(.baskets(500)))
    static let sunset = CabinetTheme(id: "sunset", name: "Sunset Beach", price: 300, background: RGBA(hex: 0xFF9A5A),
                                     body: Shift(hue: 338, amount: 1, saturation: 0.85, brightness: 1),
                                     trim: Shift(hue: 275, amount: 1, saturation: 0.9, brightness: 0.8),
                                     glass: Shift(hue: 28, amount: 1, saturation: 0.55, brightness: 1.05),
                                     led: RGBA(hex: 0xFFE95A), unlock: .needs(.games(25), .score(100)))
    static let midnight = CabinetTheme(id: "midnight", name: "Gold Rush", price: 500, background: RGBA(hex: 0x111418),
                                       body: Shift(hue: 220, amount: 1, saturation: 0.2, brightness: 0.55),
                                       trim: Shift(hue: 44, amount: 1, saturation: 0.9, brightness: 1),
                                       glass: Shift(hue: 44, amount: 1, saturation: 0.35, brightness: 0.95),
                                       led: RGBA(hex: 0xF5C542), unlock: .needs(.baskets(2500), .streak(20)))

    /// Which family each colour of the reference cabinet belongs to.
    private static let families: [RGBA: KeyPath<CabinetTheme, Shift>] = {
        var f: [RGBA: KeyPath<CabinetTheme, Shift>] = [:]
        for h in [0x1463AD, 0x227BCF, 0x0C4E8C, 0x083662, 0x0E4579] { f[RGBA(hex: UInt32(h))] = \.body }
        for h in [0xFF1414, 0xFF7373, 0xD42C2C, 0xBB7E8A] { f[RGBA(hex: UInt32(h))] = \.trim }
        for h in [0x4ECAF2, 0xA7E5F9, 0xBBF3FF, 0x46A6D6, 0xA3D3EB, 0xDDF9FF,
                  0x5C949F, 0x3C7480, 0x9EBAC0, 0xA6C2C8, 0xAECACF, 0x4D8590] { f[RGBA(hex: UInt32(h))] = \.glass }
        return f
    }()

    func recolor(_ c: PixelCanvas) {
        guard self != .classic else { return }
        var map: [RGBA: RGBA] = [:]
        for (colour, family) in CabinetTheme.families { map[colour] = self[keyPath: family].apply(colour) }
        c.replace(map)
    }
}

extension CabinetTheme.Shift {
    func apply(_ c: RGBA) -> RGBA {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = Double(h) * 360
        if amount > 0 {
            // Move toward the target hue along the short way round.
            var d = self.hue - hue
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            hue += d * amount
        }
        let out = UIColor(hue: CGFloat((hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360),
                          saturation: min(1, s * CGFloat(saturation)),
                          brightness: min(1, b * CGFloat(brightness)), alpha: 1)
        return out.rgba
    }
}

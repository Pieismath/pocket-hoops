import SpriteKit
import UIKit

/// Where things are in the reference art, as written by `scripts/extract_gif_art.py`
/// (`GIFArt/layout.json`). Units are native art pixels, y down, in the GIF's 200×150 frame.
struct GIFLayout: Decodable {
    let machineCanvas: [Int]   // x, y, width, height
    let rimBox: [Int]          // x0, y0, x1, y1 (exclusive)
    let trough: [Int]          // x0, y0, x1, y1 (exclusive)
    let lamps: [[Int]]         // top-left of each 3×3 player lamp
    let kidCanvas: [Int]       // x0, y0, x1, y1 (exclusive)
    let kidBall: [String: [String: [Int]]]
    let sparkleCanvas: [Int]   // x, y, width, height
    let playerText: [Int]?     // x0, y0, x1, y1 (exclusive): where the strip says "PLAYER:"

    static let shared: GIFLayout = {
        guard let url = GIFArt.url("layout", "json"), let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(GIFLayout.self, from: data) else {
            fatalError("GIFArt/layout.json missing from the bundle — run scripts/extract_gif_art.py")
        }
        return layout
    }()

    var canvasX: Int { machineCanvas[0] }
    var canvasY: Int { machineCanvas[1] }
    var canvasWidth: Int { machineCanvas[2] }
    var canvasHeight: Int { machineCanvas[3] }

    /// Converts a GIF art rectangle (x0, y0, x1, y1; y down) into machine-canvas coordinates with
    /// SpriteKit's y-up convention (origin at the canvas's bottom-left).
    func canvasRect(_ r: [Int]) -> CGRect {
        CGRect(x: r[0] - canvasX, y: canvasY + canvasHeight - r[3], width: r[2] - r[0], height: r[3] - r[1])
    }

    /// Canvas-space (y-up) coordinate of a GIF art row boundary.
    func canvasY(ofArtRow row: Double) -> Double { Double(canvasY + canvasHeight) - row }
    func canvasX(ofArtColumn col: Double) -> Double { col - Double(canvasX) }
}

/// Sprites cut from the reference GIF, recoloured for the chosen cabinet theme / ball skin and
/// cached as nearest-neighbour textures. Each is Scale2x-upscaled, so a texture has 2 texels per
/// art pixel: nodes are sized in art pixels with `size(of:)` and may sit on half-pixel positions.
enum GIFArt {
    static let ballFrames = 5
    static let texelsPerPixel: CGFloat = 2

    /// A texture's size in art pixels (scene units).
    static func size(of t: SKTexture) -> CGSize {
        CGSize(width: t.size().width / texelsPerPixel, height: t.size().height / texelsPerPixel)
    }
    private static var cache: [String: SKTexture] = [:]
    private static var imageCache: [String: CGImage] = [:]

    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "GIFArt")
    }

    static func image(_ name: String) -> CGImage {
        if let img = imageCache[name] { return img }
        guard let url = url(name, "png"), let ui = UIImage(contentsOfFile: url.path), let cg = ui.cgImage else {
            fatalError("GIFArt/\(name).png missing from the bundle — run scripts/extract_gif_art.py")
        }
        imageCache[name] = cg
        return cg
    }

    /// A machine layer (`machine`, `panel`, `lip`, `rim_back_rest`, …) in the theme's colours.
    static func machine(_ name: String, theme: CabinetTheme) -> SKTexture {
        texture(name, key: "\(name)|\(theme.id)") { theme.recolor($0) }
    }

    /// Ball frame `i` (0..<ballFrames), or the squash frame, in the skin's colours.
    static func ball(_ i: Int, skin: BallSkin, squash: Bool = false) -> SKTexture {
        let name = squash ? "ball_squash" : "ball_\(((i % ballFrames) + ballFrames) % ballFrames)"
        return texture(name, key: "\(name)|\(skin.id)") { skin.recolor($0) }
    }

    /// The shooter in `pose` wearing `outfit`; the ball in their hands (if any) takes the skin's colours.
    static func kid(_ pose: KidPose, skin: BallSkin, outfit: Outfit = .standard) -> SKTexture {
        let key = "kid_\(pose.rawValue)|\(skin.id)|\(outfit.key)"
        if let t = cache[key] { return t }
        let t = SKTexture(cgImage: kidImage(pose, skin: skin, outfit: outfit))
        t.filteringMode = .nearest
        cache[key] = t
        return t
    }

    /// The same, as an image (2 texels per art pixel) for SwiftUI previews.
    static func kidImage(_ pose: KidPose, skin: BallSkin, outfit: Outfit = .standard) -> CGImage {
        let key = "kid_\(pose.rawValue)|\(skin.id)|\(outfit.key)"
        if let img = kidImages[key] { return img }
        let canvas = kidCanvas(pose, outfit: outfit).scale2x()
        if let box = GIFLayout.shared.kidBall[pose.rawValue]?["ball"] {
            skin.recolor(canvas, region: box.map { $0 * Int(texelsPerPixel) })
        }
        let img = canvas.makeImage()!
        kidImages[key] = img
        return img
    }
    private static var kidImages: [String: CGImage] = [:]

    /// The shooter at one pixel per art pixel: the character's body, then the accessories it's
    /// wearing (pants, shoes, shirt, jacket), any hair it wears over its clothes, then the hat.
    static func kidCanvas(_ pose: KidPose, outfit: Outfit) -> PixelCanvas {
        let avatar = Avatar.byID(outfit.avatar)
        let canvas = avatar == .rookie ? PixelCanvas(image: image("kid_\(pose.rawValue)"))
            : outfitCell("outfit_avatar_\(avatar.id)", pose)
        // Skin painted by an accessory (bare legs under shorts) is this character's skin.
        let art = OutfitArt.shared
        var skinMap: [RGBA: RGBA] = [:]
        if let tones = art.avatars[avatar.id]?.skin.map(OutfitArt.colour) {
            for (k, key) in art.skinKeys.map(OutfitArt.colour).enumerated() where k < tones.count { skinMap[key] = tones[k] }
        }
        func layer(_ name: String) {
            let l = outfitCell(name, pose)
            if !skinMap.isEmpty { l.replace(skinMap) }
            canvas.draw(l, x: 0, y: 0)
        }
        let worn = outfit.worn
        for c in AccessoryCategory.bodyOrder { if let id = worn[c] { layer("outfit_acc_\(id)") } }
        if art.avatars[avatar.id]?.hairOver == true { layer("outfit_hair_\(avatar.id)") }
        if let hat = worn[.hat] { layer("outfit_acc_\(hat)") }
        return canvas
    }

    /// One pose's cell of an outfit sheet (the poses side by side, in `OutfitArt.poses` order).
    private static func outfitCell(_ name: String, _ pose: KidPose) -> PixelCanvas {
        let art = OutfitArt.shared
        let i = art.poses.firstIndex(of: pose.rawValue) ?? 0
        let cell = image(name).cropping(to: CGRect(x: i * art.cell[0], y: 0, width: art.cell[0], height: art.cell[1]))!
        return PixelCanvas(image: cell)
    }

    static func sparkle(_ i: Int) -> SKTexture { texture("sparkle_\(i)", key: "sparkle_\(i)") { _ in } }

    private static func texture(_ name: String, key: String, recolor: (PixelCanvas) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        // Upscale first, then recolour (a pure per-pixel swap), so every theme has the same shapes.
        let canvas = name.hasPrefix("rim_") ? rimCanvas(name) : PixelCanvas(image: image(name)).scale2x()
        recolor(canvas)
        let t = SKTexture(cgImage: canvas.makeImage()!)
        t.filteringMode = .nearest
        cache[key] = t
        return t
    }

    /// The ring's colours in the art: its red, its highlight and its outline (the net is white).
    static let rimColours: Set<RGBA> = [RGBA(hex: 0xFF1414), RGBA(hex: 0xFF7373), RGBA(hex: 0x000000)]

    /// One layer of the rim, upscaled. The rim is a single ring drawn as two layers: `rim_back_*` goes
    /// behind a ball in the hoop and `rim_front_*` in front of it. Upscaled one layer at a time, each
    /// rounds off its corners where it meets the other, and the board shows through the seams. So
    /// wherever the seam changes a ring pixel's upscaled look, this layer takes the look of the whole
    /// ring upscaled in one piece. Every pixel stays in its own layer, the net keeps its own
    /// upscaling, and nothing is ever cleared.
    static func rimCanvas(_ name: String) -> PixelCanvas {
        let back = name.hasPrefix("rim_back_")
        let partner = back ? name.replacingOccurrences(of: "rim_back_", with: "rim_front_")
                           : name.replacingOccurrences(of: "rim_front_", with: "rim_back_")
        let mine = PixelCanvas(image: image(name))
        let other = PixelCanvas(image: image(partner))
        let whole = PixelCanvas(width: mine.width, height: mine.height)
        for y in 0..<whole.height {
            for x in 0..<whole.width {
                let (b, f) = back ? (mine[x, y], other[x, y]) : (other[x, y], mine[x, y])
                whole[x, y] = f.a > 0 ? f : b
            }
        }
        let out = mine.scale2x()
        let ring = whole.scale2x()
        for y in 0..<out.height {
            for x in 0..<out.width {
                let own = mine[x / 2, y / 2]
                let alone = out[x, y], together = ring[x, y]
                guard rimColours.contains(own), alone != together else { continue }
                if rimColours.contains(together) {
                    out[x, y] = together
                } else if alone.a == 0 {
                    out[x, y] = own
                }
            }
        }
        return out
    }
}

/// How `scripts/make_outfits.py` laid out the outfit sheets (`GIFArt/outfits.json`).
struct OutfitArt: Decodable {
    struct Character: Decodable {
        let skin: [String]
        let hairOver: Bool
    }

    let poses: [String]
    let cell: [Int]
    let skinKeys: [String]
    let avatars: [String: Character]

    static let shared: OutfitArt = {
        guard let url = GIFArt.url("outfits", "json"), let data = try? Data(contentsOf: url),
              let art = try? JSONDecoder().decode(OutfitArt.self, from: data) else {
            fatalError("GIFArt/outfits.json missing from the bundle — run scripts/make_outfits.py")
        }
        return art
    }()

    /// "#RRGGBB" → colour.
    static func colour(_ hex: String) -> RGBA { RGBA(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0) }
}

/// The shooter's poses, named after the sprite files (frames of the reference GIF).
enum KidPose: String, CaseIterable {
    case reach, lift, hold, crouch, jump, follow1, follow2, follow3, idle, ready

    /// Poses where the ball is in the kid's hands (drawn as part of the sprite).
    var holdsBall: Bool { self == .lift || self == .hold || self == .crouch || self == .jump }
}

extension PixelCanvas {
    /// Decodes a CGImage into a canvas (bottom-left origin, like the rest of the art code).
    convenience init(image: CGImage) {
        let w = image.width, h = image.height
        self.init(width: w, height: h)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CGContext memory is top row first.
        for row in 0..<h {
            let y = h - 1 - row
            for x in 0..<w {
                let o = (row * w + x) * 4
                let a = bytes[o + 3]
                guard a > 0 else { continue }
                // Art is fully opaque or fully clear, so un-premultiplying is exact.
                self[x, y] = RGBA(bytes[o], bytes[o + 1], bytes[o + 2], a)
            }
        }
    }

    /// Replaces every pixel of colour `from` with `to` (optionally only inside a GIF-space box of a
    /// sprite: x0, y0, x1, y1 with y down from the sprite's top).
    func replace(_ map: [RGBA: RGBA], region: [Int]? = nil) {
        for y in 0..<height {
            for x in 0..<width {
                if let r = region {
                    let topY = height - 1 - y
                    guard x >= r[0], x < r[2], topY >= r[1], topY < r[3] else { continue }
                }
                if let to = map[self[x, y]] { set(x, y, to) }
            }
        }
    }
}

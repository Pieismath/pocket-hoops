import SwiftUI

/// Text in the arcade pixel font. `px` = points per font pixel.
struct PixelText: View {
    let text: String
    var color: RGBA = .white
    var px: CGFloat = 3
    var outline: RGBA? = nil
    var shadow: RGBA? = RGBA.black

    init(_ text: String, color: RGBA = .white, px: CGFloat = 3, outline: RGBA? = nil, shadow: RGBA? = .black) {
        self.text = text
        self.color = color
        self.px = px
        self.outline = outline
        self.shadow = shadow
    }

    var body: some View {
        if let img = PixelFont.image(text, color: color.uiColor, shadow: shadow?.uiColor, outline: outline?.uiColor) {
            Image(decorative: img, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
                .accessibilityLabel(text)
        }
    }
}

/// Word-wrapped pixel text, centred.
struct PixelParagraph: View {
    let text: String
    var maxChars = 22
    var color: RGBA = .white
    var px: CGFloat = 2
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: px * 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                PixelText(l, color: color, px: px)
            }
        }
    }

    private var lines: [String] {
        var out: [String] = []
        var cur = ""
        for w in text.split(separator: " ") {
            if cur.isEmpty { cur = String(w) } else if cur.count + 1 + w.count <= maxChars { cur += " " + w } else {
                out.append(cur); cur = String(w)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

/// Chunky arcade button: black outline, drop shadow that collapses when pressed.
struct PixelButtonStyle: ButtonStyle {
    var fill: RGBA
    var px: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(.horizontal, px * 4)
            .padding(.vertical, px * 3)
            .frame(maxWidth: .infinity)
            .background(
                ZStack(alignment: .top) {
                    Rectangle().fill(Color(fill.uiColor))
                    Rectangle().fill(Color(fill.lighter(0.35).uiColor)).frame(height: px)
                }
            )
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: px))
            .background(Rectangle().fill(Color.black).offset(x: pressed ? 0 : px, y: pressed ? 0 : px))
            .offset(x: pressed ? px : 0, y: pressed ? px : 0)
            .onChange(of: pressed) { _, now in
                if now { Sound.shared.play(.tap); Haptics.tap() }
            }
    }
}

/// Panel with a pixel frame.
struct PixelPanel<Content: View>: View {
    var fill: RGBA
    var border: RGBA = .black
    var px: CGFloat = 3
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(px * 5)
            .background(Color(fill.uiColor))
            .overlay(Rectangle().strokeBorder(Color(border.uiColor), lineWidth: px))
            .background(Rectangle().fill(Color.black.opacity(0.5)).offset(x: px * 1.5, y: px * 1.5))
    }
}

/// A ball skin, drawn with the reference art's ball frames (optionally spinning).
struct BallPreview: View {
    let skin: BallSkin
    var size: CGFloat = 56
    var spinning = false
    @State private var frame = 0

    var body: some View {
        Image(decorative: GIFArt.ball(frame, skin: skin).cgImage(), scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
            .task(id: spinning) {
                while spinning && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    frame = (frame + 1) % GIFArt.ballFrames
                }
            }
    }
}

/// The shooter in an outfit, going through the throw like in the game.
struct KidPreview: View {
    let outfit: Outfit
    let skin: BallSkin
    /// Points per art pixel.
    var scale: CGFloat = 2.6
    @State private var step = 0

    private static let cycle: [KidPose] = [.idle, .idle, .idle, .idle, .ready, .crouch, .jump, .follow1, .follow2,
                                           .follow3, .reach, .lift, .hold, .hold, .hold]
    /// Art rows any pose reaches (the jump's ball tops out at row 13), so the preview can be bigger.
    private static let rows = 12..<66

    var body: some View {
        let art = OutfitArt.shared
        let k = Int(GIFArt.texelsPerPixel)
        let full = GIFArt.kidImage(KidPreview.cycle[step % KidPreview.cycle.count], skin: skin, outfit: outfit)
        let crop = full.cropping(to: CGRect(x: 0, y: KidPreview.rows.lowerBound * k, width: art.cell[0] * k,
                                            height: KidPreview.rows.count * k)) ?? full
        Image(decorative: crop, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(art.cell[0]) * scale, height: CGFloat(KidPreview.rows.count) * scale)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 240_000_000)
                    step += 1
                }
            }
    }
}

/// The shooter standing still, cropped to the body (for a shop card).
struct KidThumb: View {
    let outfit: Outfit
    let skin: BallSkin
    var scale: CGFloat = 2

    /// Art rows of the standing pose worth showing (the rest of the cell is room for raised arms).
    private static let rows = 30..<66

    var body: some View {
        let art = OutfitArt.shared
        let k = Int(GIFArt.texelsPerPixel)
        let full = GIFArt.kidImage(.idle, skin: skin, outfit: outfit)
        let crop = full.cropping(to: CGRect(x: 0, y: KidThumb.rows.lowerBound * k, width: art.cell[0] * k,
                                            height: KidThumb.rows.count * k)) ?? full
        Image(decorative: crop, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(art.cell[0]) * scale, height: CGFloat(KidThumb.rows.count) * scale)
    }
}

/// A leaderboard player: their character standing still, from antennae to shoes, trimmed to the body.
struct KidBadge: View {
    let outfit: Outfit
    var scale: CGFloat = 1.2

    /// Art rows and columns of the standing pose that any character or hat reaches.
    private static let rows = 28..<65
    private static let cols = 9..<35

    var body: some View {
        let k = Int(GIFArt.texelsPerPixel)
        let full = GIFArt.kidImage(.idle, skin: .classic, outfit: outfit)
        let crop = full.cropping(to: CGRect(x: KidBadge.cols.lowerBound * k, y: KidBadge.rows.lowerBound * k,
                                            width: KidBadge.cols.count * k, height: KidBadge.rows.count * k)) ?? full
        Image(decorative: crop, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(KidBadge.cols.count) * scale, height: CGFloat(KidBadge.rows.count) * scale)
    }
}

/// A cabinet theme: the reference machine recoloured, at 1 art pixel per `scale` points.
struct CabinetPreview: View {
    let theme: CabinetTheme
    var scale: CGFloat = 1

    var body: some View {
        let layout = GIFLayout.shared
        Image(decorative: CabinetPreview.render(theme: theme), scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(layout.canvasWidth) * scale, height: CGFloat(layout.canvasHeight) * scale)
            .background(theme.background.color)
    }

    static func render(theme: CabinetTheme) -> CGImage {
        let layout = GIFLayout.shared
        let k = Int(GIFArt.texelsPerPixel)
        let c = PixelCanvas(width: layout.canvasWidth * k, height: layout.canvasHeight * k)
        let rim = layout.canvasRect(layout.rimBox)
        for (name, at) in [("machine", CGPoint.zero), ("rim_back_rest", rim.origin), ("rim_front_rest", rim.origin),
                           ("panel", .zero), ("lip", .zero)] {
            let layer = PixelCanvas(image: GIFArt.machine(name, theme: theme).cgImage())
            c.draw(layer, x: Int(at.x) * k, y: Int(at.y) * k)
        }
        return c.makeImage()!
    }
}

extension RGBA {
    var color: Color { Color(uiColor) }
}

enum Palette {
    static let sky = RGBA(hex: 0x29A8E0)
    static let navy = RGBA(hex: 0x16325E)
    static let red = RGBA(hex: 0xE3262F)
    static let blue = RGBA(hex: 0x1C5FA8)
    static let gold = RGBA(hex: 0xFFC83A)
    static let green = RGBA(hex: 0x3DBE5A)
    static let purple = RGBA(hex: 0x7A4BD6)
    static let grey = RGBA(hex: 0x5A6378)
    static let led = RGBA(hex: 0xFFB43A)
}

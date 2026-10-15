import SpriteKit

/// SpriteKit node that draws text in the arcade pixel font. Textures are cached per
/// (text, colour, style) and rendered at 1 texel per font pixel; `pixelScale` enlarges with
/// nearest-neighbour filtering so the chunky look survives.
final class PixelLabel: SKSpriteNode {
    private static var cache: [String: SKTexture] = [:]

    private(set) var text = ""
    var textColor: RGBA { didSet { if oldValue != textColor { redraw() } } }
    var outline: RGBA? { didSet { redraw() } }
    var shadow: RGBA? { didSet { redraw() } }
    var pixelScale: CGFloat = 1 { didSet { setScale(pixelScale) } }
    /// Font size: `.tiny` is the machine's 3×5 LCD lettering.
    let fontSize: PixelFont.Size

    init(_ text: String = "", color: RGBA = .white, scale: CGFloat = 1, outline: RGBA? = nil, shadow: RGBA? = nil,
         size: PixelFont.Size = .big) {
        self.textColor = color
        self.fontSize = size
        self.outline = outline
        self.shadow = shadow
        super.init(texture: nil, color: .clear, size: .zero)
        self.text = text
        redraw()
        pixelScale = scale
        setScale(scale)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ newText: String) {
        guard newText != text else { return }
        text = newText
        redraw()
    }

    private func redraw() {
        guard !text.isEmpty else { texture = nil; size = .zero; return }
        let key = "\(text)|\(textColor)|\(String(describing: outline))|\(String(describing: shadow))|\(fontSize)"
        let tex: SKTexture
        if let t = PixelLabel.cache[key] {
            tex = t
        } else if let img = PixelFont.image(text, color: textColor.uiColor, shadow: shadow?.uiColor, outline: outline?.uiColor,
                                                size: fontSize) {
            tex = SKTexture(cgImage: img)
            tex.filteringMode = .nearest
            PixelLabel.cache[key] = tex
        } else { return }
        texture = tex
        // SKSpriteNode.size is the *scaled* size: set it at scale 1, then scale up.
        setScale(1)
        size = tex.size()
        setScale(pixelScale)
    }
}

extension CGPoint {
    /// Snap to whole scene pixels so sprites line up with the pixel grid.
    var snapped: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
    /// Snap to half pixels: the texel grid of the 2× (Scale2x) sprites and half-scale text.
    var halfSnapped: CGPoint { CGPoint(x: (x * 2).rounded() / 2, y: (y * 2).rounded() / 2) }
}

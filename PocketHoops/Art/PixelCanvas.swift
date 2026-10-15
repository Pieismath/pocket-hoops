import CoreGraphics
import UIKit

/// 8-bit RGBA colour used by the pixel painters.
struct RGBA: Equatable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: UInt8 = 255) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF), alpha)
    }

    static let clear = RGBA(0, 0, 0, 0)
    static let black = RGBA(hex: 0x10131C)
    static let white = RGBA(hex: 0xFFFFFF)

    func mix(_ o: RGBA, _ t: Double) -> RGBA {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(a) + (Double(b) - Double(a)) * t))) }
        return RGBA(m(r, o.r), m(g, o.g), m(b, o.b), m(a, o.a))
    }
    func darker(_ t: Double = 0.3) -> RGBA { mix(RGBA(hex: 0x0A0A1E), t) }
    func lighter(_ t: Double = 0.3) -> RGBA { mix(.white, t) }
    func withAlpha(_ a: UInt8) -> RGBA { RGBA(r, g, b, a) }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension UIColor {
    var rgba: RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), UInt8(a * 255))
    }
}

/// A software pixel buffer with a bottom-left origin (matches SpriteKit).
/// Everything is drawn without anti-aliasing so textures stay crisp when scaled with `.nearest`.
final class PixelCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]

    init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = max(1, width)
        self.height = max(1, height)
        pixels = Array(repeating: fill, count: self.width * self.height)
    }

    subscript(x: Int, y: Int) -> RGBA {
        get { inBounds(x, y) ? pixels[y * width + x] : .clear }
        set { set(x, y, newValue) }
    }

    func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// Source-over blend.
    func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard inBounds(x, y), c.a > 0 else { return }
        let i = y * width + x
        if c.a == 255 { pixels[i] = c; return }
        let d = pixels[i]
        let sa = Double(c.a) / 255, da = Double(d.a) / 255
        let oa = sa + da * (1 - sa)
        guard oa > 0 else { return }
        func ch(_ s: UInt8, _ t: UInt8) -> UInt8 {
            UInt8(max(0, min(255, (Double(s) * sa + Double(t) * da * (1 - sa)) / oa)))
        }
        pixels[i] = RGBA(ch(c.r, d.r), ch(c.g, d.g), ch(c.b, d.b), UInt8(oa * 255))
    }

    func fill(x: Int, y: Int, w: Int, h: Int, _ c: RGBA) {
        let y0 = max(0, y), y1 = min(height, y + h), x0 = max(0, x), x1 = min(width, x + w)
        guard y0 < y1, x0 < x1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { set(xx, yy, c) }
        }
    }

    func rect(x: Int, y: Int, w: Int, h: Int, _ c: RGBA) {
        fill(x: x, y: y, w: w, h: 1, c)
        fill(x: x, y: y + h - 1, w: w, h: 1, c)
        fill(x: x, y: y, w: 1, h: h, c)
        fill(x: x + w - 1, y: y, w: 1, h: h, c)
    }

    /// Scanline polygon fill sampled at pixel centres (even-odd rule).
    func fillPolygon(_ pts: [CGPoint], _ c: RGBA) {
        guard pts.count >= 3 else { return }
        let minY = max(0, Int(floor(pts.map(\.y).min()!)))
        let maxY = min(height - 1, Int(ceil(pts.map(\.y).max()!)))
        guard minY <= maxY else { return }
        for y in minY...maxY {
            let sy = CGFloat(y) + 0.5
            var xs: [CGFloat] = []
            for i in 0..<pts.count {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                if (a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy) {
                    xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let x0 = max(0, Int((xs[i] - 0.5).rounded(.up)))
                let x1 = min(width - 1, Int((xs[i + 1] - 0.5).rounded(.down)))
                if x0 <= x1 { for x in x0...x1 { set(x, y, c) } }
                i += 2
            }
        }
    }

    /// Bresenham line.
    func line(_ p0: CGPoint, _ p1: CGPoint, _ c: RGBA, thickness: Int = 1) {
        var x0 = Int(p0.x.rounded(.down)), y0 = Int(p0.y.rounded(.down))
        let x1 = Int(p1.x.rounded(.down)), y1 = Int(p1.y.rounded(.down))
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            if thickness <= 1 { set(x0, y0, c) } else {
                fill(x: x0 - thickness / 2, y: y0 - thickness / 2, w: thickness, h: thickness, c)
            }
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    func strokePolygon(_ pts: [CGPoint], _ c: RGBA, thickness: Int = 1) {
        for i in 0..<pts.count { line(pts[i], pts[(i + 1) % pts.count], c, thickness: thickness) }
    }

    /// Filled ellipse centred at (cx, cy) with radii in pixels.
    func fillEllipse(cx: Double, cy: Double, rx: Double, ry: Double, _ c: RGBA) {
        guard rx > 0, ry > 0 else { return }
        for y in Int(floor(cy - ry))...Int(ceil(cy + ry)) {
            for x in Int(floor(cx - rx))...Int(ceil(cx + rx)) {
                let nx = (Double(x) + 0.5 - cx) / rx, ny = (Double(y) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 { set(x, y, c) }
            }
        }
    }

    /// Ring (ellipse outline) of the given pixel thickness.
    func strokeEllipse(cx: Double, cy: Double, rx: Double, ry: Double, thickness: Double, _ c: RGBA,
                       only: ((Double) -> Bool)? = nil) {
        for y in Int(floor(cy - ry - 1))...Int(ceil(cy + ry + 1)) {
            for x in Int(floor(cx - rx - 1))...Int(ceil(cx + rx + 1)) {
                let px = Double(x) + 0.5 - cx, py = Double(y) + 0.5 - cy
                let outer = (px * px) / (rx * rx) + (py * py) / (ry * ry)
                let irx = max(0.1, rx - thickness), iry = max(0.1, ry - thickness)
                let inner = (px * px) / (irx * irx) + (py * py) / (iry * iry)
                if outer <= 1 && inner >= 1 {
                    if let only, !only(atan2(py / ry, px / rx)) { continue }
                    set(x, y, c)
                }
            }
        }
    }

    /// Adds a 1-px outline around every opaque shape (the classic sprite look).
    func addOutline(_ color: RGBA, minAlpha: UInt8 = 200) {
        let solid = pixels.map { $0.a >= minAlpha }
        for y in 0..<height {
            for x in 0..<width where !solid[y * width + x] {
                let n = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                if n.contains(where: { inBounds($0.0, $0.1) && solid[$0.1 * width + $0.0] }) { set(x, y, color) }
            }
        }
    }

    /// Scale2x (EPX): doubles the resolution, rounding off diagonal staircases while keeping
    /// straight edges, flat areas and every colour exactly as drawn — pixel art, a little less chunky.
    func scale2x() -> PixelCanvas {
        let out = PixelCanvas(width: width * 2, height: height * 2)
        func at(_ x: Int, _ y: Int) -> RGBA { self[min(max(x, 0), width - 1), min(max(y, 0), height - 1)] }
        for y in 0..<height {
            for x in 0..<width {
                // y grows upward here: A is the pixel above, D below, C left, B right.
                let p = at(x, y), a = at(x, y + 1), b = at(x + 1, y), c = at(x - 1, y), d = at(x, y - 1)
                out.set(2 * x, 2 * y + 1, c == a && c != d && a != b ? a : p)
                out.set(2 * x + 1, 2 * y + 1, a == b && a != c && b != d ? b : p)
                out.set(2 * x, 2 * y, d == c && d != b && c != a ? c : p)
                out.set(2 * x + 1, 2 * y, b == d && b != a && d != c ? d : p)
            }
        }
        return out
    }

    func draw(_ other: PixelCanvas, x: Int, y: Int) {
        for yy in 0..<other.height {
            for xx in 0..<other.width { set(x + xx, y + yy, other.pixels[yy * other.width + xx]) }
        }
    }

    func makeImage() -> CGImage? {
        // CGImage rows run top-down; ours run bottom-up.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let srcRow = (height - 1 - y) * width
            for x in 0..<width {
                let p = pixels[srcRow + x]
                let a = Double(p.a) / 255
                let o = (y * width + x) * 4
                bytes[o] = UInt8(Double(p.r) * a)
                bytes[o + 1] = UInt8(Double(p.g) * a)
                bytes[o + 2] = UInt8(Double(p.b) * a)
                bytes[o + 3] = p.a
            }
        }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

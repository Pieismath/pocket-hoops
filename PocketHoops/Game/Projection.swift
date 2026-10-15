import CoreGraphics
import Foundation

/// Maps the 3D court onto the reference art's top-down "three-quarter" view: the floor seen from
/// above (depth squashed), height moving things up the screen. Scene units are art pixels.
///
/// The scale factors were measured off the reference art so the physics lines up with its pixels:
/// the drawn rim's 9.5 × 6.5 px radii are the 0.235 m rim seen from above (so a ball that looks
/// centred in the rim *is* centred), the lane's front edge is art row 96, the rim centre is art
/// (100, 49) and the foot of the backboard is art row 58.
struct Projection {
    /// Art pixels per metre across (x), along the lane (y) and upward (z).
    static let kx = 40.4
    static let ky = 6.5 / 0.235
    static let kz = 20.0

    var kx: Double { Projection.kx }
    var ky: Double { Projection.ky }
    var kz: Double { Projection.kz }
    /// Scene position of the world origin (x = 0, y = 0, z = 0).
    var origin: CGPoint

    init(origin: CGPoint) {
        self.origin = origin
    }

    /// The projection for a machine canvas whose bottom-left corner is at `canvasOrigin`.
    static func machine(at canvasOrigin: CGPoint, court: Court = Court(), layout: GIFLayout = .shared) -> Projection {
        // World x = 0 is the machine's centre line (art column 100); the lane's front edge
        // (y = frontY, z = 0) is the top of art row 96.
        let x = canvasOrigin.x + CGFloat(layout.canvasX(ofArtColumn: 100))
        let frontEdge = canvasOrigin.y + CGFloat(layout.canvasY(ofArtRow: 96))
        return Projection(origin: CGPoint(x: x, y: frontEdge - CGFloat(court.frontY * Projection.ky)))
    }

    func project(_ p: Vec3) -> CGPoint {
        CGPoint(x: origin.x + p.x * kx, y: origin.y + p.y * ky + p.z * kz)
    }

    /// Screen y of a world depth/height.
    func sy(_ y: Double, _ z: Double) -> CGFloat { origin.y + y * ky + z * kz }

    /// Horizontal screen pixels per world metre.
    func pixelsPerMetre(at p: Vec3) -> Double { kx }

    /// Sorting key: larger = further from the viewer (deeper down the lane, lower down).
    func depth(_ p: Vec3) -> Double { p.y - p.z * 0.6 }

    /// World x under a screen x (x doesn't depend on depth or height in this view).
    func worldX(screenX: CGFloat) -> Double { Double(screenX - origin.x) / kx }
}

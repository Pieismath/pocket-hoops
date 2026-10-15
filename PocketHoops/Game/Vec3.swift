import Foundation

/// Tiny 3D vector. World axes: x = right, y = forward (toward the hoop), z = up. Units are metres.
struct Vec3: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
    static func += (a: inout Vec3, b: Vec3) { a = a + b }
    static func -= (a: inout Vec3, b: Vec3) { a = a - b }

    func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    var length: Double { sqrt(dot(self)) }
    var normalized: Vec3 { let l = length; return l > 1e-9 ? self * (1 / l) : .zero }
    var horizontalLength: Double { sqrt(x * x + y * y) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

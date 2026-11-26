import Foundation

/// 決まった種から同じ並びの乱数を出す（撮影・テスト・毎日の家が毎回同じになるように）
struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 以上 1 未満
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

/// 部屋の中の点（単位は「床の点」。部屋は幅 360 × 奥行き 560）
struct Vec: Equatable, Hashable, Sendable, Codable {
    var x: Double
    var y: Double

    static let zero = Vec(x: 0, y: 0)

    static func + (a: Vec, b: Vec) -> Vec { Vec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(x: a.x * k, y: a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }

    var normalized: Vec {
        let l = length
        return l < 1e-9 ? .zero : Vec(x: x / l, y: y / l)
    }

    func distance(to o: Vec) -> Double { (self - o).length }
}

/// 長方形（家具・ラグ・ドック）
struct Box: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    var center: Vec { Vec(x: x + w / 2, y: y + h / 2) }

    func contains(_ p: Vec) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }

    func insetBy(_ d: Double) -> Box { Box(x: x + d, y: y + d, w: w - 2 * d, h: h - 2 * d) }

    /// いちばん近い箱の中の点
    func closest(to p: Vec) -> Vec { Vec(x: min(max(p.x, x), maxX), y: min(max(p.y, y), maxY)) }

    func distance(to p: Vec) -> Double { closest(to: p).distance(to: p) }

    /// 左右を入れかえる（部屋の幅 width の中で）
    func mirrored(width: Double) -> Box { Box(x: width - x - w, y: y, w: w, h: h) }
}

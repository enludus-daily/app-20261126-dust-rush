import Foundation

/// ゴミ箱がいっぱいになるたびに 3 つ（Pro は 4 つ）から 1 つ選ぶ強化。1 回の掃除（5 部屋）のあいだ続く
enum Upgrade: String, CaseIterable, Codable, Sendable, Identifiable {
    case sideBrush, speed, battery, suction, eco, bumper, magnet

    var id: String { rawValue }

    var maxLevel: Int {
        switch self {
        case .sideBrush: 4
        case .speed, .battery, .suction, .eco: 3
        case .bumper: 2
        case .magnet: 1
        }
    }

    var name: String {
        switch self {
        case .sideBrush: tr("サイドブラシ", "Side Brush")
        case .speed: tr("速いタイヤ", "Quick Wheels")
        case .battery: tr("大きな電池", "Big Battery")
        case .suction: tr("吸う力", "Suction")
        case .eco: tr("省エネモーター", "Eco Motor")
        case .bumper: tr("ふかふかバンパー", "Soft Bumper")
        case .magnet: tr("磁石", "Magnet")
        }
    }

    var detail: String {
        switch self {
        case .sideBrush: tr("掃除できる幅 +27%", "Cleaning width +27%")
        case .speed: tr("進む速さ +18%", "Move speed +18%")
        case .battery: tr("充電 +20（いま 20 足す）", "Charge +20, refilled now")
        case .suction: tr("吸いこむ輪 +10、毛玉も早く", "Pull range +10, hairballs faster")
        case .eco: tr("充電の減り −15%", "Battery drain −15%")
        case .bumper: tr("毛玉にぶつかっても減りが半分", "Half damage from hairballs")
        case .magnet: tr("落とし物とパンくずを遠くから", "Pulls lost items and crumbs from afar")
        }
    }

    /// 札の絵（RoomCanvas の小さな部品の名前）
    var glyph: String {
        switch self {
        case .sideBrush: "✳︎"
        case .speed: "»"
        case .battery: "▮"
        case .suction: "◎"
        case .eco: "❦"
        case .bumper: "◖"
        case .magnet: "∩"
        }
    }
}

/// 強化を重ねた今のロボの値（決まりの数字はここだけ）
struct RobotStats: Equatable, Sendable {
    var bodyRadius = 15.0
    var brushRadius = 22.0
    var pullRadius = 36.0
    var speed = 66.0
    var maxCharge = 100.0
    /// 動いているとき 1 秒の充電の減り
    var moveDrain = 1.2
    var idleDrain = 0.5
    var hairDamage = 4.0
    var hairSuckTime = 0.5
    var magnetRadius = 0.0

    init() {}

    init(levels: [Upgrade: Int]) {
        func lv(_ u: Upgrade) -> Double { Double(min(levels[u] ?? 0, u.maxLevel)) }
        brushRadius = 22.0 + 6 * lv(.sideBrush)
        speed = 66.0 * (1 + 0.18 * lv(.speed))
        maxCharge = 100 + 20 * lv(.battery)
        pullRadius = 36 + 10 * lv(.suction)
        hairSuckTime = 0.5 * pow(0.7, lv(.suction))
        let eco = pow(0.85, lv(.eco))
        moveDrain = 1.2 * eco
        idleDrain = 0.5 * eco
        hairDamage = 4.0 * pow(0.5, lv(.bumper))
        magnetRadius = lv(.magnet) > 0 ? 120 : 0
    }

    /// 距離 d を進むのにかかる充電
    func cost(distance d: Double) -> Double { d / speed * moveDrain }
}

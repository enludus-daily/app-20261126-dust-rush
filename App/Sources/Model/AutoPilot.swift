import Foundation

/// 自動の運転（決まりのテストとデモで使う）。下から上へ、しまに往復して掃除し、充電が returnAt を切ったらドックへ帰る
struct Mower: Sendable {
    /// この割合（0〜1）を切ったら帰る
    var returnAt: Double
    private(set) var waypoints: [Vec] = []
    private(set) var index = 0
    private var fields: [Int: [Double]] = [:]
    private var stuckClock = 0.0
    private var lastPos = Vec.zero
    /// 強化を選ぶ順（いちばん前の候補を選ぶ）
    var preference: [Upgrade] = [.sideBrush, .speed, .battery, .eco, .suction, .bumper, .magnet]

    init(world: World, returnAt: Double, laneShift: Double = 0) {
        self.returnAt = returnAt
        let gap = world.stats.brushRadius * 2 * 0.85
        var y = RoomPlan.height - 40 - laneShift
        var leftToRight = world.plan.dockX > RoomPlan.width / 2 ? false : true
        while y > 12 {
            let xs = stride(from: 20.0, through: RoomPlan.width - 20, by: 56).map { $0 }
            for x in (leftToRight ? xs : xs.reversed()) { waypoints.append(Vec(x: x, y: y)) }
            leftToRight.toggle()
            y -= gap
        }
    }

    mutating func drive(_ w: inout World, dt: Double) {
        if w.awaitingChoice, let c = w.choices {
            w.choose(preference.first { c.contains($0) } ?? c[0])
            return
        }
        if w.chargeRatio <= returnAt || index >= waypoints.count {
            w.homing = true
            return
        }
        let wp = waypoints[index]
        if w.robot.distance(to: wp) < 12 || stuckClock > 1.5 {
            index += 1
            stuckClock = 0
            return
        }
        if fields[index] == nil { fields = [index: w.grid.field(from: wp)] }
        let field = fields[index]!
        let k = w.grid.nearestPassable(to: w.robot)
        if !field[k].isFinite || field[w.grid.nearestPassable(to: wp)] > 9_000 { index += 1; return }
        // 目的の点のまわりのマスに着いたら次へ
        if field[k] < 10 { index += 1; return }
        w.target = w.grid.step(along: field, from: w.robot) ?? wp
        if w.robot.distance(to: lastPos) < 0.3 * w.stats.speed * dt { stuckClock += dt } else { stuckClock = 0 }
        lastPos = w.robot
    }

    /// 1 部屋を最後まで動かす（テスト用）。結果の世界を返す
    static func run(_ world: World, returnAt: Double, laneShift: Double = 0, dt: Double = 1.0 / 30, limit: Double = 400) -> World {
        var w = world
        var m = Mower(world: w, returnAt: returnAt, laneShift: laneShift)
        while w.phase == .playing && w.time < limit {
            m.drive(&w, dt: dt)
            w.step(dt)
            _ = w.drainEvents()
        }
        return w
    }
}

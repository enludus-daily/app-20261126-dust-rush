import Foundation

enum DustKind: Sendable, Equatable {
    /// ふわふわのほこり（寄ってくる）
    case fluff
    /// パンくず（動かない）
    case crumb
    /// 大きい毛玉（ぶつかると充電が減る。吸うのに時間がかかる）
    case hair
    /// 落とし物（持ってドックに帰ると図鑑に入る）
    case lost
}

struct Dust: Sendable, Equatable {
    var id: Int
    var kind: DustKind
    var pos: Vec
    /// 吸いこまれ中
    var pulled = false
    /// 毛玉を吸う進み（0〜1）
    var suck = 0.0
    var wander = 0.0
    var age = 0.0

    var radius: Double {
        switch kind {
        case .fluff: 5
        case .crumb: 3
        case .hair: 10
        case .lost: 8
        }
    }

    var points: Int {
        switch kind {
        case .fluff, .crumb: 1
        case .hair: 4
        case .lost: 0
        }
    }
}

/// 部屋 1 つぶんの掃除（画面から切り離した決まり。テストはこれを直接動かす）
struct World: Sendable {
    enum Phase: Equatable, Sendable { case playing, docked, dead }

    enum Event: Equatable, Sendable {
        case sucked(DustKind, Vec)
        case hit(Vec)
        case warn(Int)
        case lostAppeared(Vec)
        case lostPicked
        case binFull
        case docked
        case dead
    }

    enum LostState: Equatable, Sendable { case hidden, onFloor, carried }

    static let warnLevels = [30, 15]
    static let starLevels = [0.5, 0.7, 0.85]

    let plan: RoomPlan
    let grid: FloorGrid
    /// ドックからの道のり
    let homeField: [Double]
    private(set) var stats: RobotStats
    private(set) var levels: [Upgrade: Int]

    private(set) var clean: [Bool]
    private(set) var cleanCount = 0
    /// 掃除した所が変わるたびに増える（画面の床の絵を作り直す合図）
    private(set) var maskVersion = 0

    private(set) var robot: Vec
    var target: Vec?
    private(set) var heading = -Double.pi / 2
    private(set) var moving = false
    private(set) var stun = 0.0
    private var hitCooldown = 0.0
    private(set) var charge: Double
    private(set) var dust: [Dust] = []
    private var nextID = 0

    private(set) var bin = 0
    private(set) var binCap = 12
    private(set) var choices: [Upgrade]?
    /// 強化の候補の数（Pro は 4）
    var choiceCount = 3
    /// false：ゴミ箱がいっぱいになっても強化を出さない（テスト用）
    var upgradesEnabled = true
    /// 練習：充電が減らない（Pro）
    var practice = false
    /// ドックへの自動の帰り道
    var homing = false

    private(set) var points = 0
    private(set) var suckedCount = 0
    private(set) var hits = 0
    private(set) var time = 0.0
    private(set) var phase: Phase = .playing
    private(set) var leftDock = false
    private(set) var lost: LostState = .hidden
    private(set) var warned: Set<Int> = []

    private var events: [Event] = []
    private var rng: SeededRNG
    private var lostClock = 0.0
    private var fluffClock = 0.0
    private var hairClock = 0.0
    private let spawnPoints: [Vec]

    init(plan: RoomPlan, levels: [Upgrade: Int] = [:], seed: UInt64 = 1) {
        self.plan = plan
        let g = FloorGrid(plan: plan)
        grid = g
        homeField = g.field(from: plan.dock)
        self.levels = levels
        stats = RobotStats(levels: levels)
        clean = [Bool](repeating: false, count: g.cols * g.rows)
        robot = plan.dock
        charge = stats.maxCharge
        rng = SeededRNG(seed: seed &+ UInt64(plan.number) &* 1_000_003)
        // ほこりは家具のふちと部屋の隅からわく
        var pts: [Vec] = []
        for f in plan.furniture where f.kind != .block {
            let b = f.box.insetBy(-6)
            let n = max(2, Int((b.w + b.h) / 40))
            for s in 0..<n {
                let t = (Double(s) + 0.5) / Double(n)
                pts += [Vec(x: b.minX + b.w * t, y: b.minY), Vec(x: b.minX + b.w * t, y: b.maxY),
                        Vec(x: b.minX, y: b.minY + b.h * t), Vec(x: b.maxX, y: b.minY + b.h * t)]
            }
        }
        pts += [Vec(x: 10, y: 10), Vec(x: RoomPlan.width - 10, y: 10), Vec(x: 10, y: RoomPlan.height * 0.6), Vec(x: RoomPlan.width - 10, y: RoomPlan.height * 0.6)]
        let dock = plan.dock
        spawnPoints = pts.filter { p in
            p.x > 6 && p.x < RoomPlan.width - 6 && p.y > 6 && p.y < RoomPlan.height - 6
                && !plan.obstacles.contains { $0.contains(p) } && p.distance(to: dock) > 120
        }
        seedDust()
    }

    // MARK: 読むだけの値

    var cleanliness: Double { grid.floorCount == 0 ? 0 : Double(cleanCount) / Double(grid.floorCount) }
    var chargeRatio: Double { charge / stats.maxCharge }
    var chargePercent: Int { Int((chargeRatio * 100).rounded(.up)) }
    var binRatio: Double { min(1, Double(bin) / Double(binCap)) }
    var upgradeCount: Int { levels.values.reduce(0, +) }
    var stars: Int { World.stars(for: cleanliness) }
    var awaitingChoice: Bool { choices != nil }
    var lostItem: LostItem { LostItem.all[plan.lostItem % LostItem.all.count] }
    var lostPosition: Vec? { dust.first { $0.kind == .lost }?.pos }

    static func stars(for cleanliness: Double) -> Int { starLevels.filter { cleanliness >= $0 - 1e-9 }.count }

    /// 今いる所からドックへ帰るのにかかる充電（道のり ÷ 速さ × 減り）
    var homeCost: Double {
        let d = homeField[grid.nearestPassable(to: robot)]
        return d.isFinite ? stats.cost(distance: d) : 0
    }

    /// たまったできごとを受け取って空にする（音・振動・知らせ）
    mutating func drainEvents() -> [Event] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    func isClean(_ k: Int) -> Bool { clean[k] }

    // MARK: はじめのほこり

    private mutating func seedDust() {
        // パンくずの山 5 つ
        for _ in 0..<5 {
            guard let c = randomFloorPoint(minDockDistance: 140) else { continue }
            for _ in 0..<6 {
                let p = c + Vec(x: rng.range(-18, 18), y: rng.range(-18, 18))
                if canHold(p) { add(.crumb, at: p) }
            }
        }
        for _ in 0..<10 { spawn(.fluff) }
    }

    private func canHold(_ p: Vec) -> Bool {
        p.x > 6 && p.y > 6 && p.x < RoomPlan.width - 6 && p.y < RoomPlan.height - 6 && !plan.obstacles.contains { $0.contains(p) }
    }

    private mutating func randomFloorPoint(minDockDistance: Double) -> Vec? {
        for _ in 0..<60 {
            let k = rng.int(grid.passable.count)
            guard grid.passable[k] else { continue }
            let p = grid.center(k)
            if p.distance(to: plan.dock) >= minDockDistance { return p }
        }
        return nil
    }

    private mutating func add(_ kind: DustKind, at p: Vec) {
        nextID += 1
        dust.append(Dust(id: nextID, kind: kind, pos: p, wander: rng.range(0, 2 * .pi)))
    }

    private mutating func spawn(_ kind: DustKind) {
        guard !spawnPoints.isEmpty else { return }
        for _ in 0..<6 {
            let p = spawnPoints[rng.int(spawnPoints.count)] + Vec(x: rng.range(-4, 4), y: rng.range(-4, 4))
            if kind == .hair && p.distance(to: robot) < 120 { continue }
            if canHold(p) { add(kind, at: p); return }
        }
    }

    // MARK: 操作

    mutating func choose(_ upgrade: Upgrade) {
        guard let c = choices, c.contains(upgrade) else { return }
        let before = stats.maxCharge
        levels[upgrade, default: 0] += 1
        stats = RobotStats(levels: levels)
        if upgrade == .battery { charge = min(stats.maxCharge, charge + (stats.maxCharge - before)) }
        bin -= binCap
        binCap += 6
        choices = nil
    }

    /// テスト・デモ用：決まった強化を持たせる
    mutating func setLevels(_ l: [Upgrade: Int]) {
        levels = l
        stats = RobotStats(levels: l)
        charge = stats.maxCharge
    }

    /// 撮影・デモ用：掃除した所を決まった形で塗る
    mutating func paint(_ path: [Vec], radius: Double) {
        for p in path { cleanAround(p, radius: radius) }
    }

    /// 撮影用：その場に置く
    mutating func place(robotAt p: Vec, charge c: Double? = nil, bin b: Int? = nil) {
        robot = p
        if let c { charge = c }
        if let b { bin = b }
        leftDock = true
    }

    /// 撮影用：落とし物をすぐ出す
    mutating func revealLost(at p: Vec) {
        guard lost == .hidden else { return }
        lost = .onFloor
        add(.lost, at: p)
    }

    /// 撮影用：毛玉やほこりを置く
    mutating func drop(_ kind: DustKind, at p: Vec) { add(kind, at: p) }

    mutating func forceChoices(_ c: [Upgrade]) { choices = c }

    // MARK: 1 こま進める

    mutating func step(_ dt: Double) {
        guard phase == .playing, choices == nil else { return }
        time += dt
        moveRobot(dt)
        drain(dt)
        updateDust(dt)
        spawnOverTime(dt)
        cleanAround(robot, radius: stats.brushRadius)
        checkLost()
        checkBin()
        checkEnd()
    }

    private mutating func moveRobot(_ dt: Double) {
        hitCooldown = max(0, hitCooldown - dt)
        if stun > 0 { stun -= dt; moving = false; return }
        if homing, let next = grid.step(along: homeField, from: robot) {
            target = robot.distance(to: plan.dock) < 30 ? plan.dock : next
        }
        guard let t = target else { moving = false; return }
        let delta = t - robot
        let d = delta.length
        if d < 1.5 { moving = false; if !homing { target = nil }; return }
        let dir = delta.normalized
        let stepLen = min(d, stats.speed * dt)
        var p = robot + dir * stepLen
        // 家具と壁で止まる（めりこんだ分を押し返す）
        let r = stats.bodyRadius
        for _ in 0..<2 {
            for b in plan.obstacles {
                let c = b.closest(to: p)
                let off = p - c
                let dist = off.length
                if dist < r {
                    if dist < 1e-6 {
                        p = p - dir * (r - dist)
                    } else {
                        p = c + off.normalized * r
                    }
                }
            }
            p.x = min(max(p.x, r), RoomPlan.width - r)
            p.y = min(max(p.y, r), RoomPlan.height - r)
        }
        let moved = p.distance(to: robot)
        moving = moved > stats.speed * dt * 0.15
        // 少しずつ向きを変える（見た目）
        let want = atan2(dir.y, dir.x)
        var diff = want - heading
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        heading += diff * min(1, dt * 10)
        robot = p
        if !leftDock && robot.distance(to: plan.dock) > 50 { leftDock = true }
    }

    private mutating func drain(_ dt: Double) {
        guard !practice else { return }
        // ドックに乗っているあいだ（出発前）は減らない
        if !leftDock && robot.distance(to: plan.dock) < 30 { return }
        charge -= (moving ? stats.moveDrain : stats.idleDrain) * dt
        for level in World.warnLevels where !warned.contains(level) && chargeRatio * 100 <= Double(level) {
            warned.insert(level)
            events.append(.warn(level))
        }
    }

    private mutating func updateDust(_ dt: Double) {
        let r = stats.bodyRadius
        var eaten: [Int] = []
        for i in dust.indices {
            var d = dust[i]
            d.age += dt
            let toRobot = robot - d.pos
            let dist = toRobot.length
            let pull = (d.kind == .lost || d.kind == .crumb) ? max(stats.pullRadius, stats.magnetRadius) : stats.pullRadius
            if d.kind == .hair && !d.pulled {
                if dist < pull { d.suck += dt / stats.hairSuckTime }
                if d.suck >= 1 { d.pulled = true }
                // 吸いきる前にぶつかると充電が減って、はじかれる
                if !d.pulled && dist < r + d.radius && hitCooldown <= 0 {
                    hitCooldown = 0.6
                    hits += 1
                    if !practice { charge -= stats.hairDamage }
                    if (levels[.bumper] ?? 0) == 0 { stun = 0.25 }
                    d.pos = d.pos - toRobot.normalized * 34
                    d.pos = clampDust(d.pos)
                    events.append(.hit(robot))
                } else if dist < 160 && dist > pull {
                    let before = grid.index(of: d.pos)
                    d.pos = clampDust(d.pos + toRobot.normalized * (12 * dt))
                    let after = grid.index(of: d.pos)
                    if after != before && clean[after] { clean[after] = false; cleanCount -= 1; maskVersion &+= 1 }
                }
            } else if d.pulled || dist < pull {
                d.pulled = true
                d.pos = d.pos + toRobot.normalized * min(dist, 190 * dt)
                if d.pos.distance(to: robot) < r * 0.8 { eaten.append(i) }
            } else if d.kind == .fluff {
                if dist < 150 {
                    d.pos = clampDust(d.pos + toRobot.normalized * (13 * dt))
                } else {
                    d.wander += rng.range(-1.5, 1.5) * dt
                    d.pos = clampDust(d.pos + Vec(x: cos(d.wander), y: sin(d.wander)) * (8 * dt))
                }
            }
            dust[i] = d
        }
        for i in eaten.reversed() {
            let d = dust.remove(at: i)
            if d.kind == .lost {
                lost = .carried
                events.append(.lostPicked)
            } else {
                points += d.points
                bin += d.points
                suckedCount += 1
                events.append(.sucked(d.kind, d.pos))
            }
        }
    }

    private func clampDust(_ p: Vec) -> Vec {
        var q = Vec(x: min(max(p.x, 6), RoomPlan.width - 6), y: min(max(p.y, 6), RoomPlan.height - 6))
        for b in plan.obstacles where b.contains(q) {
            // 家具の中に入ったら、いちばん近いふちへ出す
            let options = [Vec(x: b.minX - 1, y: q.y), Vec(x: b.maxX + 1, y: q.y), Vec(x: q.x, y: b.minY - 1), Vec(x: q.x, y: b.maxY + 1)]
            q = options.min { $0.distance(to: q) < $1.distance(to: q) } ?? q
        }
        return q
    }

    private mutating func spawnOverTime(_ dt: Double) {
        fluffClock += plan.fluffRate * dt
        while fluffClock >= 1 {
            fluffClock -= 1
            if dust.filter({ $0.kind == .fluff }).count < 90 { spawn(.fluff) }
        }
        hairClock += dt
        if hairClock >= plan.hairEvery {
            hairClock = 0
            if dust.filter({ $0.kind == .hair }).count < 8 { spawn(.hair) }
        }
    }

    private mutating func cleanAround(_ p: Vec, radius: Double) {
        let c = FloorGrid.cell
        let i0 = max(0, Int((p.x - radius) / c)), i1 = min(grid.cols - 1, Int((p.x + radius) / c))
        let j0 = max(0, Int((p.y - radius) / c)), j1 = min(grid.rows - 1, Int((p.y + radius) / c))
        guard i0 <= i1, j0 <= j1 else { return }
        let r2 = radius * radius
        var changed = false
        for j in j0...j1 {
            for i in i0...i1 {
                let k = j * grid.cols + i
                guard grid.floor[k], !clean[k] else { continue }
                let dx = (Double(i) + 0.5) * c - p.x, dy = (Double(j) + 0.5) * c - p.y
                if dx * dx + dy * dy <= r2 { clean[k] = true; cleanCount += 1; changed = true }
            }
        }
        if changed { maskVersion &+= 1 }
    }

    /// 充電が 6 割を切ったら、取りにいけばぎりぎりになる所ができたときに、落とし物が出る。今いる所から取りにいってドックへ帰ると、残りが 0〜15% になる所に置く（惜しい）
    private mutating func checkLost() {
        guard lost == .hidden, !practice, chargeRatio <= 0.6, chargeRatio > 0.12, time >= lostClock else { return }
        lostClock = time + 1
        guard let spot = World.lostSpot(grid: grid, homeField: homeField, from: robot, charge: charge, stats: stats) else { return }
        lost = .onFloor
        add(.lost, at: spot)
        events.append(.lostAppeared(spot))
    }

    /// 落とし物を置く所：取りにいって帰ったときの残りが 7% にいちばん近い（2〜13% の）床。壁ぎわを選ぶ
    static func lostSpot(grid: FloorGrid, homeField: [Double], from p: Vec, charge: Double, stats: RobotStats) -> Vec? {
        let there = grid.field(from: p)
        var best: (Int, Double)?
        for k in 0..<there.count where grid.passable[k] && there[k].isFinite && homeField[k].isFinite {
            let c = grid.center(k)
            // 壁ぎわ・家具のそば（入れないマスがとなりにある）
            let i = k % grid.cols, j = k / grid.cols
            let nearEdge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { di, dj in
                let ni = i + di, nj = j + dj
                return ni < 0 || nj < 0 || ni >= grid.cols || nj >= grid.rows || !grid.passable[nj * grid.cols + ni]
            }
            guard nearEdge, c.distance(to: p) > 60 else { continue }
            let left = (charge - stats.cost(distance: there[k] + homeField[k])) / stats.maxCharge * 100
            guard left >= 2, left <= 13 else { continue }
            let score = abs(left - 7)
            if best == nil || score < best!.1 { best = (k, score) }
        }
        return best.map { grid.center($0.0) }
    }

    private mutating func checkBin() {
        guard upgradesEnabled, choices == nil, bin >= binCap else { return }
        let open = Upgrade.allCases.filter { (levels[$0] ?? 0) < $0.maxLevel }
        guard !open.isEmpty else { return }
        var pool = open
        var picked: [Upgrade] = []
        while picked.count < min(choiceCount, open.count) {
            let k = rng.int(pool.count)
            picked.append(pool.remove(at: k))
        }
        choices = picked
        homing = false
        events.append(.binFull)
    }

    private mutating func checkEnd() {
        // 通りかかっただけでは終わらない：帰る途中か、ドックで止まるつもりのときだけ
        let wantsDock = homing || target == nil
        if leftDock && wantsDock && robot.distance(to: plan.dock) < 14 {
            phase = .docked
            moving = false
            if lost == .carried { points += 15 }
            events.append(.docked)
        } else if charge <= 0 {
            charge = 0
            phase = .dead
            moving = false
            events.append(.dead)
        }
    }
}

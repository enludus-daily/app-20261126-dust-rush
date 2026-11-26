import Foundation

/// 床のマス目（8 点ごと）。掃除した所の記録と、ドックへの帰り道に使う
struct FloorGrid: Sendable {
    static let cell = 8.0
    let cols: Int
    let rows: Int
    /// ロボの中心が入れるマス
    let passable: [Bool]
    /// 掃除できる床のマス（家具の下ではない・ロボが届く）
    let floor: [Bool]
    let floorCount: Int

    init(plan: RoomPlan, bodyRadius: Double = 15) {
        let c = Int(RoomPlan.width / FloorGrid.cell), r = Int(RoomPlan.height / FloorGrid.cell)
        cols = c
        rows = r
        var pass = [Bool](repeating: false, count: c * r)
        var under = [Bool](repeating: false, count: c * r)
        let obstacles = plan.obstacles
        for j in 0..<r {
            for i in 0..<c {
                let p = Vec(x: (Double(i) + 0.5) * FloorGrid.cell, y: (Double(j) + 0.5) * FloorGrid.cell)
                under[j * c + i] = obstacles.contains { $0.contains(p) }
                let inWalls = p.x >= bodyRadius && p.x <= RoomPlan.width - bodyRadius && p.y >= bodyRadius && p.y <= RoomPlan.height - bodyRadius
                pass[j * c + i] = inWalls && !obstacles.contains { $0.distance(to: p) < bodyRadius - 1 }
            }
        }
        // ドックから行けるマスだけを残す（家具に囲まれた小さなすき間は数えない）
        let dockCell = FloorGrid.index(of: plan.dock, cols: c, rows: r)
        var reach = [Bool](repeating: false, count: c * r)
        var queue = [dockCell]
        reach[dockCell] = pass[dockCell]
        var head = 0
        while head < queue.count {
            let k = queue[head]; head += 1
            let i = k % c, j = k / c
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let ni = i + di, nj = j + dj
                guard ni >= 0, nj >= 0, ni < c, nj < r else { continue }
                let n = nj * c + ni
                if pass[n] && !reach[n] { reach[n] = true; queue.append(n) }
            }
        }
        passable = reach
        // 届くマスから brush の半径（最小 18）ぶん内側は掃除できる
        var fl = [Bool](repeating: false, count: c * r)
        let span = 2
        for k in 0..<(c * r) where reach[k] {
            let i = k % c, j = k / c
            for dj in -span...span {
                for di in -span...span {
                    let ni = i + di, nj = j + dj
                    guard ni >= 0, nj >= 0, ni < c, nj < r else { continue }
                    if !under[nj * c + ni] { fl[nj * c + ni] = true }
                }
            }
        }
        floor = fl
        floorCount = fl.filter { $0 }.count
    }

    static func index(of p: Vec, cols: Int, rows: Int) -> Int {
        let i = min(max(Int(p.x / cell), 0), cols - 1)
        let j = min(max(Int(p.y / cell), 0), rows - 1)
        return j * cols + i
    }

    func index(of p: Vec) -> Int { FloorGrid.index(of: p, cols: cols, rows: rows) }

    func center(_ k: Int) -> Vec {
        Vec(x: (Double(k % cols) + 0.5) * FloorGrid.cell, y: (Double(k / cols) + 0.5) * FloorGrid.cell)
    }

    /// いちばん近い入れるマス
    func nearestPassable(to p: Vec) -> Int {
        let k = index(of: p)
        if passable[k] { return k }
        // まず近くの輪（6 マスまで）から探す
        let ci = k % cols, cj = k / cols
        for ring in 1...6 {
            var best = -1, bestD = Double.infinity
            for dj in -ring...ring {
                for di in -ring...ring where abs(di) == ring || abs(dj) == ring {
                    let ni = ci + di, nj = cj + dj
                    guard ni >= 0, nj >= 0, ni < cols, nj < rows else { continue }
                    let n = nj * cols + ni
                    guard passable[n] else { continue }
                    let d = center(n).distance(to: p)
                    if d < bestD { bestD = d; best = n }
                }
            }
            if best >= 0 { return best }
        }
        var best = k, bestD = Double.infinity
        for n in 0..<passable.count where passable[n] {
            let d = center(n).distance(to: p)
            if d < bestD { bestD = d; best = n }
        }
        return best
    }

    /// 点 from からの道のりの長さ（入れないマスは無限大）。8 方向のダイクストラ
    func field(from p: Vec) -> [Double] {
        var dist = [Double](repeating: .infinity, count: cols * rows)
        let start = nearestPassable(to: p)
        dist[start] = center(start).distance(to: p)
        var heap = MinHeap()
        heap.push(start, dist[start])
        let diag = FloorGrid.cell * 2.0.squareRoot()
        while let (k, d) = heap.pop() {
            if d > dist[k] { continue }
            let i = k % cols, j = k / cols
            for dj in -1...1 {
                for di in -1...1 where di != 0 || dj != 0 {
                    let ni = i + di, nj = j + dj
                    guard ni >= 0, nj >= 0, ni < cols, nj < rows else { continue }
                    let n = nj * cols + ni
                    guard passable[n] else { continue }
                    // 角を切らない（斜めは両隣が入れるときだけ）
                    if di != 0 && dj != 0 && !(passable[j * cols + ni] && passable[nj * cols + i]) { continue }
                    let nd = d + (di != 0 && dj != 0 ? diag : FloorGrid.cell)
                    if nd < dist[n] { dist[n] = nd; heap.push(n, nd) }
                }
            }
        }
        return dist
    }

    /// 道のりの場 field の上で、p から 1 歩先に向かう点（数マス先を見て、まっすぐ進めるところまで）
    func step(along field: [Double], from p: Vec, lookahead: Int = 4) -> Vec? {
        var k = nearestPassable(to: p)
        guard field[k].isFinite else { return nil }
        for _ in 0..<lookahead {
            let i = k % cols, j = k / cols
            var best = k
            for dj in -1...1 {
                for di in -1...1 where di != 0 || dj != 0 {
                    let ni = i + di, nj = j + dj
                    guard ni >= 0, nj >= 0, ni < cols, nj < rows else { continue }
                    let n = nj * cols + ni
                    if field[n] < field[best] { best = n }
                }
            }
            if best == k { break }
            k = best
        }
        return center(k)
    }
}

/// ダイクストラ用の小さな二分ヒープ
struct MinHeap {
    private var items: [(Int, Double)] = []

    mutating func push(_ k: Int, _ d: Double) {
        items.append((k, d))
        var c = items.count - 1
        while c > 0 {
            let p = (c - 1) / 2
            if items[p].1 <= items[c].1 { break }
            items.swapAt(p, c)
            c = p
        }
    }

    mutating func pop() -> (Int, Double)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var p = 0
            while true {
                let l = 2 * p + 1, r = l + 1
                var m = p
                if l < items.count && items[l].1 < items[m].1 { m = l }
                if r < items.count && items[r].1 < items[m].1 { m = r }
                if m == p { break }
                items.swapAt(p, m)
                p = m
            }
        }
        return top
    }
}

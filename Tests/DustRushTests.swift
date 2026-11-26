import Foundation
import Testing
@testable import DustRush

/// 自動の運転で 1 部屋を最後まで動かしたときの数字（決まりのテスト。#54 の「うれしい・怖い・惜しい」）
enum Trials {
    static func runs(rooms: ClosedRange<Int>, seeds: Range<Int>, levels: [Upgrade: Int] = [:], returnAt: Double) -> [World] {
        var out: [World] = []
        for r in rooms {
            for s in seeds {
                var w = World(plan: Rooms.numbered(r), levels: levels, seed: UInt64(s))
                w.upgradesEnabled = false
                out.append(Mower.run(w, returnAt: returnAt, laneShift: Double(s % 4) * 8, dt: 1.0 / 20))
            }
        }
        return out
    }

    static func meanClean(_ ws: [World]) -> Double {
        let alive = ws.filter { $0.phase == .docked }
        return alive.map(\.cleanliness).reduce(0, +) / Double(max(1, alive.count))
    }

    static func deadRate(_ ws: [World]) -> Double {
        Double(ws.filter { $0.phase == .dead }.count) / Double(max(1, ws.count))
    }
}

struct TensionTests {
    /// うれしい：強化 0 で部屋のきれいさ平均 50〜60%
    @Test func noUpgradesCleansAboutHalf() {
        let ws = Trials.runs(rooms: 1...30, seeds: 0..<2, returnAt: 0.30)
        let mean = Trials.meanClean(ws)
        #expect(mean >= 0.50 && mean <= 0.60, "強化 0 の平均 \(mean)")
    }

    /// うれしい：強化 4 つ（ブラシ 2・タイヤ 1・電池 1）で 85% 以上
    @Test func fourUpgradesCleanMostOfTheRoom() {
        let ws = Trials.runs(rooms: 1...10, seeds: 0..<3, levels: [.sideBrush: 2, .speed: 1, .battery: 1], returnAt: 0.30)
        let mean = Trials.meanClean(ws)
        #expect(mean >= 0.85, "強化 4 つの平均 \(mean)")
        #expect(Trials.deadRate(ws) == 0)
    }

    /// 怖い：ドックを見ずに吸い続けて残り 11% で帰ると、充電切れが 2〜4 割（2026-11-26 の見積もり 29%）
    @Test func greedyRunsOutOfBatterySometimes() {
        let ws = Trials.runs(rooms: 1...30, seeds: 0..<3, returnAt: 0.11)
        let rate = Trials.deadRate(ws)
        #expect(rate >= 0.2 && rate <= 0.4, "充電切れの割合 \(rate)")
    }

    /// 怖い：残り 30% で帰れば、一度も充電切れにならない
    @Test func returningAtThirtyPercentIsSafe() {
        let ws = Trials.runs(rooms: 1...30, seeds: 0..<3, returnAt: 0.30)
        #expect(Trials.deadRate(ws) == 0)
    }

    /// 惜しい：落とし物は、取りにいって帰ると残りが 2〜13% の所に出る。どの部屋でも出る
    @Test func lostItemAppearsAtATemptingSpot() {
        for r in 1...30 {
            var w = World(plan: Rooms.numbered(r), seed: 1)
            w.upgradesEnabled = false
            var m = Mower(world: w, returnAt: 0)
            var spotLeft: Double?
            let dt = 1.0 / 20
            while w.phase == .playing && w.time < 200 && spotLeft == nil {
                m.drive(&w, dt: dt)
                w.step(dt)
                for e in w.drainEvents() {
                    if case .lostAppeared(let p) = e {
                        let there = w.grid.field(from: w.robot)[w.grid.nearestPassable(to: p)]
                        let back = w.homeField[w.grid.nearestPassable(to: p)]
                        spotLeft = (w.charge - w.stats.cost(distance: there + back)) / w.stats.maxCharge * 100
                    }
                }
            }
            #expect(spotLeft != nil, "部屋 \(r) で落とし物が出ない")
            if let left = spotLeft { #expect(left >= 0 && left <= 15, "部屋 \(r) の残り \(left)") }
        }
    }

    /// 惜しい：取りにいって帰った人の残りは 0〜15%（ぎりぎり）
    @Test func fetchingTheLostItemLeavesLittleCharge() {
        var survivors: [Double] = []
        for r in 1...10 {
            var w = World(plan: Rooms.numbered(r), seed: 2)
            w.upgradesEnabled = false
            var m = Mower(world: w, returnAt: 0)
            var fetching = false
            var field: [Double]?
            let dt = 1.0 / 20
            while w.phase == .playing && w.time < 300 {
                if !fetching { m.drive(&w, dt: dt) }
                w.step(dt)
                for e in w.drainEvents() { if case .lostAppeared(let p) = e { fetching = true; field = w.grid.field(from: p) } }
                if fetching {
                    if w.lost == .onFloor, let f = field { w.target = w.grid.step(along: f, from: w.robot) }
                    else if w.lost == .carried { w.homing = true }
                }
            }
            if w.phase == .docked { survivors.append(w.chargeRatio * 100) }
        }
        #expect(survivors.count >= 4, "持ち帰れた部屋 \(survivors.count)")
        #expect(survivors.allSatisfy { $0 <= 16 }, "残り \(survivors)")
    }
}

struct WorldTests {
    @Test func startsAtTheDockWithFullCharge() {
        let w = World(plan: Rooms.numbered(1))
        #expect(w.robot == w.plan.dock)
        #expect(w.chargePercent == 100)
        #expect(w.cleanliness == 0)
        #expect(w.phase == .playing)
    }

    @Test func drivingCleansTheFloorAndDrainsCharge() {
        var w = World(plan: Rooms.numbered(1))
        w.target = Vec(x: w.plan.dockX, y: 300)
        for _ in 0..<120 { w.step(1.0 / 60) }
        #expect(w.cleanliness > 0.02)
        #expect(w.charge < 100)
        #expect(w.robot.y < w.plan.dock.y - 60)
    }

    @Test func passingTheDockDoesNotEndTheRoom() {
        var w = World(plan: Rooms.numbered(1))
        w.target = Vec(x: w.plan.dockX, y: 400)
        for _ in 0..<180 { w.step(1.0 / 60) }
        // ドックの上を通りすぎて反対へ
        w.target = Vec(x: max(30, w.plan.dockX - 150), y: w.plan.dock.y)
        for _ in 0..<300 { w.step(1.0 / 60) }
        #expect(w.phase == .playing)
    }

    @Test func homingReturnsToTheDock() {
        var w = World(plan: Rooms.numbered(4))
        w.upgradesEnabled = false
        w.target = Vec(x: 60, y: 60)
        for _ in 0..<600 { w.step(1.0 / 60) }
        w.homing = true
        for _ in 0..<1800 where w.phase == .playing { w.step(1.0 / 60) }
        #expect(w.phase == .docked)
    }

    @Test func runningOutOfChargeEndsTheRun() {
        var w = World(plan: Rooms.numbered(1))
        w.upgradesEnabled = false
        w.place(robotAt: Vec(x: 60, y: 60), charge: 0.5)
        w.target = Vec(x: 300, y: 60)
        for _ in 0..<120 { w.step(1.0 / 60) }
        #expect(w.phase == .dead)
        #expect(w.drainEvents().contains(.dead))
    }

    @Test func practiceNeverDrains() {
        var w = World(plan: Rooms.numbered(1))
        w.practice = true
        w.target = Vec(x: 60, y: 60)
        for _ in 0..<600 { w.step(1.0 / 60) }
        #expect(w.charge == w.stats.maxCharge)
    }

    @Test func warningsComeAtThirtyAndFifteen() {
        var w = World(plan: Rooms.numbered(1))
        w.upgradesEnabled = false
        w.place(robotAt: Vec(x: 180, y: 300), charge: 31)
        var warns: [Int] = []
        for _ in 0..<2000 where w.phase == .playing {
            w.target = Vec(x: w.robot.x < 100 ? 300 : 40, y: 300)
            w.step(1.0 / 60)
            for e in w.drainEvents() { if case .warn(let l) = e { warns.append(l) } }
        }
        #expect(warns == [30, 15])
    }

    @Test func starsFollowCleanliness() {
        #expect(World.stars(for: 0.49) == 0)
        #expect(World.stars(for: 0.5) == 1)
        #expect(World.stars(for: 0.7) == 2)
        #expect(World.stars(for: 0.85) == 3)
    }
}

struct UpgradeTests {
    @Test func fullBinOffersThreeDifferentChoices() {
        var w = World(plan: Rooms.numbered(1))
        var m = Mower(world: w, returnAt: 0.3)
        m.preference = []
        for _ in 0..<6000 where !w.awaitingChoice && w.phase == .playing {
            m.drive(&w, dt: 1.0 / 30)
            w.step(1.0 / 30)
        }
        #expect(w.choices?.count == 3)
        #expect(Set(w.choices ?? []).count == 3)
    }

    @Test func proGetsFourChoices() {
        var w = World(plan: Rooms.numbered(1))
        w.choiceCount = 4
        var m = Mower(world: w, returnAt: 0.3)
        for _ in 0..<6000 where !w.awaitingChoice && w.phase == .playing {
            m.drive(&w, dt: 1.0 / 30)
            w.step(1.0 / 30)
        }
        #expect(w.choices?.count == 4)
    }

    @Test func choosingBatteryRefills() {
        var w = World(plan: Rooms.numbered(1))
        w.place(robotAt: Vec(x: 180, y: 300), charge: 50)
        w.forceChoices([.battery, .speed, .eco])
        w.choose(.battery)
        #expect(w.stats.maxCharge == 120)
        #expect(w.charge == 70)
        #expect(w.choices == nil)
    }

    @Test func statsGrowWithLevels() {
        let base = RobotStats(levels: [:])
        let up = RobotStats(levels: [.sideBrush: 2, .speed: 1, .eco: 1, .bumper: 1, .magnet: 1])
        #expect(up.brushRadius > base.brushRadius)
        #expect(up.speed > base.speed)
        #expect(up.moveDrain < base.moveDrain)
        #expect(up.hairDamage == base.hairDamage / 2)
        #expect(up.magnetRadius > 0)
        // 上限より上は増えない
        #expect(RobotStats(levels: [.magnet: 5]).magnetRadius == RobotStats(levels: [.magnet: 1]).magnetRadius)
    }
}

struct RoomTests {
    @Test func thirtyRoomsAllReachable() {
        #expect(Rooms.all.count == 30)
        #expect(Rooms.courseCount == 6)
        for plan in Rooms.all {
            let g = FloorGrid(plan: plan)
            #expect(g.floorCount > 1500, "部屋 \(plan.number) の床 \(g.floorCount)")
            #expect(g.passable[g.index(of: plan.dock)], "部屋 \(plan.number) のドック")
        }
    }

    @Test func toysAndPetsChangeTheRoom() {
        #expect(Rooms.numbered(11).furniture.contains { $0.kind == .block })
        #expect(Rooms.numbered(21).furniture.contains { $0.kind == .petbed })
        #expect(Rooms.numbered(21).hairEvery < Rooms.numbered(1).hairEvery)
    }

    @Test func dailyHouseIsTheSameAllDayAndChangesTomorrow() {
        let a = Rooms.daily("2026-11-26"), b = Rooms.daily("2026-11-26"), c = Rooms.daily("2026-11-27")
        #expect(a == b)
        #expect(a != c)
        #expect(a.count == 5)
        #expect(Set(a.map(\.titleEN)).count == 5)
    }

    @Test func lostItemsHaveBothLanguages() {
        #expect(LostItem.all.count == 30)
        #expect(Set(LostItem.all.map(\.id)) == Set(0..<30))
        #expect(LostItem.all.allSatisfy { !$0.nameEN.isEmpty && !$0.noteEN.isEmpty })
    }
}

struct RecordTests {
    let room = Rooms.numbered(2)

    @Test func keepsTheBestStarsAndFoundItems() {
        var s = SaveData()
        s.record(RoomOutcome(cleanliness: 0.9, stars: 3, points: 40, foundItem: 4, docked: true), room: room, daily: false)
        s.record(RoomOutcome(cleanliness: 0.6, stars: 1, points: 20, foundItem: nil, docked: true), room: room, daily: false)
        #expect(s.stars[room.id] == 3)
        #expect(s.found == [4])
        #expect(s.totalDust == 60)
        #expect(s.roomsCleaned == 2)
    }

    @Test func deadRoomGivesNoItem() {
        var s = SaveData()
        s.record(RoomOutcome(cleanliness: 0.7, stars: 0, points: 30, foundItem: nil, docked: false), room: room, daily: false)
        #expect(s.found.isEmpty)
        #expect(s.stars[room.id] == nil)
        #expect(s.runsDead == 1)
    }

    @Test func coursesOpenInOrderAndProUnlocksTheRest() {
        var s = SaveData()
        #expect(s.courseOpen(1, isPro: false))
        #expect(!s.courseOpen(2, isPro: false))
        s.finishRun(course: 1, completed: true, score: 100, day: nil, today: "2026-11-26", yesterday: "2026-11-25")
        #expect(s.courseOpen(2, isPro: false))
        s.finishRun(course: 2, completed: true, score: 100, day: nil, today: "2026-11-26", yesterday: "2026-11-25")
        #expect(!s.courseOpen(3, isPro: false))
        #expect(s.courseOpen(3, isPro: true))
        #expect(s.nextCourse(isPro: false) == 1)
    }

    @Test func streakCountsTodayOnly() {
        var s = SaveData()
        s.finishRun(course: nil, completed: false, score: 900, day: "2026-11-25", today: "2026-11-25", yesterday: "2026-11-24")
        s.finishRun(course: nil, completed: true, score: 2000, day: "2026-11-26", today: "2026-11-26", yesterday: "2026-11-25")
        #expect(s.streak == 2)
        // 同じ日の 2 回目は数えない。点はいちばんを残す
        s.finishRun(course: nil, completed: true, score: 1500, day: "2026-11-26", today: "2026-11-26", yesterday: "2026-11-25")
        #expect(s.streak == 2)
        #expect(s.daily["2026-11-26"] == 2000)
        // 過去の家は数えない
        s.finishRun(course: nil, completed: true, score: 3000, day: "2026-11-20", today: "2026-11-26", yesterday: "2026-11-25")
        #expect(s.daily["2026-11-20"] == nil)
        s.refreshStreak(today: "2026-11-29", yesterday: "2026-11-28")
        #expect(s.streak == 0)
        #expect(s.bestStreak == 2)
    }

    @Test func saveRoundTrips() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        var s = SaveData()
        s.found = [1, 2]
        s.skin = .cat
        s.store(defaults)
        #expect(SaveData.load(defaults) == s)
    }

    @Test func shareLineShowsStarsAndDeadRooms() {
        let line = Score.shareLine([
            RoomOutcome(cleanliness: 0.9, stars: 3, points: 1, foundItem: nil, docked: true),
            RoomOutcome(cleanliness: 0.4, stars: 0, points: 1, foundItem: nil, docked: true),
            RoomOutcome(cleanliness: 0.6, stars: 0, points: 1, foundItem: nil, docked: false),
        ])
        #expect(line == "🟩⬜🟥")
        #expect(Score.room(RoomOutcome(cleanliness: 0.8, stars: 2, points: 30, foundItem: nil, docked: true)) == 830)
    }
}

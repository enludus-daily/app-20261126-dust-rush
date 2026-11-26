import Foundation
import Observation
import SwiftUI

enum ActiveSheet: String, Identifiable {
    case result, collection, settings, paywall, days
    var id: String { rawValue }
}

enum Screen: Equatable { case home, play }

/// 1 回の掃除（5 部屋）の種類
enum RunKind: Equatable {
    case course(Int)
    case daily(String)
}

/// 遊ぶ画面に出す数字（毎こま変わる World から、変わったときだけ写す）
struct Hud: Equatable {
    var charge = 100
    var chargeRatio = 1.0
    var homeCost = 0
    var bin = 0.0
    var clean = 0
    var stars = 0
    var choices: [Upgrade]?
    var homing = false
    var lost: World.LostState = .hidden
}

struct Banner: Equatable, Identifiable {
    enum Tint { case info, good, alert }
    let id = UUID()
    var title: String
    var detail: String
    var tint: Tint = .info
}

/// アプリの状態。決まりは World、ここは画面とつなぐ
@MainActor
@Observable
final class AppModel {
    // 保存するもの
    var save: SaveData
    var onboarded: Bool { didSet { if persists { UserDefaults.standard.set(onboarded, forKey: "onboarded") } } }
    var soundOn: Bool { didSet { if persists { UserDefaults.standard.set(soundOn, forKey: "sound") } } }
    var hapticsOn: Bool { didSet { if persists { UserDefaults.standard.set(hapticsOn, forKey: "haptics") } } }
    var practiceOn: Bool { didSet { if persists { UserDefaults.standard.set(practiceOn, forKey: "practice") } } }
    var paywallOffered: Bool { didSet { if persists { UserDefaults.standard.set(paywallOffered, forKey: "paywallOffered") } } }
    @ObservationIgnored let persists: Bool

    // 画面
    var screen: Screen = .home
    var activeSheet: ActiveSheet?
    var banner: Banner?
    var onboardingPage = 0
    var reduceMotion = false
    var paused = false
    /// 撮影：動きを止める
    var still = false
    var now: Date
    let calendar = Calendar.current

    // 1 回の掃除
    private(set) var run: RunKind = .course(1)
    private(set) var rooms: [RoomPlan] = []
    private(set) var roomIndex = 0
    private(set) var outcomes: [RoomOutcome] = []
    /// 部屋が終わったあとの札（星・きれいさ）
    var roomCard: RoomOutcome?
    private(set) var runOver = false
    var hud = Hud()
    /// 描きなおしの合図（毎こま増える）
    private(set) var frame = 0
    @ObservationIgnored private(set) var world: World
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    /// 吸ったときの小さな光（画面の飾り）
    @ObservationIgnored private(set) var puffs: [(Vec, Double, DustKind)] = []
    @ObservationIgnored private(set) var hitFlash = 0.0
    @ObservationIgnored private var suckStreak = 0
    /// デモ：時間を速める・自動で運転する
    @ObservationIgnored var timeScale = 1.0
    @ObservationIgnored var autopilot: Mower?

    // 手応え（振動の引き金）
    var pressTick = 0
    var suckTick = 0
    var upgradeTick = 0
    var hitTick = 0
    var warnTick = 0
    var dockTick = 0
    var deadTick = 0
    var lostTick = 0

    // 課金
    let purchases: PurchaseStore
    var proOverride = false
    var isPro: Bool { proOverride || purchases.entitlements.isPro }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.enludus.daily.019" }
    static var proID: String { ProductID.pro(bundleID: bundleID) }

    init(persists: Bool = true, now: Date = Date()) {
        self.persists = persists
        self.now = now
        let d = UserDefaults.standard
        save = persists ? SaveData.load() : SaveData()
        onboarded = persists ? d.bool(forKey: "onboarded") : false
        soundOn = persists ? (d.object(forKey: "sound") as? Bool ?? true) : true
        hapticsOn = persists ? (d.object(forKey: "haptics") as? Bool ?? true) : true
        practiceOn = persists ? d.bool(forKey: "practice") : false
        paywallOffered = persists ? d.bool(forKey: "paywallOffered") : false
        purchases = PurchaseStore(productIDs: [AppModel.proID], proProductIDs: [AppModel.proID])
        world = World(plan: Rooms.numbered(1))
        save.refreshStreak(today: today, yesterday: yesterday)
    }

    var today: String { Days.key(now, calendar: calendar) }
    var yesterday: String { Days.offset(now, days: -1, calendar: calendar) }
    var dailyRooms: [RoomPlan] { Rooms.daily(today) }
    var dailyDone: Bool { save.daily[today] != nil }
    var room: RoomPlan { world.plan }
    var practiceActive: Bool { isPro && practiceOn }
    var runScore: Int { outcomes.map(Score.room).reduce(0, +) }
    var levels: [Upgrade: Int] { world.levels }
    var isDaily: Bool { if case .daily = run { true } else { false } }

    func courseRooms(_ n: Int) -> [RoomPlan] {
        let start = (n - 1) * Rooms.perCourse + 1
        return (start..<(start + Rooms.perCourse)).map(Rooms.numbered)
    }

    // MARK: 始める・進める

    func startCourse(_ n: Int) {
        guard save.courseOpen(n, isPro: isPro) else {
            if n > 2 && !isPro { activeSheet = .paywall }
            return
        }
        begin(.course(n), rooms: courseRooms(n))
    }

    func startDaily(_ day: String? = nil) {
        let d = day ?? today
        if d != today && !isPro { activeSheet = .paywall; return }
        begin(.daily(d), rooms: Rooms.daily(d))
    }

    private func begin(_ kind: RunKind, rooms: [RoomPlan]) {
        run = kind
        self.rooms = rooms
        outcomes = []
        runOver = false
        roomIndex = 0
        activeSheet = nil
        loadRoom(levels: [:])
        screen = .play
        startLoop()
    }

    private func loadRoom(levels: [Upgrade: Int]) {
        let plan = rooms[roomIndex]
        var w = World(plan: plan, levels: levels, seed: Rooms.seed(of: today + plan.id))
        w.choiceCount = isPro ? 4 : 3
        w.practice = practiceActive
        world = w
        roomCard = nil
        paused = false
        puffs = []
        syncHud()
        frame &+= 1
        showBanner(trf("部屋 %d / %d", "Room %d of %d", roomIndex + 1, rooms.count), plan.title)
    }

    func nextRoom() {
        press()
        guard roomIndex + 1 < rooms.count, !runOver else { finishRun(); return }
        roomIndex += 1
        loadRoom(levels: world.levels)
    }

    func goHome() {
        press()
        stopLoop()
        roomCard = nil
        paused = false
        screen = .home
    }

    // MARK: 操作

    /// 指でなぞった所（部屋の座標）
    func steer(to p: Vec) {
        guard world.phase == .playing, !paused else { return }
        world.homing = false
        world.target = p
    }

    func toggleHome() {
        press()
        world.homing.toggle()
        if world.homing { world.target = nil }
        syncHud()
    }

    func togglePause() {
        press()
        paused.toggle()
    }

    func choose(_ u: Upgrade) {
        world.choose(u)
        upgradeTick += 1
        play(.upgrade)
        syncHud()
    }

    func press() {
        pressTick += 1
        play(.tap)
    }

    // MARK: こま送り

    func startLoop() {
        loop?.cancel()
        guard !still else { return }
        loop = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let t = Date()
                let dt = min(0.05, t.timeIntervalSince(last))
                last = t
                self.tick(dt)
            }
        }
    }

    func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    func tick(_ dt: Double) {
        guard screen == .play, !paused, roomCard == nil, !runOver else { return }
        // 1/60 ごとに進める（決まりのテストと同じ刻み）
        var left = dt * timeScale
        while left > 1e-6 {
            let s = min(1.0 / 60, left)
            if var m = autopilot { m.drive(&world, dt: s); autopilot = m }
            world.step(s)
            left -= s
        }
        puffs = puffs.compactMap { p in p.1 + dt < 0.35 ? (p.0, p.1 + dt, p.2) : nil }
        hitFlash = max(0, hitFlash - dt)
        handle(world.drainEvents())
        syncHud()
        frame &+= 1
    }

    func syncHud() {
        let w = world
        var h = Hud()
        h.charge = w.chargePercent
        h.chargeRatio = w.chargeRatio
        h.homeCost = Int((w.homeCost / w.stats.maxCharge * 100).rounded(.up))
        h.bin = (w.binRatio * 20).rounded() / 20
        h.clean = Int((w.cleanliness * 100).rounded(.down))
        h.stars = w.stars
        h.choices = w.choices
        h.homing = w.homing
        h.lost = w.lost
        if h != hud { hud = h }
    }

    private func handle(_ events: [World.Event]) {
        for e in events {
            switch e {
            case .sucked(let kind, let p):
                puffs.append((p, 0, kind))
                suckStreak += 1
                if suckStreak % 8 == 0 { suckTick += 1 }
                play(.suck(min(suckStreak % 12, 11)))
            case .hit:
                hitFlash = 0.35
                hitTick += 1
                play(.hit)
            case .warn(let level):
                warnTick += 1
                play(.warn)
                showBanner(trf("残り %d%%", "%d%% left", level), tr("ドックの点線が帰り道。早めに帰ろう", "The dotted line leads home. Head back soon."), tint: .alert)
            case .lostAppeared:
                lostTick += 1
                play(.lost)
                let item = world.lostItem
                showBanner(tr("何か落ちてる！", "Something's on the floor!"), trf("%@ %@ — 持ち帰れるかな", "%@ %@ — can you bring it home?", item.emoji, item.name), tint: .good)
            case .lostPicked:
                play(.lost)
                lostTick += 1
            case .binFull:
                upgradeTick += 1
                play(.binFull)
            case .docked:
                dockTick += 1
                play(.dock)
                endRoom(docked: true)
            case .dead:
                deadTick += 1
                play(.dead)
                endRoom(docked: false)
            }
        }
    }

    private func endRoom(docked: Bool) {
        suckStreak = 0
        let w = world
        let o = RoomOutcome(cleanliness: w.cleanliness, stars: docked ? w.stars : 0, points: w.points,
                            foundItem: docked && w.lost == .carried ? w.lostItem.id : nil, docked: docked)
        outcomes.append(o)
        if !practiceActive {
            save.record(o, room: w.plan, daily: isDaily)
            if !docked { runOver = true }
            if persists { save.store() }
        } else if !docked {
            runOver = true
        }
        roomCard = o
    }

    /// 札の「次へ」：最後の部屋か充電切れなら結果へ
    func roomCardNext() {
        if runOver || roomIndex + 1 >= rooms.count { finishRun() } else { nextRoom() }
    }

    private func finishRun() {
        stopLoop()
        let completed = !runOver && outcomes.count == rooms.count
        if !practiceActive {
            var course: Int?
            var day: String?
            switch run {
            case .course(let n): course = n
            case .daily(let d): day = d
            }
            save.finishRun(course: course, completed: completed, score: runScore, day: day, today: today, yesterday: yesterday)
            if persists { save.store() }
        }
        roomCard = nil
        screen = .home
        activeSheet = .result
    }

    /// 結果を閉じたあと：はじめて 3 部屋以上きれいにしたら、一度だけ Pro を見せる
    func resultClosed() {
        guard !isPro, !paywallOffered, save.roomsCleaned >= 3 else { return }
        paywallOffered = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.activeSheet = .paywall
        }
    }

    // MARK: 共有

    var shareText: String {
        let title: String
        switch run {
        case .course(let n): title = trf("コース %d", "Course %d", n)
        case .daily(let d): title = trf("%@ の家", "House of %@", d)
        }
        return trf("すいこみロボ %@\n%@ %d 点\n#すいこみロボ", "Dust Rush %@\n%@ %d pts\n#DustRush", title, Score.shareLine(outcomes), runScore)
    }

    // MARK: 知らせ・音

    func showBanner(_ title: String, _ detail: String, tint: Banner.Tint = .info) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            banner = Banner(title: title, detail: detail, tint: tint)
        }
        bannerTask?.cancel()
        guard !still else { return }
        bannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.banner = nil }
        }
    }

    func play(_ cue: SoundBox.Cue) {
        guard soundOn, !still else { return }
        SoundBox.shared.play(cue)
    }

    func syncPro() {
        if isPro { world.choiceCount = 4 }
    }

    // MARK: 撮影・デモ用

    /// 撮影用：今の部屋を差しかえる
    func stage(_ change: (inout World) -> Void) {
        change(&world)
        syncHud()
        frame &+= 1
    }

    func stageRun(_ kind: RunKind, rooms: [RoomPlan], index: Int = 0, outcomes: [RoomOutcome] = [], levels: [Upgrade: Int] = [:]) {
        run = kind
        self.rooms = rooms
        roomIndex = index
        self.outcomes = outcomes
        runOver = false
        loadRoom(levels: levels)
        screen = .play
    }

    func stageRoomCard(_ o: RoomOutcome) {
        outcomes.append(o)
        roomCard = o
    }

    func stageResult(_ outs: [RoomOutcome], runKind: RunKind, rooms: [RoomPlan]) {
        run = runKind
        self.rooms = rooms
        outcomes = outs
        runOver = outs.contains { !$0.docked }
        screen = .home
        activeSheet = .result
    }

    /// デモ用：自動の運転を 1 こまぶん
    func autoDrive(_ m: inout Mower) {
        m.drive(&world, dt: 1.0 / 60)
    }

    func addPuff(_ p: Vec) { puffs.append((p, 0.1, .fluff)) }
}

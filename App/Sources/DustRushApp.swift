import SwiftUI

@main
struct DustRushApp: App {
    /// アプリ全体で 1 つだけ（App の init は何度も呼ばれることがあるので、ここで作り直さない）
    private let model = Launch.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        ZStack {
            if !model.onboarded {
                OnboardingView().transition(.opacity)
            } else if model.screen == .play {
                PlayView().transition(.opacity)
            } else {
                HomeView().transition(.opacity)
            }
        }
        .environment(model)
        // 昼の部屋の色を自前で描くので、ライトに固定する
        .preferredColorScheme(.light)
        .sheet(item: $model.activeSheet, onDismiss: {
            if model.activeSheet == nil { model.resultClosed() }
        }) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
                .environment(\.locale, Lang.locale)
                .presentationCornerRadius(Theme.radiusL)
                .presentationDetents([.large])
        }
        // 手応えの表（README）：押す・吸う（8 個ごと）・強化・ぶつかる・残りわずか・帰った・充電切れ・落とし物
        .sensoryFeedback(trigger: model.pressTick) { _, _ in model.hapticsOn ? .selection : nil }
        .sensoryFeedback(trigger: model.suckTick) { _, _ in model.hapticsOn ? .impact(weight: .light, intensity: 0.5) : nil }
        .sensoryFeedback(trigger: model.upgradeTick) { _, _ in model.hapticsOn ? .impact(weight: .medium) : nil }
        .sensoryFeedback(trigger: model.hitTick) { _, _ in model.hapticsOn ? .error : nil }
        .sensoryFeedback(trigger: model.warnTick) { _, _ in model.hapticsOn ? .warning : nil }
        .sensoryFeedback(trigger: model.dockTick) { _, _ in model.hapticsOn ? .success : nil }
        .sensoryFeedback(trigger: model.deadTick) { _, _ in model.hapticsOn ? .impact(weight: .heavy) : nil }
        .sensoryFeedback(trigger: model.lostTick) { _, _ in model.hapticsOn ? .impact(flexibility: .rigid, intensity: 0.7) : nil }
        .modifier(WideOverride(on: Launch.scene == "wide"))
        .task { await Launch.run(model) }
        .task { await model.purchases.load(); model.syncPro() }
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, v in model.reduceMotion = v }
        .onChange(of: scenePhase) { _, phase in
            guard !model.still, !Launch.isDemo else { return }
            if phase == .active {
                model.now = Date()
                model.save.refreshStreak(today: model.today, yesterday: model.yesterday)
            } else if model.screen == .play && model.roomCard == nil {
                // 離れたら止める（充電が勝手に減らないように）
                model.paused = true
            }
        }
        .environment(\.locale, Lang.locale)
    }
}

/// 撮影の場面 wide だけ、広い画面の並べ方（size class regular）を強制する（Duo の内側は CI で描かれないため）
struct WideOverride: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.environment(\.horizontalSizeClass, .regular) } else { content }
    }
}

/// 起動の仕方：ふつう・撮影（-screenshotScene <名前>）・デモ（-demo）・UI テスト（-uiTestFresh）。
/// 撮影とデモは見本のデータで動かし、保存されたデータを書き換えない
@MainActor
enum Launch {
    /// 撮る画面の名前。後ろに _ja を付けると日本語で撮る（CI のシミュレータは英語のため）
    static var scene: String? {
        var value = UserDefaults.standard.string(forKey: "screenshotScene") ?? ""
        if value.hasSuffix("_ja") { value = String(value.dropLast(3)) }
        return value.isEmpty || value == "launch" ? nil : value
    }

    static var forcesJapanese: Bool {
        UserDefaults.standard.string(forKey: "screenshotScene")?.hasSuffix("_ja") ?? false
    }

    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var isFreshUITest: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestFresh") }

    static let shared: AppModel = makeModel()

    /// 撮影の日（決まった日にして、今日の家が毎回同じになるように）
    static func stageDate() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 13, minute: 0)) ?? Date()
    }

    static func makeModel() -> AppModel {
        Lang.forcedJapanese = forcesJapanese
        if isFreshUITest {
            let model = AppModel(persists: false, now: stageDate())
            model.soundOn = false
            return model
        }
        guard isDemo || scene != nil else { return AppModel() }
        let model = AppModel(persists: false, now: stageDate())
        model.still = scene != nil
        let name = scene ?? ""
        model.onboarded = !name.hasPrefix("onboarding")
        model.onboardingPage = name == "onboarding2" ? 1 : (name == "onboarding3" ? 2 : 0)
        if name != "empty" && !name.hasPrefix("onboarding") {
            model.save = sampleSave(model)
        }
        return model
    }

    /// 見本：遊んで 4 日目くらい
    static func sampleSave(_ model: AppModel) -> SaveData {
        var s = SaveData()
        for (n, stars) in [(1, 3), (2, 2), (3, 3), (4, 1), (5, 2), (6, 2), (7, 1)] {
            s.stars["room-\(n)"] = stars
            s.bestClean["room-\(n)"] = [0, 55, 74, 88][stars]
        }
        s.coursesCleared = [1]
        s.found = [0, 3, 5, 9, 13, 21]
        s.totalDust = 1_284
        s.roomsCleaned = 12
        s.streak = 3
        s.bestStreak = 5
        s.lastDaily = model.yesterday
        for (i, v) in [2_410, 3_120, 0, 2_870].enumerated() where v > 0 {
            s.daily[Days.offset(model.now, days: -(4 - i), calendar: model.calendar)] = v
        }
        return s
    }

    /// 見本の部屋：自動の運転で seconds 秒だけ掃除したところ
    static func simulate(_ model: AppModel, seconds: Double, returnAt: Double = 0, until: ((World) -> Bool)? = nil) {
        var m = Mower(world: model.world, returnAt: returnAt)
        let dt = 1.0 / 60
        var t = 0.0
        while t < seconds && model.world.phase == .playing {
            if let until, until(model.world) { break }
            if !model.world.awaitingChoice { model.autoDrive(&m) }
            model.stage { $0.step(dt) }
            model.stage { _ = $0.drainEvents() }
            t += dt
        }
    }

    static func run(_ model: AppModel) async {
        if isDemo {
            await Demo.play(model)
            return
        }
        guard let scene else { return }
        if scene.hasPrefix("onboarding") { return }
        let course = model.courseRooms(2)
        switch scene {
        case "play", "wide":
            model.stageRun(.course(2), rooms: course, index: 1, levels: [.sideBrush: 1, .speed: 1])
            simulate(model, seconds: 24, until: { $0.awaitingChoice })
            if model.world.awaitingChoice { model.stage { $0.choose($0.choices![0]) } }
            simulate(model, seconds: 4)
            model.banner = nil
        case "low":
            model.stageRun(.course(1), rooms: model.courseRooms(1), index: 3, levels: [.sideBrush: 1])
            model.stage { $0.upgradesEnabled = false }
            simulate(model, seconds: 200, until: { $0.chargeRatio < 0.2 })
            model.showBanner(trf("残り %d%%", "%d%% left", 15), tr("ドックの点線が帰り道。早めに帰ろう", "The dotted line leads home. Head back soon."), tint: .alert)
        case "upgrade":
            model.stageRun(.course(1), rooms: model.courseRooms(1), index: 0)
            simulate(model, seconds: 120, until: { $0.awaitingChoice })
            model.banner = nil
        case "clear":
            model.stageRun(.course(1), rooms: model.courseRooms(1), index: 2, levels: [.sideBrush: 2, .battery: 1])
            model.stage { $0.upgradesEnabled = false }
            simulate(model, seconds: 200, returnAt: 0.3)
            model.banner = nil
            model.stageRoomCard(RoomOutcome(cleanliness: 0.88, stars: 3, points: 64, foundItem: 9, docked: true))
        case "dead":
            model.stageRun(.course(3), rooms: model.courseRooms(3), index: 3)
            model.stage { $0.upgradesEnabled = false }
            simulate(model, seconds: 200, until: { $0.chargeRatio < 0.03 })
            model.banner = nil
            model.stageRoomCard(RoomOutcome(cleanliness: 0.62, stars: 0, points: 41, foundItem: nil, docked: false))
        case "result":
            model.stageResult([
                RoomOutcome(cleanliness: 0.91, stars: 3, points: 58, foundItem: 13, docked: true),
                RoomOutcome(cleanliness: 0.74, stars: 2, points: 47, foundItem: nil, docked: true),
                RoomOutcome(cleanliness: 0.86, stars: 3, points: 66, foundItem: 21, docked: true),
                RoomOutcome(cleanliness: 0.57, stars: 1, points: 39, foundItem: nil, docked: true),
                RoomOutcome(cleanliness: 0.79, stars: 2, points: 52, foundItem: nil, docked: true),
            ], runKind: .daily(model.today), rooms: model.dailyRooms)
        case "collection": model.activeSheet = .collection
        case "settings": model.activeSheet = .settings
        case "paywall": model.activeSheet = .paywall
        case "days": model.activeSheet = .days
        default: break
        }
    }
}

/// デモの再生（YouTube の録画用。人の操作なしで約 18 秒）
/// 今日の家の 1 部屋目 → 自動で掃除（3 倍速）→ ゴミ箱がいっぱいで強化 → 落とし物 → ドックへ帰る → 星
@MainActor
enum Demo {
    static func play(_ model: AppModel) async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        model.soundOn = true
        model.onboarded = true
        await wait(1.5)
        model.startCourse(1)
        model.timeScale = 3
        model.autopilot = Mower(world: model.world, returnAt: 0.3)
        // 部屋が終わるまで（最長 25 秒）
        for _ in 0..<250 {
            await wait(0.1)
            if model.roomCard != nil { break }
        }
        await wait(3.0)
        model.autopilot = nil
        model.timeScale = 1
    }
}

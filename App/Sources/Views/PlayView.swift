import SwiftUI

/// 遊ぶ画面：上に充電・ゴミ箱・きれいさ、まん中に部屋、下に「止める」「帰る」（画面の下に固定）
/// 広い画面（Duo の内側・size class regular）は、左に部屋、右に強化と充電
struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Theme.wall.ignoresSafeArea()
            if sizeClass == .regular {
                GeometryReader { geo in
                    // 右の板は画面の 4 割まで（狭い画面でも部屋が小さくなりすぎない）
                    let panel = min(320, max(180, geo.size.width * 0.38))
                    HStack(spacing: 16) {
                        RoomStage()
                        VStack(spacing: 12) {
                            HudPanel(wide: true)
                            UpgradeShelf()
                            Spacer(minLength: 0)
                            PlayButtons(stacked: panel < 300)
                        }
                        .frame(width: panel)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    HudPanel(wide: false)
                        .padding(.horizontal, 14)
                    RoomStage()
                        .padding(.horizontal, 6)
                }
                .padding(.top, 4)
                .safeAreaInset(edge: .bottom) {
                    PlayButtons()
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .background(Theme.wall)
                }
            }
            if let choices = model.hud.choices, model.roomCard == nil {
                UpgradePicker(choices: choices)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let card = model.roomCard {
                RoomCardView(outcome: card)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if model.paused && model.roomCard == nil {
                PauseCard()
                    .transition(.opacity)
            }
        }
        .animation(model.reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: model.hud.choices)
        .animation(model.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: model.roomCard)
    }
}

/// 部屋（指でなぞった方へ進む）
struct RoomStage: View {
    @Environment(AppModel.self) private var model
    @State private var mask = MaskCache()
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let map = RoomMap(size: geo.size)
            ZStack(alignment: .top) {
                TimelineView(.animation(minimumInterval: Launch.isFreshUITest ? 1.0 / 20 : 1.0 / 60, paused: model.still || model.paused || model.roomCard != nil || model.hud.choices != nil)) { tl in
                    Canvas { ctx, size in
                        let w = model.world
                        var drawing = RoomDrawing(world: w, time: model.still ? 1.2 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000),
                                                  skin: model.isPro ? model.save.skin : .snow, puffs: model.puffs, hitFlash: model.hitFlash)
                        drawing.mask = mask.image(for: w)
                        drawing.draw(&ctx, size: size)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(trf("%@。きれいさ %d%%、充電 %d%%", "%@. %d%% clean, %d%% charge", model.room.title, model.hud.clean, model.hud.charge))
                .accessibilityIdentifier("room")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !touching { touching = true; model.press() }
                            model.steer(to: map.world(v.location))
                        }
                        .onEnded { _ in touching = false }
                )
                if model.showDriveHint {
                    let p = map.pt(model.room.dock + Vec(x: 0, y: -90))
                    VStack(spacing: 4) {
                        Text(tr("部屋を指でなぞって進もう", "Drag on the floor to drive")).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                        Image(systemName: "arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.mintDeep)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.card.opacity(0.95)))
                    .overlay(Capsule().stroke(Theme.mintDeep.opacity(0.4), lineWidth: 1.5))
                    .position(x: p.x, y: p.y)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
                if let banner = model.banner {
                    BannerView(banner: banner)
                        .padding(.top, map.origin.y + 10)
                        .padding(.horizontal, 24)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        let tint: Color = switch banner.tint {
        case .info: Theme.mintDeep
        case .good: Theme.lavenderDeep
        case .alert: Theme.peachDeep
        }
        VStack(spacing: 2) {
            Text(banner.title).font(Theme.title(17)).foregroundStyle(tint)
            Text(banner.detail).font(Theme.body(13)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.card.opacity(0.96)))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1.5))
        .shadow(color: Theme.ink.opacity(0.12), radius: 10, y: 4)
    }
}

/// 充電の輪・ゴミ箱の帯・きれいさ
struct HudPanel: View {
    @Environment(AppModel.self) private var model
    var wide: Bool

    var body: some View {
        let h = model.hud
        VStack(alignment: .leading, spacing: 8) {
            let titleLayout = wide ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            titleLayout {
                Eyebrow(text: model.isDaily ? trf("今日の家 %d/%d", "TODAY %d/%d", model.roomIndex + 1, model.rooms.count)
                                            : trf("部屋 %d/%d", "ROOM %d/%d", model.roomIndex + 1, model.rooms.count))
                Text(model.room.title).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if model.practiceActive {
                    Text(tr("練習", "Practice")).font(Theme.label(11)).foregroundStyle(Theme.lavenderDeep)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.lavenderSoft))
                }
            }
            if wide {
                // 広い画面の右の板：充電の輪を上に、帯は幅いっぱいに
                ChargeRing(ratio: h.chargeRatio, percent: h.charge, homeCost: h.homeCost)
                BinBar(ratio: h.bin)
                CleanMeter(clean: h.clean)
            } else {
                HStack(spacing: 12) {
                    ChargeRing(ratio: h.chargeRatio, percent: h.charge, homeCost: h.homeCost)
                    VStack(alignment: .leading, spacing: 6) {
                        BinBar(ratio: h.bin)
                        CleanMeter(clean: h.clean)
                    }
                }
            }
        }
        .padding(wide ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ChargeRing: View {
    var ratio: Double
    var percent: Int
    var homeCost: Int

    var body: some View {
        let color = Theme.chargeColor(ratio)
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 6)
                // 帰り道に要る分（うすい印）
                Circle().trim(from: 0, to: min(1, Double(homeCost) / 100))
                    .stroke(Theme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Circle().trim(from: 0, to: max(0, min(1, ratio)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .font(Theme.number(15))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("充電", "Charge")).font(Theme.label(10)).foregroundStyle(Theme.inkSoft)
                Text(trf("帰りに %d%%", "Home %d%%", homeCost)).font(Theme.body(12, weight: .bold))
                    .foregroundStyle(percent - homeCost < 8 ? Theme.peachDeep : Theme.ink)
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

struct BinBar: View {
    var ratio: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(tr("ゴミ箱", "Dust bin")).font(Theme.label(10)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(tr("いっぱいで強化", "Full = upgrade")).font(Theme.label(10)).foregroundStyle(Theme.lavenderDeep)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.lavenderSoft)
                    Capsule().fill(Theme.lavender).frame(width: max(8, g.size.width * ratio))
                }
            }
            .frame(height: 9)
        }
    }
}

struct CleanMeter: View {
    var clean: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(tr("きれいさ", "Clean")).font(Theme.label(10)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text("\(clean)%").font(Theme.number(13)).foregroundStyle(Theme.mintDeep).contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.mintSoft)
                    Capsule().fill(Theme.mint).frame(width: max(8, g.size.width * Double(clean) / 100))
                    // 星の目盛り 50・70・85
                    ForEach(Array(World.starLevels.enumerated()), id: \.offset) { i, level in
                        Text("★").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Double(clean) / 100 >= level ? Color(hex: 0xC99A2E) : Theme.inkSoft.opacity(0.5))
                            .position(x: g.size.width * level, y: 4.5)
                    }
                }
            }
            .frame(height: 9)
        }
    }
}

/// 下に固定するボタン（幅は半分ずつ。0 にならない）
struct PlayButtons: View {
    @Environment(AppModel.self) private var model
    var stacked = false

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { model.togglePause() } label: {
                Label(tr("止める", "Pause"), systemImage: "pause.fill")
            }
            .buttonStyle(SoftButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("main.pause")
            Button { model.toggleHome() } label: {
                Label(model.hud.homing ? tr("掃除にもどる", "Keep cleaning") : tr("ドックへ帰る", "Head home"),
                      systemImage: model.hud.homing ? "sparkles" : "house.fill")
            }
            .buttonStyle(PillButtonStyle(fill: model.hud.homing ? Theme.lavenderDeep : Theme.mintDeep,
                                         edge: model.hud.homing ? Color(hex: 0x4E3F96) : Color(hex: 0x1F6B57)))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("main.home")
        }
    }
}

/// 今の強化（広い画面の右）
struct UpgradeShelf: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: tr("いまの強化", "UPGRADES"))
            let owned = Upgrade.allCases.filter { (model.levels[$0] ?? 0) > 0 }
            if owned.isEmpty {
                Text(tr("ゴミ箱がいっぱいになると、3 つから 1 つ選べます", "Fill the bin to pick 1 of 3 upgrades."))
                    .font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(owned) { u in
                HStack {
                    UpgradeBadge(upgrade: u, size: 30)
                    Text(u.name).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    LevelDots(level: model.levels[u] ?? 0, max: u.maxLevel)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct UpgradeBadge: View {
    var upgrade: Upgrade
    var size: CGFloat
    var body: some View {
        let colors: (Color, Color) = switch upgrade {
        case .sideBrush, .suction, .magnet: (Theme.mintSoft, Theme.mintDeep)
        case .speed, .bumper: (Theme.peachSoft, Theme.peachDeep)
        case .battery, .eco: (Theme.lavenderSoft, Theme.lavenderDeep)
        }
        Text(upgrade.glyph)
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(colors.1)
            .frame(width: size, height: size)
            .background(Circle().fill(colors.0))
            .overlay(Circle().stroke(colors.1.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct LevelDots: View {
    var level: Int
    var max: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max, id: \.self) { i in
                Circle().fill(i < level ? Theme.mintDeep : Theme.line).frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel(trf("レベル %d / %d", "Level %d of %d", level, max))
    }
}

/// ゴミ箱がいっぱい：強化を選ぶ（3 枚の札がせり上がる）
struct UpgradePicker: View {
    @Environment(AppModel.self) private var model
    let choices: [Upgrade]
    @State private var shown = false

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Eyebrow(text: tr("ゴミ箱がいっぱい", "DUST BIN FULL"), color: Theme.lavenderDeep)
                    Text(tr("強化をひとつ選ぶ", "Pick an upgrade")).font(Theme.title(24)).foregroundStyle(Theme.ink)
                }
                ForEach(Array(choices.enumerated()), id: \.element) { i, u in
                    Button { model.choose(u) } label: {
                        HStack(spacing: 14) {
                            UpgradeBadge(upgrade: u, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.name).font(Theme.body(17, weight: .heavy)).foregroundStyle(Theme.ink)
                                Text(u.detail).font(Theme.body(13)).foregroundStyle(Theme.inkSoft).lineLimit(2).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 4)
                            LevelDots(level: model.levels[u] ?? 0, max: u.maxLevel)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("main.upgrade\(i)")
                    .offset(y: shown || model.reduceMotion ? 0 : 60)
                    .opacity(shown || model.reduceMotion ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(Double(i) * 0.07), value: shown)
                }
            }
            .padding(20)
            .frame(maxWidth: 440)
        }
        .onAppear { shown = true }
    }
}

/// 部屋が終わった札：星が 1 つずつ弾む
struct RoomCardView: View {
    @Environment(AppModel.self) private var model
    let outcome: RoomOutcome
    @State private var revealed = 0

    var body: some View {
        let last = model.runOver || model.roomIndex + 1 >= model.rooms.count
        ZStack {
            Theme.ink.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                if outcome.docked {
                    Eyebrow(text: tr("ドックに帰った", "BACK AT THE DOCK"), color: Theme.mintDeep)
                    Text(model.room.title).font(Theme.title(24)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Text("★")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(i < outcome.stars ? Color(hex: 0xE3B23C) : Theme.line)
                                .scaleEffect(i < revealed || model.reduceMotion ? 1 : 0.4)
                                .opacity(i < revealed || model.reduceMotion || i >= outcome.stars ? 1 : 0.3)
                        }
                    }
                    Text(trf("きれいさ %d%%", "%d%% clean", Int((outcome.cleanliness * 100).rounded(.down))))
                        .font(Theme.number(30)).kerning(-1).foregroundStyle(Theme.mintDeep)
                    if let id = outcome.foundItem {
                        let item = LostItem.all[id]
                        HStack(spacing: 10) {
                            Text(item.emoji).font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trf("落とし物「%@」を持ち帰った", "Brought home: %@", item.name)).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                                Text(item.note).font(Theme.body(12)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous).fill(Theme.lavenderSoft))
                    }
                    Text(trf("吸ったほこり %d", "Dust picked up: %d", outcome.points)).font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
                } else {
                    Eyebrow(text: tr("充電切れ！", "OUT OF BATTERY"), color: Theme.peachDeep)
                    Text(tr("ドックまで帰れなかった…", "Didn't make it back to the dock…")).font(Theme.title(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    Text(tr("「帰りに ○%」が充電に近づいたら、帰る合図。点線がドックへの道です。", "When \"Home %\" gets close to your charge, head back. The dotted line shows the way."))
                        .font(Theme.body(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
                Button { model.roomCardNext() } label: {
                    Text(last ? tr("結果を見る", "See results") : tr("次の部屋へ", "Next room"))
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("main.next")
            }
            .padding(22)
            .frame(maxWidth: 420)
            .card()
            .padding(20)
        }
        .task {
            guard outcome.docked, !model.reduceMotion else { revealed = 3; return }
            for i in 0..<outcome.stars {
                try? await Task.sleep(for: .milliseconds(model.still ? 0 : 260))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { revealed = i + 1 }
                model.play(.star)
            }
            revealed = 3
        }
    }
}

struct PauseCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            Theme.ink.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(tr("ひとやすみ", "Paused")).font(Theme.title(24)).foregroundStyle(Theme.ink)
                Text(tr("充電は減りません。", "Your battery won't drain.")).font(Theme.body(14)).foregroundStyle(Theme.inkSoft)
                Button { model.togglePause() } label: { Text(tr("続ける", "Resume")) }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("main.resume")
                Button { model.goHome() } label: { Text(tr("やめてホームへ", "Quit to home")) }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("main.quit")
            }
            .padding(22)
            .frame(maxWidth: 380)
            .card()
            .padding(24)
        }
    }
}

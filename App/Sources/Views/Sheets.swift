import StoreKit
import SwiftUI

struct SheetContent: View {
    let sheet: ActiveSheet
    var body: some View {
        switch sheet {
        case .result: ResultSheet()
        case .collection: CollectionSheet()
        case .settings: SettingsSheet()
        case .paywall: PaywallSheet()
        case .days: DaysSheet()
        }
    }
}

/// シートの見出しと閉じるボタン
struct SheetHeader: View {
    @Environment(AppModel.self) private var model
    var eyebrow: String
    var title: String
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: eyebrow)
                Text(title).font(Theme.title(24)).foregroundStyle(Theme.ink).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer()
            Button { model.press(); model.activeSheet = nil } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.wallDeep))
            }
            .accessibilityLabel(tr("閉じる", "Close"))
            .accessibilityIdentifier("main.close")
        }
    }
}

// MARK: 結果

struct ResultSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let outs = model.outcomes
        let found = outs.compactMap(\.foundItem)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(eyebrow: model.isDaily ? tr("今日の家", "TODAY'S HOUSE") : tr("コースの結果", "COURSE RESULT"),
                            title: model.runOver ? tr("充電切れでおしまい", "Battery ran out") : tr("ぜんぶの部屋がぴかぴか", "Every room sparkles"))
                VStack(spacing: 6) {
                    Text(Score.shareLine(outs)).font(.system(size: 30))
                    Text(trf("%d 点", "%d pts", model.runScore)).font(Theme.number(44)).kerning(-2).foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .card(Theme.mintSoft)
                VStack(spacing: 0) {
                    ForEach(Array(outs.enumerated()), id: \.offset) { i, o in
                        HStack {
                            Text(i < model.rooms.count ? model.rooms[i].title : "").font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            if o.docked {
                                Text(String(repeating: "★", count: o.stars) + String(repeating: "☆", count: 3 - o.stars))
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xC99A2E))
                                Text("\(Int((o.cleanliness * 100).rounded(.down)))%").font(Theme.number(14)).foregroundStyle(Theme.mintDeep).frame(width: 46, alignment: .trailing)
                            } else {
                                Text(tr("充電切れ", "Battery out")).font(Theme.body(13, weight: .bold)).foregroundStyle(Theme.peachDeep)
                            }
                        }
                        .padding(.vertical, 9)
                        if i < outs.count - 1 { Divider().overlay(Theme.line) }
                    }
                }
                .padding(.horizontal, 14)
                .card()
                if !found.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: tr("持ち帰った落とし物", "LOST ITEMS FOUND"), color: Theme.lavenderDeep)
                        ForEach(found, id: \.self) { id in
                            let item = LostItem.all[id]
                            HStack { Text(item.emoji).font(.system(size: 24)); Text(item.name).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink) }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(Theme.lavenderSoft)
                }
                HStack(spacing: 12) {
                    ShareLink(item: model.shareText) {
                        Label(tr("共有", "Share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("main.share")
                    Button { model.press(); model.activeSheet = nil } label: { Text(tr("ホームへ", "Home")) }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityIdentifier("main.resultDone")
                }
            }
            .padding(20)
        }
        .background(Theme.wall)
    }
}

// MARK: 図鑑

struct CollectionSheet: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(eyebrow: trf("落とし物図鑑 %d / %d", "LOST & FOUND %d / %d", model.save.found.count, LostItem.all.count),
                            title: tr("ソファの下から出てきたもの", "Found under the sofa"))
                Text(tr("充電が減ってくると、部屋の隅に落とし物が出ます。取りにいくと帰りはぎりぎり。持ったままドックに帰ると、ここに並びます。",
                        "As your battery runs low, a lost item appears in a far corner. Grabbing it makes the trip home tight. Carry it back to the dock to keep it here."))
                    .font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(LostItem.all) { item in
                        let has = model.save.found.contains(item.id)
                        Button { model.press(); selected = has ? item.id : nil } label: {
                            VStack(spacing: 4) {
                                Text(has ? item.emoji : "?").font(has ? .system(size: 30) : Theme.title(26))
                                    .foregroundStyle(Theme.inkSoft.opacity(0.5))
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(has ? Theme.tags[item.tint] : Theme.wallDeep))
                                Text(has ? item.name : tr("まだ", "Not yet")).font(Theme.body(11, weight: .bold)).foregroundStyle(has ? Theme.ink : Theme.inkSoft)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .card(selected == item.id ? Theme.lavenderSoft : Theme.card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let id = selected {
                    let item = LostItem.all[id]
                    HStack(spacing: 12) {
                        Text(item.emoji).font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(Theme.body(16, weight: .heavy)).foregroundStyle(Theme.ink)
                            Text(item.note).font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(Theme.lavenderSoft)
                }
            }
            .padding(20)
        }
        .background(Theme.wall)
    }
}

// MARK: 過去の家（Pro）

struct DaysSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(eyebrow: tr("毎日の家", "DAILY HOUSES"), title: tr("過去 30 日の家", "The last 30 days"))
                if !model.isPro {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("過去の家は Pro で遊べます。今日の家はいつでも無料です。", "Past houses are part of Pro. Today's house is always free."))
                            .font(Theme.body(14)).foregroundStyle(Theme.ink)
                        Button { model.press(); model.activeSheet = .paywall } label: { Text(tr("Pro を見る", "See Pro")) }
                            .buttonStyle(PillButtonStyle(fill: Theme.lavenderDeep, edge: Color(hex: 0x4E3F96)))
                    }
                    .padding(14)
                    .card(Theme.lavenderSoft)
                }
                VStack(spacing: 0) {
                    ForEach(0..<30, id: \.self) { back in
                        let day = Days.offset(model.now, days: -back, calendar: model.calendar)
                        Button { model.press(); model.startDaily(day) } label: {
                            HStack {
                                Text(back == 0 ? tr("今日", "Today") : day).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                                Text(Rooms.daily(day).first?.title ?? "").font(Theme.body(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                Spacer()
                                if let s = model.save.daily[day] {
                                    Text(trf("%d 点", "%d pts", s)).font(Theme.number(13)).foregroundStyle(Theme.mintDeep)
                                } else if back > 0 && !model.isPro {
                                    Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.line)
                    }
                }
                .padding(.horizontal, 14)
                .card()
            }
            .padding(20)
        }
        .background(Theme.wall)
    }
}

// MARK: 設定

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(eyebrow: tr("設定", "Settings"), title: tr("ロボの調子", "Robot settings"))
                VStack(spacing: 0) {
                    Toggle(tr("効果音", "Sound effects"), isOn: $model.soundOn).padding(.vertical, 8)
                    Divider().overlay(Theme.line)
                    Toggle(tr("振動", "Haptics"), isOn: $model.hapticsOn).padding(.vertical, 8)
                    Divider().overlay(Theme.line)
                    Toggle(isOn: $model.practiceOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("練習モード（Pro）", "Practice mode (Pro)"))
                            Text(tr("充電が減らない。記録には残りません", "Battery never drains. Not recorded.")).font(Theme.body(11)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .disabled(!model.isPro)
                    .padding(.vertical, 8)
                }
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .tint(Theme.mintDeep)
                .padding(.horizontal, 14)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: tr("ロボの色と形", "ROBOT LOOK"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(RobotSkin.allCases) { skin in
                            let locked = skin.isPro && !model.isPro
                            Button {
                                model.press()
                                if locked { model.activeSheet = .paywall } else { model.save.skin = skin; if model.persists { model.save.store() } }
                            } label: {
                                VStack(spacing: 6) {
                                    Canvas { ctx, size in
                                        RobotPreview(skin: skin).draw(&ctx, size: size)
                                    }
                                    .frame(width: 46, height: 46)
                                    Text(skin.name).font(Theme.body(12, weight: .bold)).foregroundStyle(Theme.ink)
                                    if locked { Text("PRO").font(Theme.label(9)).foregroundStyle(Theme.lavenderDeep) }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .card(model.save.skin == skin && !locked ? Theme.mintSoft : Theme.card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Button { model.press(); model.activeSheet = nil; model.onboardingPage = 0; model.onboarded = false } label: {
                        Label(tr("遊び方をもう一度見る", "Show how to play again"), systemImage: "questionmark.circle")
                    }
                    Divider().overlay(Theme.line)
                    if model.isPro {
                        Label(tr("Pro を使っています。ありがとう！", "You have Pro. Thank you!"), systemImage: "checkmark.seal.fill").foregroundStyle(Theme.mintDeep)
                    } else {
                        Button { model.press(); model.activeSheet = .paywall } label: { Label(tr("Pro を見る", "See Pro"), systemImage: "sparkles") }
                    }
                    Divider().overlay(Theme.line)
                    Button { Task { await model.purchases.restore(); model.syncPro() } } label: {
                        Label(tr("購入を復元", "Restore purchases"), systemImage: "arrow.clockwise")
                    }
                }
                .font(Theme.body(15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Text(tr("遊んだ記録は、この iPhone の中だけに残ります。外へ送ったり集めたりしません。",
                        "Your progress stays on this iPhone. Nothing is sent or collected."))
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
        }
        .background(Theme.wall)
    }
}

/// 設定・課金の画面の小さなロボの絵
struct RobotPreview {
    var skin: RobotSkin
    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        var w = World(plan: Rooms.numbered(1))
        w.place(robotAt: Vec(x: 180, y: 280))
        // ロボのまわりだけを大きく描く：部屋の座標で 46 × 46 の窓
        let s = size.width / 46
        let map = RoomMap(size: CGSize(width: 360 * s, height: 560 * s))
        var c = ctx
        c.translateBy(x: -map.pt(Vec(x: 180 - 23, y: 280 - 23)).x, y: -map.pt(Vec(x: 180 - 23, y: 280 - 23)).y)
        var only = RoomDrawing(world: w, time: 1, skin: skin, showPath: false)
        only.drawRobotOnly(&c, size: CGSize(width: 360 * s, height: 560 * s))
    }
}

// MARK: Pro

struct PaywallSheet: View {
    @Environment(AppModel.self) private var model
    @State private var buying = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SheetHeader(eyebrow: "PRO", title: tr("すいこみロボ Pro", "Dust Rush Pro"))
                    Text(tr("1 回買うだけ。広告もサブスクもありません。", "Pay once. No ads, no subscription."))
                        .font(Theme.body(14)).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 12) {
                        feature("🏠", tr("部屋が 10 → 30 に", "30 rooms instead of 10"), tr("おもちゃだらけの家・ねこといぬの家など 4 コース", "4 more courses: toy-filled homes, cats & dogs"))
                        feature("🃏", tr("強化の候補が 4 つに", "4 upgrade choices"), tr("ゴミ箱がいっぱいのとき、選べる札が 1 枚増える", "One more card every time the bin fills"))
                        feature("📅", tr("過去 30 日の毎日の家", "Last 30 days of daily houses"), tr("遊びそびれた日の家も掃除できる", "Catch up on days you missed"))
                        feature("🐱", tr("ロボの色と形 5 種", "5 robot looks"), tr("ミント・ラベンダー・ピーチ・ねこ耳・おむすび", "Mint, lavender, peach, cat ears, rice ball"))
                        feature("🧘", tr("練習モード", "Practice mode"), tr("充電が減らない部屋で、道すじを試せる", "Try routes without the battery draining"))
                    }
                    .padding(16)
                    .card()
                    if let message {
                        Text(message).font(Theme.body(13)).foregroundStyle(Theme.peachDeep)
                    }
                }
                .padding(20)
            }
            VStack(spacing: 8) {
                if model.isPro {
                    Label(tr("Pro を使っています", "Pro is active"), systemImage: "checkmark.seal.fill").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.mintDeep)
                } else if let product = model.purchases.products.first {
                    Button {
                        buying = true
                        Task {
                            let r = await model.purchases.purchase(product)
                            buying = false
                            model.syncPro()
                            switch r {
                            case .purchased: model.activeSheet = nil
                            case .pending: message = tr("承認を待っています。", "Waiting for approval.")
                            case .failed: message = tr("買えませんでした。少し待ってからもう一度どうぞ。", "The purchase didn't go through. Please try again later.")
                            case .cancelled: break
                            }
                        }
                    } label: {
                        Text(buying ? tr("手続き中…", "Processing…") : trf("%@ で Pro にする", "Get Pro for %@", product.displayPrice))
                    }
                    .buttonStyle(PillButtonStyle(fill: Theme.lavenderDeep, edge: Color(hex: 0x4E3F96)))
                    .disabled(buying)
                    .accessibilityIdentifier("main.buy")
                } else {
                    Text(model.purchases.loadState == .loading ? tr("読み込み中…", "Loading…")
                                                                : tr("いまは購入できません。通信を確かめて、あとでもう一度開いてください。", "Purchases aren't available right now. Check your connection and try again later."))
                        .font(Theme.body(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
                Button { Task { await model.purchases.restore(); model.syncPro() } } label: {
                    Text(tr("購入を復元", "Restore purchases")).font(Theme.body(13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Theme.wall)
        }
        .background(Theme.wall)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon).font(.system(size: 22)).frame(width: 40, height: 40).background(Circle().fill(Theme.lavenderSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.body(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

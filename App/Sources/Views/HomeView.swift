import SwiftUI

enum Courses {
    static func name(_ n: Int) -> String {
        switch n {
        case 1: tr("ひとり暮らしの部屋", "Small Apartment")
        case 2: tr("家族の家", "Family House")
        case 3: tr("おもちゃだらけ", "Toys Everywhere")
        case 4: tr("おもちゃだらけ・2", "Toys Everywhere II")
        case 5: tr("ねこといぬの家", "Cats & Dogs")
        default: tr("ねこといぬの家・2", "Cats & Dogs II")
        }
    }

    static func note(_ n: Int) -> String {
        switch n {
        case 1, 2: tr("家具のふちから、ほこりがわく", "Dust bunnies creep out from under the furniture")
        case 3, 4: tr("床のブロックが帰り道をふさぐ", "Toy blocks get in the way home")
        default: tr("大きい毛玉がどんどん来る", "Big hairballs keep rolling in")
        }
    }
}

/// ホーム：今日の家・コース・図鑑。主なボタンは下に固定
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let next = model.save.nextCourse(isPro: model.isPro)
        ZStack {
            HomeBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 14) {
                            DailyCard()
                            VStack(spacing: 14) { CourseList(); ShelfRow() }
                        }
                    } else {
                        DailyCard()
                        CourseList()
                        ShelfRow()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: sizeClass == .regular ? 900 : 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button { model.press(); model.startCourse(next) } label: {
                    Label(model.save.coursesCleared.contains(next) ? trf("コース %d をもう一度", "Replay course %d", next)
                                                                    : trf("コース %d をはじめる", "Start course %d", next),
                          systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("main.play")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(Theme.wall.opacity(0.94))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RobotMark().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("すいこみロボ", "Dust Rush")).font(Theme.title(30)).kerning(-0.5).foregroundStyle(Theme.ink)
                Text(tr("吸って、強くなって、充電が切れる前に帰る", "Vacuum, upgrade, and get home before the battery dies"))
                    .font(Theme.body(12)).foregroundStyle(Theme.inkSoft).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button { model.press(); model.activeSheet = .settings } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.card)).overlay(Circle().stroke(Theme.line))
            }
            .accessibilityLabel(tr("設定", "Settings"))
            .accessibilityIdentifier("main.settings")
        }
    }
}

/// ホームの背景：うすい板目の床
struct HomeBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.wall))
            var seams = Path()
            var y: CGFloat = 30
            var row = 0
            while y < size.height {
                seams.move(to: CGPoint(x: 0, y: y)); seams.addLine(to: CGPoint(x: size.width, y: y))
                var x = CGFloat((row * 113) % 170)
                while x < size.width { seams.move(to: CGPoint(x: x, y: y - 30)); seams.addLine(to: CGPoint(x: x, y: y)); x += 190 }
                y += 30
                row += 1
            }
            ctx.stroke(seams, with: .color(Theme.wallDeep), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// 白い丸のロボ（題字の横・案内）
struct RobotMark: View {
    var ring: Color = Theme.chargeHigh
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + 2, width: r * 2, height: r * 2)), with: .color(Theme.ink.opacity(0.15)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: 0xCFC7D8)), lineWidth: 1.2)
            var bumper = Path()
            bumper.addArc(center: c, radius: r * 0.88, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
            ctx.stroke(bumper, with: .color(Color(hex: 0xBDB4C9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let rr = r * 0.55
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(ring), lineWidth: 3)
        }
        .accessibilityHidden(true)
    }
}

struct DailyCard: View {
    @Environment(AppModel.self) private var model
    @State private var preview: World?

    var body: some View {
        let rooms = model.dailyRooms
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: tr("今日の家", "TODAY'S HOUSE"), color: Theme.peachDeep)
                Spacer()
                StreakPill(streak: model.save.streak)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(rooms.first?.title ?? "").font(Theme.title(20)).foregroundStyle(Theme.ink).lineLimit(2).minimumScaleFactor(0.8)
                    Text(tr("毎日ちがう 5 部屋。だれでも同じ家。", "5 new rooms every day — the same house for everyone."))
                        .font(Theme.body(12)).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(rooms.enumerated()), id: \.offset) { i, r in
                            HStack(spacing: 6) {
                                Text("\(i + 1)").font(Theme.label(10)).foregroundStyle(Theme.peachDeep)
                                    .frame(width: 16, height: 16).background(Circle().fill(Theme.peachSoft))
                                Text(r.title).font(Theme.body(12)).foregroundStyle(Theme.ink).lineLimit(1)
                                if r.pet { Text("🐾").font(.system(size: 10)) }
                                if r.toys { Text("🧱").font(.system(size: 10)) }
                            }
                        }
                    }
                    if let best = model.save.daily[model.today] {
                        Text(trf("今日のいちばん %d 点", "Today's best: %d pts", best)).font(Theme.body(12, weight: .bold)).foregroundStyle(Theme.mintDeep)
                    }
                }
                Spacer(minLength: 0)
                Group {
                    if let preview {
                        Canvas { ctx, size in
                            RoomDrawing(world: preview, time: 1, skin: model.isPro ? model.save.skin : .snow, showPath: false,
                                        mask: MaskCache.make(preview)).draw(&ctx, size: size)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 104, height: 162)
                .accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                Button { model.press(); model.startDaily() } label: {
                    Label(model.dailyDone ? tr("もう一度", "Play again") : tr("今日の家を掃除", "Clean today's house"), systemImage: "sun.max.fill")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.peachDeep, edge: Color(hex: 0x8E4528)))
                .accessibilityIdentifier("main.daily")
                Button { model.press(); model.activeSheet = .days } label: {
                    Label(tr("過去の家", "Past days"), systemImage: model.isPro ? "calendar" : "lock.fill")
                }
                .buttonStyle(SoftButtonStyle())
                .frame(maxWidth: 150)
                .accessibilityIdentifier("main.days")
            }
        }
        .padding(16)
        .card()
        .onAppear { if preview == nil { preview = DailyCard.makePreview(rooms.first ?? Rooms.numbered(1)) } }
    }

    /// 見本：ドックから 2 本の筋を掃除したところ
    static func makePreview(_ plan: RoomPlan) -> World {
        var w = World(plan: plan, seed: 7)
        let d = plan.dock
        w.paint(stride(from: 0.0, through: 1, by: 0.02).map { t in Vec(x: d.x + (180 - d.x) * t, y: d.y - 330 * t) }, radius: 22)
        w.paint(stride(from: 0.0, through: 1, by: 0.02).map { t in Vec(x: 40 + 280 * t, y: 240) }, radius: 22)
        w.place(robotAt: Vec(x: 300, y: 240))
        return w
    }
}

struct StreakPill: View {
    var streak: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("🔥").font(.system(size: 12))
            Text(trf("%d 日つづけて", "%d-day streak", streak)).font(Theme.label(11)).foregroundStyle(Theme.peachDeep)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Theme.peachSoft))
    }
}

struct CourseList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: tr("コース（5 部屋ずつ）", "COURSES · 5 ROOMS EACH"))
                Spacer()
                Text(trf("★ %d / %d", "★ %d / %d", model.save.totalStars, Rooms.all.count * 3)).font(Theme.number(12)).foregroundStyle(Color(hex: 0xB0861F))
            }
            ForEach(1...Rooms.courseCount, id: \.self) { n in
                CourseRow(n: n)
            }
        }
        .padding(16)
        .card()
    }
}

struct CourseRow: View {
    @Environment(AppModel.self) private var model
    let n: Int

    var body: some View {
        let open = model.save.courseOpen(n, isPro: model.isPro)
        let needsPro = n > 2 && !model.isPro
        let rooms = model.courseRooms(n)
        let stars = rooms.map { model.save.starsOf($0) }.reduce(0, +)
        Button { model.press(); model.startCourse(n) } label: {
            HStack(spacing: 12) {
                Text("\(n)").font(Theme.number(17)).foregroundStyle(open ? Theme.mintDeep : Theme.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous).fill(open ? Theme.mintSoft : Theme.wallDeep))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Courses.name(n)).font(Theme.body(15, weight: .bold)).foregroundStyle(open ? Theme.ink : Theme.inkSoft)
                    Text(Courses.note(n)).font(Theme.body(11)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if needsPro {
                    Text("PRO").font(Theme.label(10)).kerning(0.8).foregroundStyle(Theme.lavenderDeep)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.lavenderSoft))
                } else if !open {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(trf("★%d", "★%d", stars)).font(Theme.number(13)).foregroundStyle(stars > 0 ? Color(hex: 0xB0861F) : Theme.inkSoft)
                    if model.save.coursesCleared.contains(n) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mintDeep) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("course\(n)")
    }
}

struct ShelfRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 12) {
            Button { model.press(); model.activeSheet = .collection } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: -6) {
                        ForEach(Array(model.save.found.sorted().suffix(4)), id: \.self) { id in
                            Text(LostItem.all[id].emoji).font(.system(size: 18)).frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.tags[id % 3])).overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        }
                        if model.save.found.isEmpty {
                            Text("?").font(Theme.title(16)).foregroundStyle(Theme.lavenderDeep).frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.lavenderSoft))
                        }
                    }
                    Text(tr("落とし物図鑑", "Lost & Found")).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(trf("%d / %d", "%d / %d", model.save.found.count, LostItem.all.count)).font(Theme.number(12)).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("collection")
            VStack(alignment: .leading, spacing: 6) {
                Text("🧹").font(.system(size: 22))
                Text(tr("吸ったほこり", "Dust collected")).font(Theme.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                Text(trf("%d こ・%d 部屋", "%d · %d rooms", model.save.totalDust, model.save.roomsCleaned)).font(Theme.number(12)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
    }
}

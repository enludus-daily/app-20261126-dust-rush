import SwiftUI

/// 遊び方 3 ページ：なぞって進む → ゴミ箱がいっぱいで強化 → 充電が切れる前にドックへ
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var worlds: [World] = []

    var body: some View {
        let page = model.onboardingPage
        ZStack {
            HomeBackdrop().ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.mintDeep : Theme.line).frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .padding(.top, 10)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                illustration(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                VStack(spacing: 8) {
                    Eyebrow(text: ["1 / 3", "2 / 3", "3 / 3"][page], color: Theme.mintDeep)
                    Text(title(page)).font(Theme.title(25)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    Text(detail(page)).font(Theme.body(15)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .id(page)
                .transition(.opacity)
            }
            .frame(maxWidth: 560)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if page < 2 {
                        Button { model.press(); withAnimation(.easeOut(duration: 0.25)) { model.onboardingPage += 1 } } label: { Text(tr("次へ", "Next")) }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityIdentifier("main.onboardNext")
                    } else {
                        Button { model.press(); withAnimation(.easeOut(duration: 0.35)) { model.onboarded = true } } label: { Text(tr("掃除をはじめる", "Start cleaning")) }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityIdentifier("main.onboardStart")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .frame(maxWidth: 560)
            }
        }
        .onAppear { if worlds.isEmpty { worlds = OnboardingView.makeWorlds() } }
    }

    private func title(_ p: Int) -> String {
        [tr("なぞった方へ進む", "Drag to drive"), tr("ゴミ箱がいっぱいで強化", "Full bin = upgrade"), tr("充電が切れる前に帰る", "Get home before the battery dies")][p]
    }

    private func detail(_ p: Int) -> String {
        [tr("ブラシは自動で回って、近くのほこりを吸いこみます。通った床がぴかぴかに。", "Brushes spin on their own and pull in nearby dust. Every path you drive starts to shine."),
         tr("3 つから 1 つ選んで、ブラシを伸ばす・速くする・電池を大きくする。", "Pick 1 of 3: longer brushes, faster wheels, a bigger battery and more."),
         tr("点線がドックへの道。「帰りに ○%」を見て、欲張りすぎないうちに。記録はこの iPhone の中だけに残ります。",
            "The dotted line leads to the dock. Watch \"Home %\" and don't get greedy. Your progress stays on this iPhone.")][p]
    }

    @ViewBuilder
    private func illustration(_ p: Int) -> some View {
        if p == 1 {
            VStack(spacing: 10) {
                ForEach([Upgrade.sideBrush, .speed, .battery], id: \.self) { u in
                    HStack(spacing: 12) {
                        UpgradeBadge(upgrade: u, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name).font(Theme.body(15, weight: .heavy)).foregroundStyle(Theme.ink)
                            Text(u.detail).font(Theme.body(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .card()
                }
            }
            .frame(maxWidth: 340)
            .frame(maxHeight: .infinity)
        } else if worlds.count == 2 && p == 0 {
            // 動く見本：ロボがなぞった道を進み、床がぴかぴかになっていく（4 秒でくり返す）
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.still || model.reduceMotion)) { tl in
                let t = model.still || model.reduceMotion ? 0.75 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
                let w = OnboardingView.drive(worlds[0], progress: t)
                Canvas { ctx, size in
                    RoomDrawing(world: w, time: t * 4, skin: .snow, showPath: false, mask: MaskCache.make(w)).draw(&ctx, size: size)
                    // 指の印
                    let map = RoomMap(size: size)
                    let f = map.pt(OnboardingView.route(min(1, t + 0.12)))
                    ctx.fill(Path(ellipseIn: CGRect(x: f.x - 14, y: f.y - 14, width: 28, height: 28)), with: .color(Theme.lavenderDeep.opacity(0.25)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: f.x - 14, y: f.y - 14, width: 28, height: 28)), with: .color(Theme.lavenderDeep.opacity(0.7)), lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
        } else if worlds.count == 2 {
            let w = worlds[p == 0 ? 0 : 1]
            Canvas { ctx, size in
                RoomDrawing(world: w, time: 1, skin: .snow, showPath: p == 2, mask: MaskCache.make(w)).draw(&ctx, size: size)
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    /// 見本の道：ドックから左上へ、S 字に
    static func route(_ t: Double) -> Vec {
        let pts = [Vec(x: 250, y: 534), Vec(x: 250, y: 420), Vec(x: 80, y: 420), Vec(x: 80, y: 320), Vec(x: 290, y: 320), Vec(x: 290, y: 230), Vec(x: 140, y: 230)]
        let x = max(0, min(1, t)) * Double(pts.count - 1)
        let i = min(pts.count - 2, Int(x))
        let f = x - Double(i)
        return pts[i] + (pts[i + 1] - pts[i]) * f
    }

    static func drive(_ base: World, progress t: Double) -> World {
        var w = base
        w.paint(stride(from: 0.0, through: t, by: 0.01).map(route), radius: 22)
        w.place(robotAt: route(t))
        return w
    }

    static func makeWorlds() -> [World] {
        var a = World(plan: Rooms.numbered(1), seed: 3)
        for i in 0..<6 { a.drop(.fluff, at: Vec(x: 160 + Double(i % 3) * 22, y: 200 - Double(i / 3) * 18)) }
        var b = World(plan: Rooms.numbered(2), seed: 4)
        b.paint(stride(from: 0.0, through: 1, by: 0.01).map { t in Vec(x: 30 + 300 * t, y: 470) }, radius: 22)
        b.paint(stride(from: 0.0, through: 1, by: 0.01).map { t in Vec(x: 330 - 300 * t, y: 420) }, radius: 22)
        b.paint(stride(from: 0.0, through: 1, by: 0.01).map { t in Vec(x: 30 + 290 * t, y: 300) }, radius: 22)
        b.place(robotAt: Vec(x: 320, y: 90), charge: 24)
        b.revealLost(at: Vec(x: 20, y: 120))
        return [a, b]
    }
}

import SwiftUI
import CoreGraphics

/// 部屋の座標（360 × 560）と画面の点の対応
struct RoomMap {
    var scale: CGFloat
    var origin: CGPoint

    init(size: CGSize) {
        scale = min(size.width / RoomPlan.width, size.height / RoomPlan.height)
        origin = CGPoint(x: (size.width - RoomPlan.width * scale) / 2, y: (size.height - RoomPlan.height * scale) / 2)
    }

    func pt(_ v: Vec) -> CGPoint { CGPoint(x: origin.x + v.x * scale, y: origin.y + v.y * scale) }
    func rect(_ b: Box) -> CGRect { CGRect(x: origin.x + b.x * scale, y: origin.y + b.y * scale, width: b.w * scale, height: b.h * scale) }
    func len(_ d: Double) -> CGFloat { d * scale }
    func world(_ p: CGPoint) -> Vec { Vec(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
    var roomRect: CGRect { rect(Box(x: 0, y: 0, w: RoomPlan.width, h: RoomPlan.height)) }
}

/// 掃除した所の膜の絵（変わったときだけ作り直す）
final class MaskCache {
    private var version = -1
    private var planID = ""
    private(set) var image: CGImage?

    func image(for w: World) -> CGImage? {
        if w.maskVersion == version && w.plan.id == planID, let image { return image }
        version = w.maskVersion
        planID = w.plan.id
        image = MaskCache.make(w)
        return image
    }

    /// 掃除していない床：ほこりの膜（灰茶 0.36）。掃除した床：光（白 0.22）。家具の下：なし
    static func make(_ w: World) -> CGImage? {
        let g = w.grid
        var px = [UInt8](repeating: 0, count: g.cols * g.rows * 4)
        for k in 0..<(g.cols * g.rows) where g.floor[k] {
            let o = k * 4
            if w.isClean(k) {
                // 前乗算アルファ：白 0.22
                px[o] = 56; px[o + 1] = 56; px[o + 2] = 56; px[o + 3] = 56
            } else {
                let a = 0.36
                px[o] = UInt8(156 * a); px[o + 1] = UInt8(143 * a); px[o + 2] = UInt8(128 * a); px[o + 3] = UInt8(255 * a)
            }
        }
        let data = Data(px) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: g.cols, height: g.rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: g.cols * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// 部屋の絵：床の板目 → ラグ → ほこりの膜 → 家具 → ドック → 帰り道の点線 → ほこり → ロボ
struct RoomDrawing {
    var world: World
    var time: Double
    var skin: RobotSkin
    var puffs: [(Vec, Double, DustKind)] = []
    var hitFlash: Double = 0
    var showPath = true
    var mask: CGImage?

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let map = RoomMap(size: size)
        let plan = world.plan
        drawFloor(&ctx, map, plan)
        for rug in plan.rugs { drawRug(&ctx, map, rug) }
        if let mask {
            let img = Image(decorative: mask, scale: 1).interpolation(.high)
            ctx.draw(img, in: map.roomRect)
        }
        // 壁（幅木）
        ctx.stroke(Path(roundedRect: map.roomRect.insetBy(dx: -map.len(3), dy: -map.len(3)), cornerRadius: map.len(6)),
                   with: .color(Color(hex: 0xD9CFC2)), lineWidth: map.len(6))
        drawDock(&ctx, map, plan)
        for f in plan.furniture { FurnitureArt.draw(&ctx, map, f) }
        if showPath { drawHomePath(&ctx, map) }
        for d in world.dust { drawDust(&ctx, map, d) }
        for p in puffs { drawPuff(&ctx, map, p) }
        drawRobot(&ctx, map)
    }

    /// ロボだけを描く（設定の見本）
    func drawRobotOnly(_ ctx: inout GraphicsContext, size: CGSize) {
        drawRobot(&ctx, RoomMap(size: size))
    }

    private func drawFloor(_ ctx: inout GraphicsContext, _ map: RoomMap, _ plan: RoomPlan) {
        let tone = Theme.floors[plan.floor % Theme.floors.count]
        let room = map.roomRect
        ctx.fill(Path(room), with: .color(Color(hex: tone.base)))
        // 板目：幅 22 の板、継ぎ目は 1 枚ごとにずらす
        let plank = 22.0
        var seams = Path()
        var y = plank
        var row = 0
        while y < RoomPlan.height {
            seams.move(to: map.pt(Vec(x: 0, y: y)))
            seams.addLine(to: map.pt(Vec(x: RoomPlan.width, y: y)))
            let shift = Double((row * 97) % 140)
            var x = shift
            while x < RoomPlan.width {
                seams.move(to: map.pt(Vec(x: x, y: y - plank)))
                seams.addLine(to: map.pt(Vec(x: x, y: y)))
                x += 150
            }
            y += plank
            row += 1
        }
        ctx.stroke(seams, with: .color(Color(hex: tone.seam)), lineWidth: max(0.6, map.len(0.9)))
    }

    private func drawRug(_ ctx: inout GraphicsContext, _ map: RoomMap, _ rug: Rug) {
        let c = Theme.rugs[rug.tint % Theme.rugs.count]
        let r = map.rect(rug.box)
        let shape = Path(roundedRect: r, cornerRadius: map.len(10))
        ctx.fill(shape, with: .color(Color(hex: c.0)))
        var inner = ctx
        inner.clip(to: shape)
        switch rug.pattern {
        case 1:
            var p = Path()
            var x = r.minX + map.len(8)
            while x < r.maxX { p.addRect(CGRect(x: x, y: r.minY, width: map.len(7), height: r.height)); x += map.len(20) }
            inner.fill(p, with: .color(Color(hex: c.1, opacity: 0.6)))
        case 2:
            var p = Path()
            var yy = r.minY + map.len(12)
            var odd = false
            while yy < r.maxY {
                var x = r.minX + map.len(odd ? 22 : 12)
                while x < r.maxX { p.addEllipse(in: CGRect(x: x - map.len(4), y: yy - map.len(4), width: map.len(8), height: map.len(8))); x += map.len(20) }
                yy += map.len(18)
                odd.toggle()
            }
            inner.fill(p, with: .color(Color(hex: c.1, opacity: 0.8)))
        case 3:
            var p = Path()
            var x = r.minX
            while x < r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += map.len(18) }
            var yy = r.minY
            while yy < r.maxY { p.move(to: CGPoint(x: r.minX, y: yy)); p.addLine(to: CGPoint(x: r.maxX, y: yy)); yy += map.len(18) }
            inner.stroke(p, with: .color(Color(hex: c.1, opacity: 0.7)), lineWidth: map.len(2))
        default:
            break
        }
        ctx.stroke(Path(roundedRect: r.insetBy(dx: map.len(4), dy: map.len(4)), cornerRadius: map.len(7)),
                   with: .color(Color(hex: c.1)), style: StrokeStyle(lineWidth: map.len(1.2), dash: [map.len(3), map.len(3)]))
    }

    private func drawDock(_ ctx: inout GraphicsContext, _ map: RoomMap, _ plan: RoomPlan) {
        let d = plan.dock
        // 床の丸い印
        let pad = CGRect(x: map.pt(d).x - map.len(26), y: map.pt(d).y - map.len(24), width: map.len(52), height: map.len(48))
        ctx.fill(Path(ellipseIn: pad), with: .color(Theme.mint.opacity(0.28)))
        ctx.stroke(Path(ellipseIn: pad), with: .color(Theme.mintDeep.opacity(0.35)), style: StrokeStyle(lineWidth: map.len(1.2), dash: [map.len(3), map.len(3)]))
        // 本体（下の壁に付いた白い箱と緑の灯り）
        let body = map.rect(Box(x: d.x - 24, y: RoomPlan.height - 12, w: 48, h: 14))
        ctx.fill(Path(roundedRect: body, cornerRadius: map.len(5)), with: .color(.white))
        ctx.stroke(Path(roundedRect: body, cornerRadius: map.len(5)), with: .color(Theme.line), lineWidth: map.len(1))
        let glow = 0.6 + 0.4 * sin(time * 3)
        let lamp = map.rect(Box(x: d.x - 10, y: RoomPlan.height - 8, w: 20, h: 3.5))
        ctx.fill(Path(roundedRect: lamp, cornerRadius: map.len(2)), with: .color(Theme.chargeHigh.opacity(glow)))
    }

    /// ドックまでの点線。帰り道に要る充電に余裕があれば緑、ぎりぎりは黄、足りなければ赤
    private func drawHomePath(_ ctx: inout GraphicsContext, _ map: RoomMap) {
        let w = world
        guard w.phase == .playing else { return }
        let margin = (w.charge - w.homeCost) / w.stats.maxCharge
        let show = w.homing || w.chargeRatio < 0.6
        var points = [w.robot]
        var p = w.robot
        for _ in 0..<90 {
            guard let n = w.grid.step(along: w.homeField, from: p, lookahead: 2), n.distance(to: p) > 0.5 else { break }
            points.append(n)
            p = n
            if p.distance(to: w.plan.dock) < 10 { break }
        }
        points.append(w.plan.dock)
        var path = Path()
        path.move(to: map.pt(points[0]))
        for q in points.dropFirst() { path.addLine(to: map.pt(q)) }
        let color = margin > 0.15 ? Theme.mintDeep : (margin > 0.05 ? Color(hex: 0xC99A2E) : Theme.chargeLow)
        ctx.stroke(path, with: .color(color.opacity(show ? 0.75 : 0.22)),
                   style: StrokeStyle(lineWidth: map.len(show ? 2.4 : 1.6), lineCap: .round, lineJoin: .round, dash: [map.len(1), map.len(6)], dashPhase: -time * 18))
    }

    private func drawDust(_ ctx: inout GraphicsContext, _ map: RoomMap, _ d: Dust) {
        let c = map.pt(d.pos)
        let wob = sin(time * 4 + Double(d.id)) * 0.08
        switch d.kind {
        case .crumb:
            let s = map.len(3.2)
            var p = Path()
            p.addRoundedRect(in: CGRect(x: c.x - s, y: c.y - s * 0.7, width: s * 2, height: s * 1.4), cornerSize: CGSize(width: s * 0.5, height: s * 0.5))
            ctx.fill(p.applying(CGAffineTransform(translationX: -c.x, y: -c.y).concatenating(CGAffineTransform(rotationAngle: Double(d.id) * 0.7)).concatenating(CGAffineTransform(translationX: c.x, y: c.y))),
                     with: .color(Color(hex: 0xD6B27E)))
        case .fluff:
            let r = map.len(5) * (1 + wob)
            for (dx, dy, k) in [(-0.45, 0.1, 0.75), (0.45, 0.05, 0.7), (0.0, -0.35, 0.8), (0, 0.15, 1.0)] {
                let rr = r * k
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - rr, y: c.y + dy * r - rr, width: rr * 2, height: rr * 2)), with: .color(Color(hex: 0xBDB6AD)))
            }
            eyes(&ctx, c, r * 0.32, spread: r * 0.36)
        case .hair:
            let r = map.len(10) * (1 - min(0.5, d.suck * 0.5)) * (1 + wob * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: 0x9C93A8)))
            var loops = Path()
            for i in 0..<5 {
                let a = Double(i) * 1.3 + time * 0.6
                loops.addArc(center: CGPoint(x: c.x + cos(a) * r * 0.35, y: c.y + sin(a) * r * 0.35), radius: r * 0.55,
                             startAngle: .radians(a), endAngle: .radians(a + 2.2), clockwise: false)
            }
            ctx.stroke(loops, with: .color(Color(hex: 0x7D7489)), lineWidth: max(0.8, map.len(1.1)))
            eyes(&ctx, c, r * 0.22, spread: r * 0.34)
            if d.suck > 0 {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)).trimmedPath(from: 0, to: min(1, d.suck)),
                           with: .color(Theme.mintDeep), lineWidth: 2)
            }
        case .lost:
            let item = LostItem.all[world.plan.lostItem % LostItem.all.count]
            let r = map.len(11)
            let ring = Path(ellipseIn: CGRect(x: c.x - r * 1.5, y: c.y - r * 1.5, width: r * 3, height: r * 3))
            ctx.stroke(ring, with: .color(Theme.lavenderDeep.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 4], dashPhase: time * 12))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.lavenderSoft))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.lavenderDeep), lineWidth: 1.5)
            ctx.draw(Text(item.emoji).font(.system(size: r * 1.1)), at: c)
        }
    }

    private func eyes(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, spread: CGFloat) {
        for s in [-1.0, 1.0] {
            let e = CGPoint(x: c.x + s * spread, y: c.y - r * 0.2)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.55, y: e.y - r * 0.7, width: r * 1.1, height: r * 1.4)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.3, y: e.y - r * 0.35, width: r * 0.6, height: r * 0.7)), with: .color(Theme.ink))
        }
    }

    private func drawPuff(_ ctx: inout GraphicsContext, _ map: RoomMap, _ p: (Vec, Double, DustKind)) {
        let t = p.1 / 0.35
        let pos = p.0 + (world.robot - p.0) * t
        let c = map.pt(pos)
        let r = map.len(4 + 6 * t)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(0.9 * (1 - t))), lineWidth: 1.5)
    }

    private func drawRobot(_ ctx: inout GraphicsContext, _ map: RoomMap) {
        let w = world
        let c = map.pt(w.robot)
        let r = map.len(w.stats.bodyRadius)
        // 吸いこむ輪
        let pr = map.len(w.stats.pullRadius)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)),
                   with: .color(Theme.mintDeep.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 4], dashPhase: -time * 10))
        // ブラシの幅（掃除の輪）
        let br = map.len(w.stats.brushRadius)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)), with: .color(.white.opacity(0.16)))
        var local = ctx
        local.translateBy(x: c.x, y: c.y)
        local.rotate(by: .radians(w.heading + .pi / 2))
        // サイドブラシ（前の左右で回る）
        let spin = w.moving ? time * 14 : time * 2
        for side in [-1.0, 1.0] {
            let bc = CGPoint(x: side * r * 0.72, y: -r * 0.62)
            var b = Path()
            let len = r * 0.55 + map.len(Double(w.levels[.sideBrush] ?? 0) * 2.5)
            for k in 0..<3 {
                let a = spin * side + Double(k) * 2.094
                b.move(to: bc)
                b.addLine(to: CGPoint(x: bc.x + cos(a) * len, y: bc.y + sin(a) * len))
            }
            local.stroke(b, with: .color(Color(hex: 0x8B8399)), lineWidth: max(1, map.len(1.2)))
        }
        // 影
        local.fill(bodyPath(r).offsetBy(dx: 0, dy: map.len(2.5)), with: .color(Theme.ink.opacity(0.16)))
        // 体
        let fill: Color
        switch skin {
        case .snow, .cat, .triangle: fill = .white
        case .mint: fill = Color(hex: 0xD3F1E6)
        case .lavender: fill = Color(hex: 0xE6DEFA)
        case .peach: fill = Color(hex: 0xFCE0D2)
        }
        if skin == .cat {
            for side in [-1.0, 1.0] {
                var ear = Path()
                ear.move(to: CGPoint(x: side * r * 0.35, y: -r * 0.85))
                ear.addLine(to: CGPoint(x: side * r * 0.95, y: -r * 1.15))
                ear.addLine(to: CGPoint(x: side * r * 0.85, y: -r * 0.4))
                ear.closeSubpath()
                local.fill(ear, with: .color(Color(hex: 0xF4C9D6)))
                local.stroke(ear, with: .color(Theme.line), lineWidth: 1)
            }
        }
        local.fill(bodyPath(r), with: .color(fill))
        local.stroke(bodyPath(r), with: .color(Color(hex: 0xCFC7D8)), lineWidth: max(1, map.len(1.1)))
        // 前のバンパー
        var bumper = Path()
        bumper.addArc(center: .zero, radius: r * 0.9, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
        local.stroke(bumper, with: .color(Color(hex: 0xBDB4C9)), style: StrokeStyle(lineWidth: map.len(2.2), lineCap: .round))
        // 光る輪（充電の色）
        let ring = Path(ellipseIn: CGRect(x: -r * 0.55, y: -r * 0.55, width: r * 1.1, height: r * 1.1))
        let col = w.phase == .dead ? Color(hex: 0xBDB4C9) : Theme.chargeColor(w.chargeRatio)
        var glow = local
        glow.addFilter(.blur(radius: map.len(2)))
        glow.stroke(ring, with: .color(col.opacity(0.9)), lineWidth: map.len(2.6))
        local.stroke(ring, with: .color(col), lineWidth: map.len(1.4))
        local.fill(Path(ellipseIn: CGRect(x: -r * 0.2, y: -r * 0.2, width: r * 0.4, height: r * 0.4)), with: .color(Color(hex: 0xEDE8F2)))
        if skin == .cat {
            // ひげ
            var whisker = Path()
            for side in [-1.0, 1.0] {
                for k in [-0.15, 0.12] {
                    whisker.move(to: CGPoint(x: side * r * 0.75, y: k * r))
                    whisker.addLine(to: CGPoint(x: side * r * 1.15, y: k * r - 0.1 * r))
                }
            }
            local.stroke(whisker, with: .color(Color(hex: 0xBDB4C9)), lineWidth: 1)
        }
        // 落とし物を運んでいる
        if w.lost == .carried {
            local.draw(Text(LostItem.all[w.plan.lostItem % LostItem.all.count].emoji).font(.system(size: r * 0.7)), at: CGPoint(x: 0, y: r * 0.35))
        }
        // ぶつかった
        if hitFlash > 0 {
            let hr = r * (1.2 + (0.35 - hitFlash) * 1.5)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                       with: .color(Theme.chargeLow.opacity(hitFlash / 0.35)), lineWidth: 3)
        }
    }

    private func bodyPath(_ r: CGFloat) -> Path {
        if skin == .triangle {
            // おむすび（角の丸い三角）
            var p = Path()
            let pts = (0..<3).map { i -> CGPoint in
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / 3
                return CGPoint(x: cos(a) * r * 1.12, y: sin(a) * r * 1.12)
            }
            p.move(to: CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2))
            for i in 1...3 {
                let a = pts[i % 3], b = pts[(i + 1) % 3]
                p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            }
            p.closeSubpath()
            return p
        }
        return Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
    }
}

/// 上から見た家具（自作の形）
enum FurnitureArt {
    static func draw(_ ctx: inout GraphicsContext, _ map: RoomMap, _ f: Furniture) {
        let c = Theme.furniture[f.tint % Theme.furniture.count]
        let top = Color(hex: c.top), edge = Color(hex: c.edge)
        let r = map.rect(f.box)
        let rad = map.len(6)
        // 影
        ctx.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: map.len(3)), cornerRadius: rad), with: .color(Theme.ink.opacity(0.10)))
        func box(_ rect: CGRect, _ color: Color, _ radius: CGFloat? = nil) {
            ctx.fill(Path(roundedRect: rect, cornerRadius: radius ?? rad), with: .color(color))
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: Color = edge, _ w: CGFloat = 1.2) {
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(color), lineWidth: max(0.8, map.len(w)))
        }
        let wood = Color(hex: 0xE3C9A6), woodEdge = Color(hex: 0xC9A87E)
        switch f.kind {
        case .sofa:
            box(r, edge)
            let horizontal = r.width >= r.height
            let inset = map.len(9)
            let seat = horizontal ? CGRect(x: r.minX + inset, y: r.minY + inset, width: r.width - inset * 2, height: r.height - inset)
                                  : CGRect(x: r.minX + inset, y: r.minY + inset, width: r.width - inset, height: r.height - inset * 2)
            box(seat, top, map.len(5))
            let n = max(2, Int((horizontal ? seat.width : seat.height) / map.len(55)))
            for i in 1..<n {
                let t = CGFloat(i) / CGFloat(n)
                if horizontal { line(CGPoint(x: seat.minX + seat.width * t, y: seat.minY + 3), CGPoint(x: seat.minX + seat.width * t, y: seat.maxY - 3)) }
                else { line(CGPoint(x: seat.minX + 3, y: seat.minY + seat.height * t), CGPoint(x: seat.maxX - 3, y: seat.minY + seat.height * t)) }
            }
        case .bed:
            box(r, Color(hex: 0xF7F3EE))
            ctx.stroke(Path(roundedRect: r, cornerRadius: rad), with: .color(Theme.line), lineWidth: 1)
            let pillow = CGRect(x: r.minX + r.width * 0.15, y: r.minY + map.len(8), width: r.width * 0.7, height: map.len(26))
            box(pillow, .white, map.len(8))
            ctx.stroke(Path(roundedRect: pillow, cornerRadius: map.len(8)), with: .color(Theme.line), lineWidth: 1)
            let blanket = CGRect(x: r.minX, y: r.minY + r.height * 0.38, width: r.width, height: r.height * 0.62)
            box(blanket, top)
            line(CGPoint(x: blanket.minX, y: blanket.minY + map.len(10)), CGPoint(x: blanket.maxX, y: blanket.minY + map.len(10)))
        case .desk, .table:
            box(r, wood)
            ctx.stroke(Path(roundedRect: r.insetBy(dx: map.len(3), dy: map.len(3)), cornerRadius: rad), with: .color(woodEdge), lineWidth: 1)
            if f.kind == .desk {
                let lap = CGRect(x: r.midX - map.len(16), y: r.midY - map.len(10), width: map.len(32), height: map.len(20))
                box(lap, Color(hex: 0xD9D6DE), map.len(3))
                box(lap.insetBy(dx: map.len(3), dy: map.len(3)), Color(hex: 0x8C8798), map.len(2))
            } else {
                for k in 0..<2 {
                    let p = CGPoint(x: r.minX + r.width * (k == 0 ? 0.3 : 0.7), y: r.midY)
                    let pr = map.len(9)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)), with: .color(top), lineWidth: map.len(2))
                }
            }
        case .shelf, .wardrobe:
            box(r, f.kind == .shelf ? wood : top)
            if f.kind == .shelf {
                // 本の背（上から見た小口）
                let vertical = r.height > r.width
                let n = Int((vertical ? r.height : r.width) / map.len(9))
                for i in 0..<n {
                    let colors = [Theme.mint, Theme.lavender, Theme.peach, Color(hex: 0xF2E2A8)]
                    let t = map.len(9) * CGFloat(i)
                    let b = vertical ? CGRect(x: r.minX + map.len(4), y: r.minY + t + map.len(1), width: r.width - map.len(8), height: map.len(7))
                                     : CGRect(x: r.minX + t + map.len(1), y: r.minY + map.len(4), width: map.len(7), height: r.height - map.len(8))
                    box(b, colors[(i * 7 + Int(r.minX)) % colors.count], map.len(1.5))
                }
            } else {
                if r.width > r.height { line(CGPoint(x: r.midX, y: r.minY + 4), CGPoint(x: r.midX, y: r.maxY - 4)) }
                else { line(CGPoint(x: r.minX + 4, y: r.midY), CGPoint(x: r.maxX - 4, y: r.midY)) }
            }
        case .tv:
            box(r, Color(hex: 0xE0DAE6))
            let screen = r.width > r.height ? CGRect(x: r.minX + map.len(10), y: r.midY - map.len(3), width: r.width - map.len(20), height: map.len(6))
                                            : CGRect(x: r.midX - map.len(3), y: r.minY + map.len(10), width: map.len(6), height: r.height - map.len(20))
            box(screen, Color(hex: 0x5A5568), map.len(2))
        case .plant:
            let pot = r.insetBy(dx: r.width * 0.25, dy: r.height * 0.25)
            for i in 0..<6 {
                let a = Double(i) * .pi / 3
                let lr = r.width * 0.28
                let p = CGPoint(x: r.midX + cos(a) * r.width * 0.26, y: r.midY + sin(a) * r.height * 0.26)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - lr, y: p.y - lr * 0.7, width: lr * 2, height: lr * 1.4)), with: .color(Color(hex: i % 2 == 0 ? 0x9ED3A8 : 0x86C493)))
            }
            ctx.fill(Path(ellipseIn: pot), with: .color(Color(hex: 0xE7B79B)))
        case .kitchen:
            box(r, Color(hex: 0xEDEAF0))
            ctx.stroke(Path(roundedRect: r, cornerRadius: rad), with: .color(Theme.line), lineWidth: 1)
            let sink = CGRect(x: r.minX + r.width * 0.12, y: r.minY + map.len(8), width: r.width * 0.22, height: r.height - map.len(16))
            box(sink, Color(hex: 0xC9D7E0), map.len(5))
            for k in 0..<2 {
                let p = CGPoint(x: r.minX + r.width * (0.62 + 0.16 * CGFloat(k)), y: r.midY)
                let pr = min(r.height * 0.28, map.len(12))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)), with: .color(Color(hex: 0x6E6884)), lineWidth: map.len(2))
            }
        case .washer:
            box(r, .white)
            ctx.stroke(Path(roundedRect: r, cornerRadius: rad), with: .color(Theme.line), lineWidth: 1)
            let d = r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2)
            ctx.fill(Path(ellipseIn: d), with: .color(Color(hex: 0xCFE3EE)))
            ctx.stroke(Path(ellipseIn: d), with: .color(Color(hex: 0xA9BCC9)), lineWidth: map.len(2))
        case .bathtub:
            box(r, .white, map.len(14))
            ctx.stroke(Path(roundedRect: r, cornerRadius: map.len(14)), with: .color(Theme.line), lineWidth: 1)
            box(r.insetBy(dx: map.len(10), dy: map.len(10)), Color(hex: 0xCDE9F0), map.len(12))
            ctx.draw(Text("🦆").font(.system(size: map.len(14))), at: CGPoint(x: r.midX + map.len(20), y: r.midY))
        case .toybox:
            box(r, top)
            line(CGPoint(x: r.minX + 4, y: r.minY + map.len(10)), CGPoint(x: r.maxX - 4, y: r.minY + map.len(10)))
            ctx.draw(Text("⭐").font(.system(size: map.len(14))), at: CGPoint(x: r.midX, y: r.midY + map.len(5)))
        case .petbed:
            ctx.fill(Path(ellipseIn: r), with: .color(edge))
            ctx.fill(Path(ellipseIn: r.insetBy(dx: map.len(8), dy: map.len(8))), with: .color(top))
            ctx.draw(Text("🐈").font(.system(size: map.len(20))), at: CGPoint(x: r.midX, y: r.midY))
        case .block:
            let colors: [UInt32] = [0xF6B9A6, 0xA9DCC7, 0xC9BDF0]
            box(r, Color(hex: colors[f.tint % 3]), map.len(3))
            let s = map.len(4)
            for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                let p = CGPoint(x: r.midX + dx * s, y: r.midY + dy * s)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - map.len(2.2), y: p.y - map.len(2.2), width: map.len(4.4), height: map.len(4.4))), with: .color(.white.opacity(0.6)))
            }
        case .piano:
            box(r, Color(hex: 0x6E6884))
            let keys = CGRect(x: r.minX + map.len(6), y: r.maxY - map.len(16), width: r.width - map.len(12), height: map.len(12))
            box(keys, .white, map.len(2))
            var x = keys.minX
            while x < keys.maxX - 2 { line(CGPoint(x: x, y: keys.minY), CGPoint(x: x, y: keys.maxY), Theme.line, 0.6); x += map.len(6) }
        case .chair:
            box(r, top, map.len(6))
            box(CGRect(x: r.minX, y: r.minY, width: r.width, height: map.len(6)), edge, map.len(3))
        }
    }
}

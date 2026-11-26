import Foundation

/// 上から見た家具の種類（絵は RoomCanvas が描く）
enum FurnitureKind: String, Sendable, CaseIterable {
    case bed, sofa, desk, shelf, tv, plant, table, kitchen, washer, bathtub, toybox, petbed, block, piano, chair, wardrobe
}

struct Furniture: Equatable, Sendable {
    var kind: FurnitureKind
    var box: Box
    /// 色の番号（Theme.furniture の何番目か）
    var tint: Int
}

struct Rug: Equatable, Sendable {
    var box: Box
    var tint: Int
    /// 0: 無地 1: しま 2: 丸 3: 格子
    var pattern: Int
}

/// 部屋のつくり（30 部屋＋毎日の家）
struct RoomPlan: Equatable, Sendable, Identifiable {
    static let width: Double = 360
    static let height: Double = 560

    var number: Int
    var titleJA: String
    var titleEN: String
    var furniture: [Furniture]
    var rugs: [Rug]
    var dockX: Double
    /// ほこりがわく速さ（1 秒あたり）
    var fluffRate: Double
    /// 大きい毛玉がわく間（秒）
    var hairEvery: Double
    var pet: Bool
    var toys: Bool
    /// 床の色の番号（Theme.floors）
    var floor: Int
    /// この部屋の落とし物（LostItem の番号）
    var lostItem: Int
    var id: String { "room-\(number)" }
    var title: String { tr(titleJA, titleEN) }

    /// ロボが止まるドックの位置（下の壁の前）
    var dock: Vec { Vec(x: dockX, y: RoomPlan.height - 26) }
    var obstacles: [Box] { furniture.map(\.box) }
}

/// 10 の間取り × 3 つの暮らし（ふつう・おもちゃ・ペット）= 30 部屋
enum Rooms {
    static let freeCount = 10
    static let perCourse = 5
    static var courseCount: Int { all.count / perCourse }

    struct Layout {
        var furniture: [(FurnitureKind, Box)]
        var rugs: [(Box, Int)]
        var dockX: Double
    }

    /// 間取り（左上が 0,0。下の壁の前にドック）
    static let layouts: [Layout] = [
        // 0 ワンルーム
        Layout(furniture: [(.bed, Box(x: 0, y: 0, w: 120, h: 190)), (.desk, Box(x: 250, y: 0, w: 110, h: 56)),
                           (.plant, Box(x: 316, y: 250, w: 40, h: 40)), (.tv, Box(x: 0, y: 330, w: 34, h: 110))],
               rugs: [(Box(x: 120, y: 220, w: 150, h: 120), 1)], dockX: 250),
        // 1 リビング
        Layout(furniture: [(.sofa, Box(x: 70, y: 0, w: 210, h: 66)), (.table, Box(x: 120, y: 150, w: 110, h: 60)),
                           (.tv, Box(x: 90, y: 330, w: 170, h: 30)), (.plant, Box(x: 0, y: 0, w: 40, h: 40)), (.shelf, Box(x: 326, y: 120, w: 34, h: 160))],
               rugs: [(Box(x: 80, y: 110, w: 190, h: 150), 2)], dockX: 180),
        // 2 台所とダイニング
        Layout(furniture: [(.kitchen, Box(x: 0, y: 0, w: 360, h: 50)), (.table, Box(x: 110, y: 200, w: 140, h: 90)),
                           (.chair, Box(x: 140, y: 168, w: 28, h: 24)), (.chair, Box(x: 196, y: 168, w: 28, h: 24)),
                           (.chair, Box(x: 140, y: 298, w: 28, h: 24)), (.chair, Box(x: 196, y: 298, w: 28, h: 24)), (.washer, Box(x: 300, y: 420, w: 60, h: 60))],
               rugs: [], dockX: 90),
        // 3 寝室
        Layout(furniture: [(.bed, Box(x: 90, y: 0, w: 180, h: 220)), (.wardrobe, Box(x: 0, y: 260, w: 46, h: 150)),
                           (.plant, Box(x: 320, y: 0, w: 40, h: 40)), (.desk, Box(x: 300, y: 330, w: 60, h: 110))],
               rugs: [(Box(x: 70, y: 230, w: 220, h: 90), 0)], dockX: 180),
        // 4 書斎
        Layout(furniture: [(.shelf, Box(x: 0, y: 0, w: 36, h: 300)), (.shelf, Box(x: 324, y: 0, w: 36, h: 300)),
                           (.desk, Box(x: 120, y: 60, w: 120, h: 60)), (.chair, Box(x: 166, y: 126, w: 28, h: 28)), (.piano, Box(x: 120, y: 380, w: 120, h: 50))],
               rugs: [(Box(x: 90, y: 200, w: 180, h: 110), 3)], dockX: 300),
        // 5 細長い廊下と玄関
        Layout(furniture: [(.shelf, Box(x: 0, y: 0, w: 120, h: 36)), (.plant, Box(x: 320, y: 0, w: 40, h: 40)),
                           (.wardrobe, Box(x: 0, y: 150, w: 130, h: 46)), (.wardrobe, Box(x: 230, y: 300, w: 130, h: 46)), (.chair, Box(x: 0, y: 440, w: 40, h: 40))],
               rugs: [(Box(x: 150, y: 60, w: 60, h: 400), 1)], dockX: 300),
        // 6 洗面所とお風呂の前
        Layout(furniture: [(.bathtub, Box(x: 0, y: 0, w: 200, h: 120)), (.washer, Box(x: 300, y: 0, w: 60, h: 60)),
                           (.shelf, Box(x: 324, y: 200, w: 36, h: 140)), (.toybox, Box(x: 0, y: 300, w: 60, h: 60))],
               rugs: [(Box(x: 40, y: 150, w: 160, h: 70), 0)], dockX: 200),
        // 7 L 字のリビング
        Layout(furniture: [(.sofa, Box(x: 0, y: 60, w: 66, h: 200)), (.sofa, Box(x: 66, y: 0, w: 160, h: 60)),
                           (.table, Box(x: 120, y: 150, w: 100, h: 100)), (.tv, Box(x: 326, y: 80, w: 34, h: 180)), (.plant, Box(x: 0, y: 500, w: 40, h: 40))],
               rugs: [(Box(x: 80, y: 90, w: 220, h: 200), 2)], dockX: 240),
        // 8 子どもの遊び場
        Layout(furniture: [(.toybox, Box(x: 0, y: 0, w: 90, h: 60)), (.bed, Box(x: 250, y: 0, w: 110, h: 170)),
                           (.desk, Box(x: 0, y: 220, w: 50, h: 120)), (.shelf, Box(x: 150, y: 400, w: 120, h: 34))],
               rugs: [(Box(x: 90, y: 180, w: 200, h: 170), 3)], dockX: 80),
        // 9 広いリビングダイニング
        Layout(furniture: [(.kitchen, Box(x: 200, y: 0, w: 160, h: 46)), (.table, Box(x: 230, y: 130, w: 100, h: 80)),
                           (.sofa, Box(x: 0, y: 260, w: 60, h: 170)), (.table, Box(x: 110, y: 310, w: 80, h: 60)),
                           (.plant, Box(x: 0, y: 0, w: 40, h: 40)), (.piano, Box(x: 0, y: 90, w: 46, h: 110))],
               rugs: [(Box(x: 80, y: 270, w: 150, h: 140), 1)], dockX: 300),
    ]

    static let names: [(String, String)] = [
        ("はじめてのワンルーム", "First Studio"), ("日曜のリビング", "Sunday Living Room"), ("朝ごはんの台所", "Breakfast Kitchen"),
        ("ねぼすけの寝室", "Sleepy Bedroom"), ("しずかな書斎", "Quiet Study"), ("細長い廊下", "Long Hallway"),
        ("湯気の洗面所", "Steamy Washroom"), ("L 字のソファ", "Corner Sofa"), ("お絵かきの部屋", "Drawing Room"), ("広いリビング", "Big Open Living"),
        ("ブロックの海", "Sea of Blocks"), ("ミニカーの道", "Toy Car Road"), ("つみきの台所", "Block Kitchen"),
        ("ぬいぐるみの寝室", "Plushie Bedroom"), ("パズルの書斎", "Puzzle Study"), ("ボールの廊下", "Ball Hallway"),
        ("アヒルの洗面所", "Rubber Duck Bath"), ("秘密基地のソファ", "Sofa Fort"), ("お店やさんごっこ", "Pretend Shop"), ("誕生日の次の朝", "Morning After the Party"),
        ("ねこの昼寝部屋", "Cat Nap Room"), ("いぬの散歩前", "Before the Dog Walk"), ("ねこと朝ごはん", "Cat's Breakfast"),
        ("ふわふわ寝室", "Fluffy Bedroom"), ("ねこの書斎", "Cat in the Study"), ("毛だらけの廊下", "Furry Hallway"),
        ("いぬのお風呂の日", "Dog Bath Day"), ("毛玉のソファ", "Hairball Sofa"), ("うさぎの遊び場", "Bunny Playroom"), ("みんなのリビング", "Everyone's Living Room"),
    ]

    static let all: [RoomPlan] = (1...30).map { make(number: $0, seed: UInt64($0) &* 7919) }

    static func numbered(_ n: Int) -> RoomPlan { all[max(1, min(all.count, n)) - 1] }

    /// 部屋 n：間取り (n-1)%10、11〜20 はおもちゃ（左右反転）、21〜30 はペット
    static func make(number n: Int, seed: UInt64) -> RoomPlan {
        let layoutIndex = (n - 1) % layouts.count
        let life = (n - 1) / layouts.count // 0 ふつう 1 おもちゃ 2 ペット
        let name = names[(n - 1) % names.count]
        return build(number: n, layoutIndex: layoutIndex, mirrored: life == 1, toys: life == 1, pet: life == 2,
                     seed: seed, titleJA: name.0, titleEN: name.1, lostItem: (n - 1) % LostItem.all.count)
    }

    /// 毎日の家：日付から 5 部屋（間取り・暮らし・左右を種で決める）
    static func daily(_ day: String) -> [RoomPlan] {
        var rng = SeededRNG(seed: seed(of: day))
        var used = Set<Int>()
        return (0..<perCourse).map { i in
            var layout = rng.int(layouts.count)
            while used.contains(layout) { layout = (layout + 1) % layouts.count }
            used.insert(layout)
            let life = rng.int(3)
            let base = names[layout + life * layouts.count]
            return build(number: 100 + i, layoutIndex: layout, mirrored: rng.unit() < 0.5, toys: life == 1, pet: life == 2,
                         seed: rng.next(), titleJA: base.0, titleEN: base.1, lostItem: rng.int(LostItem.all.count))
        }
    }

    static func seed(of text: String) -> UInt64 {
        // FNV-1a（起動ごとに変わる hashValue は使わない）
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
        return h
    }

    static func build(number: Int, layoutIndex: Int, mirrored: Bool, toys: Bool, pet: Bool, seed: UInt64,
                      titleJA: String, titleEN: String, lostItem: Int) -> RoomPlan {
        let layout = layouts[layoutIndex]
        let W = RoomPlan.width
        var rng = SeededRNG(seed: seed)
        var furniture = layout.furniture.enumerated().map { i, f in
            Furniture(kind: f.0, box: mirrored ? f.1.mirrored(width: W) : f.1, tint: (i + layoutIndex) % 3)
        }
        var dockX = mirrored ? W - layout.dockX : layout.dockX
        dockX = min(max(dockX, 40), W - 40)
        let dock = Vec(x: dockX, y: RoomPlan.height - 26)
        func free(_ b: Box) -> Bool {
            let grown = b.insetBy(-34)
            if furniture.contains(where: { Box.overlaps(grown, $0.box) }) { return false }
            return b.center.distance(to: dock) > 110 && b.minX > 30 && b.maxX < W - 30 && b.minY > 30 && b.maxY < RoomPlan.height - 60
        }
        if toys {
            var placed = 0, tries = 0
            while placed < 6 && tries < 400 {
                tries += 1
                let b = Box(x: rng.range(30, W - 50), y: rng.range(40, RoomPlan.height - 110), w: 18, h: 18)
                if free(b) { furniture.append(Furniture(kind: .block, box: b, tint: placed % 3)); placed += 1 }
            }
        }
        if pet {
            var tries = 0
            while tries < 400 {
                tries += 1
                let b = Box(x: rng.range(30, W - 90), y: rng.range(40, RoomPlan.height - 160), w: 60, h: 50)
                if free(b) { furniture.append(Furniture(kind: .petbed, box: b, tint: 1)); break }
            }
        }
        let rugs = layout.rugs.enumerated().map { i, r in
            Rug(box: mirrored ? r.0.mirrored(width: W) : r.0, tint: (i + layoutIndex) % 3, pattern: r.1)
        }
        let stage = Double(min(number, 30) - 1) / 29 // 0〜1（奥の部屋ほど少しずつ多く）
        return RoomPlan(number: number, titleJA: titleJA, titleEN: titleEN, furniture: furniture, rugs: rugs, dockX: dockX,
                        fluffRate: 1.1 + 0.5 * stage + (toys ? 0.2 : 0), hairEvery: pet ? 3.2 : 6.5 - 1.5 * stage,
                        pet: pet, toys: toys, floor: layoutIndex % 4, lostItem: lostItem)
    }
}

extension Box {
    static func overlaps(_ a: Box, _ b: Box) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }
}

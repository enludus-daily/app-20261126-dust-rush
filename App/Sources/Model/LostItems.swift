import Foundation

/// ソファの下・部屋の隅から出てくる落とし物（図鑑の 30 種）。持ってドックに帰ると図鑑に入る
struct LostItem: Equatable, Sendable, Identifiable {
    var id: Int
    var emoji: String
    var nameJA: String
    var nameEN: String
    var noteJA: String
    var noteEN: String
    /// 札の色の番号（Theme.tags）
    var tint: Int

    var name: String { tr(nameJA, nameEN) }
    var note: String { tr(noteJA, noteEN) }

    static let all: [LostItem] = [
        LostItem(id: 0, emoji: "💍", nameJA: "指輪", nameEN: "Ring", noteJA: "洗い物の前に外して、それきり。", noteEN: "Taken off before the dishes. Never seen again.", tint: 0),
        LostItem(id: 1, emoji: "🔑", nameJA: "合いかぎ", nameEN: "Spare key", noteJA: "合いかぎの合いかぎが要るところだった。", noteEN: "Almost needed a spare for the spare.", tint: 1),
        LostItem(id: 2, emoji: "🪙", nameJA: "100 円玉", nameEN: "Lucky coin", noteJA: "自販機の前で落としたのとは別のやつ。", noteEN: "Not the one from the vending machine. Another one.", tint: 2),
        LostItem(id: 3, emoji: "🧦", nameJA: "片方の靴下", nameEN: "Lone sock", noteJA: "相方は洗濯機の中で待っている。", noteEN: "Its partner is still waiting in the washer.", tint: 0),
        LostItem(id: 4, emoji: "🎸", nameJA: "ギターのピック", nameEN: "Guitar pick", noteJA: "3 年前の文化祭のもの。", noteEN: "From the school festival, three years ago.", tint: 1),
        LostItem(id: 5, emoji: "🔘", nameJA: "コートのボタン", nameEN: "Coat button", noteJA: "冬の前に見つかってよかった。", noteEN: "Found just before winter. Nice timing.", tint: 2),
        LostItem(id: 6, emoji: "🧩", nameJA: "パズルの 1 ピース", nameEN: "Last puzzle piece", noteJA: "1000 ピースの最後のひとつ。", noteEN: "The very last of a thousand.", tint: 0),
        LostItem(id: 7, emoji: "🎲", nameJA: "サイコロ", nameEN: "Die", noteJA: "すごろくが止まっていた理由。", noteEN: "Why game night was on hold.", tint: 1),
        LostItem(id: 8, emoji: "🖊️", nameJA: "ペンのキャップ", nameEN: "Pen cap", noteJA: "ペン本体はもう乾いている。", noteEN: "The pen itself has dried out by now.", tint: 2),
        LostItem(id: 9, emoji: "🦕", nameJA: "小さな恐竜", nameEN: "Tiny dinosaur", noteJA: "ソファの下で 6,600 万年待った顔。", noteEN: "Waited under the sofa like it was 66 million years.", tint: 0),
        LostItem(id: 10, emoji: "🔔", nameJA: "ねこの鈴", nameEN: "Cat bell", noteJA: "最近しずかだと思っていた。", noteEN: "So that's why the cat was so quiet.", tint: 1),
        LostItem(id: 11, emoji: "🌰", nameJA: "どんぐり", nameEN: "Acorn", noteJA: "公園から子どものポケットで来た。", noteEN: "Arrived from the park in a small pocket.", tint: 2),
        LostItem(id: 12, emoji: "🐚", nameJA: "貝がら", nameEN: "Seashell", noteJA: "夏の旅行の砂がまだ少し入っている。", noteEN: "Still has a little sand from summer.", tint: 0),
        LostItem(id: 13, emoji: "🚗", nameJA: "ミニカー", nameEN: "Toy car", noteJA: "ソファの下は駐車場ではありません。", noteEN: "Under the sofa is not a parking lot.", tint: 1),
        LostItem(id: 14, emoji: "⭐", nameJA: "星のシール", nameEN: "Star sticker", noteJA: "よくできましたの星。", noteEN: "A gold star for a job well done.", tint: 2),
        LostItem(id: 15, emoji: "🃏", nameJA: "ジョーカー", nameEN: "Joker card", noteJA: "ババ抜きが終わらなかった理由。", noteEN: "Why that card game never ended.", tint: 0),
        LostItem(id: 16, emoji: "🎀", nameJA: "ヘアゴム", nameEN: "Hair tie", noteJA: "家に 30 本はあるはずの 1 本。", noteEN: "One of the thirty that should be in this house.", tint: 1),
        LostItem(id: 17, emoji: "🎧", nameJA: "イヤホンのゴム", nameEN: "Earbud tip", noteJA: "左耳がずっと落ち着かなかった。", noteEN: "The left ear never felt right without it.", tint: 2),
        LostItem(id: 18, emoji: "🧲", nameJA: "冷蔵庫の磁石", nameEN: "Fridge magnet", noteJA: "旅行のおみやげ。メモが落ちていた。", noteEN: "A travel souvenir. The note fell too.", tint: 0),
        LostItem(id: 19, emoji: "🪀", nameJA: "ヨーヨー", nameEN: "Yo-yo", noteJA: "糸はからまったまま。", noteEN: "String still tangled.", tint: 1),
        LostItem(id: 20, emoji: "🖍️", nameJA: "水色のクレヨン", nameEN: "Sky blue crayon", noteJA: "空の絵がずっと描けなかった。", noteEN: "No sky in any drawing until now.", tint: 2),
        LostItem(id: 21, emoji: "🍬", nameJA: "包んだあめ", nameEN: "Wrapped candy", noteJA: "まだ食べられる…たぶん。", noteEN: "Still good... probably.", tint: 0),
        LostItem(id: 22, emoji: "🧸", nameJA: "くまの目", nameEN: "Teddy's eye", noteJA: "くまが片目で待っている。", noteEN: "Teddy has been winking for weeks.", tint: 1),
        LostItem(id: 23, emoji: "🎟️", nameJA: "映画の半券", nameEN: "Movie stub", noteJA: "はじめて 2 人で観た日の。", noteEN: "From the first movie you saw together.", tint: 2),
        LostItem(id: 24, emoji: "🔩", nameJA: "家具のネジ", nameEN: "Furniture screw", noteJA: "本棚が少し傾いていた理由。", noteEN: "Why the bookshelf leans a little.", tint: 0),
        LostItem(id: 25, emoji: "🪁", nameJA: "たこの糸巻き", nameEN: "Kite spool", noteJA: "風の強い日を待っている。", noteEN: "Waiting for a windy day.", tint: 1),
        LostItem(id: 26, emoji: "🦴", nameJA: "いぬのガム", nameEN: "Dog chew", noteJA: "隠した本人も忘れていた。", noteEN: "Even the dog forgot where it was hidden.", tint: 2),
        LostItem(id: 27, emoji: "🧶", nameJA: "毛糸玉", nameEN: "Ball of yarn", noteJA: "マフラーはあと 10 センチ。", noteEN: "The scarf is ten centimeters from done.", tint: 0),
        LostItem(id: 28, emoji: "🥕", nameJA: "うさぎのにんじん", nameEN: "Bunny's carrot", noteJA: "非常食として隠してあった。", noteEN: "Stashed as an emergency snack.", tint: 1),
        LostItem(id: 29, emoji: "📸", nameJA: "小さな写真", nameEN: "Tiny photo", noteJA: "みんなが笑っている 1 枚。", noteEN: "Everyone is smiling in this one.", tint: 2),
    ]
}

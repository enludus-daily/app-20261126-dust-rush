import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// 真上から見た、すっきりした昼の部屋。パステル（ミント・ラベンダー・ピーチ）、丸ゴシック、ぴかぴかになる床。
/// 色・書体・形はここだけで決める
enum Theme {
    // 地と文字
    /// 壁の外（部屋のまわり）：明るいミルク
    static let wall = Color(hex: 0xF5F1EC)
    static let wallDeep = Color(hex: 0xE8E1D8)
    /// 文字：紫がかった墨（真っ黒にしない）
    static let ink = Color(hex: 0x3B3650)
    static let inkSoft = Color(hex: 0x6E6884)
    static let line = Color(hex: 0xDCD5CC)
    /// 札の地（白に近いミルク）
    static let card = Color(hex: 0xFFFCF8)

    // 主な色（各 5 段階：accent / soft / deep / paper / 飾り）
    static let mint = Color(hex: 0x9EDCC8)
    static let mintSoft = Color(hex: 0xE2F5EE)
    static let mintDeep = Color(hex: 0x2F8A72)
    static let lavender = Color(hex: 0xCBBFF0)
    static let lavenderSoft = Color(hex: 0xEEEAFB)
    static let lavenderDeep = Color(hex: 0x6A58B8)
    static let peach = Color(hex: 0xF7C7B0)
    static let peachSoft = Color(hex: 0xFDEDE4)
    static let peachDeep = Color(hex: 0xB8613F)

    /// 充電の段階（多い→少ない）。赤は小さな点と輪だけに使う
    static let chargeHigh = Color(hex: 0x5FCFAE)
    static let chargeMid = Color(hex: 0xF2C25B)
    static let chargeLow = Color(hex: 0xEE7D6B)

    static func chargeColor(_ ratio: Double) -> Color {
        ratio > 0.3 ? chargeHigh : (ratio > 0.15 ? chargeMid : chargeLow)
    }

    /// 床（フローリング）の 4 種：明るいオーク・白樺・グレージュ・はちみつ
    static let floors: [(base: UInt32, seam: UInt32)] = [
        (0xEFDDC2, 0xE2CBAA), (0xF3E8D6, 0xE6D7BF), (0xE9E2D8, 0xD9D0C3), (0xF0D9B8, 0xE1C59C),
    ]
    /// ほこりの膜（掃除していない床にかかる）
    static let grime = Color(hex: 0x9C8F80)
    /// 家具の 3 色（ミント・ラベンダー・ピーチの少し濃い面）
    static let furniture: [(top: UInt32, edge: UInt32)] = [(0xBFE6D7, 0x93CDB8), (0xD8CEF4, 0xB5A6E6), (0xF8D2C0, 0xEBB197)]
    static let rugs: [(UInt32, UInt32)] = [(0xE6F4EF, 0xBFE3D6), (0xF1EDFC, 0xD4CBF2), (0xFDF0E8, 0xF5CDB8)]
    /// 落とし物の札
    static let tags: [Color] = [mintSoft, lavenderSoft, peachSoft]

    // 書体：丸ゴシック。見出しと大きな数字は heavy、本文は medium
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .bold, design: .rounded) }

    // 角丸：小 10・札 18・大きな板 26・ボタンは丸い（高さの半分）
    static let radiusS: CGFloat = 10
    static let radiusM: CGFloat = 18
    static let radiusL: CGFloat = 26
    static let buttonHeight: CGFloat = 54
}

/// 押せるボタン：丸い「ロボのボタン」。下辺だけ濃い 3pt で押せる厚みを出す
struct PillButtonStyle: ButtonStyle {
    var fill: Color = Theme.mintDeep
    var text: Color = .white
    var edge: Color = Color(hex: 0x1F6B57)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(16, weight: .bold))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .background(
                Capsule().fill(edge).offset(y: configuration.isPressed ? 0 : 3)
            )
            .background(Capsule().fill(fill))
            .offset(y: configuration.isPressed ? 3 : 0)
            .padding(.bottom, 3)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// 白い丸ボタン（ロボの体と同じ）
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(15, weight: .bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .background(Capsule().fill(Theme.wallDeep).offset(y: configuration.isPressed ? 0 : 3))
            .background(Capsule().fill(Theme.card))
            .offset(y: configuration.isPressed ? 3 : 0)
            .padding(.bottom, 3)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// 札（ミルクの板・角丸 18・やわらかい影）
struct CardBackground: ViewModifier {
    var fill: Color = Theme.card
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.07), radius: 10, y: 4)
    }
}

extension View {
    func card(_ fill: Color = Theme.card) -> some View { modifier(CardBackground(fill: fill)) }
}

/// 小さなラベル（字間を開けた大文字風）
struct Eyebrow: View {
    var text: String
    var color: Color = Theme.inkSoft
    var body: some View {
        Text(text).font(Theme.label(11)).kerning(0.8).foregroundStyle(color)
    }
}

import Foundation

/// ロボの色と形（白は無料、ほかは Pro）
enum RobotSkin: String, Codable, Sendable, CaseIterable, Identifiable {
    case snow, mint, lavender, peach, cat, triangle
    var id: String { rawValue }
    var isPro: Bool { self != .snow }
    var name: String {
        switch self {
        case .snow: tr("しろ", "Snow")
        case .mint: tr("ミント", "Mint")
        case .lavender: tr("ラベンダー", "Lavender")
        case .peach: tr("ピーチ", "Peach")
        case .cat: tr("ねこ耳", "Cat ears")
        case .triangle: tr("おむすび", "Rice ball")
        }
    }
}

/// 日付のキー（yyyy-MM-dd、端末の暦で）
enum Days {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func offset(_ date: Date, days: Int, calendar: Calendar = .current) -> String {
        key(calendar.date(byAdding: .day, value: days, to: date) ?? date, calendar: calendar)
    }
}

/// 1 部屋の結果
struct RoomOutcome: Equatable, Sendable, Codable {
    var cleanliness: Double
    var stars: Int
    var points: Int
    var foundItem: Int?
    var docked: Bool
}

/// 端末に残すもの（保存は部屋の終わりだけ）
struct SaveData: Codable, Equatable, Sendable {
    /// 部屋ごとのいちばんの星（"room-3": 2）
    var stars: [String: Int] = [:]
    /// いちばんのきれいさ（%）
    var bestClean: [String: Int] = [:]
    /// 最後まで掃除したコース（1〜6）
    var coursesCleared: Set<Int> = []
    /// 見つけた落とし物の番号
    var found: Set<Int> = []
    var totalDust = 0
    var roomsCleaned = 0
    var runsDead = 0
    /// 毎日の家：日付 → その日のいちばんの点
    var daily: [String: Int] = [:]
    var streak = 0
    var bestStreak = 0
    var lastDaily: String?
    var skin: RobotSkin = .snow

    var totalStars: Int { stars.values.reduce(0, +) }

    func starsOf(_ room: RoomPlan) -> Int { stars[room.id] ?? 0 }

    /// コース n（1 始まり）が開いているか。前のコースを最後まで掃除すると開く。無料は 2 まで
    func courseOpen(_ n: Int, isPro: Bool) -> Bool {
        if n > 2 && !isPro { return false }
        return n == 1 || coursesCleared.contains(n - 1)
    }

    /// 次に遊ぶとよいコース
    func nextCourse(isPro: Bool) -> Int {
        let limit = isPro ? Rooms.courseCount : 2
        return (1...limit).first { courseOpen($0, isPro: isPro) && !coursesCleared.contains($0) } ?? 1
    }

    /// 部屋が終わったとき（ドックに帰った・充電切れ）
    mutating func record(_ o: RoomOutcome, room: RoomPlan, daily: Bool) {
        totalDust += o.points
        guard o.docked else { runsDead += 1; return }
        roomsCleaned += 1
        if let item = o.foundItem { found.insert(item) }
        if !daily {
            stars[room.id] = max(stars[room.id] ?? 0, o.stars)
            bestClean[room.id] = max(bestClean[room.id] ?? 0, Int((o.cleanliness * 100).rounded()))
        }
    }

    /// 1 回の掃除（5 部屋）が終わったとき
    mutating func finishRun(course: Int?, completed: Bool, score: Int, day: String?, today: String, yesterday: String) {
        if let course, completed { coursesCleared.insert(course) }
        // 毎日の家は、今日の家を遊んだときだけ続いた日数に数える（最後まで行かなくても数える）
        if let day, day == today {
            daily[today] = max(daily[today] ?? 0, score)
            if lastDaily != today {
                streak = lastDaily == yesterday ? streak + 1 : 1
                bestStreak = max(bestStreak, streak)
                lastDaily = today
            }
        }
    }

    /// 開いた日に、続いた日数が切れていたら 0 に戻す
    mutating func refreshStreak(today: String, yesterday: String) {
        if let last = lastDaily, last != today, last != yesterday { streak = 0 }
    }

    // MARK: 保存

    static let key = "save"

    static func load(_ defaults: UserDefaults = .standard) -> SaveData {
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(SaveData.self, from: data) else { return SaveData() }
        return s
    }

    func store(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: SaveData.key) }
    }
}

/// 1 回の掃除の点（共有の文にも使う）
enum Score {
    /// きれいさ 1% = 10 点、ほこり 1 つ = 1 点、落とし物 = 15 点（World.points に入っている）
    static func room(_ o: RoomOutcome) -> Int { o.docked ? Int((o.cleanliness * 1000).rounded()) + o.points : o.points }

    /// 共有の文：🟩 は星 3、🟨 は 2、🟧 は 1、⬜ は 0、🟥 は充電切れ
    static func shareLine(_ outcomes: [RoomOutcome]) -> String {
        outcomes.map { o in
            guard o.docked else { return "🟥" }
            return ["⬜", "🟧", "🟨", "🟩"][min(3, o.stars)]
        }.joined()
    }
}

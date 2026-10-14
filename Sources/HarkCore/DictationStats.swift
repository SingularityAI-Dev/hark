import Foundation

/// One finished dictation, reduced to what the stats need.
public struct DictationRecord: Equatable, Sendable {
    public var date: Date
    public var words: Int
    /// Time spent speaking: key down to the finishing key press.
    public var seconds: Double

    public init(date: Date, words: Int, seconds: Double) {
        self.date = date
        self.words = words
        self.seconds = seconds
    }
}

/// Totals for the Home page. Words, time and active days cover the chosen period; the two
/// streaks always cover the whole history, since a streak cut off by a period is misleading.
public struct DictationStats: Equatable, Sendable {
    /// What dictation is compared against for "time saved". A typical typing speed, not a
    /// measurement of the person using hark.
    public static let typingWordsPerMinute = 40.0

    public var words = 0
    public var dictations = 0
    public var seconds = 0.0
    public var activeDays = 0
    public var currentStreak = 0
    public var longestStreak = 0

    /// Nil until there is at least a second of speech to divide by.
    public var wordsPerMinute: Int? {
        seconds >= 1 ? Int((Double(words) / (seconds / 60)).rounded()) : nil
    }

    /// Typing time for the same words minus the time spent speaking them, never negative.
    public var secondsSaved: Double {
        max(0, Double(words) / Self.typingWordsPerMinute * 60 - seconds)
    }

    public init(records: [DictationRecord], since start: Date? = nil, now: Date = Date(), calendar: Calendar = .current) {
        let inPeriod = records.filter { start == nil || $0.date >= start! }
        words = inPeriod.reduce(0) { $0 + $1.words }
        dictations = inPeriod.count
        seconds = inPeriod.reduce(0) { $0 + $1.seconds }
        activeDays = Set(inPeriod.map { calendar.startOfDay(for: $0.date) }).count

        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        currentStreak = Self.streak(endingAt: calendar.startOfDay(for: now), days: days, calendar: calendar)
        longestStreak = Self.longestStreak(days, calendar: calendar)
    }

    /// Counts back from today, or from yesterday when nothing has been dictated yet today,
    /// so the streak does not read zero every morning.
    private static func streak(endingAt today: Date, days: Set<Date>, calendar: Calendar) -> Int {
        var day = today
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private static func longestStreak(_ days: Set<Date>, calendar: Calendar) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}

/// The activity grid on the Home page: one column per week, one row per weekday.
public enum ActivityGrid {
    /// Words per day, keyed by the start of the day.
    public static func wordsByDay(_ records: [DictationRecord], calendar: Calendar = .current) -> [Date: Int] {
        records.reduce(into: [:]) { $0[calendar.startOfDay(for: $1.date), default: 0] += $1.words }
    }

    /// `count` weeks ending with the week that contains `now`, oldest first. Each week holds
    /// seven day starts beginning on the calendar's first weekday.
    public static func weeks(endingAt now: Date, count: Int, calendar: Calendar = .current) -> [[Date]] {
        guard count > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<count).reversed().compactMap { back in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { return nil }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        }
    }

    /// 0 for no words, otherwise 1 to 4 relative to the busiest day shown.
    public static func level(words: Int, busiest: Int) -> Int {
        guard words > 0, busiest > 0 else { return 0 }
        return min(4, max(1, Int((4 * Double(words) / Double(busiest)).rounded(.up))))
    }
}

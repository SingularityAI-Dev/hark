import HarkCore
import SwiftUI

/// The main window: stats, history and dictionary. Opened from the menu bar icon; nothing
/// in it talks to a network.
struct DashboardView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var settings: Settings
    let openSettings: () -> Void
    @State private var page: Page? = .home

    enum Page: String, CaseIterable, Identifiable {
        case home, history, dictionary
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "book.closed"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(16)
            }
        } detail: {
            switch page ?? .home {
            case .home: HomePage(history: history, settings: settings)
            case .history: HistoryPage(history: history, settings: settings)
            case .dictionary: DictionaryPage(settings: settings)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}

// MARK: Shared pieces

private extension Color {
    static let hark = Color(red: 0.176, green: 0.722, blue: 0.541)
}

private extension View {
    func card(radius: CGFloat = 16) -> some View {
        background(Color.primary.opacity(0.05), in: .rect(cornerRadius: radius))
    }
}

private struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 30, weight: .bold))
    }
}

/// A number with its unit in smaller type, for example 13 hr 41 min.
private struct StatValue: View {
    let parts: [(value: String, unit: String)]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.value).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(part.unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }
}

private enum Format {
    static func count(_ n: Int) -> String {
        n < 10_000 ? n.formatted() : String(format: "%.1fK", Double(n) / 1000)
    }

    static func duration(_ seconds: Double) -> [(value: String, unit: String)] {
        let total = Int(seconds.rounded())
        if total < 60 { return [("\(total)", "sec")] }
        let minutes = total / 60
        if minutes < 60 { return [("\(minutes)", "min")] }
        return [("\(minutes / 60)", "hr"), ("\(minutes % 60)", "min")]
    }

    static func days(_ n: Int) -> [(value: String, unit: String)] {
        [("\(n)", n == 1 ? "day" : "days")]
    }
}

// MARK: Home

private enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", year = "12 months", all = "All time"
    var id: String { rawValue }

    func start(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year: return calendar.date(byAdding: .month, value: -12, to: today)
        case .all: return nil
        }
    }
}

private struct HomePage: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var settings: Settings
    @AppStorage("statsPeriod") private var period: StatsPeriod = .month

    var body: some View {
        let now = Date()
        let records = history.entries.map(\.record)
        let stats = DictationStats(records: records, since: period.start(now: now), now: now)

        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        PageTitle(text: "Home")
                        Spacer()
                        Picker("Period", selection: $period) {
                            ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            StatCard(parts: [(Format.count(stats.words), "words")], caption: "Words dictated")
                            StatCard(
                                parts: Format.duration(stats.secondsSaved), caption: "Time saved",
                                note: "Compared with typing at \(Int(DictationStats.typingWordsPerMinute)) words a minute")
                        }
                        GridRow {
                            StatCard(parts: [(stats.wordsPerMinute.map(String.init) ?? "–", "WPM")], caption: "Average speaking speed")
                            StatCard(parts: Format.duration(stats.seconds), caption: "Time dictating")
                        }
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            Metric(parts: Format.days(stats.activeDays), caption: "Active days")
                            Metric(parts: Format.days(stats.currentStreak), caption: "Current streak")
                            Metric(parts: Format.days(stats.longestStreak), caption: "Longest streak")
                        }
                        ActivityHeatmap(wordsByDay: ActivityGrid.wordsByDay(records), now: now)
                    }
                    .padding(20)
                    .card()

                    if records.isEmpty {
                        Text("Hold \(settings.triggerKey.label) and speak. Your stats appear here after the first dictation.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 16) {
                    ShortcutsCard(trigger: settings.triggerKey)
                    PrivacyCard(dictations: history.entries.count, server: URL(string: settings.polishServerURL)?.host())
                }
                .frame(width: 250)
            }
            .padding(32)
        }
    }
}

private struct StatCard: View {
    let parts: [(value: String, unit: String)]
    let caption: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatValue(parts: parts)
            Text(caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
        .help(note ?? "")
    }
}

private struct Metric: View {
    let parts: [(value: String, unit: String)]
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatValue(parts: parts)
            Text(caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Words per day as a grid of squares, as many weeks as fit the width.
private struct ActivityHeatmap: View {
    let wordsByDay: [Date: Int]
    let now: Date
    private let cell: CGFloat = 13
    private let gap: CGFloat = 4
    private let labelWidth: CGFloat = 20
    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { geometry in
            let count = max(4, Int((geometry.size.width - labelWidth) / (cell + gap)))
            grid(ActivityGrid.weeks(endingAt: now, count: count))
        }
        .frame(height: 7 * (cell + gap) + 44)
    }

    private func grid(_ weeks: [[Date]]) -> some View {
        let busiest = weeks.joined().compactMap { wordsByDay[$0] }.max() ?? 0
        let today = calendar.startOfDay(for: now)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdayInitial(row)).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: labelWidth - gap, height: cell)
                    }
                }
                ForEach(weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(week, id: \.self) { day in
                            if day > today {
                                Color.clear.frame(width: cell, height: cell)
                            } else {
                                let words = wordsByDay[day] ?? 0
                                square(level: ActivityGrid.level(words: words, busiest: busiest))
                                    .help("\(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(words) words")
                            }
                        }
                    }
                }
            }
            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth - gap, height: 1)
                ForEach(weeks, id: \.self) { week in
                    Text(monthLabel(week, first: week == weeks.first)).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            HStack(spacing: 4) {
                Text("Less")
                ForEach(1...4, id: \.self) { square(level: $0) }
                Text("More")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func square(level: Int) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(level == 0 ? Color.primary.opacity(0.08) : Color.hark.opacity([0, 0.3, 0.5, 0.75, 1][level]))
            .frame(width: cell, height: cell)
    }

    private func weekdayInitial(_ row: Int) -> String {
        calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + row) % 7]
    }

    /// The month name under the week that holds its first day.
    private func monthLabel(_ week: [Date], first: Bool) -> String {
        guard let day = week.first(where: { calendar.component(.day, from: $0) == 1 }) ?? (first ? week.first : nil) else { return "" }
        return day.formatted(.dateTime.month(.abbreviated))
    }
}

private struct ShortcutsCard: View {
    let trigger: TriggerKey

    private var key: String {
        switch trigger {
        case .fn: "Fn"
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Dictate", keys: [key], hint: "hold")
            row("Hands-free", keys: [key], hint: "tap, then again to finish")
            row("Skip polish for this one", keys: ["Shift"], hint: "while dictating")
            row("Cancel", keys: ["Esc"])
            row("Paste last again", keys: ["Ctrl", "⌘", "V"])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
    }

    private func row(_ title: String, keys: [String], hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(.callout.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25)))
                }
                if let hint { Text(hint).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}

private struct PrivacyCard: View {
    let dictations: Int
    /// The polish server's host, when one is set.
    let server: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let server {
                Label("Polish via \(server)", systemImage: "network").font(.headline)
                Text("Speech and history stay on this Mac. Polished dictations go to the polish server, which may pass them to free cloud providers. Clear its URL in Settings to keep everything here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Label("On this Mac only", systemImage: "lock").font(.headline)
                Text("Speech, cleanup and history never leave this Mac. There is nothing to sign in to.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("\(dictations) dictations stored").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
    }
}

// MARK: History

private struct HistoryPage: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var settings: Settings
    @State private var query = ""
    @State private var confirmingClear = false
    private let calendar = Calendar.current
    private let retention: [(days: Int, label: String)] = [(0, "Forever"), (365, "1 year"), (90, "90 days"), (30, "30 days"), (7, "7 days")]

    var body: some View {
        let groups = groupedEntries()

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageTitle(text: "History")
                Spacer()
                Button("Clear all…", role: .destructive) { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Keep history", systemImage: "internaldrive").font(.headline)
                        Text("Older dictations are deleted from this Mac.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Keep history", selection: $settings.keepHistoryDays) {
                        ForEach(retention, id: \.days) { Text($0.label).tag($0.days) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("Text only, kept locally", systemImage: "lock").font(.headline)
                    Text("No audio is saved. History lives in ~/Library/Application Support/hark/history.jsonl; the file itself is never sent anywhere.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .card()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search dictations", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            .card(radius: 10)

            if groups.isEmpty {
                Text(history.entries.isEmpty ? "Nothing dictated yet." : "No dictations match.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    ForEach(groups, id: \.day) { group in
                        Section(header(group.day)) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry)
                                    .contextMenu {
                                        Button("Copy") { copy(entry.text) }
                                        Button("Copy as heard") { copy(entry.raw) }
                                        Divider()
                                        Button("Delete", role: .destructive) { history.remove(entry.id) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(32)
        .confirmationDialog("Delete all \(history.entries.count) dictations?", isPresented: $confirmingClear) {
            Button("Delete all", role: .destructive) { history.clear() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func groupedEntries() -> [(day: Date, entries: [HistoryStore.Entry])] {
        let matching = history.entries.reversed().filter {
            query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || ($0.app ?? "").localizedCaseInsensitiveContains(query)
        }
        return Dictionary(grouping: matching) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private func header(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    let entry: HistoryStore.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).textSelection(.enabled)
                Text([entry.app, "\(TextCleaner.wordCount(entry.text)) words"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: Dictionary

private struct DictionaryPage: View {
    @ObservedObject var settings: Settings
    @State private var term = ""
    @State private var heard = ""
    @State private var meant = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PageTitle(text: "Dictionary")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Words").font(.title2.weight(.semibold))
                    Text("Names and terms the recogniser should expect, spelled the way you want them.")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("New word, for example Modular9", text: $term).onSubmit(addTerm)
                        Button("Add", action: addTerm).disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(maxWidth: 480)
                    if settings.dictionary.isEmpty {
                        Text("No words yet.").foregroundStyle(.tertiary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(settings.dictionary, id: \.self) { word in
                                HStack {
                                    Text(word).lineLimit(1)
                                    Spacer()
                                    Button { settings.removeTerm(word) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                        .help("Remove \(word)")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .card(radius: 10)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Corrections").font(.title2.weight(.semibold))
                    Text("Words that keep being misheard. Swapped in every dictation, whole words only.")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Heard, for example tasting", text: $heard).onSubmit(addCorrection)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Meant, for example testing", text: $meant).onSubmit(addCorrection)
                        Button("Add", action: addCorrection)
                            .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty || meant.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(maxWidth: 620)
                    if settings.corrections.isEmpty {
                        Text("No corrections yet.").foregroundStyle(.tertiary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(settings.corrections.enumerated()), id: \.offset) { _, correction in
                                HStack(spacing: 12) {
                                    Text(correction.heard).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                    Text(correction.meant)
                                    Spacer()
                                    Button { settings.removeCorrection(correction) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                        .help("Remove")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .card(radius: 10)
                            }
                        }
                        .frame(maxWidth: 620)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private func addTerm() {
        settings.addTerm(term)
        term = ""
    }

    private func addCorrection() {
        guard !heard.trimmingCharacters(in: .whitespaces).isEmpty, !meant.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        settings.addCorrection(heard: heard, meant: meant)
        heard = ""
        meant = ""
    }
}

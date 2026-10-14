import Foundation
import Testing
@testable import HarkCore

@Suite struct HotkeyStateMachineTests {
    @Test func holdAndReleaseFinishes() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.triggerDown, at: 0) == .start)
        #expect(machine.isRecording)
        #expect(machine.handle(.triggerUp, at: 1.0) == .finish)
        #expect(!machine.isRecording)
    }

    @Test func tapTogglesHandsFree() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.triggerDown, at: 0) == .start)
        #expect(machine.handle(.triggerUp, at: 0.1) == .lock)
        #expect(machine.isRecording)
        #expect(machine.handle(.triggerDown, at: 5) == .finish)
        #expect(machine.handle(.triggerUp, at: 5.1) == .none)
        #expect(!machine.isRecording)
    }

    @Test func holdJustPastTheTapLimitFinishes() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        #expect(machine.handle(.triggerUp, at: machine.tapLimit + 0.01) == .finish)
    }

    @Test func lockKeepsRecordingAfterRelease() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        #expect(machine.handle(.lockKeyDown, at: 0.05) == .lock)
        #expect(machine.handle(.triggerUp, at: 0.1) == .none)
        #expect(machine.isRecording)
        #expect(machine.handle(.triggerDown, at: 5) == .finish)
        #expect(machine.handle(.triggerUp, at: 5.1) == .none)
        #expect(!machine.isRecording)
    }

    @Test func escapeCancelsInBothModes() {
        var held = HotkeyStateMachine()
        _ = held.handle(.triggerDown, at: 0)
        #expect(held.handle(.cancelKeyDown, at: 1) == .cancel)
        #expect(held.handle(.triggerUp, at: 2) == .none)

        var locked = HotkeyStateMachine()
        _ = locked.handle(.triggerDown, at: 0)
        _ = locked.handle(.lockKeyDown, at: 0.1)
        #expect(locked.handle(.cancelKeyDown, at: 1) == .cancel)
    }

    @Test func usingTriggerAsModifierCancels() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        #expect(machine.handle(.otherKeyDown, at: 0.5) == .cancel)
    }

    @Test func idleIgnoresStrayEvents() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.triggerUp, at: 0) == .none)
        #expect(machine.handle(.lockKeyDown, at: 0) == .none)
        #expect(machine.handle(.cancelKeyDown, at: 0) == .none)
    }
}

@Suite struct TextCleanerTests {
    @Test func correctionsSwapWholeWordsAndKeepCapitals() {
        let corrections = TextCleaner.corrections(from: "tasting = testing\nnot a pair\n sequel=SQL \n = nothing\n")
        #expect(corrections == [.init(heard: "tasting", meant: "testing"), .init(heard: "sequel", meant: "SQL")])
        #expect(
            TextCleaner.apply(corrections, to: "Tasting, tasting hands-free. No pretasting or tastings.")
                == "Testing, testing hands-free. No pretasting or tastings.")
        #expect(TextCleaner.apply(corrections, to: "I use Sequel daily") == "I use SQL daily")
        #expect(TextCleaner.apply([], to: "unchanged") == "unchanged")
    }

    @Test func removesFillers() {
        #expect(TextCleaner.clean("Um, so I think, uh, we should ship it.") == "So I think, we should ship it.")
        #expect(TextCleaner.clean("hmm let me check") == "Let me check")
    }

    @Test func keepsWordsThatContainFillerLetters() {
        #expect(TextCleaner.clean("The summer umbrella is under the drum.") == "The summer umbrella is under the drum.")
    }

    @Test func collapsesStutters() {
        #expect(TextCleaner.clean("I I think the the plan works") == "I think the plan works")
        #expect(TextCleaner.clean("He had had enough") == "He had had enough")
    }

    @Test func tidiesSpacingAndCapitals() {
        #expect(TextCleaner.clean("  hello there .  how are you ?") == "Hello there. How are you?")
    }

    @Test func emptyStaysEmpty() {
        #expect(TextCleaner.clean("um uh") == "")
    }

    @Test func plausibilityAcceptsCleanupAndSelfCorrection() {
        let original = "let's meet on Tuesday no wait Wednesday at three in the afternoon"
        #expect(TextCleaner.isPlausibleRefinement(original: original, refined: "Let's meet on Wednesday at three in the afternoon."))
    }

    @Test func plausibilityRejectsAnswersAndEmptyOutput() {
        let original = "what is the capital of France"
        let answer = "The capital of France is Paris, a city on the Seine known for the Eiffel Tower and the Louvre."
        #expect(!TextCleaner.isPlausibleRefinement(original: original, refined: answer))
        #expect(!TextCleaner.isPlausibleRefinement(original: original, refined: ""))
        // Same length as the dictation, but made of words the speaker never said.
        let question = "hey can you tell me what the capital of France is and also how far it is from London by train"
        let reply = "Sure, the capital of France is Paris. It's about 2 hours and 15 minutes by train from London."
        #expect(!TextCleaner.isPlausibleRefinement(original: question, refined: reply))
        #expect(!TextCleaner.isPlausibleRefinement(original: "one two three four five six seven eight nine ten", refined: "Summary."))
    }
}

@Suite struct DictationStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Johannesburg")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// Noon on the given day of October 2026 (the 14th is a Wednesday).
    private func day(_ number: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: hour))!
    }

    @Test func totalsSpeedAndTimeSaved() {
        let stats = DictationStats(
            records: [.init(date: day(13), words: 100, seconds: 30), .init(date: day(14), words: 50, seconds: 30)],
            now: day(14), calendar: calendar)
        #expect(stats.words == 150)
        #expect(stats.dictations == 2)
        #expect(stats.wordsPerMinute == 150)
        // 150 words typed at 40 WPM is 225 s; speaking took 60 s.
        #expect(stats.secondsSaved == 165)
        #expect(stats.activeDays == 2)
    }

    @Test func emptyHistoryHasNoSpeedAndNothingSaved() {
        let stats = DictationStats(records: [], now: day(14), calendar: calendar)
        #expect(stats.wordsPerMinute == nil)
        #expect(stats.secondsSaved == 0)
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 0)
    }

    @Test func slowDictationNeverSavesNegativeTime() {
        let stats = DictationStats(records: [.init(date: day(14), words: 5, seconds: 60)], now: day(14), calendar: calendar)
        #expect(stats.secondsSaved == 0)
    }

    @Test func periodLimitsTotalsButNotStreaks() {
        let records: [DictationRecord] = [1, 2, 3, 12, 13, 14].map { .init(date: day($0), words: 10, seconds: 5) }
        let stats = DictationStats(records: records, since: day(12, hour: 0), now: day(14), calendar: calendar)
        #expect(stats.words == 30)
        #expect(stats.activeDays == 3)
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 3)
    }

    @Test func streakSurvivesUntilTodaysFirstDictation() {
        let records: [DictationRecord] = [11, 12, 13].map { .init(date: day($0), words: 1, seconds: 1) }
        #expect(DictationStats(records: records, now: day(14, hour: 8), calendar: calendar).currentStreak == 3)
        #expect(DictationStats(records: records, now: day(15), calendar: calendar).currentStreak == 0)
    }

    @Test func severalDictationsOnOneDayCountOnce() {
        let records: [DictationRecord] = [8, 12, 18].map { .init(date: day(14, hour: $0), words: 1, seconds: 1) }
        let stats = DictationStats(records: records, now: day(14), calendar: calendar)
        #expect(stats.activeDays == 1)
        #expect(stats.longestStreak == 1)
        #expect(ActivityGrid.wordsByDay(records, calendar: calendar) == [calendar.startOfDay(for: day(14)): 3])
    }

    @Test func gridEndsWithTheCurrentWeekStartingOnSunday() {
        let weeks = ActivityGrid.weeks(endingAt: day(14), count: 3, calendar: calendar)
        #expect(weeks.count == 3)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.last?.first == calendar.startOfDay(for: day(11)))
        #expect(weeks.first?.first == calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: day(11))))
    }

    @Test func levelsScaleToTheBusiestDay() {
        #expect(ActivityGrid.level(words: 0, busiest: 100) == 0)
        #expect(ActivityGrid.level(words: 1, busiest: 100) == 1)
        #expect(ActivityGrid.level(words: 50, busiest: 100) == 2)
        #expect(ActivityGrid.level(words: 100, busiest: 100) == 4)
    }
}

@Suite struct HesitationTests {
    @Test func repeatedPhrasesCollapse() {
        #expect(TextCleaner.clean("so I'm going to I'm going to look at it after lunch") == "So I'm going to look at it after lunch")
        #expect(TextCleaner.clean("I think we should we should probably move it") == "I think we should probably move it")
        #expect(TextCleaner.clean("He had had enough") == "He had had enough")
    }

    @Test func ahIsAFillerOnlyOnItsOwn() {
        #expect(TextCleaner.clean("ah jeez it's broken") == "Jeez it's broken")
        #expect(TextCleaner.clean("Utah is ahead, aha") == "Utah is ahead, aha")
    }

    @Test func youKnowGoesOnlyWhenItIsFiller() {
        #expect(TextCleaner.clean("we should probably you know move the meeting") == "We should probably move the meeting")
        #expect(TextCleaner.clean("it was, you know, fine") == "It was fine")
        #expect(TextCleaner.clean("do you know where it is") == "Do you know where it is")
        #expect(TextCleaner.clean("you know the answer") == "You know the answer")
        #expect(TextCleaner.clean("if you know what I mean") == "If you know what I mean")
    }

    @Test func plausibilityAcceptsHeavySelfCorrection() {
        let original = "So I need to go to this website wait sorry its its jeez its an email in my gmail oh no wait sorry it's a conversation in whatsapp"
        #expect(TextCleaner.isPlausibleRefinement(original: original, refined: "I need to go to a conversation in WhatsApp."))
        // Without anything taken back, the same shrink still looks like a summary.
        let plain = "please book the room on the third floor for the whole team from nine until twelve on Thursday and order coffee and lunch for twelve people"
        #expect(!TextCleaner.isPlausibleRefinement(original: plain, refined: "Book the room on Thursday."))
    }
}

@Suite struct ChimeTests {
    @Test func wavHeaderMatchesTheSamples() {
        let data = Chime.wav(Chime.start)
        let samples = Chime.samples(Chime.start)
        #expect(data.count == 44 + samples.count * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(samples.count == Chime.start.reduce(0) { $0 + Int($1.seconds * Double(Chime.sampleRate)) })
    }

    @Test func staysQuietAndStartsAndEndsSoftly() {
        for notes in [Chime.start, Chime.finish] {
            let samples = Chime.samples(notes)
            let peak = samples.map { abs(Int($0)) }.max() ?? 0
            #expect(peak <= Int(0.12 * Double(Int16.max)) + 1)
            #expect(abs(Int(samples.first!)) < 100)
            #expect(abs(Int(samples.last!)) < Int(0.12 * Double(Int16.max) * 0.05))
        }
    }
}

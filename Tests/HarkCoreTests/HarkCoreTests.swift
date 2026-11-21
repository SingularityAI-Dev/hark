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

    @Test func plausibilityAcceptsSpokenFormattingInstructions() {
        let heard = "see if you can register single source studios single source one word single stores AI single source one word but with capital S and"
        #expect(TextCleaner.isPlausibleRefinement(original: heard, refined: "See if you can register SingleSource Studios and SingleSource AI."))
        #expect(TextCleaner.isPlausibleRefinement(original: "the client is data lineage one word all lowercase dot AI", refined: "The client is datalineage.ai."))
        // Joining words the speaker never said in sequence is still an invention.
        #expect(!TextCleaner.isPlausibleRefinement(original: "book the room for the whole team on Thursday", refined: "Book Teamroom Wholething Thursday."))
    }

    @Test func plausibilityAcceptsAWordSwappedWithNo() {
        let heard = "can you pull that from bookings no or bookings or applications at IDSA on it"
        #expect(TextCleaner.isPlausibleRefinement(original: heard, refined: "Can you pull that from applications at IDSA on it?"))
        #expect(TextCleaner.isPlausibleRefinement(original: "the meeting is on monday no tuesday at ten", refined: "The meeting is on Tuesday at ten."))
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

@Suite struct RepairTests {
    @Test func acceptsARepairOfMisheardWords() {
        let heard = "we need to go over the hole operation of agents"
        let repaired = "We need to review the whole operation of all agents."
        #expect(TextCleaner.isPlausibleRefinement(original: heard, refined: repaired))
    }

    @Test func stillRefusesAnswersAndSummaries() {
        let question = "what is the weather going to be like tomorrow in Durban"
        let answer = "It will be sunny with a high of twenty six degrees and a light breeze from the sea."
        #expect(!TextCleaner.isPlausibleRefinement(original: question, refined: answer))
        let long = "please book the room on the third floor for the whole team from nine until twelve on Thursday and order coffee and lunch for twelve people"
        #expect(!TextCleaner.isPlausibleRefinement(original: long, refined: "Book a room."))
    }
}

@Suite struct PolishTraceTests {
    @Test func roundTripsAndEncodesEnumsAsStrings() throws {
        let trace = PolishTrace(
            entryID: UUID(), winner: .server, skipped: nil, shiftFlipped: true, totalMilliseconds: 1200,
            contenders: [.init(name: "server", outcome: .answered, milliseconds: 1100),
                         .init(name: "on-device", outcome: .notStarted, milliseconds: 0)],
            serverModel: "gpt-oss-20b", transcribeMilliseconds: 300)
        let data = try JSONEncoder().encode(trace)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"winner\":\"server\""))
        #expect(json.contains("\"outcome\":\"answered\""))
        #expect(try JSONDecoder().decode(PolishTrace.self, from: data) == trace)
    }

    @Test func aLineMissingOptionalFieldsDecodesWithDefaults() throws {
        let id = UUID()
        let line = #"{"entryID":"\#(id.uuidString)","winner":"rules","contenders":[{"name":"server","outcome":"deadline"}]}"#
        let trace = try JSONDecoder().decode(PolishTrace.self, from: Data(line.utf8))
        #expect(trace.entryID == id)
        #expect(trace.winner == .rules)
        #expect(trace.contenders.first?.outcome == .deadline)
        #expect(trace.contenders.first?.milliseconds == 0)
        #expect(!trace.late && !trace.orphanInFlight && !trace.shiftFlipped)
        #expect(trace.learnedIDs.isEmpty)
        #expect(trace.skipped == nil)
    }

    @Test func refusesALineWithoutTheRequiredFields() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PolishTrace.self, from: Data(#"{"winner":"rules"}"#.utf8)) }
    }
}

@Suite struct PlausibilityReasonTests {
    @Test func namesEachFailure() {
        #expect(TextCleaner.plausibilityFailure(original: "one two three", refined: "") == "empty")
        #expect(TextCleaner.plausibilityFailure(
            original: "please book the room on the third floor for the whole team from nine until twelve",
            refined: "Book a room.") == "too short")
        #expect(TextCleaner.plausibilityFailure(
            original: "call me", refined: "Please call me back as soon as you possibly can today, thanks.") == "too long")
        #expect(TextCleaner.plausibilityFailure(
            original: "what is the capital of France and how far is it from London",
            refined: "Paris is the capital and London is two hours away by fast train.") == "too few spoken words")
    }

    @Test func passesWhatTheBoolGuardPasses() {
        let original = "let's meet on Tuesday no wait Wednesday at three in the afternoon"
        let refined = "Let's meet on Wednesday at three in the afternoon."
        #expect(TextCleaner.plausibilityFailure(original: original, refined: refined) == nil)
        #expect(TextCleaner.isPlausibleRefinement(original: original, refined: refined))
    }

    @Test func spokenWordsIncludeJoinedRuns() {
        let spoken = TextCleaner.spokenWords("single source one word")
        #expect(spoken.contains("singlesource"))
        #expect(spoken.contains("sourceoneword"))
        #expect(!spoken.contains("singleword"))
    }

    @Test func recognisesFillers() {
        #expect(TextCleaner.isFiller("um"))
        #expect(TextCleaner.isFiller("#Ah,"))
        #expect(TextCleaner.isFiller("like"))
        #expect(!TextCleaner.isFiller("umbrella"))
        #expect(!TextCleaner.isFiller("aha"))
    }
}

@Suite struct DictationSnapshotTests {
    @Test func decodesTheExampleAndParsesCorrections() throws {
        let json = #"{"dictionary":["SingleSource"],"correctionsText":"tasting = testing","polishServerURL":null,"polishServerModel":null}"#
        let snapshot = try JSONDecoder().decode(DictationSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.dictionary == ["SingleSource"])
        #expect(snapshot.corrections == [.init(heard: "tasting", meant: "testing")])
        #expect(snapshot.polishServerURL == nil)
    }

    @Test func splitsDictionaryTextLikeSettings() {
        let snapshot = DictationSnapshot(dictionaryText: " Ruen \n\nZernio\n", correctionsText: "", polishServerURL: nil, polishServerModel: nil)
        #expect(snapshot.dictionary == ["Ruen", "Zernio"])
    }

    @Test func toleratesMissingFields() throws {
        let snapshot = try JSONDecoder().decode(DictationSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot.dictionary.isEmpty && snapshot.correctionsText.isEmpty)
    }
}

@Suite struct EditDistanceTests {
    @Test func countsEdits() {
        #expect(editDistance("ruin", "ruen") == 1)
        #expect(editDistance("elser", "elsa") == 2)
        #expect(editDistance("", "abc") == 3)
        #expect(editDistance(["a", "b"], ["a", "b"]) == 0)
    }

    @Test func alignsCommonSubsequence() {
        let pairs = longestCommonSubsequence(["a", "x", "b", "c"], ["a", "b", "y", "c"])
        #expect(pairs.map { $0.0 } == [0, 2, 3])
        #expect(pairs.map { $0.1 } == [0, 1, 3])
        #expect(longestCommonSubsequence([Int](), [1]).isEmpty)
    }
}

@Suite struct NearCopyTests {
    let pasted = "Ask Elser to send the forms before Friday."

    @Test func unchangedWhenTheTextIsStillThere() {
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "notes here. Ask Elser to send the forms before Friday. And then") == .unchanged)
    }

    @Test func countsOneAndTwoChangedWords() {
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "Ask Elsa to send the forms before Friday.") == .changed(count: 1))
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "Ask Elsa to send the forms before Thursday.") == .changed(count: 2))
    }

    @Test func threeChangesOrGoneIsDifferent() {
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "Ask Elsa to post the forms before Thursday.") == .different)
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "") == .different)
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "something else entirely was typed here") == .different)
    }

    @Test func earlierTextSharingWordsIsNotAnEdit() {
        #expect(EditDiff.nearCopy(pasted: "I think it's fine.", readBack: "I think we should go. I think it's fine.") == .unchanged)
        #expect(EditDiff.nearCopy(pasted: "The meeting is on Tuesday.", readBack: "Send it to the team. The meeting is on Tuesday.") == .unchanged)
        #expect(EditDiff.nearCopy(pasted: "The meeting is on Tuesday.", readBack: "Send it to the team. The meeting is on Thursday.") == .changed(count: 1))
    }

    @Test func cutWordsAtTheWindowEdgesAreIgnored() {
        #expect(EditDiff.nearCopy(pasted: pasted, readBack: "ffee later. Ask Elser to send the forms before Friday. Then we mee") == .unchanged)
    }
}

@Suite struct EditPairsTests {
    func pairs(_ pasted: String, _ readBack: String) -> [EditPairs.Pair]? {
        if case .pairs(let pairs, _) = EditPairs.align(pasted: pasted, readBack: readBack) { return pairs }
        return nil
    }

    @Test func oneFixedWordIsOnePair() {
        let result = EditPairs.align(
            pasted: "Send the forms to brine bakeries", readBack: "Send the forms to Bryne bakeries")
        let pair = EditPairs.Pair(heard: "brine", meant: "Bryne", caseOnly: false, wordIndex: 4, atSentenceStart: false)
        #expect(result == .pairs([pair], line: "Send the forms to Bryne bakeries"))
    }

    @Test func capitalsOnlyIsMarkedCaseOnly() {
        let found = pairs("ask bakeries for the forms", "ask Bakeries for the forms")
        #expect(found?.count == 1)
        #expect(found?.first?.caseOnly == true)
    }

    @Test func twoFixedWordsAreTwoPairs() {
        let found = pairs("Ask Elser to send the forms before Friday.", "Ask Elsa to send the forms before Thursday.")
        #expect(found?.map(\.meant) == ["Elsa", "Thursday"])
    }

    @Test func shortDictationsNeedTwoWords() {
        #expect(pairs("brine bakeries", "Bryne bakeries")?.first?.meant == "Bryne")
        #expect(EditPairs.align(pasted: "brine", readBack: "Bryne") == .different)
    }

    @Test func anInsertionIsDifferent() {
        #expect(EditPairs.align(pasted: "Ask Elser to send the forms", readBack: "Ask Elser to send out the forms") == .different)
    }

    @Test func aWordSplitAcrossRowsStillMatches() {
        #expect(EditPairs.align(pasted: "Send the forms to Bryne bakeries", readBack: "Send the forms to Bry\nne bakeries") == .unchanged)
        #expect(pairs("Send the forms to brine bakeries", "Send the forms to Bry\nne bakeries")?.first?.meant == "Bryne")
    }

    @Test func fewestChangesBeatsRightmostAndRightmostBreaksATie() {
        #expect(EditPairs.align(
            pasted: "meet me at noon tomorrow", readBack: "meet me at noon tomorrow\nmeet me at noon today") == .unchanged)
        #expect(pairs(
            "ask Elser to send the forms", "ask Elsa to send the forms\nask Elsy to send the forms")?.first?.meant == "Elsy")
    }

    @Test func shortPastesNeedExactNeighbours() {
        #expect(EditPairs.align(pasted: "send forms", readBack: "the forms") == .different)
        #expect(pairs("send the forms now", "send a forms now")?.first?.meant == "a")
        #expect(EditPairs.align(pasted: "send the forms now", readBack: "give a forms now") == .different)
    }

    @Test func bordersAndPromptsAreStripped() {
        let result = EditPairs.align(
            pasted: "Send the forms to brine bakeries", readBack: "\u{2502} > Send the forms to Bryne bakeries \u{2502}")
        guard case .pairs(let found, let line) = result else { Issue.record("expected pairs"); return }
        #expect(found.first?.meant == "Bryne")
        #expect(line == "Send the forms to Bryne bakeries")
    }

    @Test func sentenceStartsAreFlagged() {
        let tokens = EditPairs.tokens(rows: ["one two. three four! five six? seven", "eight nine"], joinRows: false)
        #expect(tokens.map(\.sentenceStart) == [true, false, true, false, true, false, true, true, false])
    }
}

@Suite struct LearnFilterTests {
    let dictionary: Set<String> = [
        "brine", "ruin", "then", "than", "monday", "sunday", "will", "bill", "tuesday", "wednesday",
        "bakeries", "send", "the", "forms", "make", "sure", "gets",
    ]
    func isWord(_ word: String) -> Bool { dictionary.contains(word.lowercased()) }

    func judge(
        _ heard: String, _ meant: String, caseOnly: Bool = false, start: Bool = false,
        raw: String? = nil, line: String = "send the forms", learned: [LearnedEntry] = []
    ) -> LearnFilter.Verdict {
        let pair = EditPairs.Pair(heard: heard, meant: meant, caseOnly: caseOnly, wordIndex: 2, atSentenceStart: start)
        return LearnFilter.judge(
            pair: pair, raw: raw ?? "send the forms to \(heard.lowercased()) bakeries", line: line,
            isWord: isWord, learned: learned)
    }

    @Test func learnsAtOnceOrWaits() {
        #expect(judge("brine", "Bryne") == .learnNow)
        #expect(judge("ruin", "Ruen") == .learnNow)
        #expect(judge("ruin", "ruen") == .waitForSecond)
        #expect(judge("brine", "Bryne", start: true) == .waitForSecond)
    }

    @Test func codeIsRejected() {
        #expect(judge("brine", "Bryne", line: "git commit -m foo_bar") == .reject(.code))
        #expect(judge("brine", "Bry/ne") == .reject(.code))
        #expect(judge("brine", "Bryne", line: "$ ls") == .reject(.code))
        #expect(judge("brine", "Bryne", line: "Make sure Bryne gets the forms") == .learnNow)
    }

    @Test func shapeRules() {
        #expect(judge("ab", "abc") == .reject(.tooShort))
        #expect(judge("brine1", "Bryne1") == .reject(.notLetters))
        #expect(judge("brine", "Bryne", raw: "send the forms") == .reject(.notInRaw))
        #expect(judge("Tuesday", "Wednesday") == .reject(.tooFar))
        #expect(judge("bakeries", "Bakeries", caseOnly: true) == .reject(.caseOnly))
    }

    @Test func rewordingsAreRejected() {
        #expect(judge("then", "than") == .reject(.rewording))
        #expect(judge("Monday", "Sunday") == .reject(.rewording))
        #expect(judge("will", "Bill") == .reject(.rewording))
        #expect(judge("Then", "Than", start: true, raw: "then we left") == .reject(.rewording))
    }

    @Test func tombstonesAndChains() {
        let removed = LearnedEntry(heard: "brine", meant: "Bryne", state: .removed)
        #expect(judge("brine", "Bryne", learned: [removed]) == .reject(.tombstoned))
        let active = LearnedEntry(heard: "brine", meant: "Bryne", state: .active)
        #expect(judge("Bryne", "Bryna", raw: "send bryne forms", learned: [active]) == .reject(.chain))
        #expect(judge("Bryne", "Bryna", raw: "send bryne forms", learned: [removed]) != .reject(.chain))
    }

    @Test func withNothingLearnedNeitherCanHappen() {
        for (heard, meant) in [("brine", "Bryne"), ("ruin", "ruen"), ("then", "than"), ("Bryne", "Bryna")] {
            let verdict = judge(heard, meant, raw: "\(heard) \(meant)".lowercased())
            #expect(verdict != .reject(.tombstoned) && verdict != .reject(.chain))
        }
    }
}

@Suite struct LearnedTests {
    let rule = LearnedRule(id: UUID(), heard: "brine", meant: "Bryne")

    @Test func aSecondSightingNeedsANewHistoryID() {
        var entries: [LearnedEntry] = []
        let first = UUID(), second = UUID()
        #expect(LearnedFile.recordSighting(heard: "ruin", meant: "ruen", app: "t", historyID: first, learnNow: false, in: &entries) == .created(.pending))
        #expect(LearnedFile.recordSighting(heard: "ruin", meant: "ruen", app: "t", historyID: first, learnNow: false, in: &entries) == .duplicate)
        #expect(entries.first?.state == .pending)
        #expect(LearnedFile.recordSighting(heard: "Ruin", meant: "ruen", app: "t", historyID: second, learnNow: false, in: &entries) == .promoted)
        #expect(entries.count == 1 && entries[0].state == .active && entries[0].sightings == 2)
    }

    @Test func removedBlocksANewSighting() {
        var entries: [LearnedEntry] = []
        LearnedFile.recordSighting(heard: "brine", meant: "Bryne", app: "t", historyID: UUID(), learnNow: true, in: &entries)
        LearnedFile.markRemoved(id: entries[0].id, in: &entries)
        #expect(LearnedFile.recordSighting(heard: "brine", meant: "Bryne", app: "t", historyID: UUID(), learnNow: true, in: &entries) == .blocked)
        #expect(LearnedFile.active(entries).isEmpty)
    }

    @Test func correctionsWinAndCapitalsAreKept() {
        let hand = TextCleaner.Correction(heard: "brine", meant: "Brianna")
        let won = Learned.apply([rule], corrections: [hand], to: "send brine bakeries")
        #expect(won.text == "send Brianna bakeries" && won.appliedIDs.isEmpty)
        let kept = Learned.apply([rule], corrections: [], to: "Brine bakeries")
        #expect(kept.text == "Bryne bakeries" && kept.appliedIDs == [rule.id])
    }

    @Test func appliedIDsListOnlyRulesThatChangedTheText() {
        let other = LearnedRule(id: UUID(), heard: "ruin", meant: "Ruen")
        #expect(Learned.apply([rule, other], corrections: [], to: "ask ruin").appliedIDs == [other.id])
    }

    @Test func capAndExpiry() {
        let now = Date()
        var entries = (0..<201).map {
            LearnedEntry(heard: "word\($0)", meant: "Meant\($0)", state: .active, lastSeen: now.addingTimeInterval(Double($0)))
        }
        entries.append(LearnedEntry(heard: "old", meant: "Old", state: .pending, lastSeen: now.addingTimeInterval(-31 * 86400)))
        entries.append(LearnedEntry(heard: "new", meant: "New", state: .pending, lastSeen: now.addingTimeInterval(-29 * 86400)))
        let pruned = LearnedFile.pruned(entries, now: now.addingTimeInterval(202))
        #expect(LearnedFile.active(pruned).count == 200)
        #expect(!pruned.contains { $0.heard == "word0" })
        #expect(pruned.contains { $0.heard == "new" } && !pruned.contains { $0.heard == "old" })
    }

    @Test func loadOfMissingOrCorruptFileIsEmpty() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("learned.json")
        #expect(LearnedFile.load(url).isEmpty)
        try Data("not json".utf8).write(to: url)
        #expect(LearnedFile.load(url).isEmpty)
        let entry = LearnedEntry(heard: "brine", meant: "Bryne", state: .active, historyIDs: [UUID()])
        try LearnedFile.save([entry], to: url)
        #expect(LearnedFile.load(url).map(\.heard) == ["brine"])
    }
}

@Suite struct WordsAfterBestStretchTests {
    @Test func countsTheWordsAfterTheLaterBestStretch() {
        #expect(EditDiff.wordsAfterBestStretch(pasted: "send the forms", readBack: "send the forms") == 0)
        #expect(EditDiff.wordsAfterBestStretch(pasted: "send the forms", readBack: "send the forms\nsend the forms\nready now ok") == 3)
        #expect(EditDiff.wordsAfterBestStretch(pasted: "send the forms", readBack: "") == nil)
    }
}

@Suite struct ScreenTailTests {
    @Test func paddingIsSqueezedSoMoreRowsFit() {
        let row = "line" + String(repeating: " ", count: 180)
        let text = String(repeating: row + "\n", count: 40) + "Ask Ruan to send it."
        #expect(EditPairs.screenTail(text, limit: 2000).contains("Ask Ruan to send it."))
        #expect(EditPairs.screenTail(text, limit: 2000).components(separatedBy: "line").count > 30)
    }

    @Test func shortTextIsKeptWhole() {
        #expect(EditPairs.screenTail("a   b  c", limit: 2000) == "a b c")
    }

    @Test func tailKeepsTheEnd() {
        #expect(EditPairs.screenTail("abcdef", limit: 3) == "def")
    }
}

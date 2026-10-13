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

    @Test func accidentalTapCancels() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        #expect(machine.handle(.triggerUp, at: 0.1) == .cancel)
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

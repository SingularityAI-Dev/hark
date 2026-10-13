import Foundation

/// Turns raw trigger-key events into dictation actions.
///
/// Hold the trigger to dictate until release. Press the lock key while holding to keep
/// recording hands-free; the next trigger press ends it.
public struct HotkeyStateMachine {
    public enum Event: Equatable {
        case triggerDown, triggerUp
        /// Lock key pressed while the trigger is held.
        case lockKeyDown
        case cancelKeyDown
        /// Any other key pressed while the trigger is held, meaning the trigger is being
        /// used as an ordinary modifier.
        case otherKeyDown
    }

    public enum Action: Equatable {
        case start, lock, finish, cancel, none
    }

    public enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case locked
    }

    public private(set) var state: State = .idle
    /// A hold shorter than this is treated as an accidental tap.
    public var minimumHold: TimeInterval = 0.25

    public init() {}

    public var isRecording: Bool { state != .idle }

    public mutating func handle(_ event: Event, at time: TimeInterval) -> Action {
        switch (state, event) {
        case (.idle, .triggerDown):
            state = .holding(since: time)
            return .start
        case (.holding(let since), .triggerUp):
            state = .idle
            return time - since < minimumHold ? .cancel : .finish
        case (.holding, .lockKeyDown):
            state = .locked
            return .lock
        case (.holding, .otherKeyDown), (.holding, .cancelKeyDown), (.locked, .cancelKeyDown):
            state = .idle
            return .cancel
        case (.locked, .triggerDown):
            state = .idle
            return .finish
        default:
            return .none
        }
    }
}

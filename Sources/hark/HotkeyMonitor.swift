import CoreGraphics
import Foundation
import HarkCore

/// Watches the keyboard through an event tap and reports dictation actions.
/// Needs the Accessibility permission; `start()` returns false until it is granted.
final class HotkeyMonitor {
    var onAction: (@MainActor (HotkeyStateMachine.Action) -> Void)?
    var onPasteLast: (@MainActor () -> Void)?
    var onPolishRequested: (@MainActor () -> Void)?
    /// Set when Shift is pressed during a recording; cleared when the next one starts.
    private(set) var polishRequested = false
    var trigger: TriggerKey = .fn

    private var machine = HotkeyStateMachine()
    private var tap: CFMachPort?
    private var triggerDown = false
    private var swallowLockKeyUp = false

    private static let lockKey: CGKeyCode = 49  // Space
    private static let cancelKey: CGKeyCode = 53  // Escape
    private static let pasteKey: CGKeyCode = 9  // V
    private static let shiftKeys: Set<CGKeyCode> = [56, 60]

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let events: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Returns true when the event should be hidden from the focused app.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS switches a slow tap off; without this the hotkey silently dies.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            if Self.shiftKeys.contains(keyCode), event.flags.contains(.maskShift),
                machine.isRecording, !polishRequested
            {
                polishRequested = true
                MainActor.assumeIsolated { onPolishRequested?() }
                return false
            }
            guard keyCode == trigger.keyCode else { return false }
            let down = event.flags.contains(trigger.flag)
            guard down != triggerDown else { return false }
            triggerDown = down
            let action = machine.handle(down ? .triggerDown : .triggerUp, at: now)
            if action == .start { polishRequested = false }
            send(action)
            return false

        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if keyCode == Self.lockKey, swallowLockKeyUp { return true }
            if isRepeat { return false }
            let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if keyCode == Self.pasteKey, modifiers == [.maskCommand, .maskControl] {
                MainActor.assumeIsolated { onPasteLast?() }
                return true
            }
            guard machine.isRecording else { return false }
            if keyCode == Self.cancelKey {
                send(machine.handle(.cancelKeyDown, at: now))
                return true
            }
            guard triggerDown else { return false }
            if keyCode == Self.lockKey {
                swallowLockKeyUp = true
                send(machine.handle(.lockKeyDown, at: now))
                return true
            }
            send(machine.handle(.otherKeyDown, at: now))
            return false

        case .keyUp:
            if keyCode == Self.lockKey, swallowLockKeyUp {
                swallowLockKeyUp = false
                return true
            }
            return false

        default:
            return false
        }
    }

    private func send(_ action: HotkeyStateMachine.Action) {
        guard action != .none else { return }
        // The tap's run loop source is on the main run loop, so this is the main thread.
        MainActor.assumeIsolated { onAction?(action) }
    }
}

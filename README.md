# hark

Hold a key, speak, release: your words are typed into whatever app has the cursor.
A small macOS menu bar app. Speech recognition and cleanup both run on the Mac, so it is
free to use and nothing leaves the machine. Personal tool for two people; not for
distribution.

## Requirements

- Apple silicon Mac on macOS 26 or later.
- Xcode or the Xcode Command Line Tools (`xcode-select --install`).
- Optional: Apple Intelligence switched on, for the "polish" feature.

## Install

```sh
git clone <this repo> hark    # or copy the folder
cd hark
make install
```

`make install` builds the app, puts it in `/Applications/hark.app` and starts it. A
microphone icon appears in the menu bar. Then:

1. Allow **Microphone** when macOS asks.
2. Allow **Accessibility** when macOS asks (System Settings > Privacy & Security >
   Accessibility). The hotkey and the paste both need it. hark picks the grant up within
   two seconds, no restart needed.
3. If you use the Fn key as the trigger: System Settings > Keyboard > "Press 🌐 key to" >
   **Do Nothing**, so macOS does not open the emoji picker as well.

Check what this Mac supports at any time:

```sh
/Applications/hark.app/Contents/MacOS/hark --doctor
```

## Use

| Action | Keys |
| --- | --- |
| Dictate | Hold **Fn**, speak, release |
| Hands-free | While holding Fn, tap **Space**. Press Fn again to finish |
| Polish this one | Tap **Shift** while dictating |
| Cancel | **Esc** |
| Paste the last result again | **Ctrl+Cmd+V** |

The trigger key, language, microphone and personal dictionary are in the menu bar icon >
Settings. The menu also lists the last five dictations; click one to copy it.

### Cleanup

Every dictation gets instant cleanup: filler sounds ("um", "uh") and stutters are removed
and sentence capitals are fixed. Polishing adds Apple's on-device language model, which
also resolves self-corrections ("Tuesday, no, Wednesday") and repairs punctuation. It is
opt-in because on an M1 it takes 1 to 8 seconds per dictation. If the model's answer does
not look like a cleaned-up version of what you said, hark ignores it and uses the instant
cleanup.

## Develop

```sh
make test      # unit tests for the hotkey logic and the cleanup rules
make verify    # synthesises a sentence, transcribes it, compares the words
make app       # builds build/hark.app without installing
```

`make` signs with your Apple Development certificate when you have one, so macOS keeps
the permission grants across rebuilds. Without one it signs ad hoc, which works but asks
for Microphone and Accessibility again after each rebuild.

Layout:

- `Sources/HarkCore`: pure logic (hotkey state machine, rule-based cleanup), unit tested.
- `Sources/hark`: the app (event tap, audio capture, Apple speech, cleanup model, paste,
  indicator, settings, history).
- `docs/findings.md`: what was learned from studying Typeless and what hark does instead.

Data lives in `~/Library/Application Support/hark/history.jsonl` (text only) and in the
app's preferences. Delete both to reset.

## Limits

- Needs macOS 26 for Apple's on-device speech recogniser. There is no fallback engine yet;
  `Transcriber` in `Sources/hark/Transcriber.swift` is the place to add one.
- Languages are whatever Apple's recogniser supports (30 locales, including `en-ZA`).
- Insertion is a paste, so apps that block pasting will not receive text.
- Password fields: macOS hides key events there, so the hotkey does not fire.

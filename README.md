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
3. Nothing to do for the Fn key: `make install` sets System Settings > Keyboard >
   "Press 🌐 key to" to **Do Nothing**, because otherwise Fn also opens the emoji picker
   and your words land in its search field. The picker stays on Ctrl+Cmd+Space. To undo,
   pick another option in that same Keyboard setting.

Check what this Mac supports at any time:

```sh
/Applications/hark.app/Contents/MacOS/hark --doctor
```

## Use

| Action | Keys |
| --- | --- |
| Dictate | Hold **Fn**, speak, release |
| Hands-free | Tap **Fn** once, speak, press Fn again to finish. Space while holding Fn does the same |
| Polish this one | Tap **Shift** while dictating |
| Cancel | **Esc** |
| Paste the last result again | **Ctrl+Cmd+V** |

Other audio is muted while you dictate and comes back when you stop, so a video or music
is not picked up by the microphone. Turn that off in Settings > General.

The trigger key, language, microphone and personal dictionary are in the menu bar icon >
Settings. The menu also lists the last five dictations; click one to copy it.

When a word keeps coming out wrong, add it under Settings > Corrections as
`heard = meant`, one per line (for example `tasting = testing`). It is swapped in every
dictation, whole words only.

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
make verify    # synthesises a sentence, transcribes it two ways, compares the words
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

When a dictation misbehaves, hark's log has the timings and outcome (never the words):

```sh
log show --last 5m --predicate 'subsystem == "dev.hark.app"'
```

## Limits

- Needs macOS 26 for Apple's on-device speech recogniser. There is no fallback engine yet;
  `Transcriber` in `Sources/hark/Transcriber.swift` is the place to add one.
- Languages are whatever Apple's recogniser supports (30 locales, including `en-ZA`).
- Insertion is a paste, so apps that block pasting will not receive text.
- Password fields: macOS hides key events there, so the hotkey does not fire.
- Muting uses the output device's own mute control. Outputs without one (some HDMI
  displays) are left alone; `hark --doctor` says which case applies.

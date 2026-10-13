# How Typeless 2.8.1 behaves

Study of the copy installed at `/Applications/Typeless.app` on 2026-10-13, used only to
decide how `hark` should behave. Everything in `hark` is written fresh. No Typeless code,
prompt text, asset or helper library is in this repository, and `hark` never contacts
Typeless's servers.

## Method and limits

- REA 6.4.0 `analyze-javascript-application` over the extracted `dist/` tree. Evidence ID
  `ev_adc2baf68c133749c4129c83c2187ed031cd69de704c3d8101a1fb62c8c7450d`. 83 JavaScript files
  parsed, 0 parse failures, coverage `partial`.
- The main process bundle and most renderer chunks are obfuscated with a string table. REA
  found 46 IPC operations and 44 main-process handlers but could resolve only 8 channel
  names; 38 stay dynamic. REA confirmed the structure, not the behaviour.
- Behaviour below therefore comes from four other sources, each named per finding: exported
  symbols and imported macOS APIs of the native helper libraries (`nm`, `otool`, `strings`),
  string literals that survived obfuscation, the database migrations shipped beside the
  bundle, and the settings file Typeless wrote on this Mac.
- A whole-archive REA run (10,499 files including dependencies) was stopped at file 12 as
  too slow to be worth it. Dependencies were inventoried from the archive header instead.
- Nothing here was observed at runtime. Each finding is marked **observed** (read directly
  from an artifact) or **inferred**.

## 1. Hotkey model

- **Observed** (settings file): dictation is bound to `Fn`, hands-free to `Fn+Space`,
  translation to `Fn+LeftShift`, paste-last-transcript to `Ctrl+Cmd+V`.
- **Observed** (keyboard helper imports): a `CGEventTap` listens for key and modifier
  changes, and the helper restarts the tap when macOS disables it for being slow. It also
  enumerates keyboards through IOKit.
- **Inferred** (settings and onboarding key names such as `pushToTalk`, `handlesFreeMode`
  and `pressToStopDictation`): holding `Fn` records until release; `Fn+Space` keeps
  recording after release until the key is pressed again.

## 2. Audio capture

- **Observed** (floating bar renderer literals): mono, 16-bit, with echo cancellation, noise
  suppression and automatic gain all switched off. Encoder sample rate 48 kHz.
- **Observed** (worker literals): Opus at 32 kbit/s in 20 ms frames, encoded in a worker
  through a native library, sent in chunks while recording.
- **Observed** (renderer literals): the start sound is delayed 300 ms when the microphone
  label contains "airpods".
- **Observed** (settings file and util helper exports): other audio is muted while
  recording (`muteAudio`, `unmuteAudio`, setting on by default here).

## 3. Where transcription and cleanup happen

- **Observed** (literals): `https://api.typeless.com`, path `/ai/voice_flow`, and a
  WebSocket message vocabulary of `start_audio`, `set_audio_chunk_info`, `end_audio`,
  `refine_completed`, `refine_error`.
- **Inferred**: both speech recognition and text cleanup run on Typeless's servers. No
  speech or language model ships in the bundle. This is why `hark` needs its own engines.

## 4. Context collected before cleanup

- **Observed** (renderer literals for the payload): app name, bundle identifier, window
  title, app type (native or browser), page title and URL for browsers, visible screen
  content, and the text before and after the input area. The context is encrypted with an
  RSA key before sending.
- **Observed** (context helper imports and strings): read through the accessibility API,
  including `AXEnhancedUserInterface`, which makes Chromium-based apps expose their content.
- **Observed** (settings file): an allow list and a block list of apps and URLs control
  where that deeper reading is attempted.

## 5. Text insertion

- **Observed** (input helper imports): the helper reads through the accessibility API but
  does not import the call that writes to it. It imports `NSPasteboard`, `CGEventPost` and
  keyboard layout translation, and contains a routine named for simulating the paste
  command plus a pasteboard archive type.
- **Inferred**: insertion is always clipboard paste. Save the clipboard, write the text
  marked as transient so clipboard managers skip it, post Cmd+V using the V key of the
  current layout, then restore the clipboard.
- **Observed**: selected text is read through accessibility first, with a simulated copy
  and a timeout as fallback.

## 6. Local data

- **Observed** (migration snapshot 0013): one history table per schema generation. Each row
  holds the refined text, duration, mode, status, focused app details, microphone, detected
  language, a path to the saved audio, and cloud sync bookkeeping.
- **Observed** (data folder): the database on this Mac is 302 MB, mostly saved audio.
- The personal dictionary is fetched from the server (`user_dictionary_id` in the payload
  vocabulary); no local dictionary table exists.

## 7. Baseline to beat

- **Observed**: 181 MB resident across 7 processes while idle, 529 MB on disk.

## What `hark` takes from this, and what it changes

| Area | Typeless | hark |
| --- | --- | --- |
| Hotkey | Hold Fn, Fn+Space hands-free, Ctrl+Cmd+V paste last | Same, trigger key selectable |
| Speech | Cloud | Apple `SpeechTranscriber`, on device |
| Cleanup | Cloud | Apple on-device language model, rule-based fallback |
| Insertion | Clipboard paste with restore | Same approach |
| Context | Screen and surrounding text sent to cloud | App name only, kept local |
| History | SQLite with saved audio and sync | JSON lines file, text only |
| Dictionary | Server side | Local list, fed to the recogniser and the cleanup prompt |

Not carried over: accounts, sync, translation and command modes, onboarding, telemetry,
auto-update, audio muting, layout-aware paste key (a fixed V key code is used).

## Still unknown

- The exact hold threshold and hands-free rules (inferred from names only).
- The cleanup instructions, which live on the server.

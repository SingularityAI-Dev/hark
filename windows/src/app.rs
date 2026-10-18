//! Windows shell: tray icon, global Right Ctrl hold-to-talk hook, Windows speech
//! recognition and clipboard paste.

use crate::polish;
use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};
use windows::core::{w, Result, HSTRING, PCWSTR};
use windows::Foundation::TypedEventHandler;
use windows::Media::SpeechRecognition::{
    SpeechContinuousRecognitionResultGeneratedEventArgs, SpeechContinuousRecognitionSession,
    SpeechRecognitionConfidence, SpeechRecognitionResultStatus, SpeechRecognitionScenario,
    SpeechRecognitionTopicConstraint, SpeechRecognizer,
};
use windows::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS, HANDLE, HINSTANCE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, GetClipboardData, OpenClipboard, SetClipboardData,
};
use windows::Win32::System::Diagnostics::Debug::MessageBeep;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP,
    VIRTUAL_KEY, VK_CONTROL, VK_RCONTROL, VK_SHIFT,
};
use windows::Win32::UI::Shell::{
    ShellExecuteW, Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NIM_MODIFY, NOTIFYICONDATAW,
};
use windows::Win32::UI::WindowsAndMessaging::*;

const WM_TRAY: u32 = WM_APP + 1;
const ID_POLISH: usize = 1;
const ID_QUIT: usize = 2;
const MIN_HOLD: Duration = Duration::from_millis(250);

static POLISH_ON: AtomicBool = AtomicBool::new(true);
static TRAY_WINDOW: AtomicIsize = AtomicIsize::new(0);
static COMMANDS: OnceLock<Sender<Command>> = OnceLock::new();
static HOLD: Mutex<Option<Instant>> = Mutex::new(None);
static OTHER_KEY: AtomicBool = AtomicBool::new(false);

enum Command {
    Start,
    Stop { skip_polish: bool },
    Cancel,
}

pub fn run() {
    unsafe {
        let _ = RoInitialize(RO_INIT_MULTITHREADED);
        let mutex = CreateMutexW(None, false, w!("Local\\hark-windows"));
        if mutex.is_err() || GetLastError() == ERROR_ALREADY_EXISTS {
            return;
        }

        let (sender, receiver) = channel();
        let _ = COMMANDS.set(sender);
        std::thread::spawn(move || worker(receiver));

        let instance: HINSTANCE = GetModuleHandleW(None).map(|m| HINSTANCE(m.0)).unwrap_or_default();
        let class = w!("HarkWindow");
        let window_class = WNDCLASSW {
            lpfnWndProc: Some(window_proc),
            hInstance: instance,
            lpszClassName: class,
            ..Default::default()
        };
        RegisterClassW(&window_class);
        let window = CreateWindowExW(
            WINDOW_EX_STYLE(0), class, w!("hark"), WINDOW_STYLE(0), 0, 0, 0, 0, None, None, instance, None,
        )
        .expect("window");
        TRAY_WINDOW.store(window.0 as isize, Ordering::SeqCst);
        set_tray(NIM_ADD, "hark: hold Right Ctrl to dictate");

        let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard_hook), instance, 0).expect("keyboard hook");

        let mut message = MSG::default();
        while GetMessageW(&mut message, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        let _ = UnhookWindowsHookEx(hook);
        set_tray(NIM_DELETE, "");
    }
}

fn set_tray(action: NotifyAction, tip: &str) {
    unsafe {
        let mut data = NOTIFYICONDATAW {
            cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: HWND(TRAY_WINDOW.load(Ordering::SeqCst) as *mut _),
            uID: 1,
            uFlags: NIF_ICON | NIF_MESSAGE | NIF_TIP,
            uCallbackMessage: WM_TRAY,
            hIcon: LoadIconW(None, IDI_APPLICATION).unwrap_or_default(),
            ..Default::default()
        };
        for (slot, unit) in data.szTip.iter_mut().zip(tip.encode_utf16().take(127)) {
            *slot = unit;
        }
        let _ = Shell_NotifyIconW(action, &data);
    }
}

type NotifyAction = windows::Win32::UI::Shell::NOTIFY_ICON_MESSAGE;

unsafe extern "system" fn window_proc(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match message {
        WM_TRAY if (lparam.0 as u32) == WM_RBUTTONUP || (lparam.0 as u32) == WM_LBUTTONUP => {
            let menu = CreatePopupMenu().unwrap_or_default();
            let polish_flags = if POLISH_ON.load(Ordering::SeqCst) { MF_CHECKED } else { MF_UNCHECKED };
            let _ = AppendMenuW(menu, MF_STRING | polish_flags, ID_POLISH, w!("Polish with language model"));
            let _ = AppendMenuW(menu, MF_STRING, ID_QUIT, w!("Quit hark"));
            let mut point = Default::default();
            let _ = GetCursorPos(&mut point);
            let _ = SetForegroundWindow(window);
            let _ = TrackPopupMenu(menu, TPM_RIGHTBUTTON, point.x, point.y, 0, window, None);
            let _ = DestroyMenu(menu);
            LRESULT(0)
        }
        WM_COMMAND => {
            match wparam.0 & 0xffff {
                ID_POLISH => {
                    POLISH_ON.fetch_xor(true, Ordering::SeqCst);
                }
                ID_QUIT => PostQuitMessage(0),
                _ => {}
            }
            LRESULT(0)
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            LRESULT(0)
        }
        _ => DefWindowProcW(window, message, wparam, lparam),
    }
}

unsafe extern "system" fn keyboard_hook(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 {
        let info = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
        let injected = info.flags.0 & LLKHF_INJECTED.0 != 0;
        if !injected {
            let is_down = matches!(wparam.0 as u32, WM_KEYDOWN | WM_SYSKEYDOWN);
            let is_up = matches!(wparam.0 as u32, WM_KEYUP | WM_SYSKEYUP);
            let mut hold = HOLD.lock().unwrap();
            if info.vkCode == VK_RCONTROL.0 as u32 {
                if is_down && hold.is_none() {
                    *hold = Some(Instant::now());
                    OTHER_KEY.store(false, Ordering::SeqCst);
                    send(Command::Start);
                } else if is_up {
                    if let Some(since) = hold.take() {
                        if OTHER_KEY.load(Ordering::SeqCst) || since.elapsed() < MIN_HOLD {
                            send(Command::Cancel);
                        } else {
                            let skip_polish = GetAsyncKeyState(VK_SHIFT.0 as i32) < 0;
                            send(Command::Stop { skip_polish });
                        }
                    }
                }
            } else if is_down && hold.is_some() {
                // Right Ctrl is being used as a normal modifier, not as the dictation key.
                OTHER_KEY.store(true, Ordering::SeqCst);
            }
        }
    }
    CallNextHookEx(None, code, wparam, lparam)
}

fn send(command: Command) {
    if let Some(sender) = COMMANDS.get() {
        let _ = sender.send(command);
    }
}

struct Recognizer {
    session: SpeechContinuousRecognitionSession,
    heard: Arc<Mutex<Vec<String>>>,
    _recognizer: SpeechRecognizer,
}

fn make_recognizer() -> Result<Recognizer> {
    let recognizer = SpeechRecognizer::new()?;
    let constraint = SpeechRecognitionTopicConstraint::Create(
        SpeechRecognitionScenario::Dictation,
        &HSTRING::from("dictation"),
    )?;
    recognizer.Constraints()?.Append(&constraint)?;
    let compiled = recognizer.CompileConstraintsAsync()?.get()?;
    if compiled.Status()? != SpeechRecognitionResultStatus::Success {
        return Err(windows::core::Error::from_hresult(windows::core::HRESULT(0x80045509u32 as i32)));
    }
    let session = recognizer.ContinuousRecognitionSession()?;
    let heard = Arc::new(Mutex::new(Vec::new()));
    let sink = heard.clone();
    session.ResultGenerated(&TypedEventHandler::new(
        move |_: &Option<SpeechContinuousRecognitionSession>,
              args: &Option<SpeechContinuousRecognitionResultGeneratedEventArgs>| {
            if let Some(args) = args {
                let result = args.Result()?;
                if result.Confidence()? != SpeechRecognitionConfidence::Rejected {
                    sink.lock().unwrap().push(result.Text()?.to_string());
                }
            }
            Ok(())
        },
    ))?;
    Ok(Recognizer { session, heard, _recognizer: recognizer })
}

fn worker(commands: Receiver<Command>) {
    unsafe {
        let _ = RoInitialize(RO_INIT_MULTITHREADED);
    }
    let mut recognizer: Option<Recognizer> = None;
    let mut warned = false;
    let mut listening = false;
    while let Ok(command) = commands.recv() {
        match command {
            Command::Start => {
                if recognizer.is_none() {
                    match make_recognizer() {
                        Ok(r) => recognizer = Some(r),
                        Err(error) => {
                            if !warned {
                                warned = true;
                                explain(&error);
                            }
                            continue;
                        }
                    }
                }
                let r = recognizer.as_ref().unwrap();
                r.heard.lock().unwrap().clear();
                match r.session.StartAsync().and_then(|a| a.get()) {
                    Ok(()) => {
                        listening = true;
                        beep(MB_ICONASTERISK);
                        set_tray(NIM_MODIFY, "hark: listening");
                    }
                    Err(_) => recognizer = None, // rebuild on the next press
                }
            }
            Command::Cancel => {
                if listening {
                    listening = false;
                    if let Some(r) = &recognizer {
                        let _ = r.session.CancelAsync().and_then(|a| a.get());
                    }
                    set_tray(NIM_MODIFY, "hark: hold Right Ctrl to dictate");
                }
            }
            Command::Stop { skip_polish } => {
                if !listening {
                    continue;
                }
                listening = false;
                let Some(r) = &recognizer else { continue };
                set_tray(NIM_MODIFY, "hark: working");
                let _ = r.session.StopAsync().and_then(|a| a.get());
                std::thread::sleep(Duration::from_millis(200));
                let raw = r.heard.lock().unwrap().join(" ");
                if !raw.trim().is_empty() {
                    let text = polish::refine(&raw, POLISH_ON.load(Ordering::SeqCst) && !skip_polish);
                    if !text.is_empty() {
                        paste(&text);
                    }
                }
                set_tray(NIM_MODIFY, "hark: hold Right Ctrl to dictate");
            }
        }
    }
}

fn beep(kind: MESSAGEBOX_STYLE) {
    unsafe {
        let _ = MessageBeep(kind);
    }
}

fn explain(error: &windows::core::Error) {
    let text = format!(
        "hark could not start speech recognition ({}).\n\nTurn on Settings > Privacy > Speech > Online speech recognition, and allow microphone access for desktop apps, then press Right Ctrl again.",
        error.message()
    );
    unsafe {
        let _ = ShellExecuteW(None, w!("open"), w!("ms-settings:privacy-speech"), PCWSTR::null(), PCWSTR::null(), SW_SHOWNORMAL);
        MessageBoxW(None, &HSTRING::from(text), w!("hark"), MB_OK | MB_ICONINFORMATION);
    }
}

const CF_UNICODETEXT: u32 = 13;

fn read_clipboard() -> Option<String> {
    unsafe {
        OpenClipboard(None).ok()?;
        let mut text = None;
        if let Ok(handle) = GetClipboardData(CF_UNICODETEXT) {
            let global = windows::Win32::Foundation::HGLOBAL(handle.0);
            let pointer = GlobalLock(global) as *const u16;
            if !pointer.is_null() {
                let mut length = 0;
                while *pointer.add(length) != 0 {
                    length += 1;
                }
                text = Some(String::from_utf16_lossy(std::slice::from_raw_parts(pointer, length)));
                let _ = GlobalUnlock(global);
            }
        }
        let _ = CloseClipboard();
        text
    }
}

fn write_clipboard(text: &str) -> bool {
    unsafe {
        let wide: Vec<u16> = text.replace("\r\n", "\n").replace('\n', "\r\n").encode_utf16().chain(Some(0)).collect();
        let Ok(global) = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2) else { return false };
        let pointer = GlobalLock(global) as *mut u16;
        if pointer.is_null() {
            return false;
        }
        std::ptr::copy_nonoverlapping(wide.as_ptr(), pointer, wide.len());
        let _ = GlobalUnlock(global);
        if OpenClipboard(None).is_err() {
            return false;
        }
        let _ = EmptyClipboard();
        let stored = SetClipboardData(CF_UNICODETEXT, HANDLE(global.0)).is_ok();
        let _ = CloseClipboard();
        stored
    }
}

fn key(code: VIRTUAL_KEY, up: bool) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: code,
                wScan: 0,
                dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

/// Puts the text on the clipboard, presses Ctrl+V, then restores the previous text.
fn paste(text: &str) {
    let previous = read_clipboard();
    if !write_clipboard(text) {
        return;
    }
    let v = VIRTUAL_KEY(0x56);
    let inputs = [key(VK_CONTROL, false), key(v, false), key(v, true), key(VK_CONTROL, true)];
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
    std::thread::sleep(Duration::from_millis(250));
    if let Some(previous) = previous {
        write_clipboard(&previous);
    }
}

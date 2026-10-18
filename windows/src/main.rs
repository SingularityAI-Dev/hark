//! hark for Windows: hold Right Ctrl, speak, release; the cleaned text is typed where the
//! cursor is. Shift held on release skips the language-model polish.

#![cfg_attr(windows, windows_subsystem = "windows")]

mod cleaner;
mod polish;
#[cfg(windows)]
mod app;

#[cfg(windows)]
fn main() {
    app::run();
}

#[cfg(not(windows))]
fn main() {
    // The app is Windows-only; on other systems the binary exists so `cargo test` can run
    // the cleaner and guard tests.
    eprintln!("{}", polish::refine("um hello hello world", false));
}

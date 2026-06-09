use enigo::*;
use parking_lot::Mutex;
use std::{thread, time::Duration};
use tauri::Emitter;

use crate::APP_HANDLE;

static SELECT_ALL: Mutex<()> = Mutex::new(());

#[allow(dead_code)]
pub fn select_all(enigo: &mut Enigo) {
    let _guard = SELECT_ALL.lock();

    up_control_keys(enigo);

    enigo.key(Key::Control, Direction::Press).unwrap();
    enigo.key(Key::A, Direction::Click).unwrap();
    enigo.key(Key::Control, Direction::Release).unwrap();
}

pub static INPUT_LOCK: Mutex<()> = Mutex::new(());

pub fn left_arrow_click(enigo: &mut Enigo, n: usize) {
    let _guard = INPUT_LOCK.lock();

    for _ in 0..n {
        enigo.key(Key::LeftArrow, Direction::Click).unwrap();
    }
}

pub fn right_arrow_click(enigo: &mut Enigo, n: usize) {
    let _guard = INPUT_LOCK.lock();

    for _ in 0..n {
        enigo.key(Key::RightArrow, Direction::Click).unwrap();
    }
}

pub fn backspace_click(enigo: &mut Enigo, n: usize) {
    let _guard = INPUT_LOCK.lock();

    for _ in 0..n {
        enigo.key(Key::Backspace, Direction::Click).unwrap();
    }
}

#[allow(dead_code)]
pub fn up_control_keys(enigo: &mut Enigo) {
    enigo.key(Key::Control, Direction::Release).unwrap();
    enigo.key(Key::Alt, Direction::Release).unwrap();
    enigo.key(Key::Shift, Direction::Release).unwrap();
    enigo.key(Key::Space, Direction::Release).unwrap();
    enigo.key(Key::Tab, Direction::Release).unwrap();
}

static COPY_PASTE: Mutex<()> = Mutex::new(());

#[allow(dead_code)]
pub fn copy(enigo: &mut Enigo) {
    let _guard = COPY_PASTE.lock();

    up_control_keys(enigo);

    enigo.key(Key::Control, Direction::Press).unwrap();
    enigo.key(Key::C, Direction::Click).unwrap();
    enigo.key(Key::Control, Direction::Release).unwrap();
}

#[allow(dead_code)]
pub fn paste(enigo: &mut Enigo) {
    let _guard = COPY_PASTE.lock();

    up_control_keys(enigo);

    enigo.key(Key::Control, Direction::Press).unwrap();
    enigo.key(Key::V, Direction::Click).unwrap();
    enigo.key(Key::Control, Direction::Release).unwrap();
}

pub fn get_selected_text_by_clipboard(
    enigo: &mut Enigo,
    cancel_select: bool,
) -> Result<String, Box<dyn std::error::Error>> {
    use arboard::Clipboard;

    let old_clipboard = (Clipboard::new()?.get_text(), Clipboard::new()?.get_image());

    let mut write_clipboard = Clipboard::new()?;

    let not_selected_placeholder = "";

    write_clipboard.set_text(not_selected_placeholder)?;

    thread::sleep(Duration::from_millis(50));

    println!(
        "get_selected_text_by_clipboard: Invoking copy shortcut to capture selected text (cancel_select={})",
        cancel_select
    );
    copy(enigo);

    if cancel_select {
        right_arrow_click(enigo, 1);
    }

    thread::sleep(Duration::from_millis(100));

    let new_text = Clipboard::new()?.get_text();

    match old_clipboard {
        (Ok(old_text), _) => {
            // Old Content is Text
            write_clipboard.set_text(old_text.clone())?;
            if let Ok(new) = new_text {
                if new.trim() == not_selected_placeholder.trim() {
                    Ok(String::new())
                } else {
                    Ok(new)
                }
            } else {
                Ok(String::new())
            }
        }
        (_, Ok(image)) => {
            // Old Content is Image
            write_clipboard.set_image(image)?;
            if let Ok(new) = new_text {
                if new.trim() == not_selected_placeholder.trim() {
                    Ok(String::new())
                } else {
                    Ok(new)
                }
            } else {
                Ok(String::new())
            }
        }
        _ => {
            // Old Content is Empty
            write_clipboard.clear()?;
            if let Ok(new) = new_text {
                if new.trim() == not_selected_placeholder.trim() {
                    Ok(String::new())
                } else {
                    Ok(new)
                }
            } else {
                Ok(String::new())
            }
        }
    }
}

pub fn get_selected_text_via_ax() -> Option<String> {
    None
}

pub fn get_focused_text_via_ax() -> Option<String> {
    None
}

pub fn get_writing_anchor_rect() -> Option<(f64, f64, f64, f64)> {
    None
}

pub fn send_text(text: String) {
    match APP_HANDLE.get() {
        Some(handle) => handle.emit("change-text", text).unwrap_or_default(),
        None => {}
    }
}

pub fn writing_text(text: String) {
    match APP_HANDLE.get() {
        Some(handle) => handle.emit("writing-text", text).unwrap_or_default(),
        None => {}
    }
}

pub fn show() {
    match APP_HANDLE.get() {
        Some(handle) => handle.emit("show", "").unwrap_or_default(),
        None => {}
    }
}

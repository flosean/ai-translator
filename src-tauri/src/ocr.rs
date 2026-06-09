use crate::insertion::remember_active_window;
use debug_print::debug_println;
use std::path::Path;
use tauri::path::BaseDirectory;
use tauri::Manager;

#[tauri::command(async)]
#[specta::specta]
pub fn cut_image(left: u32, top: u32, width: u32, height: u32) {
    use image::GenericImage;
    let app_handle = match crate::APP_HANDLE.get() {
        Some(handle) => handle,
        None => {
            eprintln!("APP_HANDLE not initialized");
            return;
        }
    };
    let image_dir = match app_handle
        .path()
        .resolve("ocr_images", BaseDirectory::AppCache)
    {
        Ok(dir) => dir,
        Err(e) => {
            eprintln!("Failed to resolve ocr_images directory: {:?}", e);
            return;
        }
    };
    let image_file_path = image_dir.join("fullscreen.png");
    if !image_file_path.exists() {
        return;
    }
    let mut img = match image::open(&image_file_path) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("error: {}", e);
            return;
        }
    };
    let img2 = img.sub_image(left, top, width, height);
    let new_image_file_path = image_dir.join("cut.png");
    match img2.to_image().save(&new_image_file_path) {
        Ok(_) => {}
        Err(e) => {
            eprintln!("{:?}", e.to_string());
            return;
        }
    }
}

#[tauri::command]
#[specta::specta]
pub fn screenshot(x: i32, y: i32) {
    use screenshots::{Compression, Screen};
    use std::fs;

    let screens = match Screen::all() {
        Ok(screens) => screens,
        Err(e) => {
            eprintln!("Failed to get screens: {:?}", e);
            return;
        }
    };
    for screen in screens {
        let info = screen.display_info;
        if info.x == x && info.y == y {
            let app_handle = match crate::APP_HANDLE.get() {
                Some(handle) => handle,
                None => {
                    eprintln!("APP_HANDLE not initialized");
                    return;
                }
            };
            let image_dir = match app_handle
                .path()
                .resolve("ocr_images", BaseDirectory::AppCache)
            {
                Ok(dir) => dir,
                Err(e) => {
                    eprintln!("Failed to resolve ocr_images directory: {:?}", e);
                    return;
                }
            };
            if !image_dir.exists() {
                if let Err(e) = std::fs::create_dir_all(&image_dir) {
                    eprintln!("Failed to create ocr_images directory: {:?}", e);
                    return;
                }
            }
            let image_file_path = image_dir.join("fullscreen.png");
            let image = match screen.capture() {
                Ok(img) => img,
                Err(e) => {
                    eprintln!("Failed to capture screen: {:?}", e);
                    return;
                }
            };
            let buffer = match image.to_png(Compression::Fast) {
                Ok(buf) => buf,
                Err(e) => {
                    eprintln!("Failed to convert image to PNG: {:?}", e);
                    return;
                }
            };
            debug_println!("image_file_path: {:?}", image_file_path);
            if let Err(e) = fs::write(&image_file_path, buffer) {
                eprintln!("Failed to write screenshot file: {:?}", e);
                return;
            }
            break;
        }
    }
}

pub fn do_ocr() -> Result<(), Box<dyn std::error::Error>> {
    use crate::windows::show_screenshot_window;
    show_screenshot_window();
    Ok(())
}

pub fn do_ocr_with_cut_file_path(image_file_path: &Path) {
    use windows::core::HSTRING;
    use windows::Graphics::Imaging::BitmapDecoder;
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::{FileAccessMode, StorageFile};

    let path = image_file_path.to_string_lossy().replace("\\\\?\\", "");
    debug_println!("ocr image file path: {:?}", path);

    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))
        .unwrap()
        .get()
        .unwrap();

    let bitmap = BitmapDecoder::CreateWithIdAsync(
        BitmapDecoder::PngDecoderId().unwrap(),
        &file.OpenAsync(FileAccessMode::Read).unwrap().get().unwrap(),
    )
    .unwrap()
    .get()
    .unwrap();

    let bitmap = bitmap.GetSoftwareBitmapAsync().unwrap().get().unwrap();

    let engine = OcrEngine::TryCreateFromUserProfileLanguages();

    match engine {
        Ok(engine) => {
            let result = engine.RecognizeAsync(&bitmap).unwrap().get().unwrap();

            let mut content = String::new();
            for line in result.Lines().unwrap() {
                content.push_str(&line.Text().unwrap().to_string_lossy().trim());
                content.push('\n');
            }

            debug_println!("ocr content: {:?}", content);
            crate::utils::send_text(content);
            remember_active_window();
            crate::windows::show_translator_window(false, true, true);
        }
        Err(e) => {
            debug_println!("ocr error: {:?}", e);
            if e.to_string().contains("0x00000000") {
                eprintln!("{}", "Language package not installed!\n\nSee: https://learn.microsoft.com/zh-cn/windows/powertoys/text-extractor#supported-languages".to_string());
            } else {
                eprintln!("{}", e.to_string());
            }
        }
    }
}

#[tauri::command(async)]
#[specta::specta]
pub fn start_ocr() {
    ocr();
}

pub fn ocr() {
    if let Err(e) = do_ocr() {
        eprintln!("OCR failed: {:?}", e);
    }
}

#[tauri::command(async)]
#[specta::specta]
pub fn finish_ocr() {
    do_finish_ocr();
}

fn do_finish_ocr() {
    let app_handle = match crate::APP_HANDLE.get() {
        Some(handle) => handle,
        None => {
            eprintln!("APP_HANDLE not initialized");
            return;
        }
    };
    let image_dir = match app_handle
        .path()
        .resolve("ocr_images", BaseDirectory::AppCache)
    {
        Ok(dir) => dir,
        Err(e) => {
            eprintln!("Failed to resolve ocr_images directory: {:?}", e);
            return;
        }
    };
    let image_file_path = image_dir.join("cut.png");
    do_ocr_with_cut_file_path(&image_file_path);
}

// Read text context from the focused / hovered Accessibility element of the
// currently active application. Used by the Quick Translator window to guess
// which word or sentence the user is most likely interested in.

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize, specta::Type)]
#[serde(rename_all = "camelCase")]
pub struct AxContext {
    pub focused_text: String,
    pub focused_role: String,
    pub selected_text: String,
    pub hovered_text: String,
    pub hovered_role: String,
    pub app_name: String,
    pub app_bundle_id: String,
    pub mouse_x: i32,
    pub mouse_y: i32,
    pub paragraphs: Vec<String>,
    pub truncated: bool,
}

fn read_narrow_impl(mouse_x: i32, mouse_y: i32) -> AxContext {
    AxContext {
        mouse_x,
        mouse_y,
        ..AxContext::default()
    }
}

fn read_wide_impl(mouse_x: i32, mouse_y: i32) -> AxContext {
    AxContext {
        mouse_x,
        mouse_y,
        ..AxContext::default()
    }
}

#[tauri::command]
#[specta::specta]
pub async fn read_ax_context_narrow() -> AxContext {
    let (x, y) = crate::windows::get_mouse_location().unwrap_or((0, 0));
    tokio::task::spawn_blocking(move || read_narrow_impl(x, y))
        .await
        .unwrap_or_default()
}

#[tauri::command]
#[specta::specta]
pub async fn read_ax_context_wide() -> AxContext {
    let (x, y) = crate::windows::get_mouse_location().unwrap_or((0, 0));
    tokio::task::spawn_blocking(move || read_wide_impl(x, y))
        .await
        .unwrap_or_default()
}

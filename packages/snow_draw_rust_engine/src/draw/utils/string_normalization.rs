/// Returns `None` for blank input, otherwise returns the trimmed string.
pub fn normalize_optional_trimmed_string(raw: Option<&str>) -> Option<String> {
    let trimmed = raw?.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    }
}

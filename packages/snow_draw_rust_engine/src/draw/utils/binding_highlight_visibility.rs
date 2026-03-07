/// Resolves which binding element should show a hover highlight.
///
/// Mirrors the Dart behavior from `resolveHoverBindingHighlightId`: when an
/// arrow handle is hovered, binding highlight is suppressed.
pub fn resolve_hover_binding_highlight_id<TArrowPointHandle>(
    hovered_binding_element_id: Option<String>,
    hovered_arrow_handle: Option<TArrowPointHandle>,
) -> Option<String> {
    if hovered_arrow_handle.is_none() {
        hovered_binding_element_id
    } else {
        None
    }
}

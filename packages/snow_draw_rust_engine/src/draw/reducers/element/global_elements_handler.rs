#![allow(dead_code)]

use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::models::global_elements_state::GlobalElementsState;

/// Action payload for updating document-level overlays.
///
/// Mirrors the Dart `UpdateGlobalElements` action. `None` means "no update"
/// for that field.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct UpdateGlobalElements {
    pub highlight_mask: Option<HighlightMaskConfig>,
    pub watermark: Option<WatermarkConfig>,
}

impl UpdateGlobalElements {
    pub fn new(
        highlight_mask: Option<HighlightMaskConfig>,
        watermark: Option<WatermarkConfig>,
    ) -> Self {
        Self {
            highlight_mask,
            watermark,
        }
    }

    pub fn has_updates(&self) -> bool {
        self.highlight_mask.is_some() || self.watermark.is_some()
    }
}

/// Document adapter required by [`handle_update_global_elements`].
pub trait GlobalElementsReducerDocument: Clone {
    fn global_elements(&self) -> &GlobalElementsState;
    fn with_global_elements(&self, global_elements: GlobalElementsState) -> Self;
}

/// Domain adapter required by [`handle_update_global_elements`].
pub trait GlobalElementsReducerDomain: Clone {
    type Document: GlobalElementsReducerDocument;

    fn document(&self) -> &Self::Document;
    fn with_document(&self, document: Self::Document) -> Self;
}

/// State adapter required by [`handle_update_global_elements`].
pub trait GlobalElementsReducerState: Clone {
    type Domain: GlobalElementsReducerDomain;

    fn domain(&self) -> &Self::Domain;
    fn with_domain(&self, domain: Self::Domain) -> Self;
}

/// Reducer branch for `UpdateGlobalElements`.
///
/// This follows the Dart flow:
/// 1. Build `nextGlobalElements` from the current document values and action.
/// 2. Return the original state if nothing changed.
/// 3. Otherwise return a copied state with an updated domain/document snapshot.
pub fn handle_update_global_elements<S>(
    state: &S,
    action: &UpdateGlobalElements,
    _context: &DrawContext,
) -> S
where
    S: GlobalElementsReducerState,
{
    if !action.has_updates() {
        return state.clone();
    }

    let current_domain = state.domain();
    let current_document = current_domain.document();
    let current_global_elements = current_document.global_elements();
    let next_global_elements =
        current_global_elements.copy_with(action.highlight_mask, action.watermark.clone());

    if next_global_elements == *current_global_elements {
        return state.clone();
    }

    let next_document = current_document.with_global_elements(next_global_elements);
    let next_domain = current_domain.with_document(next_document);
    state.with_domain(next_domain)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::draw_color::DrawColor;

    #[derive(Clone, Debug, PartialEq)]
    struct TestDocument {
        global_elements: GlobalElementsState,
    }

    impl GlobalElementsReducerDocument for TestDocument {
        fn global_elements(&self) -> &GlobalElementsState {
            &self.global_elements
        }

        fn with_global_elements(&self, global_elements: GlobalElementsState) -> Self {
            Self { global_elements }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestDomain {
        document: TestDocument,
    }

    impl GlobalElementsReducerDomain for TestDomain {
        type Document = TestDocument;

        fn document(&self) -> &Self::Document {
            &self.document
        }

        fn with_document(&self, document: Self::Document) -> Self {
            Self { document }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        domain: TestDomain,
    }

    impl GlobalElementsReducerState for TestState {
        type Domain = TestDomain;

        fn domain(&self) -> &Self::Domain {
            &self.domain
        }

        fn with_domain(&self, domain: Self::Domain) -> Self {
            Self { domain }
        }
    }

    fn state_with_defaults() -> TestState {
        TestState {
            domain: TestDomain {
                document: TestDocument {
                    global_elements: GlobalElementsState::default(),
                },
            },
        }
    }

    #[test]
    fn returns_same_state_when_action_has_no_updates() {
        let state = state_with_defaults();
        let action = UpdateGlobalElements::default();
        let context = DrawContext::default();

        let next = handle_update_global_elements(&state, &action, &context);

        assert_eq!(next, state);
    }

    #[test]
    fn updates_highlight_mask_when_provided() {
        let state = state_with_defaults();
        let current_mask = state.domain.document.global_elements.highlight_mask;
        let updated_mask = current_mask.copy_with(Some(DrawColor::new(0xFF00_FF00)), Some(0.35));
        let action = UpdateGlobalElements::new(Some(updated_mask), None);
        let context = DrawContext::default();

        let next = handle_update_global_elements(&state, &action, &context);

        assert_eq!(
            next.domain.document.global_elements.highlight_mask,
            updated_mask
        );
        assert_eq!(
            next.domain.document.global_elements.watermark,
            state.domain.document.global_elements.watermark
        );
    }

    #[test]
    fn updates_watermark_when_provided() {
        let state = state_with_defaults();
        let action = UpdateGlobalElements::new(
            None,
            Some(WatermarkConfig::new(
                WatermarkConfig::DEFAULT_COLOR,
                "CONFIDENTIAL".to_string(),
                WatermarkConfig::DEFAULT_FONT_SIZE,
                WatermarkConfig::DEFAULT_FONT_FAMILY.to_string(),
                WatermarkConfig::DEFAULT_ANGLE,
                WatermarkConfig::DEFAULT_GAP,
                WatermarkConfig::DEFAULT_OPACITY,
            )),
        );
        let context = DrawContext::default();

        let next = handle_update_global_elements(&state, &action, &context);

        assert_eq!(
            next.domain.document.global_elements.watermark.text,
            "CONFIDENTIAL"
        );
        assert_eq!(
            next.domain.document.global_elements.highlight_mask,
            state.domain.document.global_elements.highlight_mask
        );
    }
}

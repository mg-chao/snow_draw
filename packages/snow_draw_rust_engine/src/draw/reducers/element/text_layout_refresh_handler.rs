#![allow(dead_code)]

use std::collections::BTreeSet;

use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::types::text::text_data::TextData as DomainTextData;
use crate::draw::elements::types::text::text_editing_geometry::{
    resolve_auto_resize_text_editing_rect, TextData as GeometryTextData,
    TextMetricsService as GeometryTextMetricsService,
};
use crate::draw::models::application_state::{
    ApplicationState, InteractionState as AppInteractionState,
    TextEditingState as AppTextEditingState,
};
use crate::draw::models::draw_state::{
    DomainDocumentState, DomainElementState, DomainState as DrawDomainState, DrawState,
};
use crate::draw::reducers::core::reducer_utils::apply_selection_change;
use crate::draw::reducers::element::element_reducer::RefreshAutoResizeTextLayoutsAfterFontLoad;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

type DomainOf<S> = <S as TextLayoutRefreshState>::Domain;
type ApplicationOf<S> = <S as TextLayoutRefreshState>::Application;
type DocumentOf<S> = <DomainOf<S> as TextLayoutRefreshDomain>::Document;
type ElementOf<S> = <DocumentOf<S> as TextLayoutRefreshDocument>::Element;
type InteractionOf<S> = <ApplicationOf<S> as TextLayoutRefreshApplication>::Interaction;
type TextEditingOf<S> = <InteractionOf<S> as TextLayoutRefreshInteraction>::TextEditing;

/// Adapter for element values used by text-layout refresh.
///
/// Implementations can return `None` from
/// [`TextLayoutRefreshElement::resolve_auto_resize_rect`] when the element is
/// not a text element or does not use auto-resize.
pub trait TextLayoutRefreshElement: Clone {
    fn id(&self) -> &str;
    fn rect(&self) -> DrawRect;
    fn resolve_auto_resize_rect(
        &self,
        text_metrics_service: Option<&dyn GeometryTextMetricsService>,
    ) -> Option<DrawRect>;
    fn with_rect(&self, rect: DrawRect) -> Self;
}

/// Adapter for a document that owns ordered elements.
pub trait TextLayoutRefreshDocument: Clone {
    type Element: TextLayoutRefreshElement;

    fn elements(&self) -> &[Self::Element];
    fn with_elements(&self, elements: Vec<Self::Element>) -> Self;
}

/// Adapter for a domain state exposing document and selected ids.
pub trait TextLayoutRefreshDomain: Clone {
    type Document: TextLayoutRefreshDocument;

    fn document(&self) -> &Self::Document;
    fn selected_ids(&self) -> &BTreeSet<String>;
    fn with_document(&self, document: Self::Document) -> Self;
}

/// Adapter for text-editing interaction payload.
pub trait TextLayoutRefreshTextEditingState: Clone {
    fn element_id(&self) -> &str;
    fn rect(&self) -> DrawRect;
    fn resolve_auto_resize_rect(
        &self,
        text_metrics_service: Option<&dyn GeometryTextMetricsService>,
    ) -> Option<DrawRect>;
    fn with_rect(&self, rect: DrawRect) -> Self;
}

/// Adapter for interaction state that may contain text-editing.
pub trait TextLayoutRefreshInteraction: Clone {
    type TextEditing: TextLayoutRefreshTextEditingState;

    fn as_text_editing(&self) -> Option<&Self::TextEditing>;
    fn with_text_editing(&self, text_editing: Self::TextEditing) -> Self;
}

/// Adapter for application state exposing interaction.
pub trait TextLayoutRefreshApplication: Clone {
    type Interaction: TextLayoutRefreshInteraction;

    fn interaction(&self) -> &Self::Interaction;
    fn with_interaction(&self, interaction: Self::Interaction) -> Self;
}

/// Adapter for aggregate draw state.
pub trait TextLayoutRefreshState: Clone {
    type Domain: TextLayoutRefreshDomain;
    type Application: TextLayoutRefreshApplication;

    fn domain(&self) -> &Self::Domain;
    fn application(&self) -> &Self::Application;
    fn with_domain(&self, domain: Self::Domain) -> Self;
    fn with_application(&self, application: Self::Application) -> Self;
    fn apply_selection_change(
        &self,
        selected_ids: BTreeSet<String>,
        force_refresh_overlay: bool,
    ) -> Self;
}

/// Helper used by adapters to resolve auto-resized text rectangles.
pub fn resolve_auto_resize_rect_for_text_data(
    current_rect: DrawRect,
    data: &GeometryTextData,
    text_metrics_service: Option<&dyn GeometryTextMetricsService>,
) -> DrawRect {
    resolve_auto_resize_text_editing_rect(
        DrawPoint::new(current_rect.min_x, current_rect.min_y),
        data,
        text_metrics_service,
        None,
    )
}

/// Core translation of Dart `handleRefreshAutoResizeTextLayoutsAfterFontLoad`.
///
/// This function is generic over model adapters so it can run with both test
/// models and the translated runtime draw state.
pub fn refresh_auto_resize_text_layouts_after_font_load<S>(
    state: &S,
    text_metrics_service: Option<&dyn GeometryTextMetricsService>,
) -> S
where
    S: TextLayoutRefreshState,
{
    let domain = state.domain();
    let document = domain.document();
    let selected_ids = domain.selected_ids().clone();
    let should_refresh_selection_overlay = selected_ids.len() > 1;

    let mut next_elements: Option<Vec<ElementOf<S>>> = None;
    let mut refresh_selection_overlay = false;

    for (index, element) in document.elements().iter().enumerate() {
        let Some(next_rect) = element.resolve_auto_resize_rect(text_metrics_service) else {
            continue;
        };

        if next_rect == element.rect() {
            continue;
        }

        let elements = next_elements.get_or_insert_with(|| document.elements().to_vec());
        elements[index] = element.with_rect(next_rect);

        if should_refresh_selection_overlay && selected_ids.contains(element.id()) {
            refresh_selection_overlay = true;
        }
    }

    let mut next_text_interaction: Option<TextEditingOf<S>> = None;
    if let Some(interaction) = state.application().interaction().as_text_editing() {
        if let Some(next_rect) = interaction.resolve_auto_resize_rect(text_metrics_service) {
            if next_rect != interaction.rect() {
                next_text_interaction = Some(interaction.with_rect(next_rect));

                if should_refresh_selection_overlay
                    && selected_ids.contains(interaction.element_id())
                {
                    refresh_selection_overlay = true;
                }
            }
        }
    }

    if next_elements.is_none() && next_text_interaction.is_none() {
        return state.clone();
    }

    let mut next_state = state.clone();
    if let Some(next_elements) = next_elements {
        let next_document = next_state.domain().document().with_elements(next_elements);
        let next_domain = next_state.domain().with_document(next_document);
        next_state = next_state.with_domain(next_domain);
    }

    if let Some(next_text_interaction) = next_text_interaction {
        let next_interaction = next_state
            .application()
            .interaction()
            .with_text_editing(next_text_interaction);
        let next_application = next_state.application().with_interaction(next_interaction);
        next_state = next_state.with_application(next_application);
    }

    if !refresh_selection_overlay {
        return next_state;
    }

    next_state.apply_selection_change(selected_ids, true)
}

/// Reducer branch used by `element_reducer`.
///
/// Uses runtime adapters on `DrawState` to refresh auto-resize text element
/// geometry in both document state and active text-editing interaction.
pub fn handle_refresh_auto_resize_text_layouts_after_font_load(
    state: DrawState,
    _action: &RefreshAutoResizeTextLayoutsAfterFontLoad,
    _context: &DrawContext,
) -> Option<DrawState> {
    Some(refresh_auto_resize_text_layouts_after_font_load(
        &state, None,
    ))
}

impl TextLayoutRefreshElement for DomainElementState {
    fn id(&self) -> &str {
        &self.id
    }

    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn resolve_auto_resize_rect(
        &self,
        text_metrics_service: Option<&dyn GeometryTextMetricsService>,
    ) -> Option<DrawRect> {
        let data = decode_domain_text_data(self)?;
        if !data.auto_resize {
            return None;
        }

        Some(resolve_auto_resize_rect_for_text_data(
            self.rect,
            &GeometryTextData {
                text: data.text,
                font_size: data.font_size,
                auto_resize: data.auto_resize,
            },
            text_metrics_service,
        ))
    }

    fn with_rect(&self, rect: DrawRect) -> Self {
        self.copy_with(None, Some(rect), None, None, None, None)
    }
}

impl TextLayoutRefreshDocument for DomainDocumentState {
    type Element = DomainElementState;

    fn elements(&self) -> &[Self::Element] {
        &self.elements
    }

    fn with_elements(&self, elements: Vec<Self::Element>) -> Self {
        self.copy_with(Some(elements), None, None)
    }
}

impl TextLayoutRefreshDomain for DrawDomainState {
    type Document = DomainDocumentState;

    fn document(&self) -> &Self::Document {
        &self.document
    }

    fn selected_ids(&self) -> &BTreeSet<String> {
        &self.selection.selected_ids
    }

    fn with_document(&self, document: Self::Document) -> Self {
        Self {
            document,
            selection: self.selection.clone(),
        }
    }
}

impl TextLayoutRefreshTextEditingState for AppTextEditingState {
    fn element_id(&self) -> &str {
        &self.element_id
    }

    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn resolve_auto_resize_rect(
        &self,
        text_metrics_service: Option<&dyn GeometryTextMetricsService>,
    ) -> Option<DrawRect> {
        if !self.draft_data.auto_resize {
            return None;
        }

        Some(resolve_auto_resize_rect_for_text_data(
            self.rect,
            &GeometryTextData {
                text: self.draft_data.text.clone(),
                font_size: self.draft_data.font_size,
                auto_resize: self.draft_data.auto_resize,
            },
            text_metrics_service,
        ))
    }

    fn with_rect(&self, rect: DrawRect) -> Self {
        self.copy_with(None, Some(rect), None, None, None, None)
    }
}

impl TextLayoutRefreshInteraction for AppInteractionState {
    type TextEditing = AppTextEditingState;

    fn as_text_editing(&self) -> Option<&<Self as TextLayoutRefreshInteraction>::TextEditing> {
        match self {
            Self::TextEditing(state) => Some(state),
            _ => None,
        }
    }

    fn with_text_editing(
        &self,
        text_editing: <Self as TextLayoutRefreshInteraction>::TextEditing,
    ) -> Self {
        Self::TextEditing(text_editing)
    }
}

impl TextLayoutRefreshApplication for ApplicationState {
    type Interaction = AppInteractionState;

    fn interaction(&self) -> &Self::Interaction {
        &self.interaction
    }

    fn with_interaction(&self, interaction: Self::Interaction) -> Self {
        self.copy_with(None, Some(interaction), None)
    }
}

impl TextLayoutRefreshState for DrawState {
    type Domain = DrawDomainState;
    type Application = ApplicationState;

    fn domain(&self) -> &Self::Domain {
        &self.domain
    }

    fn application(&self) -> &Self::Application {
        &self.application
    }

    fn with_domain(&self, domain: Self::Domain) -> Self {
        self.copy_with(Some(domain), None)
    }

    fn with_application(&self, application: Self::Application) -> Self {
        self.copy_with(None, Some(application))
    }

    fn apply_selection_change(
        &self,
        selected_ids: BTreeSet<String>,
        force_refresh_overlay: bool,
    ) -> Self {
        apply_selection_change(self, selected_ids, force_refresh_overlay)
    }
}

fn decode_domain_text_data(element: &DomainElementState) -> Option<DomainTextData> {
    if element.data.type_id().as_str() != DomainTextData::TYPE_ID_TOKEN {
        return None;
    }

    DomainTextData::from_json(&element.data.to_json()).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone, Debug, PartialEq)]
    struct TestElement {
        id: String,
        rect: DrawRect,
        text_data: Option<GeometryTextData>,
    }

    impl TestElement {
        fn shape(id: &str, rect: DrawRect) -> Self {
            Self {
                id: id.to_owned(),
                rect,
                text_data: None,
            }
        }

        fn auto_resize_text(id: &str, rect: DrawRect, text: &str) -> Self {
            Self {
                id: id.to_owned(),
                rect,
                text_data: Some(GeometryTextData {
                    text: text.to_owned(),
                    font_size: 14.0,
                    auto_resize: true,
                }),
            }
        }

        fn fixed_text(id: &str, rect: DrawRect, text: &str) -> Self {
            Self {
                id: id.to_owned(),
                rect,
                text_data: Some(GeometryTextData {
                    text: text.to_owned(),
                    font_size: 14.0,
                    auto_resize: false,
                }),
            }
        }
    }

    impl TextLayoutRefreshElement for TestElement {
        fn id(&self) -> &str {
            &self.id
        }

        fn rect(&self) -> DrawRect {
            self.rect
        }

        fn resolve_auto_resize_rect(
            &self,
            text_metrics_service: Option<&dyn GeometryTextMetricsService>,
        ) -> Option<DrawRect> {
            let data = self.text_data.as_ref()?;
            if !data.auto_resize {
                return None;
            }

            Some(resolve_auto_resize_rect_for_text_data(
                self.rect,
                data,
                text_metrics_service,
            ))
        }

        fn with_rect(&self, rect: DrawRect) -> Self {
            Self {
                id: self.id.clone(),
                rect,
                text_data: self.text_data.clone(),
            }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestDocument {
        elements: Vec<TestElement>,
    }

    impl TextLayoutRefreshDocument for TestDocument {
        type Element = TestElement;

        fn elements(&self) -> &[Self::Element] {
            &self.elements
        }

        fn with_elements(&self, elements: Vec<Self::Element>) -> Self {
            Self { elements }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestDomain {
        document: TestDocument,
        selected_ids: BTreeSet<String>,
    }

    impl TextLayoutRefreshDomain for TestDomain {
        type Document = TestDocument;

        fn document(&self) -> &Self::Document {
            &self.document
        }

        fn selected_ids(&self) -> &BTreeSet<String> {
            &self.selected_ids
        }

        fn with_document(&self, document: Self::Document) -> Self {
            Self {
                document,
                selected_ids: self.selected_ids.clone(),
            }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestTextEditingState {
        element_id: String,
        draft_data: GeometryTextData,
        rect: DrawRect,
    }

    impl TextLayoutRefreshTextEditingState for TestTextEditingState {
        fn element_id(&self) -> &str {
            &self.element_id
        }

        fn rect(&self) -> DrawRect {
            self.rect
        }

        fn resolve_auto_resize_rect(
            &self,
            text_metrics_service: Option<&dyn GeometryTextMetricsService>,
        ) -> Option<DrawRect> {
            if !self.draft_data.auto_resize {
                return None;
            }

            Some(resolve_auto_resize_rect_for_text_data(
                self.rect,
                &self.draft_data,
                text_metrics_service,
            ))
        }

        fn with_rect(&self, rect: DrawRect) -> Self {
            Self {
                element_id: self.element_id.clone(),
                draft_data: self.draft_data.clone(),
                rect,
            }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    enum TestInteraction {
        Idle,
        TextEditing(TestTextEditingState),
    }

    impl TextLayoutRefreshInteraction for TestInteraction {
        type TextEditing = TestTextEditingState;

        fn as_text_editing(&self) -> Option<&<Self as TextLayoutRefreshInteraction>::TextEditing> {
            match self {
                Self::TextEditing(value) => Some(value),
                Self::Idle => None,
            }
        }

        fn with_text_editing(
            &self,
            text_editing: <Self as TextLayoutRefreshInteraction>::TextEditing,
        ) -> Self {
            Self::TextEditing(text_editing)
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestApplication {
        interaction: TestInteraction,
    }

    impl TextLayoutRefreshApplication for TestApplication {
        type Interaction = TestInteraction;

        fn interaction(&self) -> &Self::Interaction {
            &self.interaction
        }

        fn with_interaction(&self, interaction: Self::Interaction) -> Self {
            Self { interaction }
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestState {
        domain: TestDomain,
        application: TestApplication,
        selection_overlay_refresh_count: usize,
        last_force_refresh_overlay: bool,
    }

    impl TestState {
        fn new(
            elements: Vec<TestElement>,
            selected_ids: BTreeSet<String>,
            interaction: TestInteraction,
        ) -> Self {
            Self {
                domain: TestDomain {
                    document: TestDocument { elements },
                    selected_ids,
                },
                application: TestApplication { interaction },
                selection_overlay_refresh_count: 0,
                last_force_refresh_overlay: false,
            }
        }
    }

    impl TextLayoutRefreshState for TestState {
        type Domain = TestDomain;
        type Application = TestApplication;

        fn domain(&self) -> &Self::Domain {
            &self.domain
        }

        fn application(&self) -> &Self::Application {
            &self.application
        }

        fn with_domain(&self, domain: Self::Domain) -> Self {
            Self {
                domain,
                application: self.application.clone(),
                selection_overlay_refresh_count: self.selection_overlay_refresh_count,
                last_force_refresh_overlay: self.last_force_refresh_overlay,
            }
        }

        fn with_application(&self, application: Self::Application) -> Self {
            Self {
                domain: self.domain.clone(),
                application,
                selection_overlay_refresh_count: self.selection_overlay_refresh_count,
                last_force_refresh_overlay: self.last_force_refresh_overlay,
            }
        }

        fn apply_selection_change(
            &self,
            selected_ids: BTreeSet<String>,
            force_refresh_overlay: bool,
        ) -> Self {
            let mut next = self.clone();
            next.domain.selected_ids = selected_ids;
            next.selection_overlay_refresh_count += 1;
            next.last_force_refresh_overlay = force_refresh_overlay;
            next
        }
    }

    fn rect(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> DrawRect {
        DrawRect::new(min_x, min_y, max_x, max_y)
    }

    fn ids(values: &[&str]) -> BTreeSet<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn no_auto_resize_candidates_return_same_state() {
        let state = TestState::new(
            vec![
                TestElement::shape("a", rect(0.0, 0.0, 20.0, 20.0)),
                TestElement::fixed_text("b", rect(10.0, 10.0, 30.0, 30.0), "fixed"),
            ],
            ids(&["a"]),
            TestInteraction::Idle,
        );

        let next = refresh_auto_resize_text_layouts_after_font_load(&state, None);

        assert_eq!(next, state);
    }

    #[test]
    fn auto_resize_text_element_updates_rect() {
        let state = TestState::new(
            vec![TestElement::auto_resize_text(
                "text",
                rect(0.0, 0.0, 1.0, 1.0),
                "Hello",
            )],
            ids(&["text"]),
            TestInteraction::Idle,
        );

        let next = refresh_auto_resize_text_layouts_after_font_load(&state, None);

        assert_ne!(
            next.domain.document.elements[0].rect,
            state.domain.document.elements[0].rect
        );
        assert_eq!(next.selection_overlay_refresh_count, 0);
    }

    #[test]
    fn multi_select_refreshes_overlay_when_selected_element_changes() {
        let state = TestState::new(
            vec![TestElement::auto_resize_text(
                "text",
                rect(0.0, 0.0, 1.0, 1.0),
                "Hello",
            )],
            ids(&["text", "other"]),
            TestInteraction::Idle,
        );

        let next = refresh_auto_resize_text_layouts_after_font_load(&state, None);

        assert_eq!(next.selection_overlay_refresh_count, 1);
        assert!(next.last_force_refresh_overlay);
    }

    #[test]
    fn text_editing_interaction_rect_is_refreshed() {
        let interaction = TestInteraction::TextEditing(TestTextEditingState {
            element_id: "text".to_string(),
            draft_data: GeometryTextData {
                text: "Hello world".to_string(),
                font_size: 14.0,
                auto_resize: true,
            },
            rect: rect(0.0, 0.0, 1.0, 1.0),
        });
        let state = TestState::new(Vec::new(), ids(&["text"]), interaction);

        let next = refresh_auto_resize_text_layouts_after_font_load(&state, None);

        let next_interaction = next.application.interaction;
        let TestInteraction::TextEditing(next_editing) = next_interaction else {
            panic!("expected text editing interaction");
        };
        assert_ne!(next_editing.rect, rect(0.0, 0.0, 1.0, 1.0));
        assert_eq!(next.selection_overlay_refresh_count, 0);
    }

    #[test]
    fn draw_state_wrapper_handles_action() {
        let state = DrawState::default();
        let context = DrawContext::default();
        let action = crate::draw::actions::draw_actions::RefreshAutoResizeTextLayoutsAfterFontLoad;

        let next = handle_refresh_auto_resize_text_layouts_after_font_load(
            state.clone(),
            &action,
            &context,
        )
        .expect("refresh action is always handled");

        assert_eq!(next, state);
    }
}

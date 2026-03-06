#![allow(dead_code)]

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use crate::draw::core::draw_context::DrawContext;
use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::arrow_data::{ArrowData, ArrowDataPatch, NullableField};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::elbow::elbow_router::route_elbow_arrow_for_element;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_layout::resolve_serial_number_rect as resolve_serial_number_layout_rect;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::interaction_state::TextEditingState;
use crate::draw::reducers::core::arrow_binding_sync::{
    apply_element_replacements_and_order, resolve_arrow_bindings_for_changed_bindables,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ElementStyleUpdate};

/// Action payload for applying style and opacity updates to multiple elements.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct UpdateElementsStyleAction {
    pub element_ids: Vec<String>,
    pub style_update: ElementStyleUpdate,
    pub opacity: Option<f64>,
}

impl UpdateElementsStyleAction {
    pub fn has_updates(&self) -> bool {
        !self.style_update.is_empty() || self.opacity.is_some()
    }
}

/// Selection adapter used by [`handle_update_elements_style`].
pub trait StyleReducerSelection {
    fn selected_ids(&self) -> &BTreeSet<String>;
}

/// Document adapter used by [`handle_update_elements_style`].
pub trait StyleReducerDocument: Clone {
    fn elements(&self) -> &[ElementState];
    fn with_elements(&self, elements: Vec<ElementState>) -> Self;

    fn element_by_id(&self, id: &str) -> Option<&ElementState> {
        self.elements().iter().find(|element| element.id == id)
    }

    fn element_map(&self) -> HashMap<String, ElementState> {
        self.elements()
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect()
    }
}

/// Domain adapter used by [`handle_update_elements_style`].
pub trait StyleReducerDomain: Clone {
    type Document: StyleReducerDocument;
    type Selection: StyleReducerSelection;

    fn document(&self) -> &Self::Document;
    fn selection(&self) -> &Self::Selection;
    fn with_document(&self, document: Self::Document) -> Self;
}

/// Interaction adapter used by [`handle_update_elements_style`].
pub trait StyleReducerInteraction: Clone {
    fn as_text_editing(&self) -> Option<&TextEditingState>;
    fn from_text_editing(text_editing: TextEditingState) -> Self;
}

/// Application adapter used by [`handle_update_elements_style`].
pub trait StyleReducerApplication: Clone {
    type Interaction: StyleReducerInteraction;

    fn interaction(&self) -> &Self::Interaction;
    fn with_interaction(&self, interaction: Self::Interaction) -> Self;
}

/// State adapter used by [`handle_update_elements_style`].
pub trait StyleReducerState: Clone {
    type Domain: StyleReducerDomain;
    type Application: StyleReducerApplication;

    fn domain(&self) -> &Self::Domain;
    fn application(&self) -> &Self::Application;
    fn with_domain(&self, domain: Self::Domain) -> Self;
    fn with_application(&self, application: Self::Application) -> Self;

    /// Optional hook for force-refreshing multi-selection overlays after a
    /// geometry-affecting style update.
    fn apply_selection_change(
        &self,
        _selected_ids: BTreeSet<String>,
        _force_refresh_overlay: bool,
    ) -> Self {
        self.clone()
    }
}

#[derive(Clone)]
struct ElementStyleUpdateResult {
    element: ElementState,
    geometry_changed: bool,
}

#[derive(Clone)]
struct ArrowRectAndData {
    rect: DrawRect,
    data: ArrowData,
}

enum StyleUpdatedDataKind {
    Generic,
    Text(TextData),
    SerialNumber(SerialNumberData),
    Arrow {
        previous: ArrowData,
        updated: ArrowData,
    },
}

struct StyleUpdatedData {
    data: Arc<dyn ElementData>,
    kind: StyleUpdatedDataKind,
}

/// Reducer branch translated from Dart `handleUpdateElementsStyle`.
///
/// The reducer is expressed through adapter traits so it can work with the
/// engine state abstractions while preserving the Dart behavior:
/// - element style updates + optional opacity updates,
/// - optional text-editing interaction updates,
/// - conditional multi-select overlay refresh when geometry changes.
pub fn handle_update_elements_style<S>(
    state: &S,
    action: &UpdateElementsStyleAction,
    context: &DrawContext,
) -> S
where
    S: StyleReducerState,
{
    let target_ids = action
        .element_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<String>>();
    if target_ids.is_empty() || !action.has_updates() {
        return state.clone();
    }

    let domain = state.domain();
    let document = domain.document();
    let selected_ids = domain.selection().selected_ids().clone();
    let track_selection_overlay = selected_ids.len() > 1;
    let elements_by_id = document.element_map();

    let mut replacements_by_id = HashMap::<String, ElementState>::new();
    let mut changed_bindable_ids = std::collections::HashSet::<String>::new();
    let mut selection_geometry_changed = false;

    for id in &target_ids {
        let Some(element) = document.element_by_id(id) else {
            continue;
        };

        let update = resolve_element_style_update(
            element,
            &action.style_update,
            action.opacity,
            track_selection_overlay && selected_ids.contains(id),
            &elements_by_id,
            context,
        );
        let Some(update) = update else {
            continue;
        };

        replacements_by_id.insert(id.clone(), update.element);
        if ArrowBindingUtils::is_bindable_target(&replacements_by_id[id]) {
            changed_bindable_ids.insert(id.clone());
        }
        if update.geometry_changed {
            selection_geometry_changed = true;
        }
    }

    let next_text_edit = resolve_text_editing_update(
        state,
        &target_ids,
        &action.style_update,
        action.opacity,
        context,
    );

    let domain_changed = !replacements_by_id.is_empty();
    let interaction_changed = next_text_edit.is_some();
    if !domain_changed && !interaction_changed {
        return state.clone();
    }

    let next_domain = if domain_changed {
        let mut merged_replacements_by_id = replacements_by_id;
        let mut ordered_element_ids = None;

        if !changed_bindable_ids.is_empty() {
            let binding_resolution = resolve_arrow_bindings_for_changed_bindables(
                document.elements(),
                &changed_bindable_ids,
                &merged_replacements_by_id,
            );
            if !binding_resolution.updated_elements.is_empty() {
                if track_selection_overlay
                    && has_selection_geometry_changes(
                        &selected_ids,
                        &elements_by_id,
                        &binding_resolution.updated_elements,
                    )
                {
                    selection_geometry_changed = true;
                }
                for (id, element) in binding_resolution.updated_elements {
                    merged_replacements_by_id.insert(id, element);
                }
            }
            ordered_element_ids = binding_resolution.ordered_element_ids;
        }

        let next_elements = apply_element_replacements_and_order(
            document.elements().to_vec(),
            &merged_replacements_by_id,
            ordered_element_ids.as_deref(),
        );
        domain.with_document(document.with_elements(next_elements))
    } else {
        domain.clone()
    };

    let next_application = if let Some(next_text_editing) = next_text_edit {
        let interaction =
            <S::Application as StyleReducerApplication>::Interaction::from_text_editing(
                next_text_editing,
            );
        state.application().with_interaction(interaction)
    } else {
        state.application().clone()
    };

    let next_state = state
        .with_domain(next_domain)
        .with_application(next_application);

    if selection_geometry_changed {
        return next_state.apply_selection_change(selected_ids, true);
    }

    next_state
}

fn resolve_element_style_update(
    element: &ElementState,
    style_update: &ElementStyleUpdate,
    opacity: Option<f64>,
    track_geometry_change: bool,
    elements_by_id: &HashMap<String, ElementState>,
    context: &DrawContext,
) -> Option<ElementStyleUpdateResult> {
    let style_updated = resolve_data_style_update(
        element,
        style_update,
        track_geometry_change,
        elements_by_id,
        context,
    );

    let base_element = style_updated
        .as_ref()
        .map(|result| result.element.clone())
        .unwrap_or_else(|| element.clone());
    let next_element = resolve_opacity_update(base_element, opacity);

    if next_element == *element {
        return None;
    }

    Some(ElementStyleUpdateResult {
        element: next_element,
        geometry_changed: style_updated.is_some_and(|result| result.geometry_changed),
    })
}

fn resolve_data_style_update(
    element: &ElementState,
    style_update: &ElementStyleUpdate,
    track_geometry_change: bool,
    elements_by_id: &HashMap<String, ElementState>,
    context: &DrawContext,
) -> Option<ElementStyleUpdateResult> {
    if style_update.is_empty() {
        return None;
    }

    let style_updated = resolve_style_updated_data(element, style_update)?;
    let mut updated_element = element.copy_with(
        None,
        None,
        None,
        None,
        None,
        Some(style_updated.data.clone()),
    );
    let mut geometry_changed = false;

    match style_updated.kind {
        StyleUpdatedDataKind::Text(updated_text_data) if should_relayout_text(style_update) => {
            let next_rect = resolve_text_rect(updated_element.rect, &updated_text_data);
            if next_rect != updated_element.rect {
                geometry_changed = track_geometry_change;
                updated_element =
                    updated_element.copy_with(None, Some(next_rect), None, None, None, None);
            }
        }
        StyleUpdatedDataKind::SerialNumber(updated_serial_number_data)
            if should_relayout_serial_number(style_update) =>
        {
            let next_rect = resolve_serial_number_rect(
                updated_element.rect,
                &updated_serial_number_data,
                context,
            );
            if next_rect != updated_element.rect {
                geometry_changed = track_geometry_change;
                updated_element =
                    updated_element.copy_with(None, Some(next_rect), None, None, None, None);
            }
        }
        StyleUpdatedDataKind::Arrow { previous, updated }
            if previous.arrow_type != updated.arrow_type
                || should_recompute_elbow_after_style_change(&previous, &updated) =>
        {
            let result = resolve_arrow_rect_and_data(&updated_element, &updated, elements_by_id);
            if result.rect != updated_element.rect && track_geometry_change {
                geometry_changed = true;
            }
            updated_element = updated_element.copy_with(
                None,
                Some(result.rect),
                None,
                None,
                None,
                Some(Arc::new(result.data)),
            );
        }
        StyleUpdatedDataKind::Generic
        | StyleUpdatedDataKind::Text(_)
        | StyleUpdatedDataKind::SerialNumber(_)
        | StyleUpdatedDataKind::Arrow { .. } => {}
    }

    Some(ElementStyleUpdateResult {
        element: updated_element,
        geometry_changed,
    })
}

fn resolve_style_updated_data(
    element: &ElementState,
    style_update: &ElementStyleUpdate,
) -> Option<StyleUpdatedData> {
    let type_id = element.data.type_id();
    match type_id.as_str() {
        TextData::TYPE_ID_TOKEN => {
            let previous = decode_text_data(element.data.as_ref())?;
            let (updated, data) =
                apply_typed_style_update(&previous, style_update, decode_text_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Text(updated),
            })
        }
        SerialNumberData::TYPE_ID_TOKEN => {
            let previous = decode_serial_number_data(element.data.as_ref())?;
            let (updated, data) =
                apply_typed_style_update(&previous, style_update, decode_serial_number_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::SerialNumber(updated),
            })
        }
        ArrowData::TYPE_ID_TOKEN => {
            let previous = decode_arrow_data(element.data.as_ref())?;
            let (updated, data) =
                apply_typed_style_update(&previous, style_update, decode_arrow_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Arrow { previous, updated },
            })
        }
        RectangleData::TYPE_ID_TOKEN => {
            let previous = decode_rectangle_data(element.data.as_ref())?;
            let (_updated, data) =
                apply_typed_style_update(&previous, style_update, decode_rectangle_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Generic,
            })
        }
        LineData::TYPE_ID_TOKEN => {
            let previous = decode_line_data(element.data.as_ref())?;
            let (_updated, data) =
                apply_typed_style_update(&previous, style_update, decode_line_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Generic,
            })
        }
        FreeDrawData::TYPE_ID_TOKEN => {
            let previous = decode_free_draw_data(element.data.as_ref())?;
            let (_updated, data) =
                apply_typed_style_update(&previous, style_update, decode_free_draw_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Generic,
            })
        }
        HighlightData::TYPE_ID_TOKEN => {
            let previous = decode_highlight_data(element.data.as_ref())?;
            let (_updated, data) =
                apply_typed_style_update(&previous, style_update, decode_highlight_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Generic,
            })
        }
        FilterData::TYPE_ID_TOKEN => {
            let previous = decode_filter_data(element.data.as_ref())?;
            let (_updated, data) =
                apply_typed_style_update(&previous, style_update, decode_filter_data)?;
            Some(StyleUpdatedData {
                data,
                kind: StyleUpdatedDataKind::Generic,
            })
        }
        _ => None,
    }
}

fn apply_typed_style_update<T>(
    previous: &T,
    style_update: &ElementStyleUpdate,
    decode_updated: fn(&dyn ElementData) -> Option<T>,
) -> Option<(T, Arc<dyn ElementData>)>
where
    T: Clone + PartialEq + ElementStyleUpdatableData,
{
    let updated_box = previous.with_style_update(style_update.clone());
    let updated_data: Arc<dyn ElementData> = Arc::from(updated_box);
    let updated = decode_updated(updated_data.as_ref())?;
    if &updated == previous {
        return None;
    }
    Some((updated, updated_data))
}

fn resolve_opacity_update(element: ElementState, opacity: Option<f64>) -> ElementState {
    match opacity {
        Some(next_opacity) if next_opacity != element.opacity => {
            element.copy_with(None, None, None, Some(next_opacity), None, None)
        }
        _ => element,
    }
}

fn resolve_text_editing_update<S>(
    state: &S,
    target_ids: &BTreeSet<String>,
    style_update: &ElementStyleUpdate,
    opacity: Option<f64>,
    context: &DrawContext,
) -> Option<TextEditingState>
where
    S: StyleReducerState,
{
    let interaction = state.application().interaction();
    let text_editing = interaction.as_text_editing()?;
    if !target_ids.contains(&text_editing.element_id) {
        return None;
    }

    apply_text_editing_style_update(text_editing, style_update, opacity, context)
}

fn apply_text_editing_style_update(
    interaction: &TextEditingState,
    style_update: &ElementStyleUpdate,
    opacity: Option<f64>,
    _context: &DrawContext,
) -> Option<TextEditingState> {
    let updated_data = if style_update.is_empty() {
        interaction.draft_data.clone()
    } else {
        let updated_box = interaction
            .draft_data
            .with_style_update(style_update.clone());
        decode_text_data(updated_box.as_ref()).unwrap_or_else(|| interaction.draft_data.clone())
    };

    let data_changed = updated_data != interaction.draft_data;
    let opacity_changed = opacity.is_some_and(|value| value != interaction.opacity);
    if !data_changed && !opacity_changed {
        return None;
    }

    let next_rect = if data_changed {
        Some(resolve_text_rect(interaction.rect, &updated_data))
    } else {
        None
    };
    let next_opacity = if opacity_changed { opacity } else { None };
    let next_data = if data_changed {
        Some(updated_data)
    } else {
        None
    };

    Some(interaction.copy_with(next_data, next_rect, None, next_opacity, None, None))
}

fn should_relayout_text(update: &ElementStyleUpdate) -> bool {
    update.font_size.is_some() || update.font_family.is_some()
}

fn should_relayout_serial_number(update: &ElementStyleUpdate) -> bool {
    update.font_size.is_some() || update.font_family.is_some() || update.serial_number.is_some()
}

fn resolve_text_rect(rect: DrawRect, data: &TextData) -> DrawRect {
    let line_height = sanitize_positive_extent(data.font_size * 1.2, 1.0);
    let glyph_width = (data.font_size * 0.6).max(1.0);
    let horizontal_padding = line_height * 0.01;

    let mut line_count = 0usize;
    let mut max_line_chars = 1usize;
    for line in data.text.lines() {
        line_count += 1;
        max_line_chars = max_line_chars.max(line.chars().count().max(1));
    }
    if line_count == 0 {
        line_count = 1;
    }

    let measured_width = max_line_chars as f64 * glyph_width + horizontal_padding * 2.0;
    let measured_height = (line_count as f64 * line_height).max(line_height);
    let width = if data.auto_resize {
        measured_width
    } else {
        rect.width()
    };

    let safe_width = sanitize_positive_extent(width, rect.width().max(1.0));
    let safe_height = sanitize_positive_extent(measured_height, rect.height().max(1.0));

    DrawRect::new(
        rect.min_x,
        rect.min_y,
        rect.min_x + safe_width,
        rect.min_y + safe_height,
    )
}

fn resolve_serial_number_rect(
    rect: DrawRect,
    data: &SerialNumberData,
    context: &DrawContext,
) -> DrawRect {
    resolve_serial_number_layout_rect(
        DrawPoint::new(rect.min_x, rect.min_y),
        data,
        0.0,
        Some(context.text_metrics_service.as_ref()),
    )
}

fn resolve_arrow_rect_and_data(
    element: &ElementState,
    data: &ArrowData,
    elements_by_id: &HashMap<String, ElementState>,
) -> ArrowRectAndData {
    let sanitized_data = data.copy_with(ArrowDataPatch {
        fixed_segments: NullableField::Null,
        start_is_special: NullableField::Null,
        end_is_special: NullableField::Null,
        ..ArrowDataPatch::default()
    });

    if sanitized_data.arrow_type == ArrowType::Elbow {
        let routed =
            route_elbow_arrow_for_element(element, &sanitized_data, elements_by_id, None, None);
        let geometry = resolve_arrow_geometry_update(
            &routed.local_points,
            element.rect,
            element.rotation,
            sanitized_data.arrow_type,
        );
        let updated_data = sanitized_data.copy_with(ArrowDataPatch {
            points: Some(geometry.normalized_points),
            ..ArrowDataPatch::default()
        });

        return ArrowRectAndData {
            rect: geometry.rect,
            data: updated_data,
        };
    }

    let world_points = ArrowGeometry::resolve_world_points(element.rect, &sanitized_data.points);
    let rect = ArrowGeometry::calculate_path_bounds(&world_points, sanitized_data.arrow_type);
    let normalized_points = ArrowGeometry::normalize_points(&world_points, rect);
    let updated_data = sanitized_data.copy_with(ArrowDataPatch {
        points: Some(normalized_points),
        ..ArrowDataPatch::default()
    });

    ArrowRectAndData {
        rect,
        data: updated_data,
    }
}

fn has_selection_geometry_changes(
    selected_ids: &BTreeSet<String>,
    original_elements_by_id: &HashMap<String, ElementState>,
    updates_by_id: &HashMap<String, ElementState>,
) -> bool {
    for id in selected_ids {
        let Some(original) = original_elements_by_id.get(id) else {
            continue;
        };
        let Some(updated) = updates_by_id.get(id) else {
            continue;
        };
        if original.rect != updated.rect || original.rotation != updated.rotation {
            return true;
        }
    }
    false
}

fn should_recompute_elbow_after_style_change(previous: &ArrowData, next: &ArrowData) -> bool {
    if previous.arrow_type != ArrowType::Elbow || next.arrow_type != ArrowType::Elbow {
        return false;
    }

    previous.start_arrowhead != next.start_arrowhead
        || previous.end_arrowhead != next.end_arrowhead
        || previous.stroke_width != next.stroke_width
}
fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn decode_text_data(data: &dyn ElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn ElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

fn decode_arrow_data(data: &dyn ElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}

fn decode_rectangle_data(data: &dyn ElementData) -> Option<RectangleData> {
    if data.type_id().as_str() != RectangleData::TYPE_ID_TOKEN {
        return None;
    }
    RectangleData::from_json(&data.to_json()).ok()
}

fn decode_line_data(data: &dyn ElementData) -> Option<LineData> {
    if data.type_id().as_str() != LineData::TYPE_ID_TOKEN {
        return None;
    }
    LineData::from_json(&data.to_json()).ok()
}

fn decode_free_draw_data(data: &dyn ElementData) -> Option<FreeDrawData> {
    if data.type_id().as_str() != FreeDrawData::TYPE_ID_TOKEN {
        return None;
    }
    FreeDrawData::from_json(&data.to_json()).ok()
}

fn decode_highlight_data(data: &dyn ElementData) -> Option<HighlightData> {
    if data.type_id().as_str() != HighlightData::TYPE_ID_TOKEN {
        return None;
    }
    HighlightData::from_json(&data.to_json()).ok()
}

fn decode_filter_data(data: &dyn ElementData) -> Option<FilterData> {
    if data.type_id().as_str() != FilterData::TYPE_ID_TOKEN {
        return None;
    }
    FilterData::from_json(&data.to_json()).ok()
}

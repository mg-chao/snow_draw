#![allow(dead_code)]

use std::any::TypeId;
use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::Arc;
use std::time::Instant;

use crate::draw::actions::draw_actions::{
    ClearDragPending, ClearSelection, SelectElement, SetDragPending, StartBoxSelect, StartEdit,
    UpdateEdit,
};
use crate::draw::config::draw_config::{DrawConfig, SelectionConfig};
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::core::edit_intent_to_operation_mapper::{
    ArrowPointOperationParams as MapperArrowPointOperationParams,
    EditOperationParams as MapperEditOperationParams,
    MoveOperationParams as MapperMoveOperationParams,
    ResizeOperationParams as MapperResizeOperationParams,
    RotateOperationParams as MapperRotateOperationParams, StartEdit as MapperStartEdit,
};
use crate::draw::edit::core::edit_operation_params::{
    ArrowPointOperationParams, EditOperationParams, MoveOperationParams, ResizeOperationParams,
    RotateOperationParams,
};
use crate::draw::elements::core::element_data::{DynElementData, ElementTypeId};
use crate::draw::elements::core::element_registry::DefaultElementRegistry;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_points::{
    ArrowPointHandle, ArrowPointKind as DomainArrowPointKind,
};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::input::double_tap_tracker::DoubleTapTracker;
use crate::draw::input::input_event::{
    PointerCancelInputEvent, PointerDownInputEvent, PointerMoveInputEvent, PointerUpInputEvent,
};
use crate::draw::input::plugin_engine::{
    downcast_input_event, DrawInputPlugin, InputEvent, InputPlugin, InputPluginBase,
    InputRoutingPolicy, PluginError, PluginHandleResult, PluginLifecycleResult,
    SupportedEventTypes,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::interaction_state::{
    DragPendingState, InteractionState, PendingIntent, PendingMoveIntent, PendingSelectIntent,
};
use crate::draw::services::draw_state_view_builder::DrawStateViewBuilder;
use crate::draw::services::element_hit_test_service::hit_test_element;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;
use crate::draw::utils::edit_intent_detector::{
    ArrowLikeData as DetectorArrowLikeData, ArrowPointKind as DetectorArrowPointKind,
    ClearSelectionIntent, DocumentState as DetectorDocumentState,
    DomainState as DetectorDomainState, DrawState as DetectorDrawState,
    DrawStateView as DetectorDrawStateView, EditIntent, ElementData as DetectorElementData,
    ElementState as DetectorElementState, HandleType as DetectorHandleType, HitTestRequest,
    HitTestResult as DetectorHitTestResult, HitTestService, HitTestTarget as DetectorHitTestTarget,
    SelectionState as DetectorSelectionState, StartArrowPointIntent, StartMoveIntent,
    EDIT_INTENT_DETECTOR,
};

#[derive(Clone, Debug, PartialEq)]
pub struct DragPendingSnapshot {
    pub pointer_down_position: DrawPoint,
    pub intent: PendingIntent,
}

impl DragPendingSnapshot {
    pub fn new(pointer_down_position: DrawPoint, intent: PendingIntent) -> Self {
        Self {
            pointer_down_position,
            intent,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowLikeDataSnapshot {
    pub points: Vec<DrawPoint>,
    pub arrow_type: ArrowType,
    pub fixed_segment_indexes: BTreeSet<usize>,
}

impl ArrowLikeDataSnapshot {
    pub fn is_fixed_segment(&self, index: usize) -> bool {
        self.fixed_segment_indexes.contains(&index)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct SelectableElementSnapshot {
    pub id: String,
    pub type_id: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub z_index: i64,
    pub is_text: bool,
    pub arrow_data: Option<ArrowLikeDataSnapshot>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SelectPluginStateSnapshot {
    pub draw_state: DrawState,
    pub draw_config: DrawConfig,
    pub selection_config: SelectionConfig,
    pub drag_pending: Option<DragPendingSnapshot>,
    pub selected_ids: BTreeSet<String>,
    pub elements: Vec<SelectableElementSnapshot>,
    pub elements_by_id: HashMap<String, SelectableElementSnapshot>,
    pub bound_text_ids: BTreeSet<String>,
}

impl Default for SelectPluginStateSnapshot {
    fn default() -> Self {
        Self {
            draw_state: DrawState::default(),
            draw_config: DrawConfig::default(),
            selection_config: SelectionConfig::default(),
            drag_pending: None,
            selected_ids: BTreeSet::new(),
            elements: Vec::new(),
            elements_by_id: HashMap::new(),
            bound_text_ids: BTreeSet::new(),
        }
    }
}

pub trait SelectPluginStateAdapter: Send + Sync {
    fn snapshot(&self, state: &DrawState, context: &DrawContext) -> SelectPluginStateSnapshot;
}

#[derive(Debug, Default)]
pub struct DefaultSelectPluginStateAdapter;

impl SelectPluginStateAdapter for DefaultSelectPluginStateAdapter {
    fn snapshot(&self, state: &DrawState, context: &DrawContext) -> SelectPluginStateSnapshot {
        let draw_config = context.config();
        let selection_config = draw_config.selection.clone();

        let drag_pending = match &state.application.interaction {
            InteractionState::DragPending(DragPendingState {
                pointer_down_position,
                intent,
            }) => Some(DragPendingSnapshot::new(
                *pointer_down_position,
                intent.clone(),
            )),
            _ => None,
        };

        let mut elements = Vec::with_capacity(state.domain.document.elements.len());
        let mut elements_by_id = HashMap::with_capacity(state.domain.document.elements.len());

        for element in &state.domain.document.elements {
            let type_id = element.data.type_id().as_str().to_owned();
            let arrow_data = arrow_data_snapshot_for_element(element);
            let snapshot = SelectableElementSnapshot {
                id: element.id.clone(),
                type_id: type_id.clone(),
                rect: element.rect,
                rotation: element.rotation,
                z_index: element.z_index,
                is_text: type_id == TextData::TYPE_ID_TOKEN,
                arrow_data,
            };
            elements.push(snapshot.clone());
            elements_by_id.insert(snapshot.id.clone(), snapshot);
        }

        SelectPluginStateSnapshot {
            draw_state: state.clone(),
            draw_config,
            selection_config,
            drag_pending,
            selected_ids: state.domain.selection.selected_ids.clone(),
            elements,
            elements_by_id,
            bound_text_ids: collect_bound_text_ids(&state.domain.document.elements),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
struct HitResult {
    hit_element_id: Option<String>,
    handle_type: Option<DetectorHandleType>,
    target: DetectorHitTestTarget,
    is_in_selection_padding: bool,
}

impl HitResult {
    fn none() -> Self {
        Self {
            hit_element_id: None,
            handle_type: None,
            target: DetectorHitTestTarget::None,
            is_in_selection_padding: false,
        }
    }
}

impl Default for HitResult {
    fn default() -> Self {
        Self::none()
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct SingleSelectionProfile {
    is_two_point_arrow: bool,
    is_elbow_arrow: bool,
    is_text: bool,
    corner_handle_offset: f64,
}

#[derive(Clone, Copy, Debug)]
struct SelectionHitContext {
    bounds: DrawRect,
    rotation: f64,
    origin: DrawPoint,
    cos: f64,
    sin: f64,
    padded_bounds: DrawRect,
    handle_bounds: DrawRect,
    test_position: DrawPoint,
}

impl SelectionHitContext {
    fn contains_in_padded_area(&self) -> bool {
        let position = self.test_position;
        let bounds = self.padded_bounds;
        position.x >= bounds.min_x
            && position.x <= bounds.max_x
            && position.y >= bounds.min_y
            && position.y <= bounds.max_y
    }
}

struct SelectPluginHitTestService<'a> {
    plugin: &'a SelectPlugin,
    snapshot: &'a SelectPluginStateSnapshot,
}

impl<'a> SelectPluginHitTestService<'a> {
    fn new(plugin: &'a SelectPlugin, snapshot: &'a SelectPluginStateSnapshot) -> Self {
        Self { plugin, snapshot }
    }
}

impl HitTestService for SelectPluginHitTestService<'_> {
    fn test(&self, request: HitTestRequest<'_>) -> DetectorHitTestResult {
        let hit = self.plugin.hit_test_with_registry(
            self.snapshot,
            request.position,
            request.filter_type_id.map(|type_id| type_id.as_str()),
            Some(request.registry),
        );

        if hit.target == DetectorHitTestTarget::None {
            return DetectorHitTestResult::none();
        }

        DetectorHitTestResult {
            element_id: hit.hit_element_id,
            handle_type: hit.handle_type,
            target: hit.target,
            is_in_selection_padding: hit.is_in_selection_padding,
        }
    }
}

pub struct SelectPlugin {
    base: InputPluginBase,
    arrow_handle_double_tap_tracker: DoubleTapTracker<ArrowPointHandle>,
    routing_policy: InputRoutingPolicy,
    state_adapter: Arc<dyn SelectPluginStateAdapter>,
    pub current_tool_type_id: Option<ElementTypeId<DynElementData>>,
    pub is_selection_tool_active: bool,
}

impl SelectPlugin {
    pub fn new(
        current_tool_type_id: Option<ElementTypeId<DynElementData>>,
        is_selection_tool_active: bool,
        routing_policy: Option<InputRoutingPolicy>,
    ) -> Self {
        Self {
            base: InputPluginBase::new("select", "Select Plugin", 20, supported_event_types()),
            arrow_handle_double_tap_tracker: DoubleTapTracker::default(),
            routing_policy: routing_policy.unwrap_or_default(),
            state_adapter: Arc::new(DefaultSelectPluginStateAdapter),
            current_tool_type_id,
            is_selection_tool_active,
        }
    }

    pub fn with_state_adapter(mut self, state_adapter: Arc<dyn SelectPluginStateAdapter>) -> Self {
        self.state_adapter = state_adapter;
        self
    }

    pub fn set_current_tool_type_id(
        &mut self,
        current_tool_type_id: Option<ElementTypeId<DynElementData>>,
    ) {
        self.current_tool_type_id = current_tool_type_id;
    }

    fn state_snapshot(&self) -> SelectPluginStateSnapshot {
        let state = self.state();
        let context = self.draw_context();
        self.state_adapter.snapshot(&state, &context)
    }

    fn dispatch_action<A>(&self, action: A) -> Result<(), PluginError>
    where
        A: Send + Sync + 'static,
    {
        self.dispatch(Box::new(action))
            .map_err(|error| Box::new(error) as PluginError)
    }

    fn handle_pointer_down(
        &mut self,
        event: &PointerDownInputEvent,
        snapshot: &SelectPluginStateSnapshot,
    ) -> PluginHandleResult {
        let position = event.input.position;
        let modifiers = event.input.modifiers;

        let intent = {
            let draw_context = self.draw_context();
            let detector_state_view = build_detector_state_view(snapshot, &draw_context);
            let hit_test_service = SelectPluginHitTestService::new(self, snapshot);
            self.filter_intent_for_tool(
                EDIT_INTENT_DETECTOR.detect_intent(
                    &detector_state_view,
                    position,
                    modifiers.shift,
                    &snapshot.selection_config,
                    draw_context.element_registry.as_ref(),
                    self.current_tool_type_id.as_ref(),
                    &hit_test_service,
                ),
                snapshot,
            )
        };

        let Some(intent) = intent else {
            return Ok(self.base.unhandled(None));
        };

        if let EditIntent::StartArrowPoint(start_intent) = &intent {
            let now = Instant::now();
            if let Some(data) = snapshot
                .elements_by_id
                .get(start_intent.element_id.as_str())
                .and_then(|element| element.arrow_data.as_ref())
            {
                let handle = self.resolve_arrow_handle_for_intent(start_intent, position, data);
                let can_double_click = self.is_arrow_handle_double_click_candidate(&handle, data);

                if can_double_click
                    && self.arrow_handle_double_tap_tracker.is_double_tap(
                        &handle,
                        position,
                        now,
                        snapshot.selection_config.interaction.handle_tolerance,
                    )
                {
                    self.arrow_handle_double_tap_tracker.clear();
                    let mut double_click_intent = start_intent.clone();
                    double_click_intent.is_double_click = true;
                    self.execute_intent(
                        &EditIntent::StartArrowPoint(double_click_intent),
                        position,
                        snapshot,
                    )?;

                    let message = if handle.is_fixed {
                        "Arrow segment released"
                    } else {
                        "Arrow point deleted"
                    };
                    return Ok(self.base.handled(Some(message.to_owned())));
                }

                if can_double_click {
                    self.arrow_handle_double_tap_tracker
                        .record_tap(handle, position, now);
                } else {
                    self.arrow_handle_double_tap_tracker.clear();
                }
            } else {
                self.arrow_handle_double_tap_tracker.clear();
            }
        } else {
            self.arrow_handle_double_tap_tracker.clear();
        }

        if let EditIntent::Select(select_intent) = &intent {
            if select_intent.defer_selection_for_drag {
                self.dispatch_action(SetDragPending::new(
                    position,
                    PendingIntent::from(PendingSelectIntent::new(
                        select_intent.element_id.clone(),
                        select_intent.add_to_selection,
                    )),
                ))?;
                return Ok(self.base.handled(Some("Pending select".to_owned())));
            }
        }

        self.execute_intent(&intent, position, snapshot)?;
        Ok(self.base.handled(Some("Selection handled".to_owned())))
    }

    fn handle_pointer_move(
        &self,
        event: &PointerMoveInputEvent,
        snapshot: &SelectPluginStateSnapshot,
    ) -> PluginHandleResult {
        let Some(drag_pending) = snapshot.drag_pending.as_ref() else {
            return Ok(self.base.unhandled(None));
        };

        if !has_reached_drag_threshold(
            drag_pending.pointer_down_position,
            event.input.position,
            snapshot.draw_config.selection.interaction.drag_threshold,
        ) {
            return Ok(self.base.handled(Some("Pending drag".to_owned())));
        }

        self.dispatch_action(ClearDragPending)?;

        let Some(start_move_intent) =
            self.resolve_pending_drag_start_intent(&drag_pending.intent, snapshot)
        else {
            return Ok(self.base.handled(Some("Pending drag".to_owned())));
        };

        let did_start = self.dispatch_mapped_start_edit(
            &EditIntent::StartMove(start_move_intent),
            drag_pending.pointer_down_position,
            true,
            snapshot,
        )?;

        if did_start {
            self.update_edit_from_event(event)?;
        }

        Ok(self.base.handled(Some("Pending drag".to_owned())))
    }

    fn handle_pointer_up(&self, snapshot: &SelectPluginStateSnapshot) -> PluginHandleResult {
        let Some(drag_pending) = snapshot.drag_pending.as_ref() else {
            return Ok(self.base.unhandled(None));
        };

        if let PendingIntent::Select(pending_intent) = &drag_pending.intent {
            self.dispatch_action(SelectElement::new(
                pending_intent.element_id.clone(),
                drag_pending.pointer_down_position,
                pending_intent.add_to_selection,
            ))?;
        }

        self.dispatch_action(ClearDragPending)?;
        Ok(self.base.handled(Some("Pending cleared".to_owned())))
    }

    fn handle_pointer_cancel(&self, snapshot: &SelectPluginStateSnapshot) -> PluginHandleResult {
        if snapshot.drag_pending.is_some() {
            self.dispatch_action(ClearDragPending)?;
            return Ok(self.base.consumed(Some("Pending canceled".to_owned())));
        }

        Ok(self.base.unhandled(None))
    }

    fn hit_test(
        &self,
        snapshot: &SelectPluginStateSnapshot,
        position: DrawPoint,
        filter_type_id: Option<&str>,
    ) -> HitResult {
        self.hit_test_with_registry(snapshot, position, filter_type_id, None)
    }

    fn hit_test_with_registry(
        &self,
        snapshot: &SelectPluginStateSnapshot,
        position: DrawPoint,
        filter_type_id: Option<&str>,
        registry: Option<&DefaultElementRegistry>,
    ) -> HitResult {
        let tolerance = snapshot.selection_config.interaction.handle_tolerance;
        let state_view_builder = match self.base.try_context() {
            Ok(plugin_context) => {
                let draw_context = plugin_context.context();
                DrawStateViewBuilder::new(draw_context.edit_operations.as_ref().clone(), None)
            }
            Err(_) => DrawStateViewBuilder::default(),
        };
        let state_view = state_view_builder.build(&snapshot.draw_state);
        let effective_elements = state_view
            .elements()
            .iter()
            .map(|element| state_view.effective_element(element))
            .collect::<Vec<_>>();
        let selection = state_view.effective_selection();
        let single_selection =
            self.resolve_single_selection_profile(snapshot, effective_elements.as_slice());
        let bound_text_ids = &snapshot.bound_text_ids;

        let mut selection_context = None;
        let mut is_in_selection_padding = false;

        if selection.has_selection && !single_selection.is_two_point_arrow {
            selection_context = self.build_selection_context(
                selection.bounds,
                selection.rotation,
                selection.center,
                position,
                &snapshot.selection_config,
                single_selection.corner_handle_offset,
            );

            if let Some(context) = selection_context.as_ref() {
                is_in_selection_padding = context.contains_in_padded_area();
                if let Some(handle_hit) = self.test_handles(
                    context,
                    position,
                    tolerance,
                    &snapshot.selection_config,
                    is_in_selection_padding,
                    single_selection.is_text,
                    !single_selection.is_elbow_arrow,
                ) {
                    return handle_hit;
                }
            }
        }

        let mut ordered = effective_elements;
        ordered.sort_by(|left, right| {
            left.z_index
                .cmp(&right.z_index)
                .then_with(|| left.id.cmp(&right.id))
        });

        for element in ordered.into_iter().rev() {
            let is_text = element.data.type_id().as_str() == TextData::TYPE_ID_TOKEN;
            if !self.matches_filter_for_effective_element(
                element.id.as_str(),
                element.data.type_id().as_str(),
                is_text,
                filter_type_id,
                bound_text_ids,
            ) {
                continue;
            }

            if self.hit_test_effective_element(&element, position, tolerance, registry) {
                return HitResult {
                    hit_element_id: Some(element.id.clone()),
                    handle_type: None,
                    target: DetectorHitTestTarget::Element,
                    is_in_selection_padding,
                };
            }
        }

        if selection_context.is_some()
            && is_in_selection_padding
            && !snapshot.selected_ids.is_empty()
        {
            return HitResult {
                hit_element_id: snapshot.selected_ids.iter().next().cloned(),
                handle_type: None,
                target: DetectorHitTestTarget::SelectionPadding,
                is_in_selection_padding: true,
            };
        }

        HitResult {
            is_in_selection_padding,
            ..HitResult::none()
        }
    }

    fn resolve_single_selection_profile(
        &self,
        snapshot: &SelectPluginStateSnapshot,
        effective_elements: &[crate::draw::models::element_state::ElementState],
    ) -> SingleSelectionProfile {
        if snapshot.selected_ids.len() != 1 {
            return SingleSelectionProfile::default();
        }

        let Some(selected_id) = snapshot.selected_ids.iter().next() else {
            return SingleSelectionProfile::default();
        };
        let effective_element = effective_elements
            .iter()
            .find(|element| element.id == selected_id.as_str())
            .cloned();

        let snapshot_element = snapshot.elements_by_id.get(selected_id.as_str());

        if effective_element.is_none() && snapshot_element.is_none() {
            return SingleSelectionProfile::default();
        }

        let (is_two_point_arrow, is_elbow_arrow, corner_handle_offset) = if let Some(arrow_data) =
            effective_element
                .as_ref()
                .and_then(arrow_data_snapshot_for_element)
                .or_else(|| snapshot_element.and_then(|element| element.arrow_data.clone()))
        {
            (
                arrow_data.points.len() == 2,
                arrow_data.arrow_type == ArrowType::Elbow,
                8.0,
            )
        } else {
            (false, false, 0.0)
        };

        let is_text = effective_element
            .as_ref()
            .map(|element| element.data.type_id().as_str() == TextData::TYPE_ID_TOKEN)
            .unwrap_or(false)
            || snapshot_element
                .map(|element| element.is_text)
                .unwrap_or(false);
        SingleSelectionProfile {
            is_two_point_arrow,
            is_elbow_arrow,
            is_text,
            corner_handle_offset,
        }
    }

    fn build_selection_context(
        &self,
        overlay_bounds: Option<DrawRect>,
        overlay_rotation: Option<f64>,
        overlay_center: Option<DrawPoint>,
        position: DrawPoint,
        config: &SelectionConfig,
        corner_handle_offset: f64,
    ) -> Option<SelectionHitContext> {
        let bounds = overlay_bounds?;
        let rotation = overlay_rotation.unwrap_or(0.0);
        let origin = overlay_center.unwrap_or(bounds.center());
        let (cos, sin) = if rotation == 0.0 {
            (1.0, 0.0)
        } else {
            (rotation.cos(), rotation.sin())
        };

        let padding = config.padding;
        let padded_bounds = DrawRect::new(
            bounds.min_x - padding,
            bounds.min_y - padding,
            bounds.max_x + padding,
            bounds.max_y + padding,
        );
        let handle_bounds = DrawRect::new(
            padded_bounds.min_x - corner_handle_offset,
            padded_bounds.min_y - corner_handle_offset,
            padded_bounds.max_x + corner_handle_offset,
            padded_bounds.max_y + corner_handle_offset,
        );
        let test_position = if rotation == 0.0 {
            position
        } else {
            let dx = position.x - origin.x;
            let dy = position.y - origin.y;
            DrawPoint::new(
                origin.x + dx * cos + dy * sin,
                origin.y - dx * sin + dy * cos,
            )
        };

        Some(SelectionHitContext {
            bounds,
            rotation,
            origin,
            cos,
            sin,
            padded_bounds,
            handle_bounds,
            test_position,
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn test_handles(
        &self,
        context: &SelectionHitContext,
        position: DrawPoint,
        tolerance: f64,
        config: &SelectionConfig,
        is_in_selection_padding: bool,
        prioritize_move_in_selection_padding: bool,
        allow_rotate_handle: bool,
    ) -> Option<HitResult> {
        if prioritize_move_in_selection_padding && is_in_selection_padding {
            return None;
        }

        let bounds = context.bounds;
        let padded_bounds = context.padded_bounds;
        let handle_bounds = context.handle_bounds;
        let test_position = context.test_position;
        let rotation = context.rotation;
        let padding = config.padding;

        if allow_rotate_handle {
            let margin = config.rotate_handle_offset;
            let rotate_handle_x = bounds.center_x();
            let rotate_handle_y = bounds.min_y - padding - margin;
            if self.is_near_rotated_point(
                position,
                rotate_handle_x,
                rotate_handle_y,
                context,
                tolerance,
            ) {
                return Some(self.build_handle_hit_result(
                    DetectorHandleType::Rotate,
                    rotation,
                    is_in_selection_padding,
                ));
            }
        }

        if let Some(corner_handle) =
            self.resolve_corner_handle(handle_bounds, position, context, tolerance)
        {
            return Some(self.build_handle_hit_result(
                corner_handle,
                rotation,
                is_in_selection_padding,
            ));
        }

        if let Some(edge_handle) = self.resolve_edge_handle(padded_bounds, test_position, tolerance)
        {
            return Some(self.build_handle_hit_result(
                edge_handle,
                rotation,
                is_in_selection_padding,
            ));
        }

        None
    }

    fn build_handle_hit_result(
        &self,
        handle: DetectorHandleType,
        _rotation: f64,
        is_in_selection_padding: bool,
    ) -> HitResult {
        HitResult {
            hit_element_id: None,
            handle_type: Some(handle),
            target: DetectorHitTestTarget::Handle,
            is_in_selection_padding,
        }
    }

    fn resolve_corner_handle(
        &self,
        handle_bounds: DrawRect,
        position: DrawPoint,
        context: &SelectionHitContext,
        tolerance: f64,
    ) -> Option<DetectorHandleType> {
        let min_x = handle_bounds.min_x;
        let min_y = handle_bounds.min_y;
        let max_x = handle_bounds.max_x;
        let max_y = handle_bounds.max_y;

        if self.is_near_rotated_point(position, min_x, min_y, context, tolerance) {
            return Some(DetectorHandleType::TopLeft);
        }
        if self.is_near_rotated_point(position, max_x, min_y, context, tolerance) {
            return Some(DetectorHandleType::TopRight);
        }
        if self.is_near_rotated_point(position, max_x, max_y, context, tolerance) {
            return Some(DetectorHandleType::BottomRight);
        }
        if self.is_near_rotated_point(position, min_x, max_y, context, tolerance) {
            return Some(DetectorHandleType::BottomLeft);
        }

        None
    }

    fn resolve_edge_handle(
        &self,
        padded_bounds: DrawRect,
        position: DrawPoint,
        tolerance: f64,
    ) -> Option<DetectorHandleType> {
        if self.test_top_edge(padded_bounds, position, tolerance) {
            return Some(DetectorHandleType::Top);
        }
        if self.test_right_edge(padded_bounds, position, tolerance) {
            return Some(DetectorHandleType::Right);
        }
        if self.test_bottom_edge(padded_bounds, position, tolerance) {
            return Some(DetectorHandleType::Bottom);
        }
        if self.test_left_edge(padded_bounds, position, tolerance) {
            return Some(DetectorHandleType::Left);
        }
        None
    }

    fn is_near_rotated_point(
        &self,
        position: DrawPoint,
        local_x: f64,
        local_y: f64,
        context: &SelectionHitContext,
        tolerance: f64,
    ) -> bool {
        if context.rotation == 0.0 {
            return self.is_near_point_coordinates(position, local_x, local_y, tolerance);
        }

        let origin = context.origin;
        let dx = local_x - origin.x;
        let dy = local_y - origin.y;
        let world_x = origin.x + dx * context.cos - dy * context.sin;
        let world_y = origin.y + dx * context.sin + dy * context.cos;
        self.is_near_point_coordinates(position, world_x, world_y, tolerance)
    }

    fn is_near_point_coordinates(&self, point: DrawPoint, x: f64, y: f64, tolerance: f64) -> bool {
        let dx = point.x - x;
        let dy = point.y - y;
        (dx * dx + dy * dy) <= tolerance * tolerance
    }

    fn test_top_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_horizontal_edge(bounds, position, bounds.min_y, tolerance)
    }

    fn test_right_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_vertical_edge(bounds, position, bounds.max_x, tolerance)
    }

    fn test_bottom_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_horizontal_edge(bounds, position, bounds.max_y, tolerance)
    }

    fn test_left_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_vertical_edge(bounds, position, bounds.min_x, tolerance)
    }

    fn test_horizontal_edge(
        &self,
        bounds: DrawRect,
        position: DrawPoint,
        edge_y: f64,
        tolerance: f64,
    ) -> bool {
        self.is_near(position.y, edge_y, tolerance)
            && self.is_inside_edge_span(position.x, bounds.min_x, bounds.max_x, tolerance)
    }

    fn test_vertical_edge(
        &self,
        bounds: DrawRect,
        position: DrawPoint,
        edge_x: f64,
        tolerance: f64,
    ) -> bool {
        self.is_near(position.x, edge_x, tolerance)
            && self.is_inside_edge_span(position.y, bounds.min_y, bounds.max_y, tolerance)
    }

    fn is_inside_edge_span(&self, value: f64, min: f64, max: f64, tolerance: f64) -> bool {
        value > min + tolerance && value < max - tolerance
    }

    fn is_near(&self, value: f64, target: f64, tolerance: f64) -> bool {
        (value - target).abs() <= tolerance
    }

    fn execute_intent(
        &self,
        intent: &EditIntent,
        position: DrawPoint,
        snapshot: &SelectPluginStateSnapshot,
    ) -> Result<(), PluginError> {
        match intent {
            EditIntent::Select(intent) => {
                self.dispatch_action(SelectElement::new(
                    intent.element_id.clone(),
                    position,
                    intent.add_to_selection,
                ))?;

                if !intent.add_to_selection {
                    self.dispatch_action(SetDragPending::new(
                        position,
                        PendingIntent::from(PendingMoveIntent),
                    ))?;
                }

                Ok(())
            }
            EditIntent::StartMove(intent) => {
                if !snapshot.selected_ids.contains(intent.element_id.as_str()) {
                    self.dispatch_action(SelectElement::new(
                        intent.element_id.clone(),
                        position,
                        intent.add_to_selection,
                    ))?;
                }

                self.dispatch_action(SetDragPending::new(
                    position,
                    PendingIntent::from(PendingMoveIntent),
                ))?;
                Ok(())
            }
            EditIntent::BoxSelect(intent) => {
                self.dispatch_action(StartBoxSelect::new(intent.start_position))
            }
            EditIntent::ClearSelection(_) => self.dispatch_action(ClearSelection),
            _ => {
                let _ = self.dispatch_mapped_start_edit(intent, position, false, snapshot)?;
                Ok(())
            }
        }
    }

    fn dispatch_mapped_start_edit(
        &self,
        intent: &EditIntent,
        position: DrawPoint,
        require_session_start: bool,
        snapshot: &SelectPluginStateSnapshot,
    ) -> Result<bool, PluginError> {
        let Some(start_edit) = self.map_to_start_edit(intent, position, snapshot) else {
            return Ok(false);
        };

        let was_editing = snapshot.draw_state.application.is_editing();
        self.dispatch_action(start_edit)?;

        if !require_session_start {
            return Ok(true);
        }

        Ok(!was_editing && self.state().application.is_editing())
    }

    fn map_to_start_edit(
        &self,
        intent: &EditIntent,
        position: DrawPoint,
        snapshot: &SelectPluginStateSnapshot,
    ) -> Option<StartEdit> {
        let draw_context = self.draw_context();
        let mapped = draw_context.edit_intent_mapper.map_to_start_edit(
            intent,
            position,
            &snapshot.draw_config,
        )?;
        Some(convert_mapper_start_edit(mapped))
    }

    fn update_edit_from_event(&self, event: &PointerMoveInputEvent) -> Result<(), PluginError> {
        self.dispatch_action(UpdateEdit::new(
            event.input.position,
            event.input.modifiers.to_edit_modifiers(),
        ))
    }

    fn filter_intent_for_tool(
        &self,
        intent: Option<EditIntent>,
        snapshot: &SelectPluginStateSnapshot,
    ) -> Option<EditIntent> {
        let intent = intent?;

        if self.is_selection_behavior_disabled() {
            return None;
        }

        let Some(tool_type_id) = self.current_tool_type_id.as_ref().map(|id| id.as_str()) else {
            return Some(intent);
        };

        match intent {
            EditIntent::BoxSelect(_) => Some(EditIntent::ClearSelection(ClearSelectionIntent)),
            EditIntent::Select(select_intent) => {
                if self.is_selectable_element(
                    select_intent.element_id.as_str(),
                    tool_type_id,
                    snapshot,
                ) {
                    Some(EditIntent::Select(select_intent))
                } else {
                    None
                }
            }
            EditIntent::StartMove(move_intent) => {
                if self.is_selectable_element(
                    move_intent.element_id.as_str(),
                    tool_type_id,
                    snapshot,
                ) {
                    Some(EditIntent::StartMove(move_intent))
                } else {
                    None
                }
            }
            other => Some(other),
        }
    }

    fn is_selection_behavior_disabled(&self) -> bool {
        self.current_tool_type_id.is_none() && !self.is_selection_tool_active
    }

    fn is_selectable_element(
        &self,
        element_id: &str,
        tool_type_id: &str,
        snapshot: &SelectPluginStateSnapshot,
    ) -> bool {
        let Some(element) = snapshot.elements_by_id.get(element_id) else {
            return false;
        };

        if element.type_id == tool_type_id {
            return true;
        }

        if tool_type_id == SerialNumberData::TYPE_ID_TOKEN && element.is_text {
            return snapshot.bound_text_ids.contains(element_id);
        }

        false
    }

    fn matches_filter_for_effective_element(
        &self,
        element_id: &str,
        element_type_id: &str,
        is_text: bool,
        filter_type_id: Option<&str>,
        bound_text_ids: &BTreeSet<String>,
    ) -> bool {
        let Some(filter_type_id) = filter_type_id else {
            return true;
        };

        if element_type_id == filter_type_id {
            return true;
        }

        if filter_type_id == SerialNumberData::TYPE_ID_TOKEN
            && is_text
            && bound_text_ids.contains(element_id)
        {
            return true;
        }

        false
    }

    fn hit_test_effective_element(
        &self,
        element: &crate::draw::models::element_state::ElementState,
        position: DrawPoint,
        tolerance: f64,
        registry: Option<&DefaultElementRegistry>,
    ) -> bool {
        if let Some(registry) = registry {
            if let Some(definition) = registry.get_definition_by_value(element.type_id().as_str()) {
                if let Some(is_hit) = definition.hit_test(element, position, tolerance) {
                    return is_hit;
                }
            }
        }

        hit_test_element(element, position, tolerance)
    }

    fn resolve_arrow_handle_for_intent(
        &self,
        intent: &StartArrowPointIntent,
        position: DrawPoint,
        data: &ArrowLikeDataSnapshot,
    ) -> ArrowPointHandle {
        let is_fixed = data.arrow_type == ArrowType::Elbow
            && intent.point_kind == DetectorArrowPointKind::Addable
            && data.is_fixed_segment(intent.point_index + 1);

        ArrowPointHandle::with_fixed(
            intent.element_id.clone(),
            map_detector_arrow_point_kind(intent.point_kind),
            intent.point_index,
            position,
            is_fixed,
        )
    }

    fn is_arrow_handle_double_click_candidate(
        &self,
        handle: &ArrowPointHandle,
        data: &ArrowLikeDataSnapshot,
    ) -> bool {
        if handle.is_fixed {
            return true;
        }
        if handle.kind != DomainArrowPointKind::Turning {
            return false;
        }

        let point_count = data.points.len();
        handle.index > 0 && handle.index + 1 < point_count
    }

    fn resolve_pending_drag_start_intent(
        &self,
        pending_intent: &PendingIntent,
        snapshot: &SelectPluginStateSnapshot,
    ) -> Option<StartMoveIntent> {
        match pending_intent {
            PendingIntent::Select(intent) => {
                if snapshot.selected_ids.is_empty() {
                    None
                } else {
                    Some(StartMoveIntent {
                        element_id: intent.element_id.clone(),
                        add_to_selection: intent.add_to_selection,
                    })
                }
            }
            PendingIntent::Move(_) => {
                snapshot
                    .selected_ids
                    .iter()
                    .next()
                    .map(|element_id| StartMoveIntent {
                        element_id: element_id.clone(),
                        add_to_selection: false,
                    })
            }
        }
    }
}

impl Default for SelectPlugin {
    fn default() -> Self {
        Self::new(None, true, None)
    }
}

impl InputPlugin for SelectPlugin {
    fn id(&self) -> &str {
        self.base.id()
    }

    fn name(&self) -> &str {
        self.base.name()
    }

    fn priority(&self) -> i32 {
        self.base.priority()
    }

    fn supported_event_types(&self) -> &SupportedEventTypes {
        self.base.supported_event_types()
    }

    fn on_load(
        &mut self,
        context: crate::draw::input::plugin_engine::PluginContext,
    ) -> PluginLifecycleResult {
        <InputPluginBase as InputPlugin>::on_load(&mut self.base, context)
    }

    fn on_unload(&mut self) -> PluginLifecycleResult {
        <InputPluginBase as InputPlugin>::on_unload(&mut self.base)
    }

    fn can_handle(&self, _event: &InputEvent, state: &DrawState) -> bool {
        !self.is_selection_behavior_disabled() && self.routing_policy.allow_selection(state)
    }

    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();

        if let Some(pointer_down) = downcast_input_event::<PointerDownInputEvent>(event) {
            return self.handle_pointer_down(pointer_down, &snapshot);
        }
        if let Some(pointer_move) = downcast_input_event::<PointerMoveInputEvent>(event) {
            return self.handle_pointer_move(pointer_move, &snapshot);
        }
        if downcast_input_event::<PointerUpInputEvent>(event).is_some() {
            return self.handle_pointer_up(&snapshot);
        }
        if downcast_input_event::<PointerCancelInputEvent>(event).is_some() {
            return self.handle_pointer_cancel(&snapshot);
        }

        Ok(self.base.unhandled(None))
    }

    fn reset(&mut self) {
        self.arrow_handle_double_tap_tracker.clear();
    }
}

impl DrawInputPlugin for SelectPlugin {
    fn base(&self) -> &InputPluginBase {
        &self.base
    }

    fn base_mut(&mut self) -> &mut InputPluginBase {
        &mut self.base
    }
}

fn supported_event_types() -> SupportedEventTypes {
    let mut types = SupportedEventTypes::new();
    types.insert(TypeId::of::<PointerDownInputEvent>());
    types.insert(TypeId::of::<PointerMoveInputEvent>());
    types.insert(TypeId::of::<PointerUpInputEvent>());
    types.insert(TypeId::of::<PointerCancelInputEvent>());
    types
}

fn selection_bounds_for_elements(elements: &[&SelectableElementSnapshot]) -> Option<DrawRect> {
    if elements.is_empty() {
        return None;
    }

    let mut bounds = element_world_aabb(elements[0]);
    for element in &elements[1..] {
        let aabb = element_world_aabb(element);
        bounds = DrawRect::new(
            bounds.min_x.min(aabb.min_x),
            bounds.min_y.min(aabb.min_y),
            bounds.max_x.max(aabb.max_x),
            bounds.max_y.max(aabb.max_y),
        );
    }
    Some(bounds)
}

fn element_world_aabb(element: &SelectableElementSnapshot) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }

    let center = element.rect.center();
    let half_width = element.rect.width().abs() / 2.0;
    let half_height = element.rect.height().abs() / 2.0;
    let cos_theta = element.rotation.cos().abs();
    let sin_theta = element.rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;

    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

fn has_reached_drag_threshold(from: DrawPoint, to: DrawPoint, threshold: f64) -> bool {
    if threshold <= 0.0 {
        return true;
    }
    from.distance_squared(to) >= threshold * threshold
}

fn arrow_data_snapshot_for_element(
    element: &crate::draw::models::element_state::ElementState,
) -> Option<ArrowLikeDataSnapshot> {
    let payload = element.data.to_json_value();
    if element.type_id().as_str() == ArrowData::TYPE_ID_TOKEN {
        let data = ArrowData::from_json_value(&payload).ok()?;
        let points = ArrowGeometry::resolve_world_points(element.rect, data.points.as_slice());
        let fixed_segment_indexes = data
            .fixed_segments
            .as_ref()
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .map(|segment| segment.index)
            .collect();
        return Some(ArrowLikeDataSnapshot {
            points,
            arrow_type: data.arrow_type,
            fixed_segment_indexes,
        });
    }

    if element.type_id().as_str() == LineData::TYPE_ID_TOKEN {
        let data = LineData::from_json_value(&payload).ok()?;
        let points = ArrowGeometry::resolve_world_points(element.rect, data.points.as_slice());
        let fixed_segment_indexes = data
            .fixed_segments
            .as_ref()
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .map(|segment| segment.index)
            .collect();
        return Some(ArrowLikeDataSnapshot {
            points,
            arrow_type: data.arrow_type,
            fixed_segment_indexes,
        });
    }

    None
}

fn collect_bound_text_ids(
    elements: &[crate::draw::models::element_state::ElementState],
) -> BTreeSet<String> {
    let mut bound_text_ids = BTreeSet::new();
    for element in elements {
        if element.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
            continue;
        }

        let Ok(data) = SerialNumberData::from_json_value(&element.data.to_json_value()) else {
            continue;
        };

        if let Some(text_element_id) = data.text_element_id {
            bound_text_ids.insert(text_element_id);
        }
    }
    bound_text_ids
}

fn build_detector_state_view(
    snapshot: &SelectPluginStateSnapshot,
    draw_context: &DrawContext,
) -> DetectorDrawStateView {
    let state_view = DrawStateViewBuilder::new(draw_context.edit_operations.as_ref().clone(), None)
        .build(&snapshot.draw_state);
    let effective_elements = state_view
        .elements()
        .iter()
        .map(|element| state_view.effective_element(element))
        .collect::<Vec<_>>();
    let elements = effective_elements
        .iter()
        .map(|element| {
            let data = if let Some(arrow_data) = arrow_data_snapshot_for_element(element) {
                DetectorElementData::ArrowLike(DetectorArrowLikeData {
                    points: arrow_data.points,
                })
            } else {
                DetectorElementData::Other
            };
            DetectorElementState::new(element.id.clone(), data)
        })
        .collect::<Vec<_>>();

    let document = DetectorDocumentState::from_elements(elements);
    let selection = DetectorSelectionState {
        selected_ids: snapshot
            .selected_ids
            .iter()
            .cloned()
            .collect::<HashSet<_>>(),
    };

    DetectorDrawStateView::new(DetectorDrawState {
        domain: DetectorDomainState {
            document,
            selection,
        },
    })
}

fn map_detector_arrow_point_kind(kind: DetectorArrowPointKind) -> DomainArrowPointKind {
    match kind {
        DetectorArrowPointKind::Turning => DomainArrowPointKind::Turning,
        DetectorArrowPointKind::Addable => DomainArrowPointKind::Addable,
        DetectorArrowPointKind::LoopStart => DomainArrowPointKind::LoopStart,
        DetectorArrowPointKind::LoopEnd => DomainArrowPointKind::LoopEnd,
    }
}

fn map_detector_arrow_point_kind_to_operation(
    kind: DetectorArrowPointKind,
) -> crate::draw::elements::types::arrow::arrow_points::ArrowPointKind {
    match kind {
        DetectorArrowPointKind::Turning => {
            crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::Turning
        }
        DetectorArrowPointKind::Addable => {
            crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::Addable
        }
        DetectorArrowPointKind::LoopStart => {
            crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::LoopStart
        }
        DetectorArrowPointKind::LoopEnd => {
            crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::LoopEnd
        }
    }
}

fn convert_mapper_start_edit(mapped: MapperStartEdit) -> StartEdit {
    StartEdit::new(
        mapped.operation_id,
        mapped.position,
        convert_mapper_params(mapped.params),
    )
}

fn convert_mapper_params(params: MapperEditOperationParams) -> EditOperationParams {
    match params {
        MapperEditOperationParams::Move(MapperMoveOperationParams {
            initial_selection_bounds,
        }) => EditOperationParams::Move(MoveOperationParams::new(initial_selection_bounds)),
        MapperEditOperationParams::Resize(MapperResizeOperationParams {
            resize_mode,
            handle_offset,
            selection_padding,
            initial_selection_bounds,
        }) => EditOperationParams::Resize(ResizeOperationParams::with_options(
            resize_mode,
            handle_offset,
            selection_padding,
            initial_selection_bounds,
        )),
        MapperEditOperationParams::Rotate(MapperRotateOperationParams {
            start_rotation_angle,
            rotation_snap_angle,
            initial_selection_bounds,
        }) => EditOperationParams::Rotate(RotateOperationParams::with_options(
            start_rotation_angle,
            rotation_snap_angle,
            initial_selection_bounds,
        )),
        MapperEditOperationParams::ArrowPoint(MapperArrowPointOperationParams {
            element_id,
            point_kind,
            point_index,
            is_double_click,
            initial_selection_bounds,
        }) => EditOperationParams::ArrowPoint(ArrowPointOperationParams::with_options(
            element_id,
            map_detector_arrow_point_kind_to_operation(point_kind),
            point_index,
            is_double_click,
            initial_selection_bounds,
        )),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::draw::elements::core::element_data::ElementData as CoreElementData;
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::models::element_state::ElementState as ModelElementState;

    fn selectable_element(
        id: &str,
        type_id: &str,
        rect: DrawRect,
        rotation: f64,
        z_index: i64,
        is_text: bool,
        arrow_data: Option<ArrowLikeDataSnapshot>,
    ) -> SelectableElementSnapshot {
        SelectableElementSnapshot {
            id: id.to_owned(),
            type_id: type_id.to_owned(),
            rect,
            rotation,
            z_index,
            is_text,
            arrow_data,
        }
    }

    fn arrow_like_data(points: Vec<DrawPoint>, arrow_type: ArrowType) -> ArrowLikeDataSnapshot {
        ArrowLikeDataSnapshot {
            points,
            arrow_type,
            fixed_segment_indexes: BTreeSet::new(),
        }
    }

    fn build_snapshot(
        elements: Vec<SelectableElementSnapshot>,
        selected_ids: &[&str],
    ) -> SelectPluginStateSnapshot {
        let selected_ids = selected_ids
            .iter()
            .map(|value| (*value).to_owned())
            .collect::<BTreeSet<_>>();

        let mut draw_state = DrawState::default();
        draw_state.domain.document.elements = elements
            .iter()
            .map(|element| {
                ModelElementState::new(
                    element.id.clone(),
                    element.rect,
                    element.rotation,
                    1.0,
                    element.z_index,
                    Arc::new(RectangleData::default()) as Arc<dyn CoreElementData>,
                )
            })
            .collect();
        draw_state.domain.selection.selected_ids = selected_ids.clone();

        let elements_by_id = elements
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect::<HashMap<_, _>>();

        SelectPluginStateSnapshot {
            draw_state,
            draw_config: DrawConfig::default(),
            selection_config: SelectionConfig::default(),
            drag_pending: None,
            selected_ids,
            elements,
            elements_by_id,
            bound_text_ids: BTreeSet::new(),
        }
    }

    #[test]
    fn hit_test_returns_corner_resize_handle_for_single_selection() {
        let plugin = SelectPlugin::default();
        let rect = DrawRect::new(100.0, 100.0, 200.0, 200.0);
        let snapshot = build_snapshot(
            vec![selectable_element(
                "rect-1",
                "rectangle",
                rect,
                0.0,
                1,
                false,
                None,
            )],
            &["rect-1"],
        );

        let hit = plugin.hit_test(&snapshot, DrawPoint::new(97.0, 97.0), None);
        assert_eq!(hit.target, DetectorHitTestTarget::Handle);
        assert_eq!(hit.handle_type, Some(DetectorHandleType::TopLeft));
        assert_eq!(hit.hit_element_id, None);
        assert!(hit.is_in_selection_padding);
    }

    #[test]
    fn hit_test_returns_rotate_handle_for_non_elbow_single_selection() {
        let plugin = SelectPlugin::default();
        let rect = DrawRect::new(100.0, 100.0, 200.0, 200.0);
        let snapshot = build_snapshot(
            vec![selectable_element(
                "rect-1",
                "rectangle",
                rect,
                0.0,
                1,
                false,
                None,
            )],
            &["rect-1"],
        );

        let hit = plugin.hit_test(&snapshot, DrawPoint::new(150.0, 85.0), None);
        assert_eq!(hit.target, DetectorHitTestTarget::Handle);
        assert_eq!(hit.handle_type, Some(DetectorHandleType::Rotate));
        assert_eq!(hit.hit_element_id, None);
        assert!(!hit.is_in_selection_padding);
    }

    #[test]
    fn hit_test_prioritizes_move_for_single_text_inside_selection_padding() {
        let plugin = SelectPlugin::default();
        let rect = DrawRect::new(100.0, 100.0, 200.0, 200.0);
        let mut snapshot = build_snapshot(
            vec![selectable_element(
                "text-1",
                TextData::TYPE_ID_TOKEN,
                rect,
                0.0,
                1,
                true,
                None,
            )],
            &["text-1"],
        );
        snapshot.selection_config.padding = 12.0;

        let hit = plugin.hit_test(&snapshot, DrawPoint::new(90.0, 90.0), None);
        assert_eq!(hit.target, DetectorHitTestTarget::SelectionPadding);
        assert_eq!(hit.handle_type, None);
        assert_eq!(hit.hit_element_id.as_deref(), Some("text-1"));
        assert!(hit.is_in_selection_padding);
    }

    #[test]
    fn hit_test_disables_rotate_handle_for_single_elbow_arrow() {
        let plugin = SelectPlugin::default();
        let rect = DrawRect::new(100.0, 100.0, 200.0, 200.0);
        let snapshot = build_snapshot(
            vec![selectable_element(
                "arrow-1",
                ArrowData::TYPE_ID_TOKEN,
                rect,
                0.0,
                1,
                false,
                Some(arrow_like_data(
                    vec![
                        DrawPoint::new(100.0, 100.0),
                        DrawPoint::new(150.0, 120.0),
                        DrawPoint::new(200.0, 200.0),
                    ],
                    ArrowType::Elbow,
                )),
            )],
            &["arrow-1"],
        );

        let hit = plugin.hit_test(&snapshot, DrawPoint::new(150.0, 85.0), None);
        assert_eq!(hit.target, DetectorHitTestTarget::None);
        assert_eq!(hit.handle_type, None);
        assert_eq!(hit.hit_element_id, None);
        assert!(!hit.is_in_selection_padding);
    }

    #[test]
    fn hit_test_skips_handle_hit_testing_for_single_two_point_arrow() {
        let plugin = SelectPlugin::default();
        let rect = DrawRect::new(100.0, 100.0, 200.0, 200.0);
        let snapshot = build_snapshot(
            vec![selectable_element(
                "arrow-1",
                ArrowData::TYPE_ID_TOKEN,
                rect,
                0.0,
                1,
                false,
                Some(arrow_like_data(
                    vec![DrawPoint::new(100.0, 100.0), DrawPoint::new(200.0, 200.0)],
                    ArrowType::Straight,
                )),
            )],
            &["arrow-1"],
        );

        let hit = plugin.hit_test(&snapshot, DrawPoint::new(150.0, 85.0), None);
        assert_eq!(hit.target, DetectorHitTestTarget::None);
        assert_eq!(hit.handle_type, None);
        assert_eq!(hit.hit_element_id, None);
        assert!(!hit.is_in_selection_padding);
    }
}

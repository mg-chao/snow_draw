#![allow(dead_code)]

use std::any::TypeId;
use std::sync::Arc;
use std::time::Instant;

use crate::draw::actions::draw_actions::{
    AddArrowPoint, CancelCreateElement, CreateElement, FinishCreateElement, UpdateCreatingElement,
};
use crate::draw::elements::core::element_data::{DynElementData, ElementTypeId};
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::input::double_tap_tracker::DoubleTapTracker;
use crate::draw::input::input_event::{
    KeyModifiers, PointerCancelInputEvent, PointerDownInputEvent, PointerHoverInputEvent,
    PointerMoveInputEvent, PointerUpInputEvent,
};
use crate::draw::input::plugin_engine::{
    DrawInputPlugin, InputEvent, InputPlugin, InputPluginBase, InputRoutingPolicy, PluginContext,
    PluginError, PluginHandleResult, PluginLifecycleResult, PluginResult, SupportedEventTypes,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::interaction_state::{
    CreationMode as DomainCreationMode, InteractionState,
};
use crate::draw::services::element_hit_test_service::query_elements_at_point_top_down;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::ArrowType;

/// Create-mode discriminator used by [`CreatePluginStateSnapshot`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CreatingMode {
    Rect,
    Point,
}

/// Element-kind discriminator used by [`CreatePluginStateSnapshot`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CreatingElementKind {
    Generic,
    FreeDraw,
    ElbowArrow,
}

/// Lightweight creation snapshot consumed by [`CreatePlugin`].
///
/// The translated Rust workspace currently contains multiple in-flight state
/// models. This snapshot keeps the plugin compile-friendly while still
/// preserving the create-plugin behavior contract.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CreatePluginStateSnapshot {
    pub is_creating: bool,
    pub has_selection: bool,
    pub creating_mode: Option<CreatingMode>,
    pub creating_element_kind: Option<CreatingElementKind>,
}

impl CreatePluginStateSnapshot {
    pub fn is_point_creation(&self) -> bool {
        matches!(self.creating_mode, Some(CreatingMode::Point))
    }

    pub fn is_free_draw_creating(&self) -> bool {
        matches!(
            self.creating_element_kind,
            Some(CreatingElementKind::FreeDraw)
        )
    }

    pub fn is_elbow_arrow_creating(&self) -> bool {
        matches!(
            self.creating_element_kind,
            Some(CreatingElementKind::ElbowArrow)
        )
    }
}

/// Adapter that extracts create-plugin state from the aggregate draw state.
pub trait CreatePluginStateAdapter: Send + Sync {
    fn snapshot(&self, state: &DrawState) -> CreatePluginStateSnapshot;
}

/// Default state adapter for the currently translated `DrawState`.
///
/// Mirrors Dart `CreatePlugin` by extracting creation mode and creating
/// element kind from the active interaction state.
#[derive(Debug, Default)]
pub struct DefaultCreatePluginStateAdapter;

impl CreatePluginStateAdapter for DefaultCreatePluginStateAdapter {
    fn snapshot(&self, state: &DrawState) -> CreatePluginStateSnapshot {
        let (creating_mode, creating_element_kind) = match &state.application.interaction {
            InteractionState::Creating(creating) => {
                let creating_mode = match creating.creation_mode {
                    DomainCreationMode::Point(_) => CreatingMode::Point,
                    DomainCreationMode::Rect(_) => CreatingMode::Rect,
                };
                let kind = resolve_creating_element_kind(&creating.element);
                (Some(creating_mode), Some(kind))
            }
            _ => (None, None),
        };

        CreatePluginStateSnapshot {
            is_creating: state.application.is_creating(),
            has_selection: state.domain.selection.has_selection(),
            creating_mode,
            creating_element_kind,
        }
    }
}

/// Policy hook for deciding whether creation should start on pointer down.
pub trait CreateStartPolicy: Send + Sync {
    fn should_start_create(
        &self,
        state: &DrawState,
        position: DrawPoint,
        tool_type_id: &ElementTypeId<DynElementData>,
        hit_tolerance: f64,
    ) -> bool;
}

/// Default create-start policy.
///
/// Dart uses hit-testing plus selection checks. The translated Rust draw-state
/// model does not yet expose full hit-test inputs here, so the default policy
/// keeps the selection guard and allows custom policies for richer behavior.
#[derive(Debug, Default)]
pub struct DefaultCreateStartPolicy;

impl CreateStartPolicy for DefaultCreateStartPolicy {
    fn should_start_create(
        &self,
        state: &DrawState,
        position: DrawPoint,
        tool_type_id: &ElementTypeId<DynElementData>,
        hit_tolerance: f64,
    ) -> bool {
        if state.domain.selection.has_selection() {
            return false;
        }

        let hits = query_elements_at_point_top_down(
            state.domain.document.elements.as_slice(),
            position,
            hit_tolerance,
        );
        let bound_text_ids = collect_bound_text_ids(state.domain.document.elements.as_slice());

        for element in hits {
            let element_type_id = element.data.type_id();
            if element_type_id.as_str() == tool_type_id.as_str() {
                return false;
            }

            if tool_type_id.as_str() == SerialNumberData::TYPE_ID_TOKEN
                && element_type_id.as_str() == TextData::TYPE_ID_TOKEN
                && bound_text_ids.contains(&element.id)
            {
                return false;
            }
        }

        true
    }
}

/// Plugin that handles element creation via the current tool.
pub struct CreatePlugin {
    base: InputPluginBase,
    routing_policy: InputRoutingPolicy,
    state_adapter: Arc<dyn CreatePluginStateAdapter>,
    start_policy: Arc<dyn CreateStartPolicy>,
    double_tap_tracker: DoubleTapTracker<&'static str>,

    pub current_tool_type_id: Option<ElementTypeId<DynElementData>>,

    pointer_down_position: Option<DrawPoint>,
    is_dragging: bool,
    is_multi_point: bool,
    update_guard: PointerUpdateGuard,
}

impl CreatePlugin {
    pub const MAX_FREE_DRAW_BATCH_SAMPLES: usize = 96;
    pub const POINT_CREATION_TAP_TARGET: &'static str = "point_creation";

    pub fn new(
        current_tool_type_id: Option<ElementTypeId<DynElementData>>,
        routing_policy: Option<InputRoutingPolicy>,
    ) -> Self {
        Self {
            base: InputPluginBase::new(
                "create",
                "Create Plugin",
                10,
                Self::supported_create_event_types(),
            ),
            routing_policy: routing_policy.unwrap_or_default(),
            state_adapter: Arc::new(DefaultCreatePluginStateAdapter),
            start_policy: Arc::new(DefaultCreateStartPolicy),
            double_tap_tracker: DoubleTapTracker::new(),
            current_tool_type_id,
            pointer_down_position: None,
            is_dragging: false,
            is_multi_point: false,
            update_guard: PointerUpdateGuard::default(),
        }
    }

    pub fn with_state_adapter(mut self, state_adapter: Arc<dyn CreatePluginStateAdapter>) -> Self {
        self.state_adapter = state_adapter;
        self
    }

    pub fn with_start_policy(mut self, start_policy: Arc<dyn CreateStartPolicy>) -> Self {
        self.start_policy = start_policy;
        self
    }

    pub fn set_current_tool_type_id(
        &mut self,
        tool_type_id: Option<ElementTypeId<DynElementData>>,
    ) {
        self.current_tool_type_id = tool_type_id;
    }

    fn supported_create_event_types() -> SupportedEventTypes {
        let mut types = SupportedEventTypes::new();
        types.insert(TypeId::of::<PointerDownInputEvent>());
        types.insert(TypeId::of::<PointerMoveInputEvent>());
        types.insert(TypeId::of::<PointerHoverInputEvent>());
        types.insert(TypeId::of::<PointerUpInputEvent>());
        types.insert(TypeId::of::<PointerCancelInputEvent>());
        types
    }

    fn state_snapshot(&self) -> CreatePluginStateSnapshot {
        let state = self.state();
        self.state_adapter.snapshot(&state)
    }

    fn should_start_create(
        &self,
        state: &DrawState,
        position: DrawPoint,
        tool_type_id: &ElementTypeId<DynElementData>,
    ) -> bool {
        self.start_policy.should_start_create(
            state,
            position,
            tool_type_id,
            self.selection_config().interaction.handle_tolerance,
        )
    }

    fn dispatch_action<A>(&self, action: A) -> Result<(), PluginError>
    where
        A: Send + Sync + 'static,
    {
        self.dispatch(Box::new(action))
            .map_err(|error| Box::new(error) as PluginError)
    }

    fn handle_pointer_down(&mut self, event: &PointerDownInputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        if snapshot.is_creating {
            if snapshot.is_point_creation() {
                self.pointer_down_position = Some(event.input.position);
                self.is_dragging = false;
                return Ok(self.base.handled(Some("Create point start".to_owned())));
            }
            return self.finish_creation("Create finished", false);
        }

        let Some(tool_type_id) = self
            .current_tool_type_id
            .as_ref()
            .map(|tool_type_id| ElementTypeId::new(tool_type_id.as_str()))
        else {
            return Ok(self.base.unhandled(None));
        };

        let state = self.state();
        if !self.should_start_create(&state, event.input.position, &tool_type_id) {
            return Ok(self.base.unhandled(None));
        }

        self.reset_point_creation_state();
        self.pointer_down_position = Some(event.input.position);

        self.dispatch_action(CreateElement::new(
            tool_type_id,
            event.input.position,
            None,
            event.input.modifiers.shift,
            event.input.modifiers.alt,
            event.input.modifiers.control,
        ))?;
        Ok(self.base.handled(Some("Create started".to_owned())))
    }

    fn handle_pointer_move(&mut self, event: &PointerMoveInputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        if !snapshot.is_creating {
            return Ok(self.base.unhandled(None));
        }

        if snapshot.is_point_creation() {
            if let Some(down_position) = self.pointer_down_position {
                if !self.is_dragging
                    && has_reached_drag_threshold(
                        down_position,
                        event.input.position,
                        self.selection_config().interaction.drag_threshold,
                    )
                {
                    self.is_dragging = true;
                }
            }
        }

        let is_free_draw_creating = snapshot.is_free_draw_creating();
        let has_batched_samples =
            is_free_draw_creating && event.sample_count() > 1 && !event.input.modifiers.shift;

        if !self.should_dispatch_creating_update(
            event.input.position,
            event.input.modifiers,
            has_batched_samples,
        ) {
            return Ok(self.base.handled(Some("Create unchanged".to_owned())));
        }

        let positions = if has_batched_samples {
            let sampled_points = event.sampled_points();
            resample_pointer_samples(sampled_points.as_slice(), Self::MAX_FREE_DRAW_BATCH_SAMPLES)
        } else {
            vec![event.input.position]
        };

        self.dispatch_creating_update(positions, event.input.modifiers)?;
        if has_batched_samples {
            Ok(self
                .base
                .handled(Some("Create updated (batched)".to_owned())))
        } else {
            Ok(self.base.handled(Some("Create updated".to_owned())))
        }
    }

    fn handle_pointer_hover(&mut self, event: &PointerHoverInputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        if !snapshot.is_point_creation() || !self.is_multi_point {
            return Ok(self.base.unhandled(None));
        }

        if !self.should_dispatch_creating_update(event.input.position, event.input.modifiers, false)
        {
            return Ok(self.base.handled(Some("Create hover unchanged".to_owned())));
        }

        self.dispatch_creating_update(vec![event.input.position], event.input.modifiers)?;
        Ok(self.base.handled(Some("Create hover updated".to_owned())))
    }

    fn handle_pointer_up(&mut self, event: &PointerUpInputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        if !snapshot.is_creating {
            return Ok(self.base.unhandled(None));
        }

        if !snapshot.is_point_creation() {
            self.dispatch_action(FinishCreateElement)?;
            return Ok(self.base.handled(Some("Create finished".to_owned())));
        }

        let was_dragging = self.is_dragging;
        let was_multi_point = self.is_multi_point;
        let down_position = self.pointer_down_position;
        self.pointer_down_position = None;
        self.is_dragging = false;

        let min_create_size = self.draw_context().config().element.min_create_size;
        let was_meaningful_drag = if was_dragging {
            if let Some(down_position) = down_position {
                has_reached_drag_threshold(down_position, event.input.position, min_create_size)
            } else {
                false
            }
        } else {
            false
        };

        if was_meaningful_drag && !was_multi_point {
            return self.finish_creation("Create finished", true);
        }

        let now = Instant::now();
        if !was_multi_point {
            self.is_multi_point = true;
            self.double_tap_tracker.record_tap(
                Self::POINT_CREATION_TAP_TARGET,
                event.input.position,
                now,
            );
            return Ok(self
                .base
                .handled(Some("Create multi-point started".to_owned())));
        }

        let handle_tolerance = self.selection_config().interaction.handle_tolerance;
        let is_double_click = !was_meaningful_drag
            && self.double_tap_tracker.is_double_tap(
                &Self::POINT_CREATION_TAP_TARGET,
                event.input.position,
                now,
                handle_tolerance,
            );

        if snapshot.is_elbow_arrow_creating() {
            self.dispatch_creating_update(vec![event.input.position], event.input.modifiers)?;
            return self.finish_creation("Create finished (elbow)", true);
        }

        if is_double_click {
            return self.finish_creation("Create finished (double-click)", true);
        }

        self.dispatch_action(AddArrowPoint::new(
            event.input.position,
            event.input.modifiers.control,
        ))?;
        self.double_tap_tracker.record_tap(
            Self::POINT_CREATION_TAP_TARGET,
            event.input.position,
            now,
        );
        Ok(self.base.handled(Some("Create point added".to_owned())))
    }

    fn handle_pointer_cancel(&mut self) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        if !snapshot.is_creating {
            return Ok(self.base.unhandled(None));
        }

        self.dispatch_action(CancelCreateElement)?;
        self.reset_point_creation_state();
        Ok(self.base.consumed(Some("Create canceled".to_owned())))
    }

    fn should_dispatch_creating_update(
        &mut self,
        position: DrawPoint,
        modifiers: KeyModifiers,
        has_batched_samples: bool,
    ) -> bool {
        self.update_guard
            .should_dispatch(position, modifiers, has_batched_samples)
    }

    fn dispatch_creating_update(
        &self,
        positions: Vec<DrawPoint>,
        modifiers: KeyModifiers,
    ) -> Result<(), PluginError> {
        if positions.is_empty() {
            return Ok(());
        }

        self.dispatch_action(UpdateCreatingElement::new(
            positions,
            modifiers.shift,
            modifiers.alt,
            modifiers.control,
        ))
    }

    fn sync_internal_state(&mut self) {
        let snapshot = self.state_snapshot();
        if snapshot.is_point_creation() {
            return;
        }

        self.reset_point_creation_session_state();
        if !snapshot.is_creating {
            self.reset_update_signature();
        }
    }

    fn reset_point_creation_state(&mut self) {
        self.reset_point_creation_session_state();
        self.reset_update_signature();
    }

    fn reset_point_creation_session_state(&mut self) {
        self.pointer_down_position = None;
        self.is_dragging = false;
        self.is_multi_point = false;
        self.double_tap_tracker.clear();
    }

    fn reset_update_signature(&mut self) {
        self.update_guard.reset();
    }

    fn finish_creation(&mut self, message: &str, reset_point_state: bool) -> PluginHandleResult {
        self.dispatch_action(FinishCreateElement)?;
        if reset_point_state {
            self.reset_point_creation_state();
        }
        Ok(self.base.handled(Some(message.to_owned())))
    }
}

impl InputPlugin for CreatePlugin {
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

    fn on_load(&mut self, context: PluginContext) -> PluginLifecycleResult {
        <InputPluginBase as InputPlugin>::on_load(&mut self.base, context)
    }

    fn on_unload(&mut self) -> PluginLifecycleResult {
        <InputPluginBase as InputPlugin>::on_unload(&mut self.base)?;
        self.reset_point_creation_state();
        Ok(())
    }

    fn can_handle(&self, _event: &InputEvent, state: &DrawState) -> bool {
        self.routing_policy.allow_create(state)
    }

    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult {
        self.sync_internal_state();

        if let Some(event) = downcast_event::<PointerDownInputEvent>(event) {
            return self.handle_pointer_down(event);
        }
        if let Some(event) = downcast_event::<PointerMoveInputEvent>(event) {
            return self.handle_pointer_move(event);
        }
        if let Some(event) = downcast_event::<PointerHoverInputEvent>(event) {
            return self.handle_pointer_hover(event);
        }
        if let Some(event) = downcast_event::<PointerUpInputEvent>(event) {
            return self.handle_pointer_up(event);
        }
        if downcast_event::<PointerCancelInputEvent>(event).is_some() {
            return self.handle_pointer_cancel();
        }

        Ok(PluginResult::unhandled(None))
    }

    fn reset(&mut self) {
        self.current_tool_type_id = None;
        self.reset_point_creation_state();
    }
}

impl DrawInputPlugin for CreatePlugin {
    fn base(&self) -> &InputPluginBase {
        &self.base
    }

    fn base_mut(&mut self) -> &mut InputPluginBase {
        &mut self.base
    }
}

#[derive(Clone, Debug, Default)]
struct PointerUpdateGuard {
    last_position: Option<DrawPoint>,
    last_modifiers: Option<KeyModifiers>,
}

impl PointerUpdateGuard {
    fn should_dispatch(
        &mut self,
        position: DrawPoint,
        modifiers: KeyModifiers,
        force: bool,
    ) -> bool {
        let unchanged = self.last_position.is_some_and(|last| {
            last.x == position.x && last.y == position.y && self.last_modifiers == Some(modifiers)
        });
        if !force && unchanged {
            return false;
        }

        self.last_position = Some(position);
        self.last_modifiers = Some(modifiers);
        true
    }

    fn reset(&mut self) {
        self.last_position = None;
        self.last_modifiers = None;
    }
}

fn has_reached_drag_threshold(from: DrawPoint, to: DrawPoint, threshold: f64) -> bool {
    if threshold <= 0.0 {
        return true;
    }
    let threshold_squared = threshold * threshold;
    from.distance_squared(to) >= threshold_squared
}

fn resample_pointer_samples(sampled_points: &[DrawPoint], max_samples: usize) -> Vec<DrawPoint> {
    if sampled_points.is_empty() || max_samples == 0 {
        return Vec::new();
    }
    if max_samples == 1 {
        return vec![sampled_points[sampled_points.len() - 1]];
    }
    if sampled_points.len() <= max_samples {
        return sampled_points.to_vec();
    }

    let last_index = sampled_points.len() - 1;
    let stride = (last_index as f64) / ((max_samples - 1) as f64);
    let mut reduced = vec![sampled_points[0]];

    for i in 1..(max_samples - 1) {
        let index = ((i as f64) * stride).round() as usize;
        let point = sampled_points[index];
        if reduced[reduced.len() - 1] != point {
            reduced.push(point);
        }
    }

    let last_point = sampled_points[last_index];
    if reduced[reduced.len() - 1] != last_point {
        reduced.push(last_point);
    }

    reduced
}

fn collect_bound_text_ids(
    elements: &[crate::draw::models::element_state::ElementState],
) -> std::collections::HashSet<String> {
    let mut bound_text_ids = std::collections::HashSet::new();
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

fn resolve_creating_element_kind(
    element: &crate::draw::models::element_state::ElementState,
) -> CreatingElementKind {
    let type_id = element.type_id();
    if type_id.as_str() == FreeDrawData::TYPE_ID_TOKEN {
        return CreatingElementKind::FreeDraw;
    }

    if type_id.as_str() == ArrowData::TYPE_ID_TOKEN {
        if let Ok(data) = ArrowData::from_json_value(&element.data.to_json_value()) {
            if data.arrow_type == ArrowType::Elbow {
                return CreatingElementKind::ElbowArrow;
            }
        }
        return CreatingElementKind::Generic;
    }

    if type_id.as_str() == LineData::TYPE_ID_TOKEN {
        if let Ok(data) = LineData::from_json_value(&element.data.to_json_value()) {
            if data.arrow_type == ArrowType::Elbow {
                return CreatingElementKind::ElbowArrow;
            }
        }
    }

    CreatingElementKind::Generic
}

fn downcast_event<T: 'static>(event: &InputEvent) -> Option<&T> {
    event.as_ref().downcast_ref::<T>()
}

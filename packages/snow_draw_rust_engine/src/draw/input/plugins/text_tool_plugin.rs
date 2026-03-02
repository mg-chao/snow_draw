#![allow(dead_code)]

use std::any::TypeId;
use std::collections::BTreeSet;
use std::sync::Arc;

use crate::draw::actions::draw_actions::{FinishTextEdit, SelectElement, StartTextEdit};
use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_data::{DynElementData, ElementTypeId};
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::input::input_event::{
    PointerCancelInputEvent, PointerDownInputEvent, PointerMoveInputEvent, PointerUpInputEvent,
};
use crate::draw::input::plugin_engine::{
    downcast_input_event, DrawInputPlugin, InputEvent, InputPlugin, InputPluginBase,
    InputRoutingPolicy, PluginContext, PluginError, PluginHandleResult, PluginLifecycleResult,
    PluginResult, SupportedEventTypes,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::interaction_state::InteractionState;
use crate::draw::services::element_hit_test_service::hit_test_element;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Lightweight text-editing interaction snapshot consumed by [`TextToolPlugin`].
#[derive(Clone, Debug, PartialEq)]
pub struct TextEditingStateSnapshot {
    pub element_id: String,
    pub draft_text: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub is_new: bool,
}

impl TextEditingStateSnapshot {
    pub fn new(
        element_id: impl Into<String>,
        draft_text: impl Into<String>,
        rect: DrawRect,
        rotation: f64,
        is_new: bool,
    ) -> Self {
        Self {
            element_id: element_id.into(),
            draft_text: draft_text.into(),
            rect,
            rotation,
            is_new,
        }
    }
}

/// Lightweight element view required by text-tool hit testing.
#[derive(Clone, Debug, PartialEq)]
pub struct TextToolElementSnapshot {
    pub id: String,
    pub type_id: ElementTypeId<DynElementData>,
    pub rect: DrawRect,
    pub rotation: f64,
    pub z_index: i64,
}

impl TextToolElementSnapshot {
    pub fn new(
        id: impl Into<String>,
        type_id: ElementTypeId<DynElementData>,
        rect: DrawRect,
        rotation: f64,
        z_index: i64,
    ) -> Self {
        Self {
            id: id.into(),
            type_id,
            rect,
            rotation,
            z_index,
        }
    }

    pub fn is_text_element(&self) -> bool {
        self.type_id.as_str() == TextData::TYPE_ID_TOKEN
    }
}

/// Aggregated state snapshot consumed by [`TextToolPlugin`].
///
/// The translated Rust workspace currently contains multiple in-progress state
/// models. This snapshot keeps text-tool behavior configurable and
/// compile-friendly until the richer model is fully wired.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TextToolPluginStateSnapshot {
    pub draw_state: DrawState,
    pub is_text_editing: bool,
    pub text_editing: Option<TextEditingStateSnapshot>,
    pub selected_ids: BTreeSet<String>,
    pub elements: Vec<TextToolElementSnapshot>,
}

impl TextToolPluginStateSnapshot {
    pub fn has_selection(&self) -> bool {
        !self.selected_ids.is_empty()
    }
}

/// Adapter that projects aggregate draw state into a text-tool snapshot.
pub trait TextToolStateAdapter: Send + Sync {
    fn snapshot(&self, state: &DrawState) -> TextToolPluginStateSnapshot;
}

/// Default adapter for the currently translated `DrawState`.
///
/// Only stable fields (`is_text_editing`, `selected_ids`) are currently
/// available from `models/draw_state.rs`. Rich text-editing payload and
/// document element metadata can be injected via a custom adapter.
#[derive(Debug, Default)]
pub struct DefaultTextToolStateAdapter;

impl TextToolStateAdapter for DefaultTextToolStateAdapter {
    fn snapshot(&self, state: &DrawState) -> TextToolPluginStateSnapshot {
        let text_editing = match &state.application.interaction {
            InteractionState::TextEditing(interaction) => Some(TextEditingStateSnapshot::new(
                interaction.element_id.clone(),
                interaction.draft_data.text.clone(),
                interaction.rect,
                interaction.rotation,
                interaction.is_new,
            )),
            _ => None,
        };

        let elements = state
            .domain
            .document
            .elements
            .iter()
            .map(|element| {
                TextToolElementSnapshot::new(
                    element.id.clone(),
                    element.type_id(),
                    element.rect,
                    element.rotation,
                    element.z_index,
                )
            })
            .collect::<Vec<_>>();

        TextToolPluginStateSnapshot {
            draw_state: state.clone(),
            is_text_editing: state.application.is_text_editing(),
            text_editing,
            selected_ids: state.domain.selection.selected_ids.clone(),
            elements,
        }
    }
}

/// Pluggable hit-testing contract used by [`TextToolPlugin`].
pub trait TextToolHitTester: Send + Sync {
    fn hit_test_text_element(
        &self,
        element: &crate::draw::models::element_state::ElementState,
        position: DrawPoint,
    ) -> bool;
}

/// Default hit tester that mirrors Dart fallback behavior.
#[derive(Debug, Default)]
pub struct DefaultTextToolHitTester;

impl TextToolHitTester for DefaultTextToolHitTester {
    fn hit_test_text_element(
        &self,
        element: &crate::draw::models::element_state::ElementState,
        position: DrawPoint,
    ) -> bool {
        hit_test_element(element, position, 0.0)
    }
}

/// Plugin that handles text-tool interactions.
pub struct TextToolPlugin {
    base: InputPluginBase,
    routing_policy: InputRoutingPolicy,
    state_adapter: Arc<dyn TextToolStateAdapter>,
    hit_tester: Arc<dyn TextToolHitTester>,

    pub current_tool_type_id: Option<ElementTypeId<DynElementData>>,
    pub is_selection_tool_active: bool,
}

impl TextToolPlugin {
    pub fn new(
        current_tool_type_id: Option<ElementTypeId<DynElementData>>,
        is_selection_tool_active: Option<bool>,
        routing_policy: Option<InputRoutingPolicy>,
    ) -> Self {
        Self {
            base: InputPluginBase::new(
                "text_tool",
                "Text Tool Plugin",
                5,
                Self::supported_text_tool_event_types(),
            ),
            routing_policy: routing_policy.unwrap_or_default(),
            state_adapter: Arc::new(DefaultTextToolStateAdapter),
            hit_tester: Arc::new(DefaultTextToolHitTester),
            current_tool_type_id,
            is_selection_tool_active: is_selection_tool_active.unwrap_or(true),
        }
    }

    pub fn with_state_adapter(mut self, state_adapter: Arc<dyn TextToolStateAdapter>) -> Self {
        self.state_adapter = state_adapter;
        self
    }

    pub fn with_hit_tester(mut self, hit_tester: Arc<dyn TextToolHitTester>) -> Self {
        self.hit_tester = hit_tester;
        self
    }

    pub fn set_current_tool_type_id(
        &mut self,
        tool_type_id: Option<ElementTypeId<DynElementData>>,
    ) {
        self.current_tool_type_id = tool_type_id;
    }

    fn supported_text_tool_event_types() -> SupportedEventTypes {
        let mut types = SupportedEventTypes::new();
        types.insert(TypeId::of::<PointerDownInputEvent>());
        types.insert(TypeId::of::<PointerMoveInputEvent>());
        types.insert(TypeId::of::<PointerUpInputEvent>());
        types.insert(TypeId::of::<PointerCancelInputEvent>());
        types
    }

    fn is_text_tool_active(&self) -> bool {
        self.current_tool_type_id
            .as_ref()
            .is_some_and(|type_id| type_id.as_str() == TextData::TYPE_ID_TOKEN)
    }

    fn is_selection_tool_mode_active(&self) -> bool {
        self.current_tool_type_id.is_none() && self.is_selection_tool_active
    }

    fn is_serial_tool_active(&self) -> bool {
        self.current_tool_type_id
            .as_ref()
            .is_some_and(|type_id| type_id.as_str() == SerialNumberData::TYPE_ID_TOKEN)
    }

    fn is_selection_like_tool_active(&self) -> bool {
        self.is_selection_tool_mode_active() || self.is_serial_tool_active()
    }

    fn state_snapshot(&self) -> TextToolPluginStateSnapshot {
        let state = self.state();
        self.state_adapter.snapshot(&state)
    }

    fn dispatch_action<A>(&self, action: A) -> Result<(), PluginError>
    where
        A: Send + Sync + 'static,
    {
        self.dispatch(Box::new(action))
            .map_err(|error| Box::new(error) as PluginError)
    }

    fn start_text_edit(
        &self,
        element_id: Option<String>,
        position: DrawPoint,
    ) -> Result<(), PluginError> {
        self.dispatch_action(StartTextEdit::new(position, element_id))
    }

    fn finish_text_edit(&self, interaction: &TextEditingStateSnapshot) -> Result<(), PluginError> {
        self.dispatch_action(FinishTextEdit::new(
            interaction.element_id.clone(),
            interaction.draft_text.clone(),
            interaction.is_new,
        ))
    }

    fn finish_text_edit_for_selection(
        &self,
        interaction: &TextEditingStateSnapshot,
        position: DrawPoint,
    ) -> Result<(), PluginError> {
        self.finish_text_edit(interaction)?;

        let trimmed = interaction.draft_text.trim();
        if !interaction.is_new && !trimmed.is_empty() {
            self.dispatch_action(SelectElement::new(
                interaction.element_id.clone(),
                position,
                false,
            ))?;
        }
        Ok(())
    }

    fn handle_pointer_down(&mut self, event: &PointerDownInputEvent) -> PluginHandleResult {
        let snapshot = self.state_snapshot();
        let position = event.input.position;

        if snapshot.is_text_editing {
            if let Some(interaction) = snapshot.text_editing.as_ref() {
                return self.handle_pointer_down_while_editing(interaction, position, &snapshot);
            }
            return Ok(self.base.handled(Some(
                "Text editing active (state snapshot unavailable)".to_owned(),
            )));
        }

        if self.should_defer_to_selection_box(&snapshot, position) {
            return Ok(self.base.unhandled(Some("Selection box hit".to_owned())));
        }

        if self.is_text_tool_active() {
            return self.handle_pointer_down_for_text_tool(position, &snapshot);
        }

        let Some(hit_id) = self.selected_text_hit_id_for_edit(&snapshot, event) else {
            return Ok(self.base.unhandled(None));
        };

        self.start_text_edit(Some(hit_id), position)?;
        Ok(self
            .base
            .handled(Some("Text edit from selection".to_owned())))
    }

    fn handle_pointer_down_while_editing(
        &self,
        interaction: &TextEditingStateSnapshot,
        position: DrawPoint,
        snapshot: &TextToolPluginStateSnapshot,
    ) -> PluginHandleResult {
        if is_inside_rect_with_padding(interaction.rect, interaction.rotation, position, 0.0) {
            return Ok(self
                .base
                .handled(Some("Text editing focus retained".to_owned())));
        }

        if self.is_selection_box_hit(snapshot, interaction, position) {
            self.finish_text_edit_for_selection(interaction, position)?;
            return Ok(self
                .base
                .unhandled(Some("Selection box hit during text edit".to_owned())));
        }

        self.finish_text_edit(interaction)?;

        if !self.is_text_tool_active() {
            return Ok(self.base.handled(Some("Text edit finished".to_owned())));
        }

        let Some(hit_id) = self.hit_text_element_id(snapshot, position, None) else {
            return Ok(self.base.handled(Some("Text edit finished".to_owned())));
        };

        self.start_text_edit(Some(hit_id), position)?;
        Ok(self.base.handled(Some("Text edit restarted".to_owned())))
    }

    fn handle_pointer_down_for_text_tool(
        &self,
        position: DrawPoint,
        snapshot: &TextToolPluginStateSnapshot,
    ) -> PluginHandleResult {
        let hit_id = self.hit_text_element_id(snapshot, position, None);

        if hit_id.is_none() && snapshot.has_selection() {
            return Ok(self
                .base
                .unhandled(Some("Defer to selection clearing".to_owned())));
        }

        if hit_id.is_some() && self.has_multiple_selected_text_elements(snapshot) {
            return Ok(self
                .base
                .unhandled(Some("Multiple text selection blocks editing".to_owned())));
        }

        self.start_text_edit(hit_id, position)?;
        Ok(self.base.handled(Some("Text edit started".to_owned())))
    }

    fn ignore_while_text_editing(&self, message: &str) -> PluginHandleResult {
        if self.state().application.is_text_editing() {
            return Ok(self.base.handled(Some(message.to_owned())));
        }
        Ok(self.base.unhandled(None))
    }

    fn is_selection_box_hit(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        interaction: &TextEditingStateSnapshot,
        position: DrawPoint,
    ) -> bool {
        if !snapshot.selected_ids.contains(&interaction.element_id) {
            return false;
        }

        self.is_selection_overlay_hit(snapshot, position)
    }

    fn is_selection_overlay_hit(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        position: DrawPoint,
    ) -> bool {
        if !snapshot.has_selection() {
            return false;
        }

        let selected_elements = snapshot
            .elements
            .iter()
            .filter(|element| snapshot.selected_ids.contains(&element.id))
            .collect::<Vec<_>>();
        if selected_elements.is_empty() {
            return false;
        }

        let padding = self.selection_config().padding;
        if selected_elements.len() == 1 {
            let element = selected_elements[0];
            return is_inside_rect_with_padding(element.rect, element.rotation, position, padding);
        }

        let Some(bounds) = selection_bounds(&selected_elements) else {
            return false;
        };
        let padded_bounds = expand_rect(bounds, padding);
        padded_bounds.contains_point(position)
    }

    fn should_defer_to_selection_box(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        position: DrawPoint,
    ) -> bool {
        if !snapshot.has_selection() || !self.has_selected_text_element(snapshot) {
            return false;
        }

        if !self.is_selection_overlay_hit(snapshot, position) {
            return false;
        }

        !self.is_inside_selected_text_element(snapshot, position)
    }

    fn has_selected_text_element(&self, snapshot: &TextToolPluginStateSnapshot) -> bool {
        snapshot.selected_ids.iter().any(|id| {
            match snapshot
                .elements
                .iter()
                .find(|element| element.id == id.as_str())
            {
                Some(element) => element.is_text_element(),
                None => false,
            }
        })
    }

    fn has_multiple_selected_text_elements(&self, snapshot: &TextToolPluginStateSnapshot) -> bool {
        snapshot
            .selected_ids
            .iter()
            .filter(|id| {
                match snapshot
                    .elements
                    .iter()
                    .find(|element| element.id == id.as_str())
                {
                    Some(element) => element.is_text_element(),
                    None => false,
                }
            })
            .take(2)
            .count()
            > 1
    }

    fn is_inside_selected_text_element(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        position: DrawPoint,
    ) -> bool {
        snapshot.selected_ids.iter().any(|id| {
            let Some(element) = snapshot
                .elements
                .iter()
                .find(|element| element.id == id.as_str())
            else {
                return false;
            };
            element.is_text_element()
                && is_inside_rect_with_padding(element.rect, element.rotation, position, 0.0)
        })
    }

    fn selected_text_hit_id_for_edit(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        event: &PointerDownInputEvent,
    ) -> Option<String> {
        if !self.is_selection_like_tool_active() {
            return None;
        }
        if event.input.modifiers.shift {
            return None;
        }
        if !snapshot.has_selection() {
            return None;
        }
        if self.has_multiple_selected_text_elements(snapshot) {
            return None;
        }

        self.hit_text_element_id(snapshot, event.input.position, Some(&snapshot.selected_ids))
    }

    fn hit_text_element_id(
        &self,
        snapshot: &TextToolPluginStateSnapshot,
        position: DrawPoint,
        allowed_ids: Option<&BTreeSet<String>>,
    ) -> Option<String> {
        let mut elements = snapshot.elements.iter().collect::<Vec<_>>();
        elements.sort_by(|left, right| {
            left.z_index
                .cmp(&right.z_index)
                .then_with(|| left.id.cmp(&right.id))
        });

        for element in elements.into_iter().rev() {
            if let Some(allowed_ids) = allowed_ids {
                if !allowed_ids.contains(&element.id) {
                    continue;
                }
            }

            if !element.is_text_element() {
                continue;
            }

            let Some(source_element) = snapshot
                .draw_state
                .domain
                .document
                .get_element_by_id(&element.id)
            else {
                continue;
            };

            if self
                .hit_tester
                .hit_test_text_element(source_element, position)
            {
                return Some(element.id.clone());
            }
        }

        None
    }
}

impl InputPlugin for TextToolPlugin {
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
        <InputPluginBase as InputPlugin>::on_unload(&mut self.base)
    }

    fn can_handle(&self, _event: &InputEvent, state: &DrawState) -> bool {
        if state.application.is_text_editing() {
            return true;
        }
        if self.is_text_tool_active() {
            return self.routing_policy.allow_create(state);
        }
        if self.is_selection_like_tool_active() {
            return self.routing_policy.allow_selection(state);
        }
        false
    }

    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult {
        if let Some(event) = downcast_input_event::<PointerDownInputEvent>(event) {
            return self.handle_pointer_down(event);
        }
        if downcast_input_event::<PointerMoveInputEvent>(event).is_some() {
            return self.ignore_while_text_editing("Text editing pointer move ignored");
        }
        if downcast_input_event::<PointerUpInputEvent>(event).is_some() {
            return self.ignore_while_text_editing("Text editing pointer up ignored");
        }
        if downcast_input_event::<PointerCancelInputEvent>(event).is_some() {
            return self.ignore_while_text_editing("Text editing pointer cancel ignored");
        }

        Ok(PluginResult::unhandled(None))
    }

    fn reset(&mut self) {
        self.current_tool_type_id = None;
        self.is_selection_tool_active = true;
    }
}

impl DrawInputPlugin for TextToolPlugin {
    fn base(&self) -> &InputPluginBase {
        &self.base
    }

    fn base_mut(&mut self) -> &mut InputPluginBase {
        &mut self.base
    }
}

fn selection_bounds(elements: &[&TextToolElementSnapshot]) -> Option<DrawRect> {
    if elements.is_empty() {
        return None;
    }

    let mut bounds = element_world_aabb(elements[0]);
    for element in &elements[1..] {
        bounds = merge_rect(bounds, element_world_aabb(element));
    }
    Some(bounds)
}

fn merge_rect(a: DrawRect, b: DrawRect) -> DrawRect {
    DrawRect::new(
        a.min_x.min(b.min_x),
        a.min_y.min(b.min_y),
        a.max_x.max(b.max_x),
        a.max_y.max(b.max_y),
    )
}

fn expand_rect(rect: DrawRect, padding: f64) -> DrawRect {
    DrawRect::new(
        rect.min_x - padding,
        rect.min_y - padding,
        rect.max_x + padding,
        rect.max_y + padding,
    )
}

fn element_world_aabb(element: &TextToolElementSnapshot) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }

    let space = ElementSpace::new(element.rotation, element.rect.center());
    let corners = [
        DrawPoint::new(element.rect.min_x, element.rect.min_y),
        DrawPoint::new(element.rect.max_x, element.rect.min_y),
        DrawPoint::new(element.rect.max_x, element.rect.max_y),
        DrawPoint::new(element.rect.min_x, element.rect.max_y),
    ];
    DrawRect::from_point_cloud(corners.into_iter().map(|point| space.to_world(point)))
}

fn is_inside_rect_with_padding(
    rect: DrawRect,
    rotation: f64,
    position: DrawPoint,
    padding: f64,
) -> bool {
    let local = if rotation == 0.0 {
        position
    } else {
        ElementSpace::new(rotation, rect.center()).from_world(position)
    };

    local.x >= rect.min_x - padding
        && local.x <= rect.max_x + padding
        && local.y >= rect.min_y - padding
        && local.y <= rect.max_y + padding
}

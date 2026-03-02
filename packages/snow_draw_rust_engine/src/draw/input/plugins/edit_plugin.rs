#![allow(dead_code)]

use std::any::TypeId;

use crate::draw::actions::draw_actions::{CancelEdit, FinishEdit, UpdateEdit};
use crate::draw::input::input_event::{
    KeyModifiers, PointerCancelInputEvent, PointerDownInputEvent, PointerMoveInputEvent,
    PointerUpInputEvent,
};
use crate::draw::input::plugin_engine::{
    downcast_input_event, DrawInputPlugin, InputEvent, InputPlugin, InputPluginBase,
    InputRoutingPolicy, PluginError, PluginHandleResult, PluginLifecycleResult, PluginResult,
    SupportedEventTypes,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::types::draw_point::DrawPoint;

/// Plugin that manages edit sessions (move/resize/rotate).
pub struct EditPlugin {
    base: InputPluginBase,
    routing_policy: InputRoutingPolicy,
    update_guard: PointerUpdateGuard,
}

impl EditPlugin {
    pub fn new(routing_policy: Option<InputRoutingPolicy>) -> Self {
        Self {
            base: InputPluginBase::new("edit", "Edit Plugin", 0, supported_event_types()),
            routing_policy: routing_policy.unwrap_or_default(),
            update_guard: PointerUpdateGuard::default(),
        }
    }

    fn dispatch_action<A>(&self, action: A) -> Result<(), PluginError>
    where
        A: Send + Sync + 'static,
    {
        self.dispatch(Box::new(action))
            .map_err(|error| Box::new(error) as PluginError)
    }

    fn handle_pointer_down(&mut self) -> PluginHandleResult {
        self.clear_update_signature();

        match self.routing_policy.edit_pointer_down_behavior {
            crate::draw::input::plugin_engine::EditPointerDownBehavior::Ignore => {
                Ok(self.base.unhandled(None))
            }
            crate::draw::input::plugin_engine::EditPointerDownBehavior::CancelEdit => {
                self.dispatch_action(CancelEdit::default())?;
                Ok(self.base.handled(Some("Edit canceled".to_owned())))
            }
            crate::draw::input::plugin_engine::EditPointerDownBehavior::CommitEdit => {
                self.dispatch_action(FinishEdit::new(None))?;
                Ok(self.base.handled(Some("Edit committed".to_owned())))
            }
        }
    }

    fn handle_pointer_move(
        &mut self,
        position: DrawPoint,
        modifiers: KeyModifiers,
    ) -> PluginHandleResult {
        if !self.should_dispatch_update(position, modifiers) {
            return Ok(self.base.handled(Some("Edit unchanged".to_owned())));
        }

        self.dispatch_action(UpdateEdit::new(position, modifiers.to_edit_modifiers()))?;
        Ok(self.base.handled(Some("Edit updated".to_owned())))
    }

    fn handle_pointer_up(&mut self) -> PluginHandleResult {
        self.clear_update_signature();
        self.dispatch_action(FinishEdit::new(None))?;
        Ok(self.base.handled(Some("Edit finished".to_owned())))
    }

    fn handle_pointer_cancel(&mut self) -> PluginHandleResult {
        self.clear_update_signature();
        self.dispatch_action(CancelEdit::default())?;
        Ok(self.base.consumed(Some("Edit canceled".to_owned())))
    }

    fn should_dispatch_update(&mut self, position: DrawPoint, modifiers: KeyModifiers) -> bool {
        self.update_guard
            .should_dispatch(position, modifiers, false)
    }

    fn clear_update_signature(&mut self) {
        self.update_guard.reset();
    }
}

impl Default for EditPlugin {
    fn default() -> Self {
        Self::new(None)
    }
}

impl InputPlugin for EditPlugin {
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
        self.clear_update_signature();
        <InputPluginBase as InputPlugin>::on_unload(&mut self.base)
    }

    fn can_handle(&self, _event: &InputEvent, state: &DrawState) -> bool {
        state.application.is_editing()
    }

    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult {
        if downcast_input_event::<PointerDownInputEvent>(event).is_some() {
            return self.handle_pointer_down();
        }
        if let Some(pointer_move) = downcast_input_event::<PointerMoveInputEvent>(event) {
            return self
                .handle_pointer_move(pointer_move.input.position, pointer_move.input.modifiers);
        }
        if downcast_input_event::<PointerUpInputEvent>(event).is_some() {
            return self.handle_pointer_up();
        }
        if downcast_input_event::<PointerCancelInputEvent>(event).is_some() {
            return self.handle_pointer_cancel();
        }

        Ok(self.base.unhandled(None))
    }

    fn reset(&mut self) {
        self.clear_update_signature();
    }
}

impl DrawInputPlugin for EditPlugin {
    fn base(&self) -> &InputPluginBase {
        &self.base
    }

    fn base_mut(&mut self) -> &mut InputPluginBase {
        &mut self.base
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
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
        if !force {
            if let Some(last_position) = self.last_position {
                if last_position.x == position.x
                    && last_position.y == position.y
                    && self.last_modifiers == Some(modifiers)
                {
                    return false;
                }
            }
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

fn supported_event_types() -> SupportedEventTypes {
    let mut types = SupportedEventTypes::new();
    types.insert(TypeId::of::<PointerDownInputEvent>());
    types.insert(TypeId::of::<PointerMoveInputEvent>());
    types.insert(TypeId::of::<PointerUpInputEvent>());
    types.insert(TypeId::of::<PointerCancelInputEvent>());
    types
}

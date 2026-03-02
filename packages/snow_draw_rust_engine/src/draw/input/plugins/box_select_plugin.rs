#![allow(dead_code)]

use std::any::TypeId;

use crate::draw::actions::draw_actions::{CancelBoxSelect, FinishBoxSelect, UpdateBoxSelect};
use crate::draw::input::input_event::{
    PointerCancelInputEvent, PointerMoveInputEvent, PointerUpInputEvent,
};
use crate::draw::input::plugin_engine::{
    downcast_input_event, DrawInputPlugin, InputEvent, InputPlugin, InputPluginBase,
    InputRoutingPolicy, PluginError, PluginHandleResult, PluginLifecycleResult,
    SupportedEventTypes,
};
use crate::draw::models::draw_state::DrawState;

/// Plugin that updates box selection interactions.
pub struct BoxSelectPlugin {
    base: InputPluginBase,
    routing_policy: InputRoutingPolicy,
}

impl BoxSelectPlugin {
    pub fn new(routing_policy: Option<InputRoutingPolicy>) -> Self {
        Self {
            base: InputPluginBase::new(
                "box_select",
                "Box Select Plugin",
                30,
                supported_event_types(),
            ),
            routing_policy: routing_policy.unwrap_or_default(),
        }
    }

    fn dispatch_action<A>(&self, action: A) -> Result<(), PluginError>
    where
        A: Send + Sync + 'static,
    {
        self.dispatch(Box::new(action))
            .map_err(|error| Box::new(error) as PluginError)
    }
}

impl Default for BoxSelectPlugin {
    fn default() -> Self {
        Self::new(None)
    }
}

impl InputPlugin for BoxSelectPlugin {
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
        self.routing_policy.allow_box_select(state)
    }

    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult {
        if !self.state().application.is_box_selecting() {
            return Ok(self.base.unhandled(None));
        }

        if let Some(pointer_move) = downcast_input_event::<PointerMoveInputEvent>(event) {
            self.dispatch_action(UpdateBoxSelect::new(pointer_move.input.position))?;
            return Ok(self.base.handled(Some("Box select updated".to_owned())));
        }
        if downcast_input_event::<PointerUpInputEvent>(event).is_some() {
            self.dispatch_action(FinishBoxSelect)?;
            return Ok(self.base.handled(Some("Box select finished".to_owned())));
        }
        if downcast_input_event::<PointerCancelInputEvent>(event).is_some() {
            self.dispatch_action(CancelBoxSelect)?;
            return Ok(self.base.consumed(Some("Box select canceled".to_owned())));
        }

        Ok(self.base.unhandled(None))
    }
}

impl DrawInputPlugin for BoxSelectPlugin {
    fn base(&self) -> &InputPluginBase {
        &self.base
    }

    fn base_mut(&mut self) -> &mut InputPluginBase {
        &mut self.base
    }
}

fn supported_event_types() -> SupportedEventTypes {
    let mut types = SupportedEventTypes::new();
    types.insert(TypeId::of::<PointerMoveInputEvent>());
    types.insert(TypeId::of::<PointerUpInputEvent>());
    types.insert(TypeId::of::<PointerCancelInputEvent>());
    types
}

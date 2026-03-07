#![allow(dead_code)]

use std::any::{Any, TypeId};
use std::collections::HashSet;
use std::error::Error;
use std::fmt;
use std::sync::Arc;

use crate::draw::config::draw_config::SelectionConfig;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::models::draw_state::DrawState;

/// Marker trait for dispatchable draw actions.
///
/// The dedicated action hierarchy is translated separately. Until then,
/// the plugin engine dispatches erased action values.
pub trait DrawAction: Send + Sync + 'static {}

impl<T> DrawAction for T where T: Send + Sync + 'static {}

/// Dispatch failure surfaced by [`ActionDispatcher`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PluginDispatchError {
    Message(String),
}

impl PluginDispatchError {
    pub fn message(message: impl Into<String>) -> Self {
        Self::Message(message.into())
    }
}

impl fmt::Display for PluginDispatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Message(message) => f.write_str(message),
        }
    }
}

impl Error for PluginDispatchError {}

/// Action dispatcher interface.
///
/// Mirrors Dart's `Future<void> Function(DrawAction action)` using a
/// synchronous `Result` contract. Async dispatch can be wrapped by callers.
pub type ActionDispatcher =
    Arc<dyn Fn(Box<dyn DrawAction>) -> Result<(), PluginDispatchError> + Send + Sync + 'static>;

/// State provider for input systems.
pub trait StateProvider {
    fn state(&self) -> DrawState;
}

/// Erased input event value used by plugins.
///
/// Plugins should store concrete input-event structs (for example
/// `PointerDownInputEvent`) inside this `Arc` and downcast in handlers.
pub type InputEvent = Arc<dyn Any + Send + Sync + 'static>;

/// Set of supported event runtime types.
pub type SupportedEventTypes = HashSet<TypeId>;

/// Returns runtime type id for an erased event.
pub fn input_event_type_id(event: &InputEvent) -> TypeId {
    event.as_ref().type_id()
}

/// Returns true if `event` has concrete type `T`.
pub fn input_event_is<T>(event: &InputEvent) -> bool
where
    T: Any + Send + Sync + 'static,
{
    event.as_ref().is::<T>()
}

/// Downcasts an erased event to `&T`.
pub fn downcast_input_event<T>(event: &InputEvent) -> Option<&T>
where
    T: Any + Send + Sync + 'static,
{
    event.as_ref().downcast_ref::<T>()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EditPointerDownBehavior {
    Ignore,
    CancelEdit,
    CommitEdit,
}

/// Explicit routing policy for input while editing.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct InputRoutingPolicy {
    pub allow_selection_while_editing: bool,
    pub allow_box_select_while_editing: bool,
    pub allow_create_while_editing: bool,
    pub edit_pointer_down_behavior: EditPointerDownBehavior,
}

impl InputRoutingPolicy {
    pub const fn new(
        allow_selection_while_editing: bool,
        allow_box_select_while_editing: bool,
        allow_create_while_editing: bool,
        edit_pointer_down_behavior: EditPointerDownBehavior,
    ) -> Self {
        Self {
            allow_selection_while_editing,
            allow_box_select_while_editing,
            allow_create_while_editing,
            edit_pointer_down_behavior,
        }
    }

    pub const DEFAULT_POLICY: Self =
        Self::new(false, false, false, EditPointerDownBehavior::CommitEdit);

    pub fn allow_selection(&self, state: &DrawState) -> bool {
        !state.application.is_editing() || self.allow_selection_while_editing
    }

    pub fn allow_box_select(&self, state: &DrawState) -> bool {
        !state.application.is_editing() || self.allow_box_select_while_editing
    }

    pub fn allow_create(&self, state: &DrawState) -> bool {
        !state.application.is_editing() || self.allow_create_while_editing
    }
}

impl Default for InputRoutingPolicy {
    fn default() -> Self {
        Self::DEFAULT_POLICY
    }
}

/// Plugin handling status.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PluginResultStatus {
    /// Event handled; stop propagation.
    Handled,
    /// Event unhandled; continue propagation.
    Unhandled,
    /// Event consumed; observation allowed.
    Consumed,
}

impl PluginResultStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Handled => "handled",
            Self::Unhandled => "unhandled",
            Self::Consumed => "consumed",
        }
    }
}

/// Plugin handling result.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct PluginResult {
    pub status: PluginResultStatus,
    pub message: Option<String>,
}

impl PluginResult {
    fn new(status: PluginResultStatus, message: Option<String>) -> Self {
        Self { status, message }
    }

    /// Event handled; stop propagation to other plugins.
    pub fn handled(message: Option<String>) -> Self {
        Self::new(PluginResultStatus::Handled, message)
    }

    /// Event unhandled; continue propagation to next plugin.
    pub fn unhandled(reason: Option<String>) -> Self {
        Self::new(PluginResultStatus::Unhandled, reason)
    }

    /// Event consumed; allow other plugins to observe.
    pub fn consumed(message: Option<String>) -> Self {
        Self::new(PluginResultStatus::Consumed, message)
    }

    pub fn is_handled(&self) -> bool {
        self.status == PluginResultStatus::Handled
    }

    pub fn is_unhandled(&self) -> bool {
        self.status == PluginResultStatus::Unhandled
    }

    pub fn is_consumed(&self) -> bool {
        self.status == PluginResultStatus::Consumed
    }

    /// Whether plugin propagation should stop.
    pub fn should_stop_propagation(&self) -> bool {
        self.status == PluginResultStatus::Handled
    }
}

impl fmt::Display for PluginResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.message {
            Some(message) => write!(f, "PluginResult.{}: {}", self.status.as_str(), message),
            None => write!(f, "PluginResult.{}", self.status.as_str()),
        }
    }
}

/// Plugin context.
///
/// Provides dependencies required by plugins.
#[derive(Clone)]
pub struct PluginContext {
    state_provider: Arc<dyn Fn() -> DrawState + Send + Sync + 'static>,
    context_provider: Arc<dyn Fn() -> DrawContext + Send + Sync + 'static>,
    selection_config_provider: Arc<dyn Fn() -> SelectionConfig + Send + Sync + 'static>,
    dispatcher: ActionDispatcher,
}

impl PluginContext {
    pub fn new(
        state_provider: Arc<dyn Fn() -> DrawState + Send + Sync + 'static>,
        context_provider: Arc<dyn Fn() -> DrawContext + Send + Sync + 'static>,
        selection_config_provider: Arc<dyn Fn() -> SelectionConfig + Send + Sync + 'static>,
        dispatcher: ActionDispatcher,
    ) -> Self {
        Self {
            state_provider,
            context_provider,
            selection_config_provider,
            dispatcher,
        }
    }

    /// Gets the current state.
    pub fn state(&self) -> DrawState {
        (self.state_provider)()
    }

    /// Gets draw context.
    pub fn context(&self) -> DrawContext {
        (self.context_provider)()
    }

    /// Gets selection configuration.
    pub fn selection_config(&self) -> SelectionConfig {
        (self.selection_config_provider)()
    }

    /// Dispatches an action.
    pub fn dispatch(&self, action: Box<dyn DrawAction>) -> Result<(), PluginDispatchError> {
        (self.dispatcher)(action)
    }
}

impl fmt::Debug for PluginContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PluginContext").finish_non_exhaustive()
    }
}

/// Standard boxed error used by plugin hooks.
pub type PluginError = Box<dyn Error + Send + Sync + 'static>;

/// Lifecycle hook result type.
pub type PluginLifecycleResult = Result<(), PluginError>;

/// Event-handle result type.
pub type PluginHandleResult = Result<PluginResult, PluginError>;

/// Input plugin interface.
///
/// Plugins are pluggable input handlers. Each plugin owns specific input logic.
pub trait InputPlugin: Send {
    /// Plugin unique identifier.
    fn id(&self) -> &str;

    /// Plugin name (for debugging and logging).
    fn name(&self) -> &str;

    /// Priority (lower number means higher priority, 0-100).
    fn priority(&self) -> i32;

    /// Event types supported by the plugin.
    fn supported_event_types(&self) -> &SupportedEventTypes;

    /// Lifecycle hook called when the plugin is loaded.
    fn on_load(&mut self, context: PluginContext) -> PluginLifecycleResult;

    /// Lifecycle hook called when the plugin is unloaded.
    fn on_unload(&mut self) -> PluginLifecycleResult;

    /// Determines whether the plugin can handle `event` in the current `state`.
    fn can_handle(&self, event: &InputEvent, state: &DrawState) -> bool;

    /// Handles one input event.
    fn handle_event(&mut self, event: &InputEvent) -> PluginHandleResult;

    /// Resets plugin-local state.
    fn reset(&mut self) {}
}

/// Error returned by [`InputPluginBase::try_context`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PluginBaseError {
    NotLoaded { plugin_name: String },
}

impl fmt::Display for PluginBaseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotLoaded { plugin_name } => {
                write!(f, "Plugin {plugin_name} has not been loaded yet")
            }
        }
    }
}

impl Error for PluginBaseError {}

/// Input plugin base class.
///
/// Provides default implementations and helpers to simplify plugin development.
#[derive(Clone, Debug)]
pub struct InputPluginBase {
    id: String,
    name: String,
    priority: i32,
    supported_event_types: SupportedEventTypes,
    context: Option<PluginContext>,
}

impl InputPluginBase {
    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        priority: i32,
        supported_event_types: SupportedEventTypes,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            priority,
            supported_event_types,
            context: None,
        }
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn priority(&self) -> i32 {
        self.priority
    }

    pub fn supported_event_types(&self) -> &SupportedEventTypes {
        &self.supported_event_types
    }

    /// Gets plugin context or panics when plugin has not been loaded yet.
    pub fn context(&self) -> &PluginContext {
        self.try_context()
            .unwrap_or_else(|_| panic!("Plugin {} has not been loaded yet", self.name))
    }

    /// Fallible variant of [`Self::context`].
    pub fn try_context(&self) -> Result<&PluginContext, PluginBaseError> {
        self.context
            .as_ref()
            .ok_or_else(|| PluginBaseError::NotLoaded {
                plugin_name: self.name.clone(),
            })
    }

    /// Returns true when plugin lifecycle is loaded.
    pub fn is_loaded(&self) -> bool {
        self.context.is_some()
    }

    pub fn load(&mut self, context: PluginContext) {
        self.context = Some(context);
    }

    pub fn unload(&mut self) {
        self.context = None;
    }

    pub fn handled(&self, message: Option<String>) -> PluginResult {
        PluginResult::handled(message)
    }

    pub fn unhandled(&self, reason: Option<String>) -> PluginResult {
        PluginResult::unhandled(reason)
    }

    pub fn consumed(&self, message: Option<String>) -> PluginResult {
        PluginResult::consumed(message)
    }
}

impl InputPlugin for InputPluginBase {
    fn id(&self) -> &str {
        self.id()
    }

    fn name(&self) -> &str {
        self.name()
    }

    fn priority(&self) -> i32 {
        self.priority()
    }

    fn supported_event_types(&self) -> &SupportedEventTypes {
        self.supported_event_types()
    }

    fn on_load(&mut self, context: PluginContext) -> PluginLifecycleResult {
        self.load(context);
        Ok(())
    }

    fn on_unload(&mut self) -> PluginLifecycleResult {
        self.unload();
        Ok(())
    }

    fn can_handle(&self, _event: &InputEvent, _state: &DrawState) -> bool {
        false
    }

    fn handle_event(&mut self, _event: &InputEvent) -> PluginHandleResult {
        Ok(PluginResult::unhandled(None))
    }
}

/// Base trait for draw input plugins.
///
/// Concrete plugin implementations should embed [`InputPluginBase`] and return
/// references through [`Self::base`] and [`Self::base_mut`].
pub trait DrawInputPlugin: InputPlugin {
    fn base(&self) -> &InputPluginBase;
    fn base_mut(&mut self) -> &mut InputPluginBase;

    fn state(&self) -> DrawState {
        self.base().context().state()
    }

    fn draw_context(&self) -> DrawContext {
        self.base().context().context()
    }

    fn selection_config(&self) -> SelectionConfig {
        self.base().context().selection_config()
    }

    fn dispatch(&self, action: Box<dyn DrawAction>) -> Result<(), PluginDispatchError> {
        self.base().context().dispatch(action)
    }
}

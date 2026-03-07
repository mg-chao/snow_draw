#![allow(dead_code)]

use std::any::TypeId;
use std::collections::{BTreeMap, HashSet};
use std::error::Error;
use std::fmt;

use crate::draw::input::plugin_engine::{
    input_event_type_id, InputEvent, InputPlugin, PluginContext, PluginResult,
};
use crate::draw::input::plugins::box_select_plugin::BoxSelectPlugin;
use crate::draw::input::plugins::create_plugin::CreatePlugin;
use crate::draw::input::plugins::edit_plugin::EditPlugin;
use crate::draw::input::plugins::select_plugin::SelectPlugin;
use crate::draw::input::plugins::text_tool_plugin::TextToolPlugin;

/// Registration/lifecycle failures emitted by [`PluginRegistry`].
#[derive(Debug)]
pub enum PluginRegistryError {
    AlreadyRegistered {
        plugin_id: String,
    },
    DuplicateBatchPluginId {
        plugin_id: String,
    },
    NotRegistered {
        plugin_id: String,
    },
    PluginLoadFailed {
        plugin_id: String,
        source: Box<dyn Error + Send + Sync + 'static>,
    },
    PluginUnloadFailed {
        plugin_id: String,
        source: Box<dyn Error + Send + Sync + 'static>,
    },
}

impl fmt::Display for PluginRegistryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AlreadyRegistered { plugin_id } => {
                write!(f, "Plugin with id \"{plugin_id}\" is already registered")
            }
            Self::DuplicateBatchPluginId { plugin_id } => write!(
                f,
                "Duplicate plugin id \"{plugin_id}\" in batch registration"
            ),
            Self::NotRegistered { plugin_id } => {
                write!(f, "Plugin with id \"{plugin_id}\" is not registered")
            }
            Self::PluginLoadFailed { plugin_id, source } => {
                write!(f, "Plugin \"{plugin_id}\" failed to load: {source}")
            }
            Self::PluginUnloadFailed { plugin_id, source } => {
                write!(f, "Plugin \"{plugin_id}\" failed to unload: {source}")
            }
        }
    }
}

impl Error for PluginRegistryError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::PluginLoadFailed { source, .. } | Self::PluginUnloadFailed { source, .. } => {
                Some(source.as_ref())
            }
            _ => None,
        }
    }
}

/// Lightweight plugin metadata entry used by [`PluginRegistryStats`].
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct PluginPriorityStat {
    pub id: String,
    pub name: String,
    pub priority: i32,
}

/// Aggregated plugin registry statistics.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PluginRegistryStats {
    pub total_plugins: usize,
    pub plugins_by_priority: Vec<PluginPriorityStat>,
    pub event_type_handlers: BTreeMap<String, usize>,
}

/// Input plugin registry.
///
/// Mirrors Dart `PluginRegistry` behavior:
/// - unique id enforcement
/// - deterministic priority ordering
/// - best-effort error logging around plugin hooks
pub struct PluginRegistry {
    context: PluginContext,
    plugins: Vec<Box<dyn InputPlugin>>,
}

impl PluginRegistry {
    pub fn new(context: PluginContext) -> Self {
        Self {
            context,
            plugins: Vec::new(),
        }
    }

    /// Registers built-in plugins in Dart order.
    ///
    /// Order by priority:
    /// - edit (0)
    /// - text_tool (5)
    /// - create (10)
    /// - select (20)
    /// - box_select (30)
    pub fn register_defaults(&mut self) -> Result<(), PluginRegistryError> {
        self.register_all(vec![
            Box::new(EditPlugin::new(None)),
            Box::new(TextToolPlugin::new(None, Some(true), None)),
            Box::new(CreatePlugin::new(None, None)),
            Box::new(SelectPlugin::new(None, true, None)),
            Box::new(BoxSelectPlugin::new(None)),
        ])
    }

    pub fn plugins(&self) -> &[Box<dyn InputPlugin>] {
        &self.plugins
    }

    pub fn plugin_count(&self) -> usize {
        self.plugins.len()
    }

    pub fn register(&mut self, plugin: Box<dyn InputPlugin>) -> Result<(), PluginRegistryError> {
        self.register_all(vec![plugin])
    }

    /// Registers plugins as an atomic batch.
    ///
    /// If one plugin fails during load, already loaded plugins in the same
    /// batch are rolled back in reverse order and nothing is inserted.
    pub fn register_all(
        &mut self,
        mut plugins: Vec<Box<dyn InputPlugin>>,
    ) -> Result<(), PluginRegistryError> {
        if plugins.is_empty() {
            return Ok(());
        }

        self.validate_batch_plugin_ids(&plugins)?;

        let mut loaded_count = 0usize;
        for plugin in plugins.iter_mut() {
            let plugin_id = plugin.id().to_owned();
            if let Err(source) = plugin.on_load(self.context.clone()) {
                for loaded in plugins[..loaded_count].iter_mut().rev() {
                    Self::rollback_plugin(&self.context, loaded.as_mut());
                }
                return Err(PluginRegistryError::PluginLoadFailed { plugin_id, source });
            }
            loaded_count += 1;
        }

        for plugin in plugins {
            self.insert_plugin(plugin);
        }

        Ok(())
    }

    pub fn unregister(&mut self, plugin_id: &str) -> Result<(), PluginRegistryError> {
        let Some(index) = self.find_plugin_index(plugin_id) else {
            return Err(PluginRegistryError::NotRegistered {
                plugin_id: plugin_id.to_owned(),
            });
        };

        if let Err(source) = self.plugins[index].on_unload() {
            return Err(PluginRegistryError::PluginUnloadFailed {
                plugin_id: plugin_id.to_owned(),
                source,
            });
        }

        self.plugins.remove(index);
        Ok(())
    }

    pub fn is_registered(&self, plugin_id: &str) -> bool {
        self.find_plugin_index(plugin_id).is_some()
    }

    pub fn get_plugin(&self, plugin_id: &str) -> Option<&dyn InputPlugin> {
        self.plugins
            .iter()
            .find(|plugin| plugin.id() == plugin_id)
            .map(Box::as_ref)
    }

    pub fn get_plugin_mut(&mut self, plugin_id: &str) -> Option<&mut (dyn InputPlugin + '_)> {
        for plugin in &mut self.plugins {
            if plugin.id() == plugin_id {
                return Some(plugin.as_mut());
            }
        }
        None
    }

    /// Dispatches one event through plugins by priority.
    ///
    /// Stops on `Handled`, keeps last result for `Consumed`/`Unhandled`.
    pub fn dispatch(&mut self, event: &InputEvent) -> Option<PluginResult> {
        let state = self.context.state();
        let event_type = input_event_type_id(event);
        let context = self.context.clone();

        let mut final_result = None;
        for plugin in &mut self.plugins {
            if !supports_event_type(plugin.supported_event_types(), event_type) {
                continue;
            }

            if !plugin.can_handle(event, &state) {
                continue;
            }

            let result = match plugin.handle_event(event) {
                Ok(result) => result,
                Err(error) => {
                    Self::log_plugin_error(
                        &context,
                        "Plugin handle_event failed",
                        plugin.id(),
                        plugin.name(),
                        Some(event_type),
                        error.as_ref(),
                    );
                    continue;
                }
            };

            let stop = result.should_stop_propagation();
            final_result = Some(result);
            if stop {
                break;
            }
        }

        final_result
    }

    pub fn reset_all(&mut self) {
        for plugin in &mut self.plugins {
            plugin.reset();
        }
    }

    pub fn dispose(&mut self) {
        let context = self.context.clone();
        for plugin in &mut self.plugins {
            if let Err(error) = plugin.on_unload() {
                Self::log_plugin_error(
                    &context,
                    "Plugin unload failed",
                    plugin.id(),
                    plugin.name(),
                    None,
                    error.as_ref(),
                );
            }
        }
        self.plugins.clear();
    }

    pub fn get_stats(&self) -> PluginRegistryStats {
        let mut event_type_handlers: BTreeMap<String, usize> = BTreeMap::new();
        for plugin in &self.plugins {
            for event_type in plugin.supported_event_types() {
                let key = format!("{event_type:?}");
                *event_type_handlers.entry(key).or_insert(0) += 1;
            }
        }

        let plugins_by_priority = self
            .plugins
            .iter()
            .map(|plugin| PluginPriorityStat {
                id: plugin.id().to_owned(),
                name: plugin.name().to_owned(),
                priority: plugin.priority(),
            })
            .collect();

        PluginRegistryStats {
            total_plugins: self.plugins.len(),
            plugins_by_priority,
            event_type_handlers,
        }
    }

    fn validate_batch_plugin_ids(
        &self,
        plugins: &[Box<dyn InputPlugin>],
    ) -> Result<(), PluginRegistryError> {
        let registered_ids: HashSet<String> = self
            .plugins
            .iter()
            .map(|plugin| plugin.id().to_owned())
            .collect();
        let mut batch_ids: HashSet<String> = HashSet::new();

        for plugin in plugins {
            let plugin_id = plugin.id().to_owned();
            if registered_ids.contains(&plugin_id) {
                return Err(PluginRegistryError::AlreadyRegistered { plugin_id });
            }
            if !batch_ids.insert(plugin_id.clone()) {
                return Err(PluginRegistryError::DuplicateBatchPluginId { plugin_id });
            }
        }

        Ok(())
    }

    fn find_plugin_index(&self, plugin_id: &str) -> Option<usize> {
        self.plugins
            .iter()
            .position(|plugin| plugin.id() == plugin_id)
    }

    fn insert_plugin(&mut self, plugin: Box<dyn InputPlugin>) {
        let insert_at = self
            .plugins
            .iter()
            .position(|candidate| candidate.priority() > plugin.priority())
            .unwrap_or(self.plugins.len());
        self.plugins.insert(insert_at, plugin);
    }

    fn rollback_plugin(context: &PluginContext, plugin: &mut dyn InputPlugin) {
        if let Err(error) = plugin.on_unload() {
            let logger = context.context().log.input();
            logger.error(
                "Plugin rollback unload failed",
                Some(&error.to_string()),
                None,
                None,
            );
        }
    }

    fn log_plugin_error(
        context: &PluginContext,
        message: &str,
        plugin_id: &str,
        plugin_name: &str,
        event_type: Option<TypeId>,
        error: &(dyn Error + Send + Sync + 'static),
    ) {
        let mut metadata = BTreeMap::new();
        metadata.insert("pluginId".to_owned(), plugin_id.to_owned());
        metadata.insert("plugin".to_owned(), plugin_name.to_owned());
        if let Some(event_type) = event_type {
            metadata.insert("eventType".to_owned(), format!("{event_type:?}"));
        }

        let logger = context.context().log.input();
        logger.error(message, Some(&error.to_string()), None, Some(&metadata));
    }
}

fn supports_event_type(supported: &HashSet<TypeId>, event_type: TypeId) -> bool {
    supported.contains(&event_type)
}

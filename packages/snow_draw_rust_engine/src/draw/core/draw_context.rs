#![allow(dead_code)]

use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};

use crate::draw::config::config_manager::{ConfigManager, DrawConfigLike};
use crate::draw::config::draw_config::{
    CanvasConfig, DrawConfig, DrawConfigPatch, SelectionConfig,
};
use crate::draw::edit::core::edit_intent_to_operation_mapper::EditIntentToOperationMapper;
use crate::draw::edit::edit_operations::DefaultEditOperationRegistry;
use crate::draw::elements::core::element_registry::DefaultElementRegistry;
use crate::draw::events::event_bus::EventBus;
use crate::draw::services::log::log_service::LogService;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::utils::id_generator::{IdGenerator, RandomStringIdGenerator};

impl DrawConfigLike for DrawConfig {
    type SelectionConfig = SelectionConfig;
    type CanvasConfig = CanvasConfig;

    fn copy_with_selection(&self, selection: Self::SelectionConfig) -> Self {
        self.copy_with(DrawConfigPatch {
            selection: Some(selection),
            ..DrawConfigPatch::default()
        })
    }

    fn copy_with_canvas(&self, canvas: Self::CanvasConfig) -> Self {
        self.copy_with(DrawConfigPatch {
            canvas: Some(canvas),
            ..DrawConfigPatch::default()
        })
    }
}

/// Canvas context holding all injectable dependencies.
///
/// This replaces global singletons and enables testability and multi-canvas
/// isolation.
#[derive(Clone)]
pub struct DrawContext {
    pub element_registry: Arc<DefaultElementRegistry>,
    pub edit_operations: Arc<DefaultEditOperationRegistry>,
    pub id_generator: IdGenerator,
    pub config_manager: Arc<Mutex<ConfigManager<DrawConfig>>>,
    pub edit_intent_mapper: Arc<EditIntentToOperationMapper>,
    pub log: Arc<LogService>,
    pub text_metrics_service: Arc<dyn TextMetricsService>,
    pub event_bus: Option<Arc<EventBus>>,
}

impl DrawContext {
    /// Creates a context from explicit dependencies.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        element_registry: DefaultElementRegistry,
        edit_operations: DefaultEditOperationRegistry,
        id_generator: IdGenerator,
        edit_intent_mapper: Option<EditIntentToOperationMapper>,
        config_manager: Option<ConfigManager<DrawConfig>>,
        log_service: Option<LogService>,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
        event_bus: Option<EventBus>,
    ) -> Self {
        Self {
            element_registry: Arc::new(element_registry),
            edit_operations: Arc::new(edit_operations),
            id_generator,
            config_manager: Arc::new(Mutex::new(
                config_manager
                    .unwrap_or_else(|| ConfigManager::new(DrawConfig::default_config().clone())),
            )),
            edit_intent_mapper: Arc::new(
                edit_intent_mapper.unwrap_or_else(EditIntentToOperationMapper::with_defaults),
            ),
            log: Arc::new(log_service.unwrap_or_default()),
            text_metrics_service: text_metrics_service.unwrap_or_else(default_text_metrics_service),
            event_bus: event_bus.map(Arc::new),
        }
    }

    /// Creates a context with built-in defaults.
    #[allow(clippy::too_many_arguments)]
    pub fn with_defaults(
        element_registry: Option<DefaultElementRegistry>,
        edit_operations: Option<DefaultEditOperationRegistry>,
        id_generator: Option<IdGenerator>,
        edit_intent_mapper: Option<EditIntentToOperationMapper>,
        config_manager: Option<ConfigManager<DrawConfig>>,
        log_service: Option<LogService>,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
        event_bus: Option<EventBus>,
    ) -> Self {
        let resolved_registry = match element_registry {
            Some(registry) => registry,
            None => crate::draw::elements::registration::resolve_element_registry(None)
                .unwrap_or_default(),
        };
        Self::new(
            resolved_registry,
            edit_operations.unwrap_or_else(DefaultEditOperationRegistry::with_defaults),
            id_generator.unwrap_or_else(|| RandomStringIdGenerator::default().as_generator()),
            edit_intent_mapper,
            config_manager,
            log_service,
            text_metrics_service,
            event_bus,
        )
    }

    /// Convenience access to the current configuration snapshot.
    pub fn config(&self) -> DrawConfig {
        self.config_manager
            .lock()
            .expect("DrawContext.config_manager lock poisoned")
            .current()
            .clone()
    }

    /// Configuration change stream.
    pub fn config_stream(&self) -> Receiver<DrawConfig> {
        self.config_manager
            .lock()
            .expect("DrawContext.config_manager lock poisoned")
            .stream()
    }

    /// Clones the context while replacing selected dependencies.
    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        &self,
        element_registry: Option<DefaultElementRegistry>,
        edit_operations: Option<DefaultEditOperationRegistry>,
        id_generator: Option<IdGenerator>,
        edit_intent_mapper: Option<EditIntentToOperationMapper>,
        config_manager: Option<ConfigManager<DrawConfig>>,
        log_service: Option<LogService>,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
        event_bus: Option<EventBus>,
    ) -> Self {
        Self {
            element_registry: element_registry
                .map(Arc::new)
                .unwrap_or_else(|| self.element_registry.clone()),
            edit_operations: edit_operations
                .map(Arc::new)
                .unwrap_or_else(|| self.edit_operations.clone()),
            id_generator: id_generator.unwrap_or_else(|| self.id_generator.clone()),
            config_manager: config_manager
                .map(|manager| Arc::new(Mutex::new(manager)))
                .unwrap_or_else(|| self.config_manager.clone()),
            edit_intent_mapper: edit_intent_mapper
                .map(Arc::new)
                .unwrap_or_else(|| self.edit_intent_mapper.clone()),
            log: log_service
                .map(Arc::new)
                .unwrap_or_else(|| self.log.clone()),
            text_metrics_service: text_metrics_service
                .unwrap_or_else(|| self.text_metrics_service.clone()),
            event_bus: match event_bus {
                Some(bus) => Some(Arc::new(bus)),
                None => self.event_bus.clone(),
            },
        }
    }

    /// Generates a new element/document id.
    pub fn next_id(&self) -> String {
        (self.id_generator)()
    }
}

impl Default for DrawContext {
    fn default() -> Self {
        Self::with_defaults(None, None, None, None, None, None, None, None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::registration::TEXT_TYPE_VALUE;

    #[test]
    fn defaults_create_working_context() {
        let context = DrawContext::default();
        let config = context.config();

        assert!(config.selection.padding >= 0.0);
        assert!(!context.next_id().is_empty());
    }

    #[test]
    fn copy_with_keeps_existing_dependencies_when_omitted() {
        let context = DrawContext::default();
        let copied = context.copy_with(None, None, None, None, None, None, None, None);

        assert!(Arc::ptr_eq(
            &context.element_registry,
            &copied.element_registry
        ));
        assert!(Arc::ptr_eq(
            &context.edit_operations,
            &copied.edit_operations
        ));
        assert!(Arc::ptr_eq(&context.config_manager, &copied.config_manager));
    }

    #[test]
    fn with_defaults_uses_provided_registry_as_is() {
        let registry = DefaultElementRegistry::new();

        let context = DrawContext::with_defaults(
            Some(registry),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        );

        assert!(!context.element_registry.supports_type_value(TEXT_TYPE_VALUE));
    }
}

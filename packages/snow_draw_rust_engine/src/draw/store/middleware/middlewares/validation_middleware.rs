#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::actions::config_actions::{
    UpdateCanvasConfig, UpdateConfig, UpdateSelectionConfig,
};
use crate::draw::actions::draw_actions::{
    ChangeElementZIndex, ChangeElementsZIndex, CreateElement, CreateSerialNumberTextElements,
    DeleteElements, DrawAction, DuplicateElements, Redo, SelectElement, Undo, UpdateElementsStyle,
    UpdateGlobalElements, ZoomCamera,
};
use crate::draw::services::log::log_service::LogData;
use crate::draw::store::middleware::middleware_context::DispatchContext;
use crate::draw::store::middleware::middleware_pipeline::{
    DispatchFuture, Middleware, MiddlewareInvocationResult, NextFunction,
};

/// Validation result payload used by [`ValidationMiddleware`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ValidationResult {
    pub is_valid: bool,
    pub message: Option<String>,
}

impl ValidationResult {
    /// Creates a successful validation result.
    pub const fn valid() -> Self {
        Self {
            is_valid: true,
            message: None,
        }
    }

    /// Creates a failed validation result with a message.
    pub fn invalid(message: impl Into<String>) -> Self {
        Self {
            is_valid: false,
            message: Some(message.into()),
        }
    }
}

/// Middleware that validates actions before reduction/history processing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ValidationMiddleware;

impl ValidationMiddleware {
    /// Human-readable middleware name.
    pub const NAME: &'static str = "Validation";

    /// High priority so validation runs first.
    pub const PRIORITY: i32 = 1000;

    /// Creates a stateless validation middleware instance.
    pub const fn new() -> Self {
        Self
    }

    fn validate_action(
        &self,
        action: &dyn DrawAction,
        context: &DispatchContext,
    ) -> ValidationResult {
        if let Some(action) = action.as_any().downcast_ref::<CreateElement>() {
            return self.validate_create_element(action, context);
        }
        if let Some(action) = action.as_any().downcast_ref::<DeleteElements>() {
            return self.validate_element_ids(action.element_ids.as_slice(), "DeleteElements");
        }
        if let Some(action) = action.as_any().downcast_ref::<DuplicateElements>() {
            return self.validate_element_ids(action.element_ids.as_slice(), "DuplicateElements");
        }
        if let Some(action) = action.as_any().downcast_ref::<ChangeElementZIndex>() {
            return self.validate_element_id(action.element_id.as_str(), "ChangeElementZIndex");
        }
        if let Some(action) = action.as_any().downcast_ref::<ChangeElementsZIndex>() {
            return self
                .validate_element_ids(action.element_ids.as_slice(), "ChangeElementsZIndex");
        }
        if let Some(action) = action.as_any().downcast_ref::<UpdateElementsStyle>() {
            return self.validate_update_elements_style(action);
        }
        if let Some(action) = action.as_any().downcast_ref::<UpdateGlobalElements>() {
            return self.validate_update_global_elements(action);
        }
        if let Some(action) = action
            .as_any()
            .downcast_ref::<CreateSerialNumberTextElements>()
        {
            return self.validate_element_ids(
                action.element_ids.as_slice(),
                "CreateSerialNumberTextElements",
            );
        }
        if let Some(action) = action.as_any().downcast_ref::<SelectElement>() {
            return self.validate_element_id(action.element_id.as_str(), "SelectElement");
        }
        if let Some(action) = action.as_any().downcast_ref::<ZoomCamera>() {
            return self.validate_zoom_camera(action);
        }
        if action.as_any().is::<Undo>() {
            return self.validate_undo(context);
        }
        if action.as_any().is::<Redo>() {
            return self.validate_redo(context);
        }

        // Config and all other actions are currently valid by default.
        let _ = action.as_any().downcast_ref::<UpdateConfig>();
        let _ = action.as_any().downcast_ref::<UpdateSelectionConfig>();
        let _ = action.as_any().downcast_ref::<UpdateCanvasConfig>();
        ValidationResult::valid()
    }

    fn validate_create_element(
        &self,
        action: &CreateElement,
        context: &DispatchContext,
    ) -> ValidationResult {
        if !context
            .draw_context
            .element_registry
            .supports(&action.type_id)
        {
            return ValidationResult::invalid(format!(
                "Unknown element type \"{}\"",
                action.type_id.as_str()
            ));
        }

        if let Some(initial_data) = action.initial_data.as_ref() {
            if initial_data.type_id() != action.type_id {
                return ValidationResult::invalid(
                    "CreateElement initialData type does not match typeId",
                );
            }
        }

        ValidationResult::valid()
    }

    fn validate_update_elements_style(&self, action: &UpdateElementsStyle) -> ValidationResult {
        if action.element_ids.is_empty() {
            return ValidationResult::invalid("UpdateElementsStyle requires elementIds");
        }
        if !action.has_updates() {
            return ValidationResult::invalid("UpdateElementsStyle has no fields to update");
        }

        ValidationResult::valid()
    }

    fn validate_update_global_elements(&self, action: &UpdateGlobalElements) -> ValidationResult {
        if !action.has_updates() {
            return ValidationResult::invalid("UpdateGlobalElements has no fields to update");
        }

        ValidationResult::valid()
    }

    fn validate_zoom_camera(&self, action: &ZoomCamera) -> ValidationResult {
        if action.scale.is_nan() || action.scale.is_infinite() {
            return ValidationResult::invalid("ZoomCamera scale is invalid");
        }
        if action.scale <= 0.0 {
            return ValidationResult::invalid("ZoomCamera scale must be > 0");
        }

        ValidationResult::valid()
    }

    fn validate_undo(&self, context: &DispatchContext) -> ValidationResult {
        let can_undo = context
            .history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .can_undo();
        if !can_undo {
            return ValidationResult::invalid("Cannot undo: history is empty");
        }

        ValidationResult::valid()
    }

    fn validate_redo(&self, context: &DispatchContext) -> ValidationResult {
        let can_redo = context
            .history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .can_redo();
        if !can_redo {
            return ValidationResult::invalid("Cannot redo: no future history");
        }

        ValidationResult::valid()
    }

    fn validate_element_ids(&self, element_ids: &[String], action: &str) -> ValidationResult {
        if element_ids.is_empty() {
            return ValidationResult::invalid(format!("{action} requires elementIds"));
        }

        ValidationResult::valid()
    }

    fn validate_element_id(&self, element_id: &str, action: &str) -> ValidationResult {
        if element_id.trim().is_empty() {
            return ValidationResult::invalid(format!("{action} needs elementId"));
        }

        ValidationResult::valid()
    }

    fn report_validation_failure(&self, context: &DispatchContext, reason: &str) {
        let mut log_data = LogData::new();
        log_data.insert("action".to_owned(), context.action.action_name().to_owned());
        log_data.insert("reason".to_owned(), reason.to_owned());
        log_data.insert("traceId".to_owned(), context.trace_id.clone());
        context
            .draw_context
            .log
            .store()
            .warning("Validation blocked action", Some(&log_data));
    }
}

impl Middleware for ValidationMiddleware {
    fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        let result = self.validate_action(context.action.as_ref(), &context);
        if result.is_valid {
            return Box::pin(async move { next(context).await });
        }

        let message = result
            .message
            .unwrap_or_else(|| "Validation failed".to_owned());
        self.report_validation_failure(&context, &message);

        Box::pin(async move { Ok(context.with_stop(message)) })
    }

    fn priority(&self) -> i32 {
        Self::PRIORITY
    }

    fn name(&self) -> &str {
        Self::NAME
    }
}

/// Shared stateless middleware constant, mirroring Dart `const` behavior.
pub const VALIDATION_MIDDLEWARE: ValidationMiddleware = ValidationMiddleware;

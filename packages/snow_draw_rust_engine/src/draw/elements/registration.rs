use std::any::Any;
use std::sync::Arc;

use serde_json::{Map, Value};

use crate::draw::config::draw_config::ElementStyleConfig;
use crate::draw::elements::core::creation_strategy::{
    CreationStrategy, ElementData as StrategyElementData,
};
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;
use crate::draw::elements::types::arrow::arrow_creation_strategy::ArrowCreationStrategy;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_creation_strategy::FreeDrawCreationStrategy;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_creation_strategy::SerialNumberCreationStrategy;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::services::element_hit_test_service::hit_test_element;

use super::core::element_registry::{
    DefaultElementRegistry, ElementDefinition, ElementRegistryError,
};

/// Canonical built-in element type value for rectangles.
pub const RECTANGLE_TYPE_VALUE: &str = "rectangle";

/// Canonical built-in element type value for arrows.
pub const ARROW_TYPE_VALUE: &str = "arrow";

/// Canonical built-in element type value for lines.
pub const LINE_TYPE_VALUE: &str = "line";

/// Canonical built-in element type value for free-draw strokes.
pub const FREE_DRAW_TYPE_VALUE: &str = "free_draw";

/// Canonical built-in element type value for filters.
pub const FILTER_TYPE_VALUE: &str = "filter";

/// Canonical built-in element type value for highlights.
pub const HIGHLIGHT_TYPE_VALUE: &str = "highlight";

/// Canonical built-in element type value for text.
pub const TEXT_TYPE_VALUE: &str = "text";

/// Canonical built-in element type value for serial numbers.
pub const SERIAL_NUMBER_TYPE_VALUE: &str = "serial_number";

type CreateDefaultDataFn = fn(&ElementStyleConfig) -> Arc<dyn StrategyElementData>;
type CreateCreationStrategyFn = fn() -> Box<dyn CreationStrategy>;

/// Runtime built-in element definition used by registration and create reducer.
#[derive(Clone)]
pub struct BuiltInElementDefinition {
    type_value: &'static str,
    display_name: &'static str,
    create_default_data_fn: CreateDefaultDataFn,
    create_creation_strategy_fn: CreateCreationStrategyFn,
}

impl std::fmt::Debug for BuiltInElementDefinition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BuiltInElementDefinition")
            .field("type_value", &self.type_value)
            .field("display_name", &self.display_name)
            .finish()
    }
}

impl BuiltInElementDefinition {
    /// Creates a built-in runtime definition descriptor.
    pub const fn new(
        type_value: &'static str,
        display_name: &'static str,
        create_default_data_fn: CreateDefaultDataFn,
        create_creation_strategy_fn: CreateCreationStrategyFn,
    ) -> Self {
        Self {
            type_value,
            display_name,
            create_default_data_fn,
            create_creation_strategy_fn,
        }
    }

    /// Raw element type value used by the registry map key.
    pub const fn type_value(&self) -> &'static str {
        self.type_value
    }

    /// Human-readable element type name.
    pub const fn display_name(&self) -> &'static str {
        self.display_name
    }
}

impl ElementDefinition for BuiltInElementDefinition {
    fn type_id_value(&self) -> &str {
        self.type_value
    }

    fn create_default_data(
        &self,
        style_defaults: &ElementStyleConfig,
    ) -> Arc<dyn StrategyElementData> {
        (self.create_default_data_fn)(style_defaults)
    }

    fn creation_strategy(&self) -> Option<Box<dyn CreationStrategy>> {
        Some((self.create_creation_strategy_fn)())
    }

    fn hit_test(
        &self,
        element: &crate::draw::models::element_state::ElementState,
        position: crate::draw::types::draw_point::DrawPoint,
        tolerance: f64,
    ) -> Option<bool> {
        Some(hit_test_element(element, position, tolerance))
    }

    fn as_any(&self) -> &dyn Any {
        self
    }
}

fn built_in_definition(
    type_value: &'static str,
    display_name: &'static str,
    create_default_data_fn: CreateDefaultDataFn,
    create_creation_strategy_fn: CreateCreationStrategyFn,
) -> Arc<dyn ElementDefinition> {
    Arc::new(BuiltInElementDefinition::new(
        type_value,
        display_name,
        create_default_data_fn,
        create_creation_strategy_fn,
    ))
}

fn create_rect_strategy() -> Box<dyn CreationStrategy> {
    Box::new(RectCreationStrategy::new())
}

fn create_arrow_strategy() -> Box<dyn CreationStrategy> {
    Box::new(ArrowCreationStrategy::new())
}

fn create_free_draw_strategy() -> Box<dyn CreationStrategy> {
    Box::new(FreeDrawCreationStrategy::new())
}

fn create_serial_number_strategy() -> Box<dyn CreationStrategy> {
    Box::new(SerialNumberCreationStrategy::new())
}

fn styled_default<T, F>(
    style_defaults: &ElementStyleConfig,
    decode: F,
) -> Arc<dyn StrategyElementData>
where
    T: Default + ElementStyleConfigurableData + CoreElementData + StrategyElementData + 'static,
    F: FnOnce(&Map<String, Value>) -> T,
{
    let styled = T::default().with_element_style(style_defaults.clone());
    let typed = decode(&styled.to_json());
    Arc::new(typed)
}

fn create_rectangle_default_data(
    style_defaults: &ElementStyleConfig,
) -> Arc<dyn StrategyElementData> {
    styled_default::<RectangleData, _>(style_defaults, |json| {
        RectangleData::from_json(json).unwrap_or_default()
    })
}

fn create_arrow_default_data(style_defaults: &ElementStyleConfig) -> Arc<dyn StrategyElementData> {
    styled_default::<ArrowData, _>(style_defaults, |json| {
        ArrowData::from_json(json).unwrap_or_default()
    })
}

fn create_line_default_data(style_defaults: &ElementStyleConfig) -> Arc<dyn StrategyElementData> {
    styled_default::<LineData, _>(style_defaults, |json| {
        LineData::from_json(json).unwrap_or_default()
    })
}

fn create_free_draw_default_data(
    style_defaults: &ElementStyleConfig,
) -> Arc<dyn StrategyElementData> {
    styled_default::<FreeDrawData, _>(style_defaults, |json| {
        FreeDrawData::from_json(json).unwrap_or_default()
    })
}

fn create_filter_default_data(style_defaults: &ElementStyleConfig) -> Arc<dyn StrategyElementData> {
    styled_default::<FilterData, _>(style_defaults, |json| {
        FilterData::from_json(json).unwrap_or_default()
    })
}

fn create_highlight_default_data(
    style_defaults: &ElementStyleConfig,
) -> Arc<dyn StrategyElementData> {
    styled_default::<HighlightData, _>(style_defaults, |json| {
        HighlightData::from_json(json).unwrap_or_default()
    })
}

fn create_text_default_data(style_defaults: &ElementStyleConfig) -> Arc<dyn StrategyElementData> {
    styled_default::<TextData, _>(style_defaults, |json| {
        TextData::from_json(json).unwrap_or_default()
    })
}

fn create_serial_number_default_data(
    style_defaults: &ElementStyleConfig,
) -> Arc<dyn StrategyElementData> {
    styled_default::<SerialNumberData, _>(style_defaults, |json| {
        SerialNumberData::from_json(json).unwrap_or_default()
    })
}

/// Built-in rectangle element definition.
pub fn rectangle_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        RECTANGLE_TYPE_VALUE,
        "Rectangle",
        create_rectangle_default_data,
        create_rect_strategy,
    )
}

/// Built-in arrow element definition.
pub fn arrow_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        ARROW_TYPE_VALUE,
        "Arrow",
        create_arrow_default_data,
        create_arrow_strategy,
    )
}

/// Built-in line element definition.
pub fn line_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        LINE_TYPE_VALUE,
        "Line",
        create_line_default_data,
        create_arrow_strategy,
    )
}

/// Built-in free-draw element definition.
pub fn free_draw_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        FREE_DRAW_TYPE_VALUE,
        "Free Draw",
        create_free_draw_default_data,
        create_free_draw_strategy,
    )
}

/// Built-in filter element definition.
pub fn filter_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        FILTER_TYPE_VALUE,
        "Filter",
        create_filter_default_data,
        create_rect_strategy,
    )
}

/// Built-in highlight element definition.
pub fn highlight_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        HIGHLIGHT_TYPE_VALUE,
        "Highlight",
        create_highlight_default_data,
        create_rect_strategy,
    )
}

/// Built-in text element definition.
pub fn text_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        TEXT_TYPE_VALUE,
        "Text",
        create_text_default_data,
        create_rect_strategy,
    )
}

/// Built-in serial-number element definition.
pub fn serial_number_definition() -> Arc<dyn ElementDefinition> {
    built_in_definition(
        SERIAL_NUMBER_TYPE_VALUE,
        "Serial Number",
        create_serial_number_default_data,
        create_serial_number_strategy,
    )
}

/// Returns the built-in element definition list in registration order.
///
/// Mirrors the Dart `_builtInDefinitions` list.
pub fn built_in_definitions() -> Vec<Arc<dyn ElementDefinition>> {
    vec![
        rectangle_definition(),
        arrow_definition(),
        line_definition(),
        free_draw_definition(),
        filter_definition(),
        highlight_definition(),
        text_definition(),
        serial_number_definition(),
    ]
}

/// Registers all built-in element types in the provided registry.
pub fn register_built_in_elements(
    registry: &mut DefaultElementRegistry,
) -> Result<(), ElementRegistryError> {
    registry.register_all(built_in_definitions())
}

/// Resolves `element_registry` and registers all built-in definitions.
///
/// If no registry is provided, a new `DefaultElementRegistry` is created.
pub fn resolve_element_registry(
    element_registry: Option<DefaultElementRegistry>,
) -> Result<DefaultElementRegistry, ElementRegistryError> {
    let mut resolved = element_registry.unwrap_or_default();
    register_built_in_elements(&mut resolved)?;
    Ok(resolved)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_default_data(_style_defaults: &ElementStyleConfig) -> Arc<dyn StrategyElementData> {
        Arc::new(())
    }

    fn test_creation_strategy() -> Box<dyn CreationStrategy> {
        Box::new(RectCreationStrategy::new())
    }

    #[test]
    fn built_in_definitions_include_all_expected_type_values() {
        let definitions = built_in_definitions();
        let type_values: Vec<&str> = definitions
            .iter()
            .map(|definition| definition.type_id_value())
            .collect();

        assert_eq!(
            type_values,
            vec![
                RECTANGLE_TYPE_VALUE,
                ARROW_TYPE_VALUE,
                LINE_TYPE_VALUE,
                FREE_DRAW_TYPE_VALUE,
                FILTER_TYPE_VALUE,
                HIGHLIGHT_TYPE_VALUE,
                TEXT_TYPE_VALUE,
                SERIAL_NUMBER_TYPE_VALUE,
            ]
        );
    }

    #[test]
    fn register_built_ins_populates_registry() {
        let mut registry = DefaultElementRegistry::new();

        register_built_in_elements(&mut registry)
            .expect("built-in definitions should register successfully");

        assert!(registry.supports_type_value(RECTANGLE_TYPE_VALUE));
        assert!(registry.supports_type_value(ARROW_TYPE_VALUE));
        assert!(registry.supports_type_value(LINE_TYPE_VALUE));
        assert!(registry.supports_type_value(FREE_DRAW_TYPE_VALUE));
        assert!(registry.supports_type_value(FILTER_TYPE_VALUE));
        assert!(registry.supports_type_value(HIGHLIGHT_TYPE_VALUE));
        assert!(registry.supports_type_value(TEXT_TYPE_VALUE));
        assert!(registry.supports_type_value(SERIAL_NUMBER_TYPE_VALUE));
    }

    #[test]
    fn resolve_element_registry_uses_provided_registry() {
        let mut registry = DefaultElementRegistry::new();
        registry
            .register(BuiltInElementDefinition::new(
                "custom",
                "Custom",
                test_default_data,
                test_creation_strategy,
            ))
            .expect("custom definition should register");

        let resolved = resolve_element_registry(Some(registry))
            .expect("resolve should register built-ins on provided registry");

        assert!(resolved.supports_type_value("custom"));
        assert!(resolved.supports_type_value(TEXT_TYPE_VALUE));
    }
}

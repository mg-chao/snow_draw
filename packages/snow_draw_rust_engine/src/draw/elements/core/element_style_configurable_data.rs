use crate::draw::config::draw_config::ElementStyleConfig;

use super::element_data::DynElementData;

/// Capability for element data payloads that can apply a default
/// [`ElementStyleConfig`].
///
/// Implementors should treat data as immutable and return a new payload with
/// the given style applied.
pub trait ElementStyleConfigurableData {
    /// Returns a new element payload with `style` applied.
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData>;
}

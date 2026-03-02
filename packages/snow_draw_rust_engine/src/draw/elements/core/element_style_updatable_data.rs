use crate::draw::types::element_style::ElementStyleUpdate;

use super::element_data::DynElementData;

/// Optional capability for element data payloads that can update style fields.
///
/// Implementors should treat element data as immutable and return a new payload
/// with changes from `update` applied.
pub trait ElementStyleUpdatableData {
    /// Returns a new element payload with style updates applied.
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData>;
}

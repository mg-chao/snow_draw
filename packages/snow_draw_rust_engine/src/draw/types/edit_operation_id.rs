#![allow(dead_code)]

/// Stable identifier for an edit-domain operation.
pub type EditOperationId = &'static str;

/// Built-in edit operation identifiers.
pub struct EditOperationIds;

impl EditOperationIds {
    pub const MOVE: EditOperationId = "move";
    pub const RESIZE: EditOperationId = "resize";
    pub const ROTATE: EditOperationId = "rotate";
    pub const ARROW_POINT: EditOperationId = "arrow_point";
}

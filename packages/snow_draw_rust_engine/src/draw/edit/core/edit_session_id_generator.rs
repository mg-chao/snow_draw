use std::sync::Arc;

use crate::draw::models::edit_session_id::EditSessionId;

/// Function signature used to generate new edit session identifiers.
///
/// Mirrors Dart's `typedef EditSessionIdGenerator = EditSessionId Function();`.
pub type EditSessionIdGenerator = Arc<dyn Fn() -> EditSessionId + Send + Sync + 'static>;

/// Edit-time keyboard modifiers coming from the UI/input layer.
///
/// These flags represent transient modifier keys at the time an edit update is
/// processed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct EditModifiers {
    /// Keeps the edited bounds constrained to an aspect ratio when supported.
    pub maintain_aspect_ratio: bool,

    /// Resizes or transforms relative to the center when supported.
    pub from_center: bool,

    /// Applies discrete rotation snapping when supported.
    pub discrete_angle: bool,

    /// Overrides default snapping behavior when supported.
    pub snap_override: bool,
}

impl EditModifiers {
    /// Creates a new set of edit modifiers.
    pub const fn new(
        maintain_aspect_ratio: bool,
        from_center: bool,
        discrete_angle: bool,
        snap_override: bool,
    ) -> Self {
        Self {
            maintain_aspect_ratio,
            from_center,
            discrete_angle,
            snap_override,
        }
    }
}

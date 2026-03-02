#![allow(dead_code)]

use crate::draw::input::input_event::KeyModifiers;
use crate::draw::types::draw_point::DrawPoint;

/// Tracks the latest pointer update payload and deduplicates no-op updates.
///
/// This guard treats updates as unchanged when `x/y` and modifiers are the
/// same. Pressure-only changes are intentionally ignored for edit/create update
/// dispatch; pressure-sensitive tools should rely on sampled batches instead.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PointerUpdateGuard {
    last_position: Option<DrawPoint>,
    last_modifiers: Option<KeyModifiers>,
}

impl PointerUpdateGuard {
    /// Returns `true` when the update should be dispatched.
    ///
    /// Set `force` to `true` to bypass de-duplication and only refresh the
    /// guard snapshot.
    pub fn should_dispatch(
        &mut self,
        position: DrawPoint,
        modifiers: KeyModifiers,
        force: bool,
    ) -> bool {
        if !force {
            if let Some(last_position) = self.last_position {
                if last_position.x == position.x
                    && last_position.y == position.y
                    && self.last_modifiers == Some(modifiers)
                {
                    return false;
                }
            }
        }

        self.last_position = Some(position);
        self.last_modifiers = Some(modifiers);
        true
    }

    /// Clears the tracked update signature.
    pub fn reset(&mut self) {
        self.last_position = None;
        self.last_modifiers = None;
    }
}

#[cfg(test)]
mod tests {
    use super::PointerUpdateGuard;
    use crate::draw::input::input_event::KeyModifiers;
    use crate::draw::types::draw_point::DrawPoint;

    #[test]
    fn dispatches_first_update() {
        let mut guard = PointerUpdateGuard::default();

        assert!(guard.should_dispatch(DrawPoint::new(10.0, 20.0), KeyModifiers::NONE, false));
    }

    #[test]
    fn deduplicates_same_position_and_modifiers() {
        let mut guard = PointerUpdateGuard::default();
        let position = DrawPoint::new(10.0, 20.0);

        assert!(guard.should_dispatch(position, KeyModifiers::NONE, false));
        assert!(!guard.should_dispatch(position, KeyModifiers::NONE, false));
    }

    #[test]
    fn ignores_pressure_only_changes() {
        let mut guard = PointerUpdateGuard::default();
        let base = DrawPoint::new(10.0, 20.0);
        let pressure_change = DrawPoint::with_pressure_and_timestamp(10.0, 20.0, 0.9, 123);

        assert!(guard.should_dispatch(base, KeyModifiers::NONE, false));
        assert!(!guard.should_dispatch(pressure_change, KeyModifiers::NONE, false));
    }

    #[test]
    fn force_bypasses_deduplication() {
        let mut guard = PointerUpdateGuard::default();
        let position = DrawPoint::new(10.0, 20.0);

        assert!(guard.should_dispatch(position, KeyModifiers::NONE, false));
        assert!(guard.should_dispatch(position, KeyModifiers::NONE, true));
    }

    #[test]
    fn reset_clears_signature() {
        let mut guard = PointerUpdateGuard::default();
        let position = DrawPoint::new(10.0, 20.0);

        assert!(guard.should_dispatch(position, KeyModifiers::NONE, false));
        guard.reset();
        assert!(guard.should_dispatch(position, KeyModifiers::NONE, false));
    }

    #[test]
    fn modifier_changes_dispatch_even_with_same_position() {
        let mut guard = PointerUpdateGuard::default();
        let position = DrawPoint::new(10.0, 20.0);

        assert!(guard.should_dispatch(position, KeyModifiers::NONE, false));
        assert!(guard.should_dispatch(position, KeyModifiers::new(true, false, false), false));
    }
}

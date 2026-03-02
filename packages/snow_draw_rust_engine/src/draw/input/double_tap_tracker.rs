#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use std::time::{Duration, Instant};

/// Tracks tap history and detects double-tap gestures.
#[derive(Debug, Clone)]
pub struct DoubleTapTracker<T> {
    /// Maximum time allowed between taps for a double tap.
    pub threshold: Duration,

    /// Multiplier applied to the base tap-position tolerance.
    pub tolerance_multiplier: f64,

    last_tap_time: Option<Instant>,
    last_tap_position: Option<DrawPoint>,
    last_tap_target: Option<T>,
}

impl<T> Default for DoubleTapTracker<T> {
    fn default() -> Self {
        Self::with_config(Duration::from_millis(500), 2.0)
    }
}

impl<T> DoubleTapTracker<T> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_config(threshold: Duration, tolerance_multiplier: f64) -> Self {
        assert!(
            tolerance_multiplier >= 0.0,
            "tolerance_multiplier must be >= 0"
        );

        Self {
            threshold,
            tolerance_multiplier,
            last_tap_time: None,
            last_tap_position: None,
            last_tap_target: None,
        }
    }

    pub fn record_tap(&mut self, target: T, position: DrawPoint, now: Instant) {
        self.last_tap_target = Some(target);
        self.last_tap_position = Some(position);
        self.last_tap_time = Some(now);
    }

    pub fn clear(&mut self) {
        self.last_tap_target = None;
        self.last_tap_position = None;
        self.last_tap_time = None;
    }
}

impl<T: PartialEq> DoubleTapTracker<T> {
    pub fn is_double_tap(
        &self,
        target: &T,
        position: DrawPoint,
        now: Instant,
        base_tolerance: f64,
    ) -> bool {
        let Some(last_tap_time) = self.last_tap_time else {
            return false;
        };
        let Some(last_tap_position) = self.last_tap_position else {
            return false;
        };
        let Some(last_tap_target) = self.last_tap_target.as_ref() else {
            return false;
        };

        if last_tap_target != target {
            return false;
        }
        if now.saturating_duration_since(last_tap_time) > self.threshold {
            return false;
        }

        let tolerance = base_tolerance * self.tolerance_multiplier;
        last_tap_position.distance_squared(position) <= tolerance * tolerance
    }
}

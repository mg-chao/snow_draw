use std::fmt;
use std::sync::Mutex;

use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::types::draw_point::DrawPoint;

/// Keyboard modifier state carried with input events.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct KeyModifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
}

impl KeyModifiers {
    pub const NONE: Self = Self::new(false, false, false);

    pub const fn new(shift: bool, control: bool, alt: bool) -> Self {
        Self {
            shift,
            control,
            alt,
        }
    }

    /// Converts keyboard modifiers to edit-domain modifiers.
    ///
    /// This centralizes mapping so every input plugin can share the same
    /// interpretation.
    pub fn to_edit_modifiers(self) -> EditModifiers {
        EditModifiers {
            maintain_aspect_ratio: self.shift,
            discrete_angle: self.shift,
            from_center: self.alt,
            snap_override: self.control,
        }
    }
}

impl fmt::Display for KeyModifiers {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "KeyModifiers(shift: {}, ctrl: {}, alt: {})",
            self.shift, self.control, self.alt
        )
    }
}

/// Base input event payload passed from UI to business logic.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct InputEvent {
    /// World coordinate pointer position.
    pub position: DrawPoint,

    /// Snapshot of keyboard modifier state.
    pub modifiers: KeyModifiers,

    /// Pointer pressure in range `0..=1` (`0` means unknown).
    pub pressure: f64,
}

impl InputEvent {
    pub const fn new(position: DrawPoint, modifiers: KeyModifiers, pressure: f64) -> Self {
        Self {
            position,
            modifiers,
            pressure,
        }
    }

    pub const fn with_default_pressure(position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self::new(position, modifiers, 0.0)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PointerDownInputEvent {
    pub input: InputEvent,
}

impl PointerDownInputEvent {
    pub const fn new(position: DrawPoint, modifiers: KeyModifiers, pressure: f64) -> Self {
        Self {
            input: InputEvent::new(position, modifiers, pressure),
        }
    }

    pub const fn with_default_pressure(position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self::new(position, modifiers, 0.0)
    }
}

impl fmt::Display for PointerDownInputEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PointerDownInputEvent({}, {})",
            self.input.position, self.input.modifiers
        )
    }
}

#[derive(Debug)]
pub struct PointerMoveInputEvent {
    pub input: InputEvent,
    sample_node: PointerSampleNode,
    sampled_points_cache: Mutex<Option<Vec<DrawPoint>>>,
}

impl PointerMoveInputEvent {
    pub fn new(
        position: DrawPoint,
        modifiers: KeyModifiers,
        pressure: f64,
        sampled_points: &[DrawPoint],
    ) -> Self {
        let normalized_samples = normalize_pointer_move_samples(sampled_points, position);
        if normalized_samples.len() == 1 {
            return Self {
                input: InputEvent::new(position, modifiers, pressure),
                sample_node: PointerSampleNode::single(normalized_samples[0]),
                sampled_points_cache: Mutex::new(Some(Vec::new())),
            };
        }

        let frozen_samples = normalized_samples;

        Self {
            input: InputEvent::new(position, modifiers, pressure),
            sample_node: PointerSampleNode::leaf(frozen_samples.clone()),
            sampled_points_cache: Mutex::new(Some(frozen_samples)),
        }
    }

    pub fn with_default_pressure(
        position: DrawPoint,
        modifiers: KeyModifiers,
        sampled_points: &[DrawPoint],
    ) -> Self {
        Self::new(position, modifiers, 0.0, sampled_points)
    }

    /// Coalesced pointer samples represented by this event.
    ///
    /// When this returns an empty vector, `input.position` is the sole sample.
    pub fn sampled_points(&self) -> Vec<DrawPoint> {
        if let Some(cached) = self
            .sampled_points_cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
        {
            return cached.clone();
        }

        let resolved: Vec<DrawPoint> = self.samples().collect();
        let cached = if resolved.len() <= 1 {
            Vec::new()
        } else {
            resolved
        };
        *self
            .sampled_points_cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(cached.clone());
        cached
    }

    /// Total number of pointer samples represented by this event.
    pub fn sample_count(&self) -> usize {
        self.sample_node.sample_count()
    }

    /// Returns all pointer samples in draw order.
    pub fn samples(&self) -> impl Iterator<Item = DrawPoint> {
        let mut stack = vec![&self.sample_node];
        let mut previous: Option<DrawPoint> = None;
        let mut output = Vec::with_capacity(self.sample_count());

        while let Some(node) = stack.pop() {
            match node {
                PointerSampleNode::Merged { left, right, .. } => {
                    stack.push(right.as_ref());
                    stack.push(left.as_ref());
                }
                PointerSampleNode::Single { point, .. } => {
                    if previous == Some(*point) {
                        continue;
                    }
                    previous = Some(*point);
                    output.push(*point);
                }
                PointerSampleNode::Leaf { points, .. } => {
                    for point in points {
                        if previous == Some(*point) {
                            continue;
                        }
                        previous = Some(*point);
                        output.push(*point);
                    }
                }
            }
        }

        output.into_iter()
    }

    /// Merges this event with `next`, preserving sample order.
    ///
    /// The merged event uses `next` event payload and keeps all intermediate
    /// samples from both events.
    pub fn merge_with(&self, next: &PointerMoveInputEvent) -> PointerMoveInputEvent {
        PointerMoveInputEvent {
            input: next.input,
            sample_node: PointerSampleNode::merged(
                self.sample_node.clone(),
                next.sample_node.clone(),
            ),
            sampled_points_cache: Mutex::new(None),
        }
    }
}

impl Clone for PointerMoveInputEvent {
    fn clone(&self) -> Self {
        let cached = self
            .sampled_points_cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone();
        Self {
            input: self.input,
            sample_node: self.sample_node.clone(),
            sampled_points_cache: Mutex::new(cached),
        }
    }
}

impl PartialEq for PointerMoveInputEvent {
    fn eq(&self, other: &Self) -> bool {
        self.input == other.input && self.sample_node == other.sample_node
    }
}

impl fmt::Display for PointerMoveInputEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PointerMoveInputEvent({}, {}, samples: {})",
            self.input.position,
            self.input.modifiers,
            self.sample_count()
        )
    }
}

fn normalize_pointer_move_samples(
    sampled_points: &[DrawPoint],
    position: DrawPoint,
) -> Vec<DrawPoint> {
    let mut normalized = Vec::with_capacity(sampled_points.len() + 1);

    for point in sampled_points {
        if normalized.last().copied() != Some(*point) {
            normalized.push(*point);
        }
    }

    if normalized.last().copied() != Some(position) {
        normalized.push(position);
    }

    normalized
}

#[derive(Clone, Debug, PartialEq)]
enum PointerSampleNode {
    Single {
        sample_count: usize,
        first_point: DrawPoint,
        last_point: DrawPoint,
        point: DrawPoint,
    },
    Leaf {
        sample_count: usize,
        first_point: DrawPoint,
        last_point: DrawPoint,
        points: Vec<DrawPoint>,
    },
    Merged {
        sample_count: usize,
        first_point: DrawPoint,
        last_point: DrawPoint,
        left: Box<PointerSampleNode>,
        right: Box<PointerSampleNode>,
    },
}

impl PointerSampleNode {
    fn single(point: DrawPoint) -> Self {
        Self::Single {
            sample_count: 1,
            first_point: point,
            last_point: point,
            point,
        }
    }

    fn leaf(points: Vec<DrawPoint>) -> Self {
        assert!(!points.is_empty(), "Pointer sample leaf cannot be empty");
        Self::Leaf {
            sample_count: points.len(),
            first_point: points[0],
            last_point: points[points.len() - 1],
            points,
        }
    }

    fn merged(left: PointerSampleNode, right: PointerSampleNode) -> Self {
        let duplicate_boundary = usize::from(left.last_point() == right.first_point());
        Self::Merged {
            sample_count: left.sample_count() + right.sample_count() - duplicate_boundary,
            first_point: left.first_point(),
            last_point: right.last_point(),
            left: Box::new(left),
            right: Box::new(right),
        }
    }

    fn sample_count(&self) -> usize {
        match self {
            Self::Single { sample_count, .. }
            | Self::Leaf { sample_count, .. }
            | Self::Merged { sample_count, .. } => *sample_count,
        }
    }

    fn first_point(&self) -> DrawPoint {
        match self {
            Self::Single { first_point, .. }
            | Self::Leaf { first_point, .. }
            | Self::Merged { first_point, .. } => *first_point,
        }
    }

    fn last_point(&self) -> DrawPoint {
        match self {
            Self::Single { last_point, .. }
            | Self::Leaf { last_point, .. }
            | Self::Merged { last_point, .. } => *last_point,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PointerHoverInputEvent {
    pub input: InputEvent,
}

impl PointerHoverInputEvent {
    pub const fn new(position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self {
            input: InputEvent::with_default_pressure(position, modifiers),
        }
    }
}

impl fmt::Display for PointerHoverInputEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PointerHoverInputEvent({}, {})",
            self.input.position, self.input.modifiers
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PointerUpInputEvent {
    pub input: InputEvent,
}

impl PointerUpInputEvent {
    pub const fn new(position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self {
            input: InputEvent::with_default_pressure(position, modifiers),
        }
    }
}

impl fmt::Display for PointerUpInputEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PointerUpInputEvent({}, {})",
            self.input.position, self.input.modifiers
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PointerCancelInputEvent {
    pub input: InputEvent,
}

impl PointerCancelInputEvent {
    pub const fn new(position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self {
            input: InputEvent::with_default_pressure(position, modifiers),
        }
    }
}

impl fmt::Display for PointerCancelInputEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PointerCancelInputEvent({}, {})",
            self.input.position, self.input.modifiers
        )
    }
}

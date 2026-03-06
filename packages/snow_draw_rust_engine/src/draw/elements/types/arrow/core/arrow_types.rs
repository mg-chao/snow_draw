#![allow(dead_code)]

use std::collections::HashMap;

use serde_json::Value;

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

pub type Point = DrawPoint;
pub type Bounds = DrawRect;
pub type BindMode = &'static str;
pub type Arrowhead = &'static str;
pub type ArrowStrokeStyle = &'static str;
pub type ArrowheadDashMode = &'static str;
pub type ArrowheadFillMode = &'static str;
pub type CanonicalBindableShape = &'static str;
pub type BindableShape = String;
pub type ArrowPatch = serde_json::Map<String, Value>;
pub type ArrowBindingStatePatch = serde_json::Map<String, Value>;
pub type IdMapRecord = HashMap<String, String>;
pub type AnchorElementIdsLookupRecord = HashMap<String, Vec<String>>;

pub const BIND_MODE_INSIDE: BindMode = "inside";
pub const BIND_MODE_ORBIT: BindMode = "orbit";
pub const BIND_MODE_SKIP: BindMode = "skip";

pub const ARROW_ENDPOINT_START: &str = "start";
pub const ARROW_ENDPOINT_END: &str = "end";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowEndpointEdge {
    Start,
    End,
}

impl ArrowEndpointEdge {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Start => ARROW_ENDPOINT_START,
            Self::End => ARROW_ENDPOINT_END,
        }
    }
}

pub fn normalize_arrow_endpoint_edge(edge: &str) -> ArrowEndpointEdge {
    match edge {
        "start" | "startBinding" => ArrowEndpointEdge::Start,
        _ => ArrowEndpointEdge::End,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BindableRoundnessType {
    Legacy,
    Proportional,
    Adaptive,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindableRoundness {
    pub kind: BindableRoundnessType,
    pub value: Option<f64>,
}

impl BindableRoundness {
    pub const fn new(kind: BindableRoundnessType, value: Option<f64>) -> Self {
        Self { kind, value }
    }
}

pub fn canonicalize_bindable_shape(shape: &str) -> String {
    match shape {
        "rect" => "rectangle".to_string(),
        "circle" => "ellipse".to_string(),
        "rhombus" => "diamond".to_string(),
        _ => shape.to_string(),
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CurvePathOp {
    pub op: String,
    pub data: Vec<f64>,
}

impl CurvePathOp {
    pub fn new(op: impl Into<String>, data: Vec<f64>) -> Self {
        Self {
            op: op.into(),
            data,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct FixedPointBinding {
    pub element_id: String,
    pub fixed_point: Point,
    pub mode: String,
}

impl FixedPointBinding {
    pub fn new(element_id: impl Into<String>, fixed_point: Point, mode: impl Into<String>) -> Self {
        Self {
            element_id: element_id.into(),
            fixed_point,
            mode: mode.into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct FixedSegment {
    pub start: Point,
    pub end: Point,
    pub index: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindableState {
    pub id: String,
    pub shape: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub angle: f64,
    pub stroke_width: f64,
    pub roundness: Option<BindableRoundness>,
    pub z_index: Option<f64>,
    pub background_opaque: Option<bool>,
    pub binding_enabled: Option<bool>,
    pub interior_hit_enabled: Option<bool>,
    pub visibility_bounds: Option<Bounds>,
}

impl BindableState {
    pub fn rect(&self) -> DrawRect {
        DrawRect::new(self.x, self.y, self.x + self.width, self.y + self.height)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowState {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub points: Vec<Point>,
    pub start_binding: Option<FixedPointBinding>,
    pub end_binding: Option<FixedPointBinding>,
    pub start_arrowhead: Option<String>,
    pub end_arrowhead: Option<String>,
    pub elbowed: bool,
    pub fixed_segments: Option<Vec<FixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

impl ArrowState {
    pub fn rect(&self) -> DrawRect {
        DrawRect::new(self.x, self.y, self.x + self.width, self.y + self.height)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EngineContext {
    pub zoom: f64,
    pub is_binding_enabled: bool,
    pub bind_mode: &'static str,
    pub max_coordinate: f64,
}

impl Default for EngineContext {
    fn default() -> Self {
        Self {
            zoom: 1.0,
            is_binding_enabled: true,
            bind_mode: BIND_MODE_ORBIT,
            max_coordinate: 1e6,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindablePatch {
    pub id: String,
    pub add_bound_arrow_id: Option<String>,
    pub remove_bound_arrow_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowBindingState {
    pub id: String,
    pub start_binding: Option<FixedPointBinding>,
    pub end_binding: Option<FixedPointBinding>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindableRelationState {
    pub id: String,
    pub bound_arrow_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindableRelationPatch {
    pub id: String,
    pub bound_arrow_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowStatePatchWithId {
    pub id: String,
    pub patch: ArrowPatch,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LifecycleSyncResult {
    pub arrows: Vec<ArrowState>,
    pub bindables: Vec<BindableRelationState>,
    pub arrow_patches: Vec<ArrowStatePatchWithId>,
    pub relation_patches: Vec<BindableRelationPatch>,
    pub events: Vec<ArrowEngineEvent>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SuggestedBinding {
    pub bindable_id: Option<String>,
    pub element: BindableState,
    pub mid_point: Option<Point>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ArrowEngineEvent {
    ReorderArrow(ReorderArrowEvent),
    BindingBroken(BindingBrokenEvent),
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReorderArrowEvent {
    pub arrow_id: String,
    pub bindable_id: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BindingBrokenEvent {
    pub arrow_id: String,
    pub edge: ArrowEndpointEdge,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EngineResult {
    pub arrow_patch: ArrowPatch,
    pub bindable_patches: Vec<BindablePatch>,
    pub suggested_binding: Option<SuggestedBinding>,
    pub events: Vec<ArrowEngineEvent>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReduceArrowEngineEventsToOrderInput {
    pub ordered_element_ids: Vec<String>,
    pub events: Vec<ArrowEngineEvent>,
    pub anchor_element_ids_by_bindable_id: Option<AnchorElementIdsLookupRecord>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReduceArrowEngineEventsToOrderResult {
    pub ordered_element_ids: Vec<String>,
    pub moved: bool,
    pub reorder_operations: Vec<ReorderArrowAboveElementsResult>,
    pub binding_broken_events: Vec<BindingBrokenEvent>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ApplyEngineResultInput {
    pub arrow: ArrowState,
    pub bindables: Vec<BindableRelationState>,
    pub result: EngineResult,
    pub ordered_element_ids: Option<Vec<String>>,
    pub anchor_element_ids_by_bindable_id: Option<AnchorElementIdsLookupRecord>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ApplyEngineResultValue {
    pub arrow: ArrowState,
    pub bindables: Vec<BindableRelationState>,
    pub relation_patches: Vec<BindableRelationPatch>,
    pub ordered_element_ids: Option<Vec<String>>,
    pub order_changed: Option<bool>,
    pub reorder_operations: Option<Vec<ReorderArrowAboveElementsResult>>,
    pub binding_broken_events: Option<Vec<BindingBrokenEvent>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ValidationReport {
    pub valid: bool,
    pub violations: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FocusPointDescriptor {
    pub edge: ArrowEndpointEdge,
    pub point: Point,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FocusPointHit {
    pub edge: Option<ArrowEndpointEdge>,
    pub pointer_offset: Point,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReorderArrowAboveElementsInput {
    pub ordered_element_ids: Vec<String>,
    pub arrow_id: String,
    pub anchor_element_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReorderArrowAboveElementsResult {
    pub ordered_element_ids: Vec<String>,
    pub moved: bool,
    pub from_index: isize,
    pub to_index: isize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReorderArrowAboveHoveredBindableInput {
    pub ordered_element_ids: Vec<String>,
    pub arrow_id: String,
    pub hovered_bindable_id: Option<String>,
    pub point: Option<Point>,
    pub bindables: Option<Vec<BindableState>>,
    pub tolerance: Option<f64>,
    pub anchor_element_ids_by_bindable_id: Option<AnchorElementIdsLookupRecord>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReorderArrowAboveHoveredBindableResult {
    pub ordered_element_ids: Vec<String>,
    pub moved: bool,
    pub from_index: isize,
    pub to_index: isize,
    pub hovered_bindable_id: Option<String>,
    pub anchor_element_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NormalizedArrowFromGlobalPoints {
    pub x: f64,
    pub y: f64,
    pub points: Vec<Point>,
    pub width: f64,
    pub height: f64,
}

pub fn is_finite_num(value: f64) -> bool {
    value.is_finite()
}

pub fn clamp_num(value: f64, min: f64, max: f64) -> f64 {
    value.clamp(min, max)
}

pub fn normalize_bindable_state(bindable: &BindableState) -> BindableState {
    let visibility_bounds = bindable.visibility_bounds.and_then(|bounds| {
        let values = [bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y];
        if values.iter().all(|value| value.is_finite()) {
            Some(bounds)
        } else {
            None
        }
    });

    BindableState {
        id: bindable.id.clone(),
        shape: canonicalize_bindable_shape(&bindable.shape),
        x: bindable.x,
        y: bindable.y,
        width: bindable.width,
        height: bindable.height,
        angle: bindable.angle,
        stroke_width: bindable.stroke_width,
        roundness: bindable.roundness.clone(),
        z_index: bindable.z_index,
        background_opaque: Some(bindable.background_opaque.unwrap_or(true)),
        binding_enabled: Some(bindable.binding_enabled.unwrap_or(true)),
        interior_hit_enabled: Some(bindable.interior_hit_enabled.unwrap_or(true)),
        visibility_bounds,
    }
}

pub fn normalize_bindable_states(bindables: &[BindableState]) -> Vec<BindableState> {
    bindables.iter().map(normalize_bindable_state).collect()
}

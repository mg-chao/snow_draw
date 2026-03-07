#![allow(dead_code)]

use std::borrow::Cow;
use std::collections::HashSet;
use std::fmt;
use std::hash::{Hash, Hasher};

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::typed_element_render_task_encoder::ElementState as TypedElementState;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

use super::arrow_data::{ArrowData, ElbowFixedSegment};
use super::arrow_geometry::ArrowGeometry;

/// Kind of interactive arrow control point.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowPointKind {
    Turning,
    Addable,
    LoopStart,
    LoopEnd,
    FocusStart,
    FocusEnd,
}

/// Interactive control point metadata for an arrow element.
///
/// Equality intentionally ignores `position`, matching Dart behavior where a
/// handle is identified by `(element_id, kind, index, is_fixed)`.
#[derive(Clone, Debug)]
pub struct ArrowPointHandle {
    /// Element id that owns this control point.
    pub element_id: String,
    /// Control point kind.
    pub kind: ArrowPointKind,
    /// Turning-point index (or segment start index for addable points).
    pub index: usize,
    /// Position in the element's un-rotated world coordinate space.
    pub position: DrawPoint,
    /// Whether the handle represents a fixed elbow segment.
    pub is_fixed: bool,
}

impl ArrowPointHandle {
    pub fn new(
        element_id: impl Into<String>,
        kind: ArrowPointKind,
        index: usize,
        position: DrawPoint,
    ) -> Self {
        Self {
            element_id: element_id.into(),
            kind,
            index,
            position,
            is_fixed: false,
        }
    }

    pub fn with_fixed(
        element_id: impl Into<String>,
        kind: ArrowPointKind,
        index: usize,
        position: DrawPoint,
        is_fixed: bool,
    ) -> Self {
        Self {
            element_id: element_id.into(),
            kind,
            index,
            position,
            is_fixed,
        }
    }
}

impl PartialEq for ArrowPointHandle {
    fn eq(&self, other: &Self) -> bool {
        self.element_id == other.element_id
            && self.kind == other.kind
            && self.index == other.index
            && self.is_fixed == other.is_fixed
    }
}

impl Eq for ArrowPointHandle {}

impl Hash for ArrowPointHandle {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.element_id.hash(state);
        self.kind.hash(state);
        self.index.hash(state);
        self.is_fixed.hash(state);
    }
}

impl fmt::Display for ArrowPointHandle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ArrowPointHandle(id: {}, kind: {:?}, index: {}, is_fixed: {})",
            self.element_id, self.kind, self.index, self.is_fixed
        )
    }
}

/// Grouped control points used by arrow editing overlays.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowPointOverlay {
    pub turning_points: Vec<ArrowPointHandle>,
    pub addable_points: Vec<ArrowPointHandle>,
    pub loop_points: Vec<ArrowPointHandle>,
    pub focus_points: Vec<ArrowPointHandle>,
}

impl ArrowPointOverlay {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn has_loop(&self) -> bool {
        !self.loop_points.is_empty()
    }

    pub fn has_focus(&self) -> bool {
        !self.focus_points.is_empty()
    }
}

/// Minimal fixed-segment shape needed by elbow point utilities.
pub trait ArrowFixedSegmentLike {
    fn index(&self) -> usize;
}

impl ArrowFixedSegmentLike for ElbowFixedSegment {
    fn index(&self) -> usize {
        self.index
    }
}

/// Minimal arrow-like payload shape needed by [`ArrowPointUtils`].
pub trait ArrowPointDataLike {
    type FixedSegment;

    fn points(&self) -> &[DrawPoint];
    fn arrow_type(&self) -> ArrowType;
    fn fixed_segments(&self) -> Option<&[Self::FixedSegment]>;
}

impl ArrowPointDataLike for ArrowData {
    type FixedSegment = ElbowFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn fixed_segments(&self) -> Option<&[Self::FixedSegment]> {
        self.fixed_segments.as_deref()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParsedArrowFixedSegment {
    index: usize,
}

impl ArrowFixedSegmentLike for ParsedArrowFixedSegment {
    fn index(&self) -> usize {
        self.index
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParsedArrowPointData {
    points: Vec<DrawPoint>,
    arrow_type: ArrowType,
    fixed_segments: Option<Vec<ParsedArrowFixedSegment>>,
}

impl ParsedArrowPointData {
    fn from_arrow_data(data: &ArrowData) -> Self {
        Self {
            points: data.points.clone(),
            arrow_type: data.arrow_type,
            fixed_segments: data.fixed_segments.as_ref().map(|segments| {
                segments
                    .iter()
                    .map(|segment| ParsedArrowFixedSegment {
                        index: segment.index,
                    })
                    .collect()
            }),
        }
    }

    fn from_line_data(data: &LineData) -> Self {
        Self {
            points: data.points.clone(),
            arrow_type: data.arrow_type,
            fixed_segments: data.fixed_segments.as_ref().map(|segments| {
                segments
                    .iter()
                    .map(|segment| ParsedArrowFixedSegment {
                        index: segment.index,
                    })
                    .collect()
            }),
        }
    }
}

impl ArrowPointDataLike for ParsedArrowPointData {
    type FixedSegment = ParsedArrowFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn fixed_segments(&self) -> Option<&[Self::FixedSegment]> {
        self.fixed_segments.as_deref()
    }
}

/// Minimal element shape needed by [`ArrowPointUtils`].
pub trait ArrowPointElementLike {
    type Data: ArrowPointDataLike + Clone;

    fn id(&self) -> &str;
    fn rect(&self) -> DrawRect;
    fn rotation(&self) -> f64;
    fn arrow_data(&self) -> Option<Cow<'_, Self::Data>>;
}

impl ArrowPointElementLike for TypedElementState {
    type Data = ArrowData;

    fn id(&self) -> &str {
        &self.id
    }

    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn rotation(&self) -> f64 {
        self.rotation
    }

    fn arrow_data(&self) -> Option<Cow<'_, Self::Data>> {
        self.data
            .as_ref()
            .as_any()
            .downcast_ref::<ArrowData>()
            .map(Cow::Borrowed)
    }
}

impl ArrowPointElementLike for DomainElementState {
    type Data = ParsedArrowPointData;

    fn id(&self) -> &str {
        &self.id
    }

    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn rotation(&self) -> f64 {
        self.rotation
    }

    fn arrow_data(&self) -> Option<Cow<'_, Self::Data>> {
        resolve_arrow_data_from_domain_element(self).map(Cow::Owned)
    }
}

type FixedSegmentOf<E> = <<E as ArrowPointElementLike>::Data as ArrowPointDataLike>::FixedSegment;

/// Utility methods for arrow turning/addable/loop point overlays and hit-tests.
pub struct ArrowPointUtils;

impl ArrowPointUtils {
    const TURNING_HIT_RADIUS_FACTOR: f64 = 1.11;
    const ADDABLE_HIT_RADIUS_FACTOR: f64 = 1.43;
    const LOOP_OUTER_HIT_RADIUS_FACTOR: f64 = 1.18;
    const LOOP_INNER_HIT_RADIUS_FACTOR: f64 = 0.69;

    /// Builds overlay handles for an arrow-like element.
    pub fn build_overlay<E>(
        element: &E,
        loop_threshold: f64,
        handle_size: Option<f64>,
    ) -> ArrowPointOverlay
    where
        E: ArrowPointElementLike,
        FixedSegmentOf<E>: ArrowFixedSegmentLike,
    {
        let Some(data) = element.arrow_data() else {
            return ArrowPointOverlay::empty();
        };
        let data = data.as_ref();

        let points = resolve_world_points(element, data);
        if points.len() < 2 {
            return ArrowPointOverlay::empty();
        }

        if data.arrow_type() == ArrowType::Elbow {
            return build_elbow_overlay(element.id(), &points, data.fixed_segments(), handle_size);
        }

        build_path_overlay(element.id(), &points, data.arrow_type(), loop_threshold)
    }

    /// Returns the nearest control-point handle at `position`.
    pub fn hit_test<E>(
        element: &E,
        position: DrawPoint,
        hit_radius: f64,
        loop_threshold: f64,
        handle_size: Option<f64>,
    ) -> Option<ArrowPointHandle>
    where
        E: ArrowPointElementLike,
        FixedSegmentOf<E>: ArrowFixedSegmentLike,
    {
        let data = element.arrow_data()?;
        let data = data.as_ref();
        let points = resolve_world_points(element, data);
        if points.len() < 2 {
            return None;
        }

        let local_position = to_local_position(element, position);
        let visual_point_radius = resolve_visual_radius(handle_size, 0.5);
        let loop_active = is_loop_active(&points, loop_threshold);

        if data.arrow_type() == ArrowType::Elbow {
            return hit_test_elbow(
                element.id(),
                &points,
                local_position,
                hit_radius,
                visual_point_radius,
                handle_size,
                data.fixed_segments(),
            );
        }

        if let Some(loop_hit) = hit_test_loop(
            element.id(),
            &points,
            local_position,
            hit_radius,
            visual_point_radius,
            resolve_visual_radius(handle_size, 1.0),
            loop_active,
        ) {
            return Some(loop_hit);
        }

        if let Some(turning_hit) = hit_test_turning_points(
            element.id(),
            &points,
            local_position,
            max_radius(
                hit_radius * Self::TURNING_HIT_RADIUS_FACTOR,
                visual_point_radius,
            ),
            loop_active,
        ) {
            return Some(turning_hit);
        }

        let addable_hit_radius = max_radius(
            hit_radius * Self::ADDABLE_HIT_RADIUS_FACTOR,
            visual_point_radius,
        );
        let addable_hit_radius_sq = addable_hit_radius * addable_hit_radius;
        for i in 0..(points.len() - 1) {
            let midpoint = segment_midpoint(&points, data.arrow_type(), i);
            if local_position.distance_squared(midpoint) <= addable_hit_radius_sq {
                return Some(ArrowPointHandle::new(
                    element.id().to_owned(),
                    ArrowPointKind::Addable,
                    i,
                    midpoint,
                ));
            }
        }

        None
    }
}

fn build_elbow_overlay<S>(
    element_id: &str,
    points: &[DrawPoint],
    fixed_segments: Option<&[S]>,
    handle_size: Option<f64>,
) -> ArrowPointOverlay
where
    S: ArrowFixedSegmentLike,
{
    let turning_points = vec![
        ArrowPointHandle::new(element_id.to_owned(), ArrowPointKind::Turning, 0, points[0]),
        ArrowPointHandle::new(
            element_id.to_owned(),
            ArrowPointKind::Turning,
            points.len() - 1,
            points[points.len() - 1],
        ),
    ];

    let fixed_segment_indexes = fixed_segment_index_set(fixed_segments);
    let mut addable_points = Vec::new();
    for i in 0..(points.len() - 1) {
        let start = points[i];
        let end = points[i + 1];
        if is_segment_too_short(start, end, handle_size) {
            continue;
        }
        addable_points.push(ArrowPointHandle::with_fixed(
            element_id.to_owned(),
            ArrowPointKind::Addable,
            i,
            midpoint(start, end),
            fixed_segment_indexes.contains(&(i + 1)),
        ));
    }

    ArrowPointOverlay {
        turning_points,
        addable_points,
        loop_points: Vec::new(),
        focus_points: Vec::new(),
    }
}

fn build_path_overlay(
    element_id: &str,
    points: &[DrawPoint],
    arrow_type: ArrowType,
    loop_threshold: f64,
) -> ArrowPointOverlay {
    let loop_active = is_loop_active(points, loop_threshold);

    let mut turning_points = Vec::with_capacity(points.len());
    for (i, point) in points.iter().copied().enumerate() {
        if loop_active && (i == 0 || i == points.len() - 1) {
            continue;
        }
        turning_points.push(ArrowPointHandle::new(
            element_id.to_owned(),
            ArrowPointKind::Turning,
            i,
            point,
        ));
    }

    let mut addable_points = Vec::with_capacity(points.len().saturating_sub(1));
    for i in 0..(points.len() - 1) {
        addable_points.push(ArrowPointHandle::new(
            element_id.to_owned(),
            ArrowPointKind::Addable,
            i,
            segment_midpoint(points, arrow_type, i),
        ));
    }

    let loop_points = if loop_active {
        vec![
            ArrowPointHandle::new(
                element_id.to_owned(),
                ArrowPointKind::LoopStart,
                0,
                points[0],
            ),
            ArrowPointHandle::new(
                element_id.to_owned(),
                ArrowPointKind::LoopEnd,
                points.len() - 1,
                points[points.len() - 1],
            ),
        ]
    } else {
        Vec::new()
    };

    ArrowPointOverlay {
        turning_points,
        addable_points,
        loop_points,
        focus_points: Vec::new(),
    }
}

fn hit_test_elbow<S>(
    element_id: &str,
    points: &[DrawPoint],
    local_position: DrawPoint,
    hit_radius: f64,
    visual_point_radius: f64,
    handle_size: Option<f64>,
    fixed_segments: Option<&[S]>,
) -> Option<ArrowPointHandle>
where
    S: ArrowFixedSegmentLike,
{
    if let Some(turning_hit) = hit_test_elbow_turning_points(
        element_id,
        points,
        local_position,
        max_radius(
            hit_radius * ArrowPointUtils::TURNING_HIT_RADIUS_FACTOR,
            visual_point_radius,
        ),
    ) {
        return Some(turning_hit);
    }

    let fixed_segment_indexes = fixed_segment_index_set(fixed_segments);
    let segment_hit_radius_sq = hit_radius * hit_radius;
    for i in 0..(points.len() - 1) {
        let start = points[i];
        let end = points[i + 1];
        if is_segment_too_short(start, end, handle_size) {
            continue;
        }
        let mid = midpoint(start, end);
        if local_position.distance_squared(mid) <= segment_hit_radius_sq {
            return Some(ArrowPointHandle::with_fixed(
                element_id.to_owned(),
                ArrowPointKind::Addable,
                i,
                mid,
                fixed_segment_indexes.contains(&(i + 1)),
            ));
        }
    }

    None
}

fn hit_test_elbow_turning_points(
    element_id: &str,
    points: &[DrawPoint],
    local_position: DrawPoint,
    hit_radius: f64,
) -> Option<ArrowPointHandle> {
    let hit_radius_sq = hit_radius * hit_radius;
    let mut nearest: Option<ArrowPointHandle> = None;
    let mut nearest_distance_sq = f64::INFINITY;

    let mut test_point = |index: usize, point: DrawPoint| {
        let distance_sq = local_position.distance_squared(point);
        if distance_sq <= hit_radius_sq && distance_sq < nearest_distance_sq {
            nearest_distance_sq = distance_sq;
            nearest = Some(ArrowPointHandle::new(
                element_id.to_owned(),
                ArrowPointKind::Turning,
                index,
                point,
            ));
        }
    };

    test_point(0, points[0]);
    test_point(points.len() - 1, points[points.len() - 1]);
    nearest
}

fn hit_test_loop(
    element_id: &str,
    points: &[DrawPoint],
    local_position: DrawPoint,
    hit_radius: f64,
    visual_point_radius: f64,
    visual_loop_outer_radius: f64,
    loop_active: bool,
) -> Option<ArrowPointHandle> {
    if !loop_active {
        return None;
    }

    let loop_center = midpoint(points[0], points[points.len() - 1]);
    let distance_sq = local_position.distance_squared(loop_center);

    let inner_radius = max_radius(
        hit_radius * ArrowPointUtils::LOOP_INNER_HIT_RADIUS_FACTOR,
        visual_point_radius,
    );
    if distance_sq <= inner_radius * inner_radius {
        return Some(ArrowPointHandle::new(
            element_id.to_owned(),
            ArrowPointKind::LoopStart,
            0,
            points[0],
        ));
    }

    let outer_radius = max_radius(
        hit_radius * ArrowPointUtils::LOOP_OUTER_HIT_RADIUS_FACTOR,
        visual_loop_outer_radius,
    );
    if distance_sq <= outer_radius * outer_radius {
        return Some(ArrowPointHandle::new(
            element_id.to_owned(),
            ArrowPointKind::LoopEnd,
            points.len() - 1,
            points[points.len() - 1],
        ));
    }

    None
}

fn hit_test_turning_points(
    element_id: &str,
    points: &[DrawPoint],
    local_position: DrawPoint,
    hit_radius: f64,
    skip_endpoints: bool,
) -> Option<ArrowPointHandle> {
    let hit_radius_sq = hit_radius * hit_radius;
    let mut nearest: Option<ArrowPointHandle> = None;
    let mut nearest_distance_sq = f64::INFINITY;

    for (index, point) in points.iter().copied().enumerate() {
        if skip_endpoints && (index == 0 || index == points.len() - 1) {
            continue;
        }
        let distance_sq = local_position.distance_squared(point);
        if distance_sq <= hit_radius_sq && distance_sq < nearest_distance_sq {
            nearest_distance_sq = distance_sq;
            nearest = Some(ArrowPointHandle::new(
                element_id.to_owned(),
                ArrowPointKind::Turning,
                index,
                point,
            ));
        }
    }

    nearest
}

fn resolve_arrow_data_from_domain_element(
    element: &DomainElementState,
) -> Option<ParsedArrowPointData> {
    let payload = element.data.to_json_value();
    match element.type_id().as_str() {
        ArrowData::TYPE_ID_TOKEN => ArrowData::from_json_value(&payload)
            .ok()
            .map(|data| ParsedArrowPointData::from_arrow_data(&data)),
        LineData::TYPE_ID_TOKEN => LineData::from_json_value(&payload)
            .ok()
            .map(|data| ParsedArrowPointData::from_line_data(&data)),
        _ => None,
    }
}

fn resolve_world_points<E>(element: &E, data: &E::Data) -> Vec<DrawPoint>
where
    E: ArrowPointElementLike,
{
    ArrowGeometry::resolve_world_points(element.rect(), data.points())
}

fn to_local_position<E>(element: &E, position: DrawPoint) -> DrawPoint
where
    E: ArrowPointElementLike,
{
    if element.rotation() == 0.0 {
        return position;
    }
    let space = ElementSpace::new(element.rotation(), element.rect().center());
    space.from_world(position)
}

fn segment_midpoint(
    points: &[DrawPoint],
    arrow_type: ArrowType,
    segment_index: usize,
) -> DrawPoint {
    debug_assert!(
        segment_index < points.len().saturating_sub(1),
        "segment_index must reference a valid segment in points."
    );
    if arrow_type == ArrowType::Curved && points.len() >= 3 {
        if let Some(curve_point) =
            ArrowGeometry::calculate_curve_draw_point(points, segment_index, 0.5)
        {
            return curve_point;
        }
    }
    midpoint(points[segment_index], points[segment_index + 1])
}

fn midpoint(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
}

fn is_loop_active(points: &[DrawPoint], loop_threshold: f64) -> bool {
    points[0].distance_squared(points[points.len() - 1]) <= loop_threshold * loop_threshold
}

fn resolve_visual_radius(handle_size: Option<f64>, multiplier: f64) -> f64 {
    let Some(handle_size) = handle_size else {
        return 0.0;
    };
    if handle_size <= 0.0 {
        return 0.0;
    }
    handle_size * multiplier
}

fn max_radius(radius: f64, visual_radius: f64) -> f64 {
    if visual_radius > radius {
        visual_radius
    } else {
        radius
    }
}

fn is_segment_too_short(start: DrawPoint, end: DrawPoint, handle_size: Option<f64>) -> bool {
    let Some(handle_size) = handle_size else {
        return false;
    };
    if handle_size <= 0.0 {
        return false;
    }
    start.distance(end) < handle_size * 0.5
}

fn fixed_segment_index_set<S>(fixed_segments: Option<&[S]>) -> HashSet<usize>
where
    S: ArrowFixedSegmentLike,
{
    let Some(fixed_segments) = fixed_segments else {
        return HashSet::new();
    };
    fixed_segments
        .iter()
        .map(ArrowFixedSegmentLike::index)
        .collect()
}

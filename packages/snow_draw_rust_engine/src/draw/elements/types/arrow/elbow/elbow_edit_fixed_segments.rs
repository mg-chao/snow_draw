#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowData, ElbowFixedSegment};
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::ArrowheadStyle;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

/// Result of path edits that also track fixed-segment remapping.
#[derive(Clone, Debug, PartialEq)]
pub struct FixedSegmentPathResult {
    pub points: Vec<DrawPoint>,
    pub fixed_segments: Vec<ElbowFixedSegment>,
}

impl FixedSegmentPathResult {
    pub fn new(points: Vec<DrawPoint>, fixed_segments: Vec<ElbowFixedSegment>) -> Self {
        Self {
            points,
            fixed_segments,
        }
    }
}

/// Elbow edit payload mirrored from the Dart editing pipeline.
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowEditResult {
    pub local_points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

/// Minimal context required for fixed-segment release rerouting.
#[derive(Clone, Debug)]
pub struct ElbowEditContext<E> {
    pub element: E,
    pub elements_by_id: HashMap<String, E>,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

/// Routing hook used by [handle_fixed_segment_release].
///
/// The Dart implementation calls routeElbowArrowForElementPoints.
pub trait LocalPathRouter<E> {
    fn route_for_element_points(
        &self,
        element: &E,
        elements_by_id: &HashMap<String, E>,
        start_local: DrawPoint,
        end_local: DrawPoint,
        start_arrowhead: ArrowheadStyle,
        end_arrowhead: ArrowheadStyle,
        start_binding: Option<&ArrowBinding>,
        end_binding: Option<&ArrowBinding>,
    ) -> Vec<DrawPoint>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ElbowAxis {
    Horizontal,
    Vertical,
}

impl ElbowAxis {
    fn is_horizontal(self) -> bool {
        matches!(self, Self::Horizontal)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ElbowHeading {
    Left,
    Right,
    Up,
    Down,
}

impl ElbowHeading {
    fn is_horizontal(self) -> bool {
        matches!(self, Self::Left | Self::Right)
    }

    fn opposite(self) -> Self {
        match self {
            Self::Left => Self::Right,
            Self::Right => Self::Left,
            Self::Up => Self::Down,
            Self::Down => Self::Up,
        }
    }
}

trait ElbowFixedSegmentExt {
    fn is_horizontal(&self) -> bool;
    fn axis_value(&self) -> f64;
    fn is_significant(&self) -> bool;
    fn with_index_start_end(
        &self,
        index: usize,
        start: DrawPoint,
        end: DrawPoint,
    ) -> ElbowFixedSegment;
}

impl ElbowFixedSegmentExt for ElbowFixedSegment {
    fn is_horizontal(&self) -> bool {
        segment_is_horizontal(self.start, self.end)
    }

    fn axis_value(&self) -> f64 {
        if self.is_horizontal() {
            (self.start.y + self.end.y) * 0.5
        } else {
            (self.start.x + self.end.x) * 0.5
        }
    }

    fn is_significant(&self) -> bool {
        !is_degenerate_segment(self.start, self.end)
    }

    fn with_index_start_end(
        &self,
        index: usize,
        start: DrawPoint,
        end: DrawPoint,
    ) -> ElbowFixedSegment {
        ElbowFixedSegment { index, start, end }
    }
}

fn approx_eq(a: f64, b: f64) -> bool {
    (a - b).abs() <= ElbowConstants::DEDUP_THRESHOLD
}

fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
    (a.x - b.x).abs() + (a.y - b.y).abs()
}

fn axis_aligned_for_segment(start: DrawPoint, end: DrawPoint) -> Option<ElbowAxis> {
    let dx = (end.x - start.x).abs();
    let dy = (end.y - start.y).abs();
    if dx <= ElbowConstants::DEDUP_THRESHOLD && dy <= ElbowConstants::DEDUP_THRESHOLD {
        return None;
    }
    if dy <= ElbowConstants::DEDUP_THRESHOLD {
        return Some(ElbowAxis::Horizontal);
    }
    if dx <= ElbowConstants::DEDUP_THRESHOLD {
        return Some(ElbowAxis::Vertical);
    }
    None
}

fn segment_is_horizontal(start: DrawPoint, end: DrawPoint) -> bool {
    matches!(
        axis_aligned_for_segment(start, end),
        Some(ElbowAxis::Horizontal)
    )
}

fn axis_value(start: DrawPoint, end: DrawPoint, axis: ElbowAxis) -> f64 {
    match axis {
        ElbowAxis::Horizontal => (start.y + end.y) * 0.5,
        ElbowAxis::Vertical => (start.x + end.x) * 0.5,
    }
}

fn segments_collinear(a: DrawPoint, b: DrawPoint, c: DrawPoint) -> bool {
    (a.x - b.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        && (b.x - c.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        || (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
            && (b.y - c.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
}

fn points_aligned(a: DrawPoint, b: DrawPoint) -> bool {
    (a.x - b.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        || (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
}

fn points_close(a: DrawPoint, b: DrawPoint) -> bool {
    manhattan_distance(a, b) <= ElbowConstants::DEDUP_THRESHOLD
}

fn heading_for_segment(a: DrawPoint, b: DrawPoint) -> Option<ElbowHeading> {
    let dx = b.x - a.x;
    let dy = b.y - a.y;

    if dx.abs() <= ElbowConstants::DEDUP_THRESHOLD && dy.abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return None;
    }

    if dy.abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return Some(if dx >= 0.0 {
            ElbowHeading::Right
        } else {
            ElbowHeading::Left
        });
    }

    if dx.abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return Some(if dy >= 0.0 {
            ElbowHeading::Down
        } else {
            ElbowHeading::Up
        });
    }

    if dx.abs() >= dy.abs() {
        Some(if dx >= 0.0 {
            ElbowHeading::Right
        } else {
            ElbowHeading::Left
        })
    } else {
        Some(if dy >= 0.0 {
            ElbowHeading::Down
        } else {
            ElbowHeading::Up
        })
    }
}

fn corner_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() <= 2 {
        return points.to_vec();
    }
    let mut corners = Vec::with_capacity(points.len());
    corners.push(points[0]);
    for i in 1..points.len() - 1 {
        if heading_for_segment(points[i - 1], points[i])
            != heading_for_segment(points[i], points[i + 1])
        {
            corners.push(points[i]);
        }
    }
    corners.push(*points.last().expect("non-empty points"));
    corners
}

fn simplify_path(points: &[DrawPoint], pinned: &HashSet<DrawPoint>) -> Vec<DrawPoint> {
    if points.len() <= 2 {
        return points.to_vec();
    }

    let mut simplified = points.to_vec();
    loop {
        let mut changed = false;

        let mut i = 1usize;
        while i < simplified.len() {
            let prev = simplified[i - 1];
            let current = simplified[i];
            if current == prev
                || (!pinned.contains(&current)
                    && manhattan_distance(prev, current) <= ElbowConstants::DEDUP_THRESHOLD)
            {
                simplified.remove(i);
                changed = true;
                continue;
            }
            i += 1;
        }

        if simplified.len() <= 2 {
            break;
        }

        let mut i = 1usize;
        while i + 1 < simplified.len() {
            if pinned.contains(&simplified[i]) {
                i += 1;
                continue;
            }
            let a = simplified[i - 1];
            let b = simplified[i];
            let c = simplified[i + 1];
            if segments_collinear(a, b, c) {
                simplified.remove(i);
                changed = true;
                continue;
            }
            i += 1;
        }

        if !changed {
            break;
        }
    }

    simplified
}

fn direct_elbow_path(start: DrawPoint, end: DrawPoint, prefer_horizontal: bool) -> Vec<DrawPoint> {
    if points_aligned(start, end) {
        return vec![start, end];
    }

    let corner = if prefer_horizontal {
        DrawPoint::new(end.x, start.y)
    } else {
        DrawPoint::new(start.x, end.y)
    };

    let mut points = Vec::with_capacity(3);
    points.push(start);
    if !points_close(start, corner) && !points_close(corner, end) {
        points.push(corner);
    }
    points.push(end);
    points
}

fn is_interior_segment_index(index: usize, point_count: usize) -> bool {
    index > 1 && index + 1 < point_count
}

fn is_degenerate_segment(start: DrawPoint, end: DrawPoint) -> bool {
    manhattan_distance(start, end) <= ElbowConstants::DEDUP_THRESHOLD
}

pub fn sanitize_fixed_segments(
    segments: Option<&[ElbowFixedSegment]>,
    point_count: usize,
) -> Vec<ElbowFixedSegment> {
    let Some(segments) = segments else {
        return Vec::new();
    };
    if segments.is_empty() || point_count < 4 {
        return Vec::new();
    }

    let mut result = Vec::with_capacity(segments.len());
    let mut used_indices = HashSet::<usize>::with_capacity(segments.len());

    for segment in segments {
        if !is_interior_segment_index(segment.index, point_count) {
            continue;
        }
        if axis_aligned_for_segment(segment.start, segment.end).is_none() {
            continue;
        }
        if !segment.is_significant() {
            continue;
        }
        if !used_indices.insert(segment.index) {
            continue;
        }
        result.push(segment.clone());
    }

    result.sort_by_key(|segment| segment.index);
    result
}

pub fn stitch_sub_path(
    points: &[DrawPoint],
    start_index: usize,
    end_index: usize,
    sub_path: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> FixedSegmentPathResult {
    let prefix = points.get(..start_index).unwrap_or(&[]);
    let suffix = points.get(end_index + 1..).unwrap_or(&[]);

    let mut stitched = Vec::with_capacity(prefix.len() + sub_path.len() + suffix.len());
    stitched.extend_from_slice(prefix);
    stitched.extend_from_slice(sub_path);
    stitched.extend_from_slice(suffix);

    let reindexed = reindex_fixed_segments(&stitched, fixed_segments);
    FixedSegmentPathResult::new(stitched, reindexed)
}

pub fn reindex_fixed_segments(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }

    let mut result = Vec::with_capacity(fixed_segments.len());
    for segment in fixed_segments {
        let Some(index) = select_segment_index(
            points,
            segment.is_horizontal(),
            segment.index,
            segment.axis_value(),
            f64::INFINITY,
            &HashSet::new(),
        ) else {
            continue;
        };

        if !is_interior_segment_index(index, points.len()) {
            continue;
        }

        let start = points[index - 1];
        let end = points[index];
        if is_degenerate_segment(start, end) {
            continue;
        }

        result.push(segment.with_index_start_end(index, start, end));
    }
    result
}

pub fn select_segment_index(
    points: &[DrawPoint],
    is_horizontal: bool,
    preferred_index: usize,
    axis_value_target: f64,
    axis_tolerance: f64,
    used_indices: &HashSet<usize>,
) -> Option<usize> {
    if points.len() < 2 {
        return None;
    }

    let max_index = points.len() - 1;
    let min_index = 2usize;
    let axis = if is_horizontal {
        ElbowAxis::Horizontal
    } else {
        ElbowAxis::Vertical
    };

    let mut best_index: Option<usize> = None;
    let mut best_axis_delta = f64::INFINITY;
    let mut best_index_delta = f64::INFINITY;

    for i in min_index..max_index {
        if used_indices.contains(&i) {
            continue;
        }

        if segment_is_horizontal(points[i - 1], points[i]) != is_horizontal {
            continue;
        }

        let candidate_axis = axis_value(points[i - 1], points[i], axis);
        let axis_delta = (candidate_axis - axis_value_target).abs();
        if axis_delta > axis_tolerance {
            continue;
        }

        let index_delta = i.abs_diff(preferred_index) as f64;
        let axis_closer = axis_delta < best_axis_delta - ElbowConstants::DEDUP_THRESHOLD;
        let axis_tie = (axis_delta - best_axis_delta).abs() <= ElbowConstants::DEDUP_THRESHOLD;

        if axis_closer || (axis_tie && index_delta < best_index_delta) {
            best_axis_delta = axis_delta;
            best_index_delta = index_delta;
            best_index = Some(i);
        }
    }

    best_index
}

pub fn fixed_segment_is_horizontal(
    fixed_segments: &[ElbowFixedSegment],
    index: usize,
) -> Option<bool> {
    fixed_segments
        .iter()
        .find(|segment| segment.index == index)
        .map(ElbowFixedSegmentExt::is_horizontal)
}

pub fn fixed_segment_axes_stable(
    original: &[ElbowFixedSegment],
    updated: &[ElbowFixedSegment],
) -> bool {
    if original.len() != updated.len() {
        return false;
    }

    for (a, b) in original.iter().zip(updated.iter()) {
        if a.is_horizontal() != b.is_horizontal() {
            return false;
        }
        if (a.axis_value() - b.axis_value()).abs() > ElbowConstants::DEDUP_THRESHOLD {
            return false;
        }
    }

    true
}

pub fn fixed_segments_equal(a: &[ElbowFixedSegment], b: &[ElbowFixedSegment]) -> bool {
    if !fixed_segment_axes_stable(a, b) {
        return false;
    }

    a.iter()
        .zip(b.iter())
        .all(|(lhs, rhs)| lhs.index == rhs.index)
}

pub fn apply_fixed_segments_to_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<DrawPoint> {
    if points.len() < 2 || fixed_segments.is_empty() {
        return points.to_vec();
    }

    let mut updated = points.to_vec();
    for segment in fixed_segments {
        let index = segment.index;
        if index == 0 || index >= updated.len() {
            continue;
        }

        let start = updated[index - 1];
        let end = updated[index];
        let axis = segment.axis_value();
        let start_axis = if segment.is_horizontal() {
            start.y
        } else {
            start.x
        };
        let end_axis = if segment.is_horizontal() {
            end.y
        } else {
            end.x
        };

        let already_aligned = approx_eq(start_axis, axis) && approx_eq(end_axis, axis);
        if already_aligned {
            continue;
        }

        updated[index - 1] = if segment.is_horizontal() {
            start.copy_with(None, Some(axis), None, None)
        } else {
            start.copy_with(Some(axis), None, None, None)
        };

        updated[index] = if segment.is_horizontal() {
            end.copy_with(None, Some(axis), None, None)
        } else {
            end.copy_with(Some(axis), None, None, None)
        };
    }

    updated
}

pub fn map_fixed_segments_to_baseline(
    baseline: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    active_segment: Option<&ElbowFixedSegment>,
    enforce_axis_on_points: bool,
    require_all: bool,
) -> Option<FixedSegmentPathResult> {
    if baseline.len() < 2 {
        return if require_all {
            None
        } else {
            Some(FixedSegmentPathResult::new(
                baseline.to_vec(),
                fixed_segments.to_vec(),
            ))
        };
    }

    if fixed_segments.is_empty() {
        return Some(FixedSegmentPathResult::new(baseline.to_vec(), Vec::new()));
    }

    let mut updated = baseline.to_vec();
    let mut used_indices = HashSet::<usize>::new();
    let mut mapped_segments = Vec::<ElbowFixedSegment>::with_capacity(fixed_segments.len());

    for segment in fixed_segments {
        let is_active = active_segment.is_some_and(|active| active.index == segment.index);
        let axis_tolerance = if is_active {
            f64::INFINITY
        } else {
            ElbowConstants::DEDUP_THRESHOLD
        };

        let Some(index) = select_segment_index(
            &updated,
            segment.is_horizontal(),
            segment.index,
            segment.axis_value(),
            axis_tolerance,
            &used_indices,
        ) else {
            if require_all {
                return None;
            }
            continue;
        };

        if !is_interior_segment_index(index, updated.len()) {
            if require_all {
                return None;
            }
            continue;
        }

        used_indices.insert(index);
        let mut start = updated[index - 1];
        let mut end = updated[index];

        if !is_active {
            let axis = segment.axis_value();
            let aligned_start = if segment.is_horizontal() {
                start.copy_with(None, Some(axis), None, None)
            } else {
                start.copy_with(Some(axis), None, None, None)
            };
            let aligned_end = if segment.is_horizontal() {
                end.copy_with(None, Some(axis), None, None)
            } else {
                end.copy_with(Some(axis), None, None, None)
            };

            if enforce_axis_on_points {
                updated[index - 1] = aligned_start;
                updated[index] = aligned_end;
            }

            start = aligned_start;
            end = aligned_end;
        }

        mapped_segments.push(ElbowFixedSegment { index, start, end });
    }

    Some(FixedSegmentPathResult::new(updated, mapped_segments))
}

pub fn sync_fixed_segments_to_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }

    let mut result = Vec::with_capacity(fixed_segments.len());
    for segment in fixed_segments {
        let index = segment.index;
        if !is_interior_segment_index(index, points.len()) {
            continue;
        }
        let start = points[index - 1];
        let end = points[index];
        if is_degenerate_segment(start, end) {
            continue;
        }
        result.push(segment.with_index_start_end(index, start, end));
    }

    result
}

/// Removes adjacent near-duplicate points and remaps fixed-segment indices.
///
/// Returns the original vectors unchanged when deduplication would lose
/// a fixed segment after reindexing.
pub fn deduplicate_adjacent_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    pinned: &HashSet<DrawPoint>,
) -> (Vec<DrawPoint>, Vec<ElbowFixedSegment>) {
    if points.len() < 2 {
        return (points.to_vec(), fixed_segments.to_vec());
    }

    let mut cleaned = Vec::<DrawPoint>::with_capacity(points.len());
    cleaned.push(points[0]);

    for current in points.iter().skip(1).copied() {
        if current == *cleaned.last().expect("cleaned has first point") {
            continue;
        }
        if !pinned.contains(&current)
            && manhattan_distance(*cleaned.last().expect("non-empty"), current)
                <= ElbowConstants::DEDUP_THRESHOLD
        {
            continue;
        }
        cleaned.push(current);
    }

    if cleaned.len() == points.len() {
        return (points.to_vec(), fixed_segments.to_vec());
    }

    let reindexed = reindex_fixed_segments(&cleaned, fixed_segments);
    if reindexed.len() != fixed_segments.len() {
        return (points.to_vec(), fixed_segments.to_vec());
    }

    (cleaned, reindexed)
}

/// Tries to merge one collinear non-fixed neighbor into a fixed segment.
pub fn try_merge_collinear_neighbor(
    points: &[DrawPoint],
    segments: &[ElbowFixedSegment],
    segment_list_index: usize,
    fixed_indices: &HashSet<usize>,
) -> Option<FixedSegmentPathResult> {
    let segment = segments.get(segment_list_index)?.clone();
    let index = segment.index;
    if index <= 1 || index >= points.len() {
        return None;
    }

    for offset in [-1isize, 1isize] {
        let remove_index = if offset == -1 { index - 1 } else { index };
        let neighbor_index = if offset == -1 { index - 1 } else { index + 1 };
        if remove_index < 1 || neighbor_index >= points.len() {
            continue;
        }
        if fixed_indices.contains(&neighbor_index) {
            continue;
        }

        let a = points[remove_index - 1];
        let b = points[remove_index];
        let c = points[remove_index + 1];
        if !segments_collinear(a, b, c) {
            continue;
        }

        let mut candidate_points = points.to_vec();
        candidate_points.remove(remove_index);
        let new_index = if offset == -1 { index - 1 } else { index };
        if new_index >= candidate_points.len() {
            continue;
        }

        let mut candidate_segments = segments.to_vec();
        candidate_segments[segment_list_index] =
            segment.with_index_start_end(new_index, a, candidate_points[new_index]);

        let reindexed = reindex_fixed_segments(&candidate_points, &candidate_segments);
        if reindexed.len() == segments.len() {
            return Some(FixedSegmentPathResult::new(candidate_points, reindexed));
        }
    }

    None
}

pub fn merge_fixed_segments_with_collinear_neighbors(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    allow_direction_flip: bool,
    pinned: &HashSet<DrawPoint>,
) -> FixedSegmentPathResult {
    if points.len() < 3 || fixed_segments.is_empty() {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    let (deduped_points, deduped_segments) =
        deduplicate_adjacent_points(points, fixed_segments, pinned);

    let mut updated_points = deduped_points;
    let mut updated_segments = deduped_segments;

    if !allow_direction_flip && updated_points.len() >= 4 {
        let mut changed = true;
        while changed {
            changed = false;
            for segment in updated_segments.clone() {
                if segment.index == 0 || segment.index + 2 >= updated_points.len() {
                    continue;
                }
                let collapsed = try_collapse_backtrack_at(
                    &updated_points,
                    &updated_segments,
                    segment.index + 1,
                    segment.index + 2,
                    segment.is_horizontal(),
                );
                let Some(collapsed) = collapsed else {
                    continue;
                };
                updated_points = collapsed.points;
                updated_segments = collapsed.fixed_segments;
                changed = true;
                break;
            }
        }
    }

    let mut merged = true;
    while merged {
        merged = false;
        let fixed_indices = updated_segments
            .iter()
            .map(|segment| segment.index)
            .collect::<HashSet<_>>();

        for i in 0..updated_segments.len() {
            let result =
                try_merge_collinear_neighbor(&updated_points, &updated_segments, i, &fixed_indices);
            let Some(result) = result else {
                continue;
            };
            updated_points = result.points;
            updated_segments = result.fixed_segments;
            merged = true;
            break;
        }
    }

    collapse_endpoint_backtracks(&updated_points, &updated_segments)
}

/// Detects and collapses a collinear backtrack at remove_index.
pub fn try_collapse_backtrack_at(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    remove_index: usize,
    after_index: usize,
    is_horizontal: bool,
) -> Option<FixedSegmentPathResult> {
    if remove_index < 1 || remove_index + 1 >= points.len() {
        return None;
    }

    let prev = points[remove_index - 1];
    let curr = points[remove_index];
    let next = points[remove_index + 1];
    if !segments_collinear(prev, curr, next) {
        return None;
    }

    let d1 = if is_horizontal {
        curr.x - prev.x
    } else {
        curr.y - prev.y
    };
    let d2 = if is_horizontal {
        next.x - curr.x
    } else {
        next.y - curr.y
    };

    if d1.abs() <= ElbowConstants::DEDUP_THRESHOLD
        || d2.abs() <= ElbowConstants::DEDUP_THRESHOLD
        || d1 * d2 >= 0.0
    {
        return None;
    }

    let mut candidate = points.to_vec();
    candidate.remove(remove_index);

    if after_index < candidate.len() {
        let mapped_after_index = if after_index > remove_index {
            after_index - 1
        } else {
            after_index
        };
        let after = candidate[mapped_after_index];
        let reference = candidate[remove_index - 1];
        if !points_aligned(reference, after) {
            let corner = if is_horizontal {
                DrawPoint::new(reference.x, after.y)
            } else {
                DrawPoint::new(after.x, reference.y)
            };
            if !points_close(corner, reference) && !points_close(corner, after) {
                candidate.insert(remove_index, corner);
            }
        }
    }

    let reindexed = reindex_fixed_segments(&candidate, fixed_segments);
    if reindexed.len() != fixed_segments.len() {
        return None;
    }

    Some(FixedSegmentPathResult::new(candidate, reindexed))
}

pub fn collapse_endpoint_backtracks(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> FixedSegmentPathResult {
    if points.len() < 3 || fixed_segments.is_empty() {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    let pinned = collect_pinned_points(points, fixed_segments);
    let mut result = FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());

    for is_start in [true, false] {
        if result.points.len() < 3 {
            continue;
        }

        let mid_index = if is_start { 1 } else { result.points.len() - 2 };
        if pinned.contains(&result.points[mid_index]) {
            continue;
        }

        let axis = axis_aligned_for_segment(
            result.points[if is_start { 0 } else { result.points.len() - 3 }],
            result.points[mid_index],
        )
        .or_else(|| {
            axis_aligned_for_segment(
                result.points[mid_index],
                result.points[if is_start { 2 } else { result.points.len() - 1 }],
            )
        });

        let Some(axis) = axis else {
            continue;
        };

        let collapsed = try_collapse_backtrack_at(
            &result.points,
            &result.fixed_segments,
            mid_index,
            mid_index,
            axis.is_horizontal(),
        );
        if let Some(collapsed) = collapsed {
            result = collapsed;
        }
    }

    result
}

pub fn collect_pinned_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> HashSet<DrawPoint> {
    if points.is_empty() {
        return HashSet::new();
    }

    let mut pinned = HashSet::<DrawPoint>::new();
    pinned.insert(points[0]);
    pinned.insert(*points.last().expect("non-empty points"));

    for segment in fixed_segments {
        let index = segment.index;
        if index == 0 || index >= points.len() {
            continue;
        }
        pinned.insert(points[index - 1]);
        pinned.insert(points[index]);
    }

    pinned
}

/// Returns interior corner points (excluding endpoints).
pub fn interior_corner_points(points: &[DrawPoint]) -> HashSet<DrawPoint> {
    let corners = corner_points(points);
    if corners.len() <= 2 {
        return HashSet::new();
    }
    corners[1..corners.len() - 1].iter().copied().collect()
}

/// Normalizes a path with fixed segments.
///
/// Sequence:
/// 1. Optionally enforce fixed axes on points.
/// 2. Simplify while preserving pinned points.
/// 3. Reindex fixed segments.
/// 4. Merge collinear neighbors and collapse backtracks.
pub fn normalize_fixed_segment_path(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    extra_pinned: &HashSet<DrawPoint>,
    enforce_axes: bool,
    allow_direction_flip: bool,
) -> FixedSegmentPathResult {
    if points.len() < 2 || fixed_segments.is_empty() {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    let enforced = if enforce_axes {
        apply_fixed_segments_to_points(points, fixed_segments)
    } else {
        points.to_vec()
    };

    let mut pinned = collect_pinned_points(&enforced, fixed_segments);
    pinned.extend(extra_pinned.iter().copied());

    let simplified = simplify_path(&enforced, &pinned);
    let reindexed = reindex_fixed_segments(&simplified, fixed_segments);
    let active_fixed = if reindexed.len() == fixed_segments.len() {
        reindexed
    } else {
        fixed_segments.to_vec()
    };

    let mut merged_pinned = collect_pinned_points(&simplified, &active_fixed);
    merged_pinned.extend(extra_pinned.iter().copied());

    merge_fixed_segments_with_collinear_neighbors(
        &simplified,
        &active_fixed,
        allow_direction_flip,
        &merged_pinned,
    )
}

pub fn finalize_elbow_edit_result<E, F>(
    element: &E,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    result: ElbowEditResult,
    start_binding_override: Option<ArrowBinding>,
    end_binding_override: Option<ArrowBinding>,
    rerun_pipeline: F,
) -> ElbowEditResult
where
    F: FnOnce(
        &E,
        &ArrowData,
        &CombinedElementLookup<'_, E>,
        &[DrawPoint],
        &[ElbowFixedSegment],
        Option<ArrowBinding>,
        Option<ArrowBinding>,
    ) -> ElbowEditResult,
{
    let Some(fixed_segments) = result.fixed_segments.clone() else {
        return result;
    };
    if fixed_segments.is_empty() {
        return result;
    }

    let to_drop = fixed_segments_with_same_heading_adjacency(&result.local_points, &fixed_segments);
    if to_drop.is_empty() {
        return result;
    }

    let remaining = fixed_segments
        .into_iter()
        .filter(|segment| !to_drop.contains(&segment.index))
        .collect::<Vec<_>>();

    rerun_pipeline(
        element,
        data,
        lookup,
        &result.local_points,
        &remaining,
        start_binding_override,
        end_binding_override,
    )
}

pub fn fixed_segments_with_same_heading_adjacency(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> HashSet<usize> {
    if points.len() < 3 || fixed_segments.is_empty() {
        return HashSet::new();
    }

    let fixed_indices = fixed_segments
        .iter()
        .map(|segment| segment.index)
        .collect::<HashSet<_>>();
    let mut to_drop = HashSet::<usize>::new();

    for i in 1..points.len() - 1 {
        let a = points[i - 1];
        let b = points[i];
        let c = points[i + 1];

        let prev_length = manhattan_distance(a, b);
        let next_length = manhattan_distance(b, c);
        if prev_length <= ElbowConstants::DEDUP_THRESHOLD
            || next_length <= ElbowConstants::DEDUP_THRESHOLD
        {
            continue;
        }

        let prev_heading = heading_for_segment(a, b);
        let next_heading = heading_for_segment(b, c);
        if prev_heading.is_none() || prev_heading != next_heading {
            continue;
        }

        let prev_index = i;
        let next_index = i + 1;
        if fixed_indices.contains(&prev_index) {
            to_drop.insert(prev_index);
        }
        if fixed_indices.contains(&next_index) {
            to_drop.insert(next_index);
        }
    }

    to_drop
}

/// Routes an elbow sub-path in local space.
///
/// When no bindings constrain the route and one side is adjacent to a fixed
/// segment, a cheap direct elbow path is preferred to preserve the axis
/// pattern around that fixed segment.
pub fn route_local_path<E, R>(
    router: &R,
    element: &E,
    elements_by_id: &HashMap<String, E>,
    start_local: DrawPoint,
    end_local: DrawPoint,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    previous_fixed: Option<&ElbowFixedSegment>,
    next_fixed: Option<&ElbowFixedSegment>,
) -> Vec<DrawPoint>
where
    R: LocalPathRouter<E>,
{
    if start_binding.is_none()
        && end_binding.is_none()
        && (previous_fixed.is_some() || next_fixed.is_some())
    {
        let prefer_horizontal = if previous_fixed.is_some() && next_fixed.is_none() {
            previous_fixed.map(ElbowFixedSegmentExt::is_horizontal)
        } else if next_fixed.is_some() && previous_fixed.is_none() {
            next_fixed.map(|segment| !segment.is_horizontal())
        } else {
            None
        };

        if let Some(prefer_horizontal) = prefer_horizontal {
            return direct_elbow_path(start_local, end_local, prefer_horizontal);
        }
    }

    router.route_for_element_points(
        element,
        elements_by_id,
        start_local,
        end_local,
        start_arrowhead,
        end_arrowhead,
        start_binding,
        end_binding,
    )
}

pub fn handle_fixed_segment_release<E, R>(
    context: &ElbowEditContext<E>,
    current_points: &[DrawPoint],
    previous_fixed: &[ElbowFixedSegment],
    remaining_fixed: &[ElbowFixedSegment],
    router: &R,
) -> FixedSegmentPathResult
where
    E: Clone,
    R: LocalPathRouter<E>,
{
    let previous_indices = previous_fixed
        .iter()
        .map(|segment| segment.index)
        .collect::<HashSet<_>>();
    let remaining_indices = remaining_fixed
        .iter()
        .map(|segment| segment.index)
        .collect::<HashSet<_>>();

    let removed_indices = previous_indices
        .difference(&remaining_indices)
        .copied()
        .collect::<HashSet<_>>();

    if removed_indices.is_empty() || current_points.len() < 2 {
        return FixedSegmentPathResult::new(current_points.to_vec(), remaining_fixed.to_vec());
    }

    let min_removed = *removed_indices
        .iter()
        .min()
        .expect("non-empty removed indices");
    let max_removed = *removed_indices
        .iter()
        .max()
        .expect("non-empty removed indices");

    let mut previous: Option<ElbowFixedSegment> = None;
    let mut next: Option<ElbowFixedSegment> = None;

    for segment in remaining_fixed {
        if segment.index < min_removed {
            previous = Some(segment.clone());
        } else if segment.index > max_removed && next.is_none() {
            next = Some(segment.clone());
        }
    }

    let start_index = previous.as_ref().map_or(0usize, |segment| segment.index);
    let end_index = next.as_ref().map_or_else(
        || current_points.len() - 1,
        |segment| segment.index.saturating_sub(1),
    );

    if start_index >= end_index || end_index >= current_points.len() {
        return FixedSegmentPathResult::new(current_points.to_vec(), remaining_fixed.to_vec());
    }

    let routed = route_local_path(
        router,
        &context.element,
        &context.elements_by_id,
        current_points[start_index],
        current_points[end_index],
        if start_index == 0 {
            context.start_arrowhead
        } else {
            ArrowheadStyle::None
        },
        if end_index == current_points.len() - 1 {
            context.end_arrowhead
        } else {
            ArrowheadStyle::None
        },
        if start_index == 0 {
            context.start_binding.as_ref()
        } else {
            None
        },
        if end_index == current_points.len() - 1 {
            context.end_binding.as_ref()
        } else {
            None
        },
        previous.as_ref(),
        next.as_ref(),
    );

    stitch_sub_path(
        current_points,
        start_index,
        end_index,
        &routed,
        remaining_fixed,
    )
}

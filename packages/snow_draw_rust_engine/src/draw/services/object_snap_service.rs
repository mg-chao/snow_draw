#![allow(dead_code)]

use std::cmp::Ordering;

use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::snap_guides::{SnapGuide, SnapGuideAxis, SnapGuideKind};

/// Axis for snapping calculations.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SnapAxis {
    X,
    Y,
}

/// Anchor position on an axis: start (min), center, or end (max).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SnapAxisAnchor {
    Start,
    Center,
    End,
}

/// Result of a snap operation.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SnapResult {
    /// Horizontal offset to apply for snapping.
    pub dx: f64,

    /// Vertical offset to apply for snapping.
    pub dy: f64,

    /// Visual guides to display for active snaps.
    pub guides: Vec<SnapGuide>,
}

impl SnapResult {
    pub fn new(dx: f64, dy: f64, guides: Vec<SnapGuide>) -> Self {
        Self { dx, dy, guides }
    }

    /// Whether any snap was found.
    pub fn has_snap(&self) -> bool {
        self.dx != 0.0 || self.dy != 0.0
    }
}

/// Service for calculating object-to-object snapping in a drawing canvas.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ObjectSnapService;

impl ObjectSnapService {
    /// Floating-point comparison tolerance.
    const EPSILON: f64 = 0.0001;

    const ALL_ANCHORS: [SnapAxisAnchor; 3] = [
        SnapAxisAnchor::Start,
        SnapAxisAnchor::Center,
        SnapAxisAnchor::End,
    ];

    /// Percentage of snap distance used as distance tie-break slack.
    const PRIORITY_DISTANCE_SLACK_FACTOR: f64 = 0.05;

    /// Absolute cap for distance tie-break slack.
    const PRIORITY_DISTANCE_SLACK_MAX: f64 = 0.5;

    /// Minimum strength difference required to immediately prefer one candidate.
    const STRENGTH_SLACK: f64 = 0.05;

    /// Point snap scoring weights.
    const POINT_DISTANCE_WEIGHT: f64 = 0.45;
    const POINT_PERPENDICULAR_WEIGHT: f64 = 0.4;
    const POINT_ANCHOR_WEIGHT: f64 = 0.15;

    /// Gap snap scoring weights.
    const GAP_DISTANCE_WEIGHT: f64 = 0.7;
    const GAP_FREQUENCY_WEIGHT: f64 = 0.2;
    const GAP_KIND_WEIGHT: f64 = 0.1;

    /// Scale factor applied to gap strengths relative to point snaps.
    const GAP_STRENGTH_SCALE: f64 = 0.9;

    /// Perpendicular range factors.
    const PERPENDICULAR_SIZE_RANGE_FACTOR: f64 = 1.5;
    const PERPENDICULAR_SNAP_RANGE_FACTOR: f64 = 4.0;

    /// Maximum number of additional gap guides.
    const MAX_ASSOCIATED_GAP_GUIDES: usize = 4;

    /// Maximum anchor priority value, for normalization.
    const MAX_ANCHOR_PRIORITY: f64 = 3.0;

    pub const fn new() -> Self {
        Self
    }

    /// Calculates snap offset for moving elements.
    pub fn snap_move(
        &self,
        target_rect: DrawRect,
        reference_elements: &[ElementState],
        snap_distance: f64,
        reference_aabbs: Option<&[DrawRect]>,
        enable_point_snaps: bool,
        enable_gap_snaps: bool,
    ) -> SnapResult {
        self.snap_rect(
            target_rect,
            reference_elements,
            snap_distance,
            &Self::ALL_ANCHORS,
            &Self::ALL_ANCHORS,
            reference_aabbs,
            enable_point_snaps,
            enable_gap_snaps,
        )
    }

    /// Calculates snap offset for resizing elements.
    pub fn snap_resize(
        &self,
        target_rect: DrawRect,
        reference_elements: &[ElementState],
        snap_distance: f64,
        target_anchors_x: &[SnapAxisAnchor],
        target_anchors_y: &[SnapAxisAnchor],
        reference_aabbs: Option<&[DrawRect]>,
        enable_point_snaps: bool,
    ) -> SnapResult {
        self.snap_rect(
            target_rect,
            reference_elements,
            snap_distance,
            target_anchors_x,
            target_anchors_y,
            reference_aabbs,
            enable_point_snaps,
            false,
        )
    }

    /// Core snapping engine used by move/resize operations.
    pub fn snap_rect(
        &self,
        target_rect: DrawRect,
        reference_elements: &[ElementState],
        snap_distance: f64,
        target_anchors_x: &[SnapAxisAnchor],
        target_anchors_y: &[SnapAxisAnchor],
        reference_aabbs: Option<&[DrawRect]>,
        enable_point_snaps: bool,
        enable_gap_snaps: bool,
    ) -> SnapResult {
        if snap_distance <= 0.0
            || reference_elements.is_empty()
            || (!enable_point_snaps && !enable_gap_snaps)
            || (target_anchors_x.is_empty() && target_anchors_y.is_empty())
        {
            return SnapResult::default();
        }

        let effective_target_anchors_x = Self::deduplicate_anchors(target_anchors_x);
        let effective_target_anchors_y = Self::deduplicate_anchors(target_anchors_y);
        let reference_rects = Self::resolve_reference_aabbs(reference_elements, reference_aabbs);

        let candidates_x = Self::build_axis_candidates(
            SnapAxis::X,
            target_rect,
            &reference_rects,
            &effective_target_anchors_x,
            snap_distance,
            enable_point_snaps,
            enable_gap_snaps,
        );
        let candidates_y = Self::build_axis_candidates(
            SnapAxis::Y,
            target_rect,
            &reference_rects,
            &effective_target_anchors_y,
            snap_distance,
            enable_point_snaps,
            enable_gap_snaps,
        );

        let x_candidate = Self::select_best_candidate(&candidates_x, target_rect, snap_distance);
        let y_candidate = Self::select_best_candidate(&candidates_y, target_rect, snap_distance);

        let dx = x_candidate.map_or(0.0, |candidate| candidate.offset);
        let dy = y_candidate.map_or(0.0, |candidate| candidate.offset);
        let snapped_rect = target_rect.translate(DrawPoint::new(dx, dy));

        let mut guides = Vec::new();

        Self::append_candidate_guides(
            x_candidate,
            y_candidate,
            snapped_rect,
            &reference_rects,
            snap_distance,
            &mut guides,
        );
        Self::append_candidate_guides(
            y_candidate,
            x_candidate,
            snapped_rect,
            &reference_rects,
            snap_distance,
            &mut guides,
        );

        SnapResult::new(dx, dy, guides)
    }

    fn build_axis_candidates(
        axis: SnapAxis,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
        target_anchors: &[SnapAxisAnchor],
        snap_distance: f64,
        enable_point_snaps: bool,
        enable_gap_snaps: bool,
    ) -> Vec<AxisCandidate> {
        if target_anchors.is_empty() {
            return Vec::new();
        }

        let mut candidates = Vec::new();
        if enable_point_snaps {
            candidates.extend(Self::build_point_candidates(
                axis,
                target_rect,
                reference_rects,
                target_anchors,
                snap_distance,
            ));
        }
        if enable_gap_snaps {
            candidates.extend(Self::build_gap_candidates(
                axis,
                target_rect,
                reference_rects,
                target_anchors,
                snap_distance,
            ));
        }
        candidates
    }

    fn append_candidate_guides(
        candidate: Option<AxisCandidate>,
        perpendicular_candidate: Option<AxisCandidate>,
        snapped_rect: DrawRect,
        reference_rects: &[DrawRect],
        snap_distance: f64,
        guides: &mut Vec<SnapGuide>,
    ) {
        let Some(candidate) = candidate else {
            return;
        };

        for guide in
            Self::build_guides_for_candidate(candidate, snapped_rect, perpendicular_candidate)
        {
            if !guides.contains(&guide) {
                guides.push(guide);
            }
        }

        if !Self::is_gap_candidate(candidate) {
            return;
        }

        for guide in Self::build_associated_gap_guides(
            candidate,
            snapped_rect,
            reference_rects,
            snap_distance,
        ) {
            if !guides.contains(&guide) {
                guides.push(guide);
            }
        }
    }
    /// Builds point snap candidates by comparing target anchors against
    /// reference anchors.
    fn build_point_candidates(
        axis: SnapAxis,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
        target_anchors: &[SnapAxisAnchor],
        snap_distance: f64,
    ) -> Vec<AxisCandidate> {
        let mut candidates = Vec::new();

        for &reference_rect in reference_rects {
            let perpendicular_distance =
                Self::rect_perpendicular_distance(target_rect, reference_rect, axis);

            for &target_anchor in target_anchors {
                let target_pos = Self::anchor_position(target_rect, axis, target_anchor);
                for &reference_anchor in &Self::ALL_ANCHORS {
                    let reference_pos =
                        Self::anchor_position(reference_rect, axis, reference_anchor);
                    let offset = reference_pos - target_pos;
                    if offset.abs() <= snap_distance {
                        candidates.push(AxisCandidate::point(
                            axis,
                            offset,
                            reference_rect,
                            target_anchor,
                            reference_anchor,
                            perpendicular_distance,
                        ));
                    }
                }
            }
        }

        candidates
    }

    /// Builds gap snap candidates by matching spacing patterns in reference
    /// elements.
    fn build_gap_candidates(
        axis: SnapAxis,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
        target_anchors: &[SnapAxisAnchor],
        snap_distance: f64,
    ) -> Vec<AxisCandidate> {
        let mut candidates = Vec::new();
        let allow_center = target_anchors.contains(&SnapAxisAnchor::Center);

        let filtered = Self::resolve_gap_reference_rects(axis, target_rect, reference_rects);
        if filtered.len() < 2 {
            return candidates;
        }

        let segments = Self::build_gap_segments(axis, &filtered);
        if segments.is_empty() {
            return candidates;
        }

        let gap_buckets = Self::gap_size_buckets(&segments);
        if gap_buckets.is_empty() {
            return candidates;
        }

        let target_center = Self::anchor_position(target_rect, axis, SnapAxisAnchor::Center);
        let target_size = Self::axis_size(target_rect, axis);

        let before_neighbor =
            Self::closest_neighbor(axis, target_rect, &filtered, GapNeighborDirection::Before);
        let after_neighbor =
            Self::closest_neighbor(axis, target_rect, &filtered, GapNeighborDirection::After);

        for segment in &segments {
            if allow_center {
                let desired_center = (Self::axis_max(segment.before, axis)
                    + Self::axis_min(segment.after, axis))
                    / 2.0;
                let offset = desired_center - target_center;
                if offset.abs() <= snap_distance {
                    let gap_frequency = Self::gap_frequency_for(&gap_buckets, segment.gap);
                    candidates.push(AxisCandidate::gap_center(
                        axis,
                        offset,
                        segment.before,
                        segment.after,
                        segment.gap,
                        gap_frequency,
                    ));
                }
            }
        }

        for bucket in &gap_buckets {
            let gap_size = bucket.size;
            let gap_frequency = bucket.count;

            Self::add_gap_side_candidate_from_neighbor(
                &mut candidates,
                axis,
                target_rect,
                target_size,
                snap_distance,
                before_neighbor,
                gap_size,
                gap_frequency,
                GapSide::After,
            );
            Self::add_gap_side_candidate_from_neighbor(
                &mut candidates,
                axis,
                target_rect,
                target_size,
                snap_distance,
                after_neighbor,
                gap_size,
                gap_frequency,
                GapSide::Before,
            );
        }

        candidates
    }

    fn resolve_gap_reference_rects(
        axis: SnapAxis,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
    ) -> Vec<DrawRect> {
        let mut filtered = reference_rects
            .iter()
            .copied()
            .filter(|rect| Self::overlaps_perpendicular(*rect, target_rect, axis))
            .collect::<Vec<_>>();

        filtered.sort_by(|left, right| {
            Self::axis_min(*left, axis)
                .partial_cmp(&Self::axis_min(*right, axis))
                .unwrap_or(Ordering::Equal)
        });

        filtered
    }

    fn build_gap_segments(axis: SnapAxis, sorted_rects: &[DrawRect]) -> Vec<GapSegment> {
        if sorted_rects.len() < 2 {
            return Vec::new();
        }

        let mut segments = Vec::new();
        for index in 0..(sorted_rects.len() - 1) {
            let before = sorted_rects[index];
            let after = sorted_rects[index + 1];
            let gap = Self::axis_min(after, axis) - Self::axis_max(before, axis);
            if gap > 0.0 {
                segments.push(GapSegment { before, after, gap });
            }
        }

        segments
    }

    fn gap_size_buckets(segments: &[GapSegment]) -> Vec<GapSizeBucket> {
        let mut buckets = Vec::new();

        for segment in segments {
            let gap = segment.gap;
            if let Some(index) = buckets
                .iter()
                .position(|bucket: &GapSizeBucket| (bucket.size - gap).abs() <= Self::EPSILON)
            {
                buckets[index].count += 1;
            } else {
                buckets.push(GapSizeBucket {
                    size: gap,
                    count: 1,
                });
            }
        }

        buckets
    }

    fn gap_frequency_for(buckets: &[GapSizeBucket], gap: f64) -> i32 {
        buckets
            .iter()
            .find(|bucket| (bucket.size - gap).abs() <= Self::EPSILON)
            .map_or(0, |bucket| bucket.count)
    }

    fn closest_neighbor(
        axis: SnapAxis,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
        direction: GapNeighborDirection,
    ) -> Option<DrawRect> {
        let target_min = Self::axis_min(target_rect, axis);
        let target_max = Self::axis_max(target_rect, axis);

        let mut closest = None;
        let mut best_distance = f64::INFINITY;

        for &reference_rect in reference_rects {
            let distance = match direction {
                GapNeighborDirection::Before => target_min - Self::axis_max(reference_rect, axis),
                GapNeighborDirection::After => Self::axis_min(reference_rect, axis) - target_max,
            };

            if distance < -Self::EPSILON || distance > best_distance {
                continue;
            }

            best_distance = distance;
            closest = Some(reference_rect);
        }

        closest
    }

    fn add_gap_side_candidate_from_neighbor(
        candidates: &mut Vec<AxisCandidate>,
        axis: SnapAxis,
        target_rect: DrawRect,
        target_size: f64,
        snap_distance: f64,
        neighbor: Option<DrawRect>,
        gap_size: f64,
        gap_frequency: i32,
        gap_side: GapSide,
    ) {
        let Some(neighbor) = neighbor else {
            return;
        };

        let desired_start = match gap_side {
            GapSide::After => Self::axis_max(neighbor, axis) + gap_size,
            GapSide::Before => Self::axis_min(neighbor, axis) - gap_size - target_size,
        };

        Self::add_gap_side_candidate(
            candidates,
            axis,
            desired_start - Self::axis_min(target_rect, axis),
            snap_distance,
            neighbor,
            gap_size,
            gap_frequency,
            gap_side,
        );
    }

    fn add_gap_side_candidate(
        candidates: &mut Vec<AxisCandidate>,
        axis: SnapAxis,
        offset: f64,
        snap_distance: f64,
        reference_rect: DrawRect,
        gap_size: f64,
        gap_frequency: i32,
        gap_side: GapSide,
    ) {
        if offset.abs() > snap_distance {
            return;
        }

        candidates.push(AxisCandidate::gap_side(
            axis,
            offset,
            reference_rect,
            gap_size,
            gap_frequency,
            gap_side,
        ));
    }

    fn select_best_candidate(
        candidates: &[AxisCandidate],
        target_rect: DrawRect,
        snap_distance: f64,
    ) -> Option<AxisCandidate> {
        let mut best = None;
        let mut best_strength = 0.0;
        let distance_slack = Self::distance_slack(snap_distance);

        for &candidate in candidates {
            let candidate_strength =
                Self::candidate_strength(candidate, target_rect, snap_distance);
            let should_replace = match best {
                None => true,
                Some(current_best) => {
                    Self::compare_candidates(
                        candidate,
                        current_best,
                        candidate_strength,
                        best_strength,
                        distance_slack,
                    ) > 0
                }
            };

            if should_replace {
                best = Some(candidate);
                best_strength = candidate_strength;
            }
        }

        best
    }

    fn distance_slack(snap_distance: f64) -> f64 {
        (snap_distance * Self::PRIORITY_DISTANCE_SLACK_FACTOR)
            .min(Self::PRIORITY_DISTANCE_SLACK_MAX)
    }

    fn candidate_strength(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        snap_distance: f64,
    ) -> f64 {
        let distance_strength = Self::distance_strength(candidate.distance(), snap_distance);

        match candidate.kind {
            SnapKind::Point => Self::clamp01(
                distance_strength * Self::POINT_DISTANCE_WEIGHT
                    + Self::perpendicular_strength(candidate, target_rect, snap_distance)
                        * Self::POINT_PERPENDICULAR_WEIGHT
                    + Self::point_alignment_strength(candidate) * Self::POINT_ANCHOR_WEIGHT,
            ),
            SnapKind::GapCenter | SnapKind::GapSide => Self::clamp01(
                Self::gap_strength_score(
                    distance_strength,
                    candidate.gap_frequency.unwrap_or(0),
                    candidate.kind == SnapKind::GapCenter,
                ) * Self::GAP_STRENGTH_SCALE,
            ),
        }
    }
    fn gap_strength_score(distance_strength: f64, gap_frequency: i32, is_center: bool) -> f64 {
        let frequency_strength = Self::gap_frequency_strength(gap_frequency);
        let kind_strength = if is_center { 1.0 } else { 0.85 };

        distance_strength * Self::GAP_DISTANCE_WEIGHT
            + frequency_strength * Self::GAP_FREQUENCY_WEIGHT
            + kind_strength * Self::GAP_KIND_WEIGHT
    }

    fn distance_strength(distance: f64, snap_distance: f64) -> f64 {
        if snap_distance <= 0.0 {
            return 0.0;
        }

        1.0 - (distance / snap_distance).clamp(0.0, 1.0)
    }

    fn perpendicular_strength(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        snap_distance: f64,
    ) -> f64 {
        let reference_rect = candidate
            .reference_rect
            .expect("point candidate requires reference_rect");
        let perpendicular_distance = candidate.perpendicular_distance.unwrap_or(0.0);

        let range =
            Self::perpendicular_range(target_rect, reference_rect, candidate.axis, snap_distance);
        if range <= 0.0 {
            return 0.0;
        }

        let ratio = (perpendicular_distance / range).min(1.0);
        1.0 - ratio
    }

    fn perpendicular_range(
        target_rect: DrawRect,
        reference_rect: DrawRect,
        axis: SnapAxis,
        snap_distance: f64,
    ) -> f64 {
        let perpendicular_axis = Self::perpendicular_axis(axis);
        let target_size = Self::axis_size(target_rect, perpendicular_axis);
        let reference_size = Self::axis_size(reference_rect, perpendicular_axis);

        let size_range = target_size.max(reference_size) * Self::PERPENDICULAR_SIZE_RANGE_FACTOR;
        let snap_range = snap_distance * Self::PERPENDICULAR_SNAP_RANGE_FACTOR;
        let range = size_range.max(snap_range);

        range.max(snap_distance)
    }

    fn point_alignment_strength(candidate: AxisCandidate) -> f64 {
        let target_anchor = candidate
            .target_anchor
            .expect("point candidate requires target_anchor");
        let reference_anchor = candidate
            .reference_anchor
            .expect("point candidate requires reference_anchor");

        let priority = Self::anchor_priority(target_anchor, reference_anchor) as f64;
        1.0 - (priority / Self::MAX_ANCHOR_PRIORITY)
    }

    fn gap_frequency_strength(gap_frequency: i32) -> f64 {
        if gap_frequency <= 0 {
            return 0.0;
        }

        1.0 - (1.0 / (f64::from(gap_frequency) + 1.0))
    }

    fn clamp01(value: f64) -> f64 {
        if value <= 0.0 {
            return 0.0;
        }
        if value >= 1.0 {
            return 1.0;
        }
        value
    }

    fn compare_candidates(
        left: AxisCandidate,
        right: AxisCandidate,
        left_strength: f64,
        right_strength: f64,
        distance_slack: f64,
    ) -> i32 {
        let strength_delta = left_strength - right_strength;
        if strength_delta.abs() > Self::STRENGTH_SLACK {
            return if strength_delta > 0.0 { 1 } else { -1 };
        }

        let left_exact = Self::is_exact(left.offset);
        let right_exact = Self::is_exact(right.offset);
        if left_exact != right_exact {
            return if left_exact { 1 } else { -1 };
        }

        let distance_delta = left.distance() - right.distance();
        if distance_delta.abs() > distance_slack {
            return if distance_delta < 0.0 { 1 } else { -1 };
        }

        let left_kind_priority = Self::snap_kind_priority(left.kind);
        let right_kind_priority = Self::snap_kind_priority(right.kind);
        if left_kind_priority != right_kind_priority {
            return if left_kind_priority < right_kind_priority {
                1
            } else {
                -1
            };
        }

        let kind_specific = Self::compare_kind_specific_tie_breakers(left, right);
        if kind_specific != 0 {
            return kind_specific;
        }

        if distance_delta.abs() > Self::EPSILON {
            return if distance_delta < 0.0 { 1 } else { -1 };
        }

        0
    }

    fn snap_kind_priority(kind: SnapKind) -> i32 {
        match kind {
            SnapKind::Point => 0,
            SnapKind::GapCenter | SnapKind::GapSide => 1,
        }
    }

    fn compare_kind_specific_tie_breakers(left: AxisCandidate, right: AxisCandidate) -> i32 {
        if left.kind == SnapKind::Point && right.kind == SnapKind::Point {
            return Self::compare_point_candidates(left, right);
        }
        if left.kind != SnapKind::Point && right.kind != SnapKind::Point {
            return Self::compare_gap_candidates(left, right);
        }
        0
    }

    fn compare_point_candidates(left: AxisCandidate, right: AxisCandidate) -> i32 {
        let left_point_priority = Self::point_priority(left);
        let right_point_priority = Self::point_priority(right);
        if left_point_priority != right_point_priority {
            return if left_point_priority < right_point_priority {
                1
            } else {
                -1
            };
        }

        let left_perpendicular_distance = left.perpendicular_distance.unwrap_or(f64::INFINITY);
        let right_perpendicular_distance = right.perpendicular_distance.unwrap_or(f64::INFINITY);
        let perpendicular_delta = left_perpendicular_distance - right_perpendicular_distance;
        if perpendicular_delta.abs() <= Self::EPSILON {
            return 0;
        }

        if perpendicular_delta < 0.0 {
            1
        } else {
            -1
        }
    }

    fn compare_gap_candidates(left: AxisCandidate, right: AxisCandidate) -> i32 {
        let left_gap_frequency = left.gap_frequency.unwrap_or(0);
        let right_gap_frequency = right.gap_frequency.unwrap_or(0);
        if left_gap_frequency != right_gap_frequency {
            return if left_gap_frequency > right_gap_frequency {
                1
            } else {
                -1
            };
        }

        let left_gap_kind_priority = Self::gap_kind_priority(left);
        let right_gap_kind_priority = Self::gap_kind_priority(right);
        if left_gap_kind_priority == right_gap_kind_priority {
            return 0;
        }

        if left_gap_kind_priority < right_gap_kind_priority {
            1
        } else {
            -1
        }
    }

    fn point_priority(candidate: AxisCandidate) -> i32 {
        let target_anchor = candidate
            .target_anchor
            .expect("point candidate requires target_anchor");
        let reference_anchor = candidate
            .reference_anchor
            .expect("point candidate requires reference_anchor");

        Self::anchor_priority(target_anchor, reference_anchor)
    }

    fn gap_kind_priority(candidate: AxisCandidate) -> i32 {
        match candidate.kind {
            SnapKind::GapCenter => 0,
            SnapKind::Point | SnapKind::GapSide => 1,
        }
    }

    fn build_guides_for_candidate(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        perpendicular_candidate: Option<AxisCandidate>,
    ) -> Vec<SnapGuide> {
        if candidate.kind == SnapKind::GapCenter {
            let split_guides = Self::build_split_gap_center_guides(candidate, target_rect);
            if !split_guides.is_empty() {
                return split_guides;
            }
        }

        vec![Self::build_guide(
            candidate,
            target_rect,
            perpendicular_candidate,
        )]
    }

    fn build_guide(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        perpendicular_candidate: Option<AxisCandidate>,
    ) -> SnapGuide {
        match candidate.kind {
            SnapKind::Point => {
                Self::build_point_guide(candidate, target_rect, perpendicular_candidate)
            }
            SnapKind::GapCenter | SnapKind::GapSide => {
                Self::build_gap_guide(candidate, target_rect)
            }
        }
    }

    fn is_gap_candidate(candidate: AxisCandidate) -> bool {
        matches!(candidate.kind, SnapKind::GapCenter | SnapKind::GapSide)
    }

    fn build_associated_gap_guides(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        reference_rects: &[DrawRect],
        snap_distance: f64,
    ) -> Vec<SnapGuide> {
        let gap_size = candidate.gap_size.expect("gap candidate requires gap_size");
        let gap_tolerance = Self::EPSILON.max(Self::distance_slack(snap_distance));

        let filtered =
            Self::resolve_gap_reference_rects(candidate.axis, target_rect, reference_rects);
        if filtered.len() < 2 {
            return Vec::new();
        }

        let segments = Self::build_gap_segments(candidate.axis, &filtered);
        if segments.is_empty() {
            return Vec::new();
        }

        let mut matching_segments = Vec::new();
        for segment in segments {
            if (segment.gap - gap_size).abs() > gap_tolerance {
                continue;
            }
            if Self::matches_gap_segment(candidate, segment) {
                continue;
            }
            matching_segments.push(segment);
        }

        if matching_segments.is_empty() {
            return Vec::new();
        }

        matching_segments.sort_by(|left, right| {
            Self::gap_segment_distance_to_target(*left, target_rect, candidate.axis)
                .partial_cmp(&Self::gap_segment_distance_to_target(
                    *right,
                    target_rect,
                    candidate.axis,
                ))
                .unwrap_or(Ordering::Equal)
        });

        let limit = Self::MAX_ASSOCIATED_GAP_GUIDES.min(matching_segments.len());
        let mut guides = Vec::with_capacity(limit);

        for segment in matching_segments.into_iter().take(limit) {
            let segment_candidate = AxisCandidate::gap_center(
                candidate.axis,
                0.0,
                segment.before,
                segment.after,
                gap_size,
                candidate.gap_frequency,
            );
            guides.push(Self::build_gap_guide(segment_candidate, target_rect));
        }

        guides
    }
    fn matches_gap_segment(candidate: AxisCandidate, segment: GapSegment) -> bool {
        if candidate.kind != SnapKind::GapCenter {
            return false;
        }

        candidate.gap_before_rect == Some(segment.before)
            && candidate.gap_after_rect == Some(segment.after)
    }

    fn gap_segment_distance_to_target(
        segment: GapSegment,
        target_rect: DrawRect,
        axis: SnapAxis,
    ) -> f64 {
        let target_center = Self::axis_center(target_rect, axis);
        let segment_center =
            (Self::axis_max(segment.before, axis) + Self::axis_min(segment.after, axis)) / 2.0;
        (segment_center - target_center).abs()
    }

    fn build_point_guide(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        perpendicular_candidate: Option<AxisCandidate>,
    ) -> SnapGuide {
        let reference_rect = candidate
            .reference_rect
            .expect("point candidate requires reference_rect");
        let reference_anchor = candidate
            .reference_anchor
            .expect("point candidate requires reference_anchor");
        let snap_pos = Self::anchor_position(reference_rect, candidate.axis, reference_anchor);

        let markers = Self::resolve_point_markers(
            candidate,
            target_rect,
            reference_rect,
            snap_pos,
            perpendicular_candidate,
        );

        if candidate.axis == SnapAxis::X {
            let min_y = reference_rect.min_y.min(target_rect.min_y);
            let max_y = reference_rect.max_y.max(target_rect.max_y);
            let start = DrawPoint::new(snap_pos, min_y);
            let end = DrawPoint::new(snap_pos, max_y);
            return SnapGuide {
                kind: SnapGuideKind::Point,
                axis: SnapGuideAxis::Vertical,
                start,
                end,
                markers,
                label: None,
            };
        }

        let min_x = reference_rect.min_x.min(target_rect.min_x);
        let max_x = reference_rect.max_x.max(target_rect.max_x);
        let start = DrawPoint::new(min_x, snap_pos);
        let end = DrawPoint::new(max_x, snap_pos);
        SnapGuide {
            kind: SnapGuideKind::Point,
            axis: SnapGuideAxis::Horizontal,
            start,
            end,
            markers,
            label: None,
        }
    }

    fn build_gap_guide(candidate: AxisCandidate, target_rect: DrawRect) -> SnapGuide {
        let (start, end) = Self::gap_bounds(candidate, target_rect);
        Self::build_gap_guide_for_bounds(
            candidate.axis,
            target_rect,
            start,
            end,
            candidate.gap_size.expect("gap candidate requires gap_size"),
        )
    }

    fn build_split_gap_center_guides(
        candidate: AxisCandidate,
        target_rect: DrawRect,
    ) -> Vec<SnapGuide> {
        let before = candidate
            .gap_before_rect
            .expect("gapCenter candidate requires gap_before_rect");
        let after = candidate
            .gap_after_rect
            .expect("gapCenter candidate requires gap_after_rect");
        let axis = candidate.axis;

        let gap_start = Self::axis_max(before, axis);
        let gap_end = Self::axis_min(after, axis);
        let target_start = Self::axis_min(target_rect, axis);
        let target_end = Self::axis_max(target_rect, axis);

        if target_start <= gap_start + Self::EPSILON || target_end >= gap_end - Self::EPSILON {
            return Vec::new();
        }

        let gap_size = candidate
            .gap_size
            .expect("gapCenter candidate requires gap_size");
        vec![
            Self::build_gap_guide_for_bounds(axis, target_rect, gap_start, target_start, gap_size),
            Self::build_gap_guide_for_bounds(axis, target_rect, target_end, gap_end, gap_size),
        ]
    }

    fn build_gap_guide_for_bounds(
        axis: SnapAxis,
        target_rect: DrawRect,
        start: f64,
        end: f64,
        gap_size: f64,
    ) -> SnapGuide {
        if axis == SnapAxis::X {
            let y = target_rect.center_y();
            let start_point = DrawPoint::new(start, y);
            let end_point = DrawPoint::new(end, y);
            return SnapGuide {
                kind: SnapGuideKind::Gap,
                axis: SnapGuideAxis::Horizontal,
                start: start_point,
                end: end_point,
                markers: vec![start_point, end_point],
                label: Some(gap_size),
            };
        }

        let x = target_rect.center_x();
        let start_point = DrawPoint::new(x, start);
        let end_point = DrawPoint::new(x, end);
        SnapGuide {
            kind: SnapGuideKind::Gap,
            axis: SnapGuideAxis::Vertical,
            start: start_point,
            end: end_point,
            markers: vec![start_point, end_point],
            label: Some(gap_size),
        }
    }

    fn gap_bounds(candidate: AxisCandidate, target_rect: DrawRect) -> (f64, f64) {
        let axis = candidate.axis;
        match candidate.kind {
            SnapKind::GapCenter => {
                let before = candidate
                    .gap_before_rect
                    .expect("gapCenter candidate requires gap_before_rect");
                let after = candidate
                    .gap_after_rect
                    .expect("gapCenter candidate requires gap_after_rect");
                (Self::axis_max(before, axis), Self::axis_min(after, axis))
            }
            SnapKind::GapSide => {
                let reference_rect = candidate
                    .reference_rect
                    .expect("gapSide candidate requires reference_rect");
                if candidate.gap_side == Some(GapSide::After) {
                    (
                        Self::axis_max(reference_rect, axis),
                        Self::axis_min(target_rect, axis),
                    )
                } else {
                    (
                        Self::axis_max(target_rect, axis),
                        Self::axis_min(reference_rect, axis),
                    )
                }
            }
            SnapKind::Point => panic!("gap bounds requested for non-gap candidate"),
        }
    }

    fn overlaps_perpendicular(a: DrawRect, b: DrawRect, axis: SnapAxis) -> bool {
        if axis == SnapAxis::X {
            return a.max_y >= b.min_y && a.min_y <= b.max_y;
        }

        a.max_x >= b.min_x && a.min_x <= b.max_x
    }

    fn anchor_position(rect: DrawRect, axis: SnapAxis, anchor: SnapAxisAnchor) -> f64 {
        match axis {
            SnapAxis::X => match anchor {
                SnapAxisAnchor::Start => rect.min_x,
                SnapAxisAnchor::Center => rect.center_x(),
                SnapAxisAnchor::End => rect.max_x,
            },
            SnapAxis::Y => match anchor {
                SnapAxisAnchor::Start => rect.min_y,
                SnapAxisAnchor::Center => rect.center_y(),
                SnapAxisAnchor::End => rect.max_y,
            },
        }
    }

    fn axis_min(rect: DrawRect, axis: SnapAxis) -> f64 {
        if axis == SnapAxis::X {
            rect.min_x
        } else {
            rect.min_y
        }
    }

    fn axis_max(rect: DrawRect, axis: SnapAxis) -> f64 {
        if axis == SnapAxis::X {
            rect.max_x
        } else {
            rect.max_y
        }
    }

    fn axis_center(rect: DrawRect, axis: SnapAxis) -> f64 {
        if axis == SnapAxis::X {
            rect.center_x()
        } else {
            rect.center_y()
        }
    }

    fn axis_size(rect: DrawRect, axis: SnapAxis) -> f64 {
        if axis == SnapAxis::X {
            rect.width()
        } else {
            rect.height()
        }
    }

    fn perpendicular_axis(axis: SnapAxis) -> SnapAxis {
        if axis == SnapAxis::X {
            SnapAxis::Y
        } else {
            SnapAxis::X
        }
    }

    fn rect_perpendicular_distance(a: DrawRect, b: DrawRect, axis: SnapAxis) -> f64 {
        if axis == SnapAxis::X {
            if a.max_y < b.min_y {
                return b.min_y - a.max_y;
            }
            if b.max_y < a.min_y {
                return a.min_y - b.max_y;
            }
            return 0.0;
        }

        if a.max_x < b.min_x {
            return b.min_x - a.max_x;
        }
        if b.max_x < a.min_x {
            return a.min_x - b.max_x;
        }
        0.0
    }

    fn resolve_point_markers(
        candidate: AxisCandidate,
        target_rect: DrawRect,
        reference_rect: DrawRect,
        snap_pos: f64,
        perpendicular_candidate: Option<AxisCandidate>,
    ) -> Vec<DrawPoint> {
        let axis = candidate.axis;
        let perpendicular_axis = Self::perpendicular_axis(axis);

        let target_perp_anchor = if perpendicular_candidate
            .is_some_and(|candidate| candidate.axis == perpendicular_axis)
        {
            perpendicular_candidate.and_then(|candidate| candidate.target_anchor)
        } else {
            None
        };

        let reference_perp_anchor = if perpendicular_candidate.is_some_and(|candidate| {
            candidate.axis == perpendicular_axis && candidate.reference_rect == Some(reference_rect)
        }) {
            perpendicular_candidate.and_then(|candidate| candidate.reference_anchor)
        } else {
            None
        };

        let target_perp = target_perp_anchor
            .map(|anchor| Self::anchor_position(target_rect, perpendicular_axis, anchor))
            .unwrap_or_else(|| Self::axis_center(target_rect, perpendicular_axis));
        let reference_perp = reference_perp_anchor
            .map(|anchor| Self::anchor_position(reference_rect, perpendicular_axis, anchor))
            .unwrap_or_else(|| Self::axis_center(reference_rect, perpendicular_axis));

        let primary = if axis == SnapAxis::X {
            DrawPoint::new(snap_pos, target_perp)
        } else {
            DrawPoint::new(target_perp, snap_pos)
        };
        let secondary = if axis == SnapAxis::X {
            DrawPoint::new(snap_pos, reference_perp)
        } else {
            DrawPoint::new(reference_perp, snap_pos)
        };

        if primary == secondary {
            vec![primary]
        } else {
            vec![primary, secondary]
        }
    }

    fn anchor_priority(target: SnapAxisAnchor, reference: SnapAxisAnchor) -> i32 {
        if target == SnapAxisAnchor::Center && reference == SnapAxisAnchor::Center {
            return 0;
        }
        if target == reference {
            return 1;
        }
        if target == SnapAxisAnchor::Center || reference == SnapAxisAnchor::Center {
            return 2;
        }
        3
    }

    fn is_exact(offset: f64) -> bool {
        offset.abs() <= Self::EPSILON
    }

    fn build_element_aabbs(elements: &[ElementState]) -> Vec<DrawRect> {
        elements
            .iter()
            .map(Self::compute_element_world_aabb)
            .collect()
    }

    fn resolve_reference_aabbs(
        reference_elements: &[ElementState],
        reference_aabbs: Option<&[DrawRect]>,
    ) -> Vec<DrawRect> {
        if let Some(aabbs) = reference_aabbs {
            if aabbs.len() == reference_elements.len() {
                return aabbs.to_vec();
            }
        }

        Self::build_element_aabbs(reference_elements)
    }

    /// Builds reusable axis-aligned bounds for reference elements.
    pub fn build_reference_aabbs(reference_elements: &[ElementState]) -> Vec<DrawRect> {
        Self::build_element_aabbs(reference_elements)
    }

    fn deduplicate_anchors(anchors: &[SnapAxisAnchor]) -> Vec<SnapAxisAnchor> {
        if anchors.len() < 2 {
            return anchors.to_vec();
        }

        let mut deduplicated = Vec::with_capacity(anchors.len());
        for &anchor in anchors {
            if !deduplicated.contains(&anchor) {
                deduplicated.push(anchor);
            }
        }

        deduplicated
    }

    fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
        let rect = element.rect;
        let rotation = element.rotation;
        if rotation == 0.0 {
            return rect;
        }

        let center = rect.center();
        let half_width = rect.width().abs() / 2.0;
        let half_height = rect.height().abs() / 2.0;
        let cos_theta = rotation.cos().abs();
        let sin_theta = rotation.sin().abs();
        let x_extent = half_width * cos_theta + half_height * sin_theta;
        let y_extent = half_width * sin_theta + half_height * cos_theta;

        DrawRect::new(
            center.x - x_extent,
            center.y - y_extent,
            center.x + x_extent,
            center.y + y_extent,
        )
    }
}

pub const OBJECT_SNAP_SERVICE: ObjectSnapService = ObjectSnapService::new();
/// Type of snap: point alignment or gap alignment.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SnapKind {
    Point,
    GapCenter,
    GapSide,
}

/// Which side of a reference element a gap snap is relative to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum GapSide {
    Before,
    After,
}

/// Direction to search for neighboring elements.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum GapNeighborDirection {
    Before,
    After,
}

/// A candidate snap for one axis, with all data needed for scoring and guides.
#[derive(Clone, Copy, Debug, PartialEq)]
struct AxisCandidate {
    axis: SnapAxis,
    offset: f64,
    kind: SnapKind,

    reference_rect: Option<DrawRect>,
    target_anchor: Option<SnapAxisAnchor>,
    reference_anchor: Option<SnapAxisAnchor>,
    perpendicular_distance: Option<f64>,

    gap_before_rect: Option<DrawRect>,
    gap_after_rect: Option<DrawRect>,
    gap_size: Option<f64>,
    gap_side: Option<GapSide>,
    gap_frequency: Option<i32>,
}

impl AxisCandidate {
    fn point(
        axis: SnapAxis,
        offset: f64,
        reference_rect: DrawRect,
        target_anchor: SnapAxisAnchor,
        reference_anchor: SnapAxisAnchor,
        perpendicular_distance: f64,
    ) -> Self {
        Self {
            axis,
            offset,
            kind: SnapKind::Point,
            reference_rect: Some(reference_rect),
            target_anchor: Some(target_anchor),
            reference_anchor: Some(reference_anchor),
            perpendicular_distance: Some(perpendicular_distance),
            gap_before_rect: None,
            gap_after_rect: None,
            gap_size: None,
            gap_side: None,
            gap_frequency: None,
        }
    }

    fn gap_center(
        axis: SnapAxis,
        offset: f64,
        gap_before_rect: DrawRect,
        gap_after_rect: DrawRect,
        gap_size: f64,
        gap_frequency: impl Into<Option<i32>>,
    ) -> Self {
        Self {
            axis,
            offset,
            kind: SnapKind::GapCenter,
            reference_rect: None,
            target_anchor: None,
            reference_anchor: None,
            perpendicular_distance: None,
            gap_before_rect: Some(gap_before_rect),
            gap_after_rect: Some(gap_after_rect),
            gap_size: Some(gap_size),
            gap_side: None,
            gap_frequency: gap_frequency.into(),
        }
    }

    fn gap_side(
        axis: SnapAxis,
        offset: f64,
        reference_rect: DrawRect,
        gap_size: f64,
        gap_frequency: i32,
        gap_side: GapSide,
    ) -> Self {
        Self {
            axis,
            offset,
            kind: SnapKind::GapSide,
            reference_rect: Some(reference_rect),
            target_anchor: None,
            reference_anchor: None,
            perpendicular_distance: None,
            gap_before_rect: None,
            gap_after_rect: None,
            gap_size: Some(gap_size),
            gap_side: Some(gap_side),
            gap_frequency: Some(gap_frequency),
        }
    }

    fn distance(self) -> f64 {
        self.offset.abs()
    }
}

/// A gap between two adjacent reference elements.
#[derive(Clone, Copy, Debug, PartialEq)]
struct GapSegment {
    before: DrawRect,
    after: DrawRect,
    gap: f64,
}

/// Bucket for grouping gaps of similar sizes and tracking frequency.
#[derive(Clone, Copy, Debug, PartialEq)]
struct GapSizeBucket {
    size: f64,
    count: i32,
}

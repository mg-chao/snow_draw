#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::elements::types::arrow::elbow::elbow_heading::ElbowHeading;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Fully resolved endpoint used by elbow obstacle planning.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct ResolvedEndpoint {
    pub point: DrawPoint,
    pub heading: ElbowHeading,
    pub has_arrowhead: bool,
    pub element_bounds: Option<DrawRect>,
    pub anchor: Option<DrawPoint>,
}

impl ResolvedEndpoint {
    pub const fn is_bound(self) -> bool {
        self.element_bounds.is_some()
    }

    pub fn anchor_or_point(self) -> DrawPoint {
        self.anchor.unwrap_or(self.point)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct BoundsPadding {
    top: f64,
    right: f64,
    bottom: f64,
    left: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct ObstaclePair {
    start: DrawRect,
    end: DrawRect,
}

/// Obstacle layout for routing a single elbow path.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ElbowObstacleLayout {
    pub common_bounds: DrawRect,
    pub start_exit: DrawPoint,
    pub end_exit: DrawPoint,
    pub obstacles: Vec<DrawRect>,
}

/// Builds padded obstacle bounds and exit points for one elbow route.
pub(crate) fn plan_obstacle_layout(
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
) -> ElbowObstacleLayout {
    let start_elbow = element_bounds_for_elbow(
        start.point,
        start.element_bounds,
        start.heading,
        start.has_arrowhead,
    );
    let end_elbow = element_bounds_for_elbow(
        end.point,
        end.element_bounds,
        end.heading,
        end.has_arrowhead,
    );
    let overlap = start.is_bound() && end.is_bound() && bounds_overlap(start_elbow, end_elbow);

    let start_base = if overlap {
        point_bounds(start.point, ElbowConstants::EXIT_POINT_PADDING)
    } else {
        start_elbow
    };
    let end_base = if overlap {
        point_bounds(end.point, ElbowConstants::EXIT_POINT_PADDING)
    } else {
        end_elbow
    };

    let start_pad = if overlap {
        overlap_padding(start.heading)
    } else {
        routing_padding(start.heading, start.has_arrowhead)
    };
    let end_pad = if overlap {
        overlap_padding(end.heading)
    } else {
        routing_padding(end.heading, end.has_arrowhead)
    };

    let common = union_bounds(&[start_base, end_base]);
    let start_obstacle = if start.is_bound() {
        dynamic_aabb_for(start_base, end_base, common, start_pad)
    } else {
        start_base
    };
    let end_obstacle = if end.is_bound() {
        dynamic_aabb_for(end_base, start_base, common, end_pad)
    } else {
        end_base
    };

    let obstacles = resolve_obstacle_bounds(
        start,
        end,
        start_base,
        end_base,
        start_obstacle,
        end_obstacle,
    );

    let common_bounds = clamp_bounds(inflate_bounds(
        union_bounds(&[obstacles.start, obstacles.end]),
        ElbowConstants::BASE_PADDING,
    ));

    ElbowObstacleLayout {
        common_bounds,
        start_exit: exit_position(obstacles.start, start.heading, start.point),
        end_exit: exit_position(obstacles.end, end.heading, end.point),
        obstacles: vec![obstacles.start, obstacles.end],
    }
}

fn inflate_bounds(rect: DrawRect, padding: f64) -> DrawRect {
    DrawRect::new(
        rect.min_x - padding,
        rect.min_y - padding,
        rect.max_x + padding,
        rect.max_y + padding,
    )
}

fn clamp_bounds(rect: DrawRect) -> DrawRect {
    DrawRect::new(
        clamp_position(rect.min_x),
        clamp_position(rect.min_y),
        clamp_position(rect.max_x),
        clamp_position(rect.max_y),
    )
}

pub(crate) fn clamp_point(point: DrawPoint) -> DrawPoint {
    DrawPoint::new(clamp_position(point.x), clamp_position(point.y))
}

fn clamp_position(value: f64) -> f64 {
    let max = ElbowConstants::MAX_POSITION;
    value.clamp(-max, max)
}

fn union_bounds(bounds: &[DrawRect]) -> DrawRect {
    let Some(first) = bounds.first().copied() else {
        return DrawRect::default();
    };

    let mut min_x = first.min_x;
    let mut min_y = first.min_y;
    let mut max_x = first.max_x;
    let mut max_y = first.max_y;

    for rect in bounds.iter().copied().skip(1) {
        min_x = min_x.min(rect.min_x);
        min_y = min_y.min(rect.min_y);
        max_x = max_x.max(rect.max_x);
        max_y = max_y.max(rect.max_y);
    }

    DrawRect::new(min_x, min_y, max_x, max_y)
}

fn bounds_overlap(a: DrawRect, b: DrawRect) -> bool {
    a.min_x < b.max_x && a.max_x > b.min_x && a.min_y < b.max_y && a.max_y > b.min_y
}

#[allow(clippy::too_many_arguments)]
fn split_overlapping_on_axis(
    start_bounds: DrawRect,
    end_bounds: DrawRect,
    start_obstacle: DrawRect,
    end_obstacle: DrawRect,
    split_value: f64,
    overlap_min: f64,
    overlap_max: f64,
    start_before_end: bool,
    horizontal: bool,
) -> ObstaclePair {
    let mut min_split = if horizontal {
        if start_before_end {
            start_bounds.max_x
        } else {
            end_bounds.max_x
        }
    } else if start_before_end {
        start_bounds.max_y
    } else {
        end_bounds.max_y
    };
    let mut max_split = if horizontal {
        if start_before_end {
            end_bounds.min_x
        } else {
            start_bounds.min_x
        }
    } else if start_before_end {
        end_bounds.min_y
    } else {
        start_bounds.min_y
    };

    if max_split < min_split {
        min_split = overlap_min;
        max_split = overlap_max;
    }
    if max_split - min_split <= ElbowConstants::INTERSECTION_EPSILON {
        return ObstaclePair {
            start: start_obstacle,
            end: end_obstacle,
        };
    }

    let clamped_split = split_value.clamp(min_split, max_split);

    let (clamped_start, clamped_end) = if horizontal {
        let start = if start_before_end {
            start_obstacle.copy_with(
                None,
                None,
                Some(start_obstacle.max_x.min(clamped_split)),
                None,
            )
        } else {
            start_obstacle.copy_with(
                Some(start_obstacle.min_x.max(clamped_split)),
                None,
                None,
                None,
            )
        };
        let end = if start_before_end {
            end_obstacle.copy_with(
                Some(end_obstacle.min_x.max(clamped_split)),
                None,
                None,
                None,
            )
        } else {
            end_obstacle.copy_with(
                None,
                None,
                Some(end_obstacle.max_x.min(clamped_split)),
                None,
            )
        };
        (start, end)
    } else {
        let start = if start_before_end {
            start_obstacle.copy_with(
                None,
                None,
                None,
                Some(start_obstacle.max_y.min(clamped_split)),
            )
        } else {
            start_obstacle.copy_with(
                None,
                Some(start_obstacle.min_y.max(clamped_split)),
                None,
                None,
            )
        };
        let end = if start_before_end {
            end_obstacle.copy_with(
                None,
                Some(end_obstacle.min_y.max(clamped_split)),
                None,
                None,
            )
        } else {
            end_obstacle.copy_with(
                None,
                None,
                None,
                Some(end_obstacle.max_y.min(clamped_split)),
            )
        };
        (start, end)
    };

    ObstaclePair {
        start: clamped_start,
        end: clamped_end,
    }
}

fn split_overlapping_obstacles(
    start_bounds: DrawRect,
    end_bounds: DrawRect,
    start_obstacle: DrawRect,
    end_obstacle: DrawRect,
    start_pivot: Option<DrawPoint>,
    end_pivot: Option<DrawPoint>,
) -> ObstaclePair {
    if !bounds_overlap(start_obstacle, end_obstacle) {
        return ObstaclePair {
            start: start_obstacle,
            end: end_obstacle,
        };
    }

    let start_center = start_pivot.unwrap_or_else(|| start_bounds.center());
    let end_center = end_pivot.unwrap_or_else(|| end_bounds.center());
    let dx = (start_center.x - end_center.x).abs();
    let dy = (start_center.y - end_center.y).abs();

    let overlap_min_x = start_obstacle.min_x.max(end_obstacle.min_x);
    let overlap_max_x = start_obstacle.max_x.min(end_obstacle.max_x);
    let overlap_min_y = start_obstacle.min_y.max(end_obstacle.min_y);
    let overlap_max_y = start_obstacle.max_y.min(end_obstacle.max_y);

    if dx >= dy {
        let split_x = (start_center.x + end_center.x) * 0.5;
        return split_overlapping_on_axis(
            start_bounds,
            end_bounds,
            start_obstacle,
            end_obstacle,
            split_x,
            overlap_min_x,
            overlap_max_x,
            start_center.x <= end_center.x,
            true,
        );
    }

    let split_y = (start_center.y + end_center.y) * 0.5;
    split_overlapping_on_axis(
        start_bounds,
        end_bounds,
        start_obstacle,
        end_obstacle,
        split_y,
        overlap_min_y,
        overlap_max_y,
        start_center.y <= end_center.y,
        false,
    )
}

fn point_bounds(point: DrawPoint, padding: f64) -> DrawRect {
    DrawRect::new(
        point.x - padding,
        point.y - padding,
        point.x + padding,
        point.y + padding,
    )
}

fn element_bounds_for_elbow(
    point: DrawPoint,
    element_bounds: Option<DrawRect>,
    heading: ElbowHeading,
    has_arrowhead: bool,
) -> DrawRect {
    let Some(bounds) = element_bounds else {
        return point_bounds(point, 0.0);
    };

    let head_offset = binding_gap(has_arrowhead);
    let padding = padding_from_heading(heading, head_offset, ElbowConstants::ELEMENT_SIDE_PADDING);
    DrawRect::new(
        bounds.min_x - padding.left,
        bounds.min_y - padding.top,
        bounds.max_x + padding.right,
        bounds.max_y + padding.bottom,
    )
}

fn overlap_padding(heading: ElbowHeading) -> BoundsPadding {
    padding_from_heading(heading, ElbowConstants::BASE_PADDING, 0.0)
}

fn routing_padding(heading: ElbowHeading, has_arrowhead: bool) -> BoundsPadding {
    padding_from_heading(
        heading,
        head_padding(has_arrowhead),
        ElbowConstants::BASE_PADDING,
    )
}

fn dynamic_aabb_for(
    self_bounds: DrawRect,
    other: DrawRect,
    common: DrawRect,
    padding: BoundsPadding,
) -> DrawRect {
    let separated_vertically = self_bounds.min_y > other.max_y || self_bounds.max_y < other.min_y;
    let separated_horizontally = self_bounds.min_x > other.max_x || self_bounds.max_x < other.min_x;

    DrawRect::new(
        dynamic_min_edge(
            self_bounds.min_x,
            other.min_x,
            other.max_x,
            common.min_x,
            padding.left,
            separated_vertically,
        ),
        dynamic_min_edge(
            self_bounds.min_y,
            other.min_y,
            other.max_y,
            common.min_y,
            padding.top,
            separated_horizontally,
        ),
        dynamic_max_edge(
            self_bounds.max_x,
            other.min_x,
            other.max_x,
            common.max_x,
            padding.right,
            separated_vertically,
        ),
        dynamic_max_edge(
            self_bounds.max_y,
            other.min_y,
            other.max_y,
            common.max_y,
            padding.bottom,
            separated_horizontally,
        ),
    )
}

fn dynamic_min_edge(
    self_min: f64,
    other_min: f64,
    other_max: f64,
    common_min: f64,
    pad: f64,
    separated: bool,
) -> f64 {
    if self_min > other_max {
        let split = (self_min + other_max) * 0.5;
        if !separated {
            return split;
        }
        return split.min(self_min - pad);
    }
    if self_min > other_min {
        return self_min - pad;
    }
    common_min - pad
}

fn dynamic_max_edge(
    self_max: f64,
    other_min: f64,
    other_max: f64,
    common_max: f64,
    pad: f64,
    separated: bool,
) -> f64 {
    if self_max < other_min {
        let split = (self_max + other_min) * 0.5;
        if !separated {
            return split;
        }
        return split.max(self_max + pad);
    }
    if self_max < other_max {
        return self_max + pad;
    }
    common_max + pad
}

fn padding_from_heading(
    heading: ElbowHeading,
    head_offset: f64,
    side_offset: f64,
) -> BoundsPadding {
    match heading {
        ElbowHeading::Up => BoundsPadding {
            top: head_offset,
            right: side_offset,
            bottom: side_offset,
            left: side_offset,
        },
        ElbowHeading::Right => BoundsPadding {
            top: side_offset,
            right: head_offset,
            bottom: side_offset,
            left: side_offset,
        },
        ElbowHeading::Down => BoundsPadding {
            top: side_offset,
            right: side_offset,
            bottom: head_offset,
            left: side_offset,
        },
        ElbowHeading::Left => BoundsPadding {
            top: side_offset,
            right: side_offset,
            bottom: side_offset,
            left: head_offset,
        },
    }
}

fn exit_position(bounds: DrawRect, heading: ElbowHeading, point: DrawPoint) -> DrawPoint {
    match heading {
        ElbowHeading::Up => DrawPoint::new(point.x, bounds.min_y),
        ElbowHeading::Right => DrawPoint::new(bounds.max_x, point.y),
        ElbowHeading::Down => DrawPoint::new(point.x, bounds.max_y),
        ElbowHeading::Left => DrawPoint::new(bounds.min_x, point.y),
    }
}

fn resolve_obstacle_bounds(
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
    start_base_bounds: DrawRect,
    end_base_bounds: DrawRect,
    start_obstacle: DrawRect,
    end_obstacle: DrawRect,
) -> ObstaclePair {
    let mut start_obs = clamp_bounds(start_obstacle);
    let mut end_obs = clamp_bounds(end_obstacle);

    if bounds_overlap(start_obs, end_obs) {
        let split = split_overlapping_obstacles(
            start_base_bounds,
            end_base_bounds,
            start_obs,
            end_obs,
            Some(start.anchor_or_point()),
            Some(end.anchor_or_point()),
        );
        start_obs = clamp_bounds(split.start);
        end_obs = clamp_bounds(split.end);
    }

    start_obs = clamp_obstacle_to_bounds_padding(start, start_obs);
    end_obs = clamp_obstacle_to_bounds_padding(end, end_obs);
    harmonize_obstacle_exit_spacing(start, end, start_obs, end_obs)
}

fn clamp_obstacle_to_bounds_padding(endpoint: ResolvedEndpoint, obstacle: DrawRect) -> DrawRect {
    let Some(bounds) = endpoint.element_bounds else {
        return obstacle;
    };

    let p = ElbowConstants::BASE_PADDING;
    obstacle.copy_with(
        Some(obstacle.min_x.max(bounds.min_x - p)),
        Some(obstacle.min_y.max(bounds.min_y - p)),
        Some(obstacle.max_x.min(bounds.max_x + p)),
        Some(obstacle.max_y.min(bounds.max_y + p)),
    )
}

fn harmonize_obstacle_exit_spacing(
    start: ResolvedEndpoint,
    end: ResolvedEndpoint,
    start_obstacle: DrawRect,
    end_obstacle: DrawRect,
) -> ObstaclePair {
    let unchanged = ObstaclePair {
        start: start_obstacle,
        end: end_obstacle,
    };

    let Some(start_bounds) = start.element_bounds else {
        return unchanged;
    };
    let Some(end_bounds) = end.element_bounds else {
        return unchanged;
    };

    let spacing = resolve_shared_spacing(
        resolve_obstacle_spacing(start_bounds, start_obstacle, start.heading),
        resolve_obstacle_spacing(end_bounds, end_obstacle, end.heading),
        start.has_arrowhead,
        end.has_arrowhead,
    );
    let Some(spacing) = spacing else {
        return unchanged;
    };

    ObstaclePair {
        start: clamp_bounds(apply_obstacle_spacing(
            start_obstacle,
            start_bounds,
            start.heading,
            spacing,
        )),
        end: clamp_bounds(apply_obstacle_spacing(
            end_obstacle,
            end_bounds,
            end.heading,
            spacing,
        )),
    }
}

fn binding_gap(has_arrowhead: bool) -> f64 {
    ArrowBindingUtils::ELBOW_BINDING_GAP_BASE
        * if has_arrowhead {
            ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
        } else {
            ElbowConstants::ELBOW_NO_ARROWHEAD_GAP_MULTIPLIER
        }
}

fn head_padding(has_arrowhead: bool) -> f64 {
    (ElbowConstants::BASE_PADDING - binding_gap(has_arrowhead)).max(0.0)
}

fn min_binding_spacing(has_arrowhead: bool) -> f64 {
    let base = ArrowBindingUtils::ELBOW_BINDING_GAP_BASE;
    if has_arrowhead {
        base * ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
    } else {
        base
    }
}

fn resolve_obstacle_spacing(
    element_bounds: DrawRect,
    obstacle: DrawRect,
    heading: ElbowHeading,
) -> Option<f64> {
    let spacing = match heading {
        ElbowHeading::Up => element_bounds.min_y - obstacle.min_y,
        ElbowHeading::Right => obstacle.max_x - element_bounds.max_x,
        ElbowHeading::Down => obstacle.max_y - element_bounds.max_y,
        ElbowHeading::Left => element_bounds.min_x - obstacle.min_x,
    };

    if spacing.is_finite() && spacing > ElbowConstants::INTERSECTION_EPSILON {
        Some(spacing)
    } else {
        None
    }
}

fn apply_obstacle_spacing(
    obstacle: DrawRect,
    element_bounds: DrawRect,
    heading: ElbowHeading,
    spacing: f64,
) -> DrawRect {
    match heading {
        ElbowHeading::Up => {
            obstacle.copy_with(None, Some(element_bounds.min_y - spacing), None, None)
        }
        ElbowHeading::Right => {
            obstacle.copy_with(None, None, Some(element_bounds.max_x + spacing), None)
        }
        ElbowHeading::Down => {
            obstacle.copy_with(None, None, None, Some(element_bounds.max_y + spacing))
        }
        ElbowHeading::Left => {
            obstacle.copy_with(Some(element_bounds.min_x - spacing), None, None, None)
        }
    }
}

fn resolve_shared_spacing(
    start_spacing: Option<f64>,
    end_spacing: Option<f64>,
    start_has_arrowhead: bool,
    end_has_arrowhead: bool,
) -> Option<f64> {
    let (Some(start_spacing), Some(end_spacing)) = (start_spacing, end_spacing) else {
        return None;
    };

    let shared = start_spacing.min(end_spacing);
    if !shared.is_finite() {
        return None;
    }

    let min_allowed =
        min_binding_spacing(start_has_arrowhead).max(min_binding_spacing(end_has_arrowhead));
    Some(shared.max(min_allowed))
}

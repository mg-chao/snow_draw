#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use std::collections::{HashMap, HashSet};

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingUtils, ElementState,
};
use crate::draw::elements::types::arrow::arrow_data::ElbowFixedSegment;
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowheadStyle;

#[derive(Clone, Debug)]
pub struct ElbowEditContext {
    pub element: ElementState,
    pub elements_by_id: HashMap<String, ElementState>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
}

#[derive(Clone, Debug)]
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

#[derive(Clone, Debug)]
struct PerpendicularAdjustment {
    points: Vec<DrawPoint>,
    moved: bool,
    inserted: bool,
}

fn unchanged_adjustment(points: Vec<DrawPoint>) -> PerpendicularAdjustment {
    PerpendicularAdjustment {
        points,
        moved: false,
        inserted: false,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ElbowHeading {
    Right,
    Down,
    Left,
    Up,
}

impl ElbowHeading {
    fn is_horizontal(self) -> bool {
        matches!(self, Self::Right | Self::Left)
    }

    fn opposite(self) -> Self {
        match self {
            Self::Right => Self::Left,
            Self::Down => Self::Up,
            Self::Left => Self::Right,
            Self::Up => Self::Down,
        }
    }

    fn dx(self) -> f64 {
        match self {
            Self::Right => 1.0,
            Self::Left => -1.0,
            _ => 0.0,
        }
    }

    fn dy(self) -> f64 {
        match self {
            Self::Down => 1.0,
            Self::Up => -1.0,
            _ => 0.0,
        }
    }
}

#[derive(Clone, Copy)]
struct EndpointLocals {
    endpoint: DrawPoint,
    neighbor: DrawPoint,
    neighbor_index: usize,
    last_index: usize,
    desired_horizontal: bool,
}

pub fn ensure_perpendicular_bindings(
    context: &ElbowEditContext,
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
) -> FixedSegmentPathResult {
    let start_binding = context.start_binding.as_ref();
    let end_binding = context.end_binding.as_ref();
    if points.len() < 2 || (start_binding.is_none() && end_binding.is_none()) {
        return FixedSegmentPathResult::new(points, fixed_segments);
    }

    let space = ElementSpace::new(context.element.rotation, context.element.rect.center());
    let mut world_points: Vec<DrawPoint> = points.iter().map(|p| space.to_world(*p)).collect();
    let mut updated_fixed = fixed_segments;
    let mut local_points = points;

    let routed = route_elbow_arrow_baseline(
        space.to_world(local_points[0]),
        space.to_world(local_points[local_points.len() - 1]),
        start_binding,
        end_binding,
        &context.elements_by_id,
    );

    let has_baseline = routed.len() >= 3;
    let start_padding = if has_baseline && start_binding.is_some() {
        baseline_len(routed[0], routed[1])
    } else {
        None
    };
    let end_padding = if has_baseline && end_binding.is_some() {
        baseline_len(routed[routed.len() - 2], routed[routed.len() - 1])
    } else {
        None
    };

    for is_start in [true, false] {
        let binding = if is_start { start_binding } else { end_binding };
        let Some(binding) = binding else {
            continue;
        };

        let neighbor_axis = if is_start {
            fixed_segment_is_horizontal(&updated_fixed, 2)
        } else {
            let ni = usize::max(2, local_points.len().saturating_sub(2));
            fixed_segment_is_horizontal(&updated_fixed, ni).or_else(|| {
                if endpoint_has_corner(&local_points, false) {
                    fixed_segment_is_horizontal(&updated_fixed, ni.saturating_sub(1))
                } else {
                    None
                }
            })
        };

        let adjustment = adjust_perpendicular_endpoint(
            &world_points,
            binding,
            &context.elements_by_id,
            if is_start { start_padding } else { end_padding },
            if is_start {
                context.start_arrowhead
            } else {
                context.end_arrowhead
            } != ArrowheadStyle::None,
            &updated_fixed,
            is_start,
            neighbor_axis,
        );

        world_points = adjustment.points;
        if adjustment.inserted || adjustment.moved {
            local_points = world_points.iter().map(|p| space.from_world(*p)).collect();
            updated_fixed = if adjustment.inserted {
                reindex_fixed_segments(&local_points, &updated_fixed)
            } else {
                sync_fixed_segments_to_points(&local_points, &updated_fixed)
            };
        }
    }

    merge_fixed_segments_with_collinear_neighbors(local_points, updated_fixed, true)
}

fn adjust_perpendicular_endpoint(
    points: &[DrawPoint],
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, ElementState>,
    direction_padding: Option<f64>,
    has_arrowhead: bool,
    fixed_segments: &[ElbowFixedSegment],
    is_start: bool,
    fixed_neighbor_axis: Option<bool>,
) -> PerpendicularAdjustment {
    if points.len() < 2 {
        return unchanged_adjustment(points.to_vec());
    }

    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };
    let Some(heading) = resolve_bound_heading(binding, elements_by_id, endpoint) else {
        return unchanged_adjustment(points.to_vec());
    };

    let locals = resolve_endpoint_locals(points, heading, is_start);
    let resolved_padding = if direction_padding.is_none()
        || !direction_padding.unwrap_or_default().is_finite()
        || direction_padding.unwrap_or_default() <= ElbowConstants::DEDUP_THRESHOLD
    {
        ElbowConstants::DIRECTION_FIX_PADDING
    } else {
        ElbowConstants::DIRECTION_FIX_PADDING.max(direction_padding.unwrap_or_default())
    };

    let aligned = if locals.desired_horizontal {
        (locals.neighbor.y - locals.endpoint.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
    } else {
        (locals.neighbor.x - locals.endpoint.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
    };

    let direction_from = if is_start {
        locals.endpoint
    } else {
        locals.neighbor
    };
    let direction_to = if is_start {
        locals.neighbor
    } else {
        locals.endpoint
    };
    let direction_heading = if is_start {
        heading
    } else {
        heading.opposite()
    };
    let direction_ok = direction_matches(direction_from, direction_to, direction_heading);

    if let Some(fixed_neighbor_axis) = fixed_neighbor_axis {
        return adjust_preserved_neighbor(
            points,
            locals,
            heading,
            resolved_padding,
            fixed_segments,
            fixed_neighbor_axis,
            has_arrowhead,
            aligned,
            direction_ok,
            is_start,
            binding,
            elements_by_id,
        );
    }

    adjust_free_neighbor(
        points,
        locals,
        heading,
        resolved_padding,
        direction_padding,
        fixed_segments,
        aligned,
        direction_ok,
        is_start,
    )
}
fn adjust_preserved_neighbor(
    points: &[DrawPoint],
    locals: EndpointLocals,
    heading: ElbowHeading,
    resolved_padding: f64,
    fixed_segments: &[ElbowFixedSegment],
    fixed_neighbor_axis: bool,
    has_arrowhead: bool,
    aligned: bool,
    direction_ok: bool,
    is_start: bool,
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, ElementState>,
) -> PerpendicularAdjustment {
    let can_slide_neighbor = fixed_neighbor_axis == locals.desired_horizontal;
    let fixed_padding = fixed_neighbor_padding(has_arrowhead);

    let try_slide = |pts: &[DrawPoint], corner_inserted: bool| -> Option<PerpendicularAdjustment> {
        if !can_slide_neighbor {
            return None;
        }
        slide_endpoint_neighbor_to_padding(
            pts,
            heading,
            Some(fixed_padding),
            corner_inserted,
            is_start,
        )
    };

    if aligned && direction_ok {
        let corner_fixed_index = if is_start {
            2
        } else {
            points.len().saturating_sub(3)
        };
        let corner_inserted = endpoint_has_corner(points, is_start)
            && fixed_segment_is_horizontal(fixed_segments, corner_fixed_index).is_some();
        return try_slide(points, corner_inserted)
            .unwrap_or_else(|| unchanged_adjustment(points.to_vec()));
    }

    if !aligned && direction_ok {
        let inserted = insert_endpoint_corner(points, heading, locals.neighbor, is_start);
        if !inserted.inserted {
            return inserted;
        }
        let Some(slid) = try_slide(&inserted.points, true) else {
            return inserted;
        };
        return PerpendicularAdjustment {
            points: slid.points,
            moved: true,
            inserted: true,
        };
    }

    if !is_start
        && !direction_ok
        && !locals.desired_horizontal
        && fixed_neighbor_axis != locals.desired_horizontal
    {
        if let Some(snapped) = snap_end_point_to_fixed_axis_at_anchor(
            points,
            locals.neighbor_index,
            binding,
            elements_by_id,
        ) {
            return snapped;
        }
    }

    if aligned {
        return try_slide(points, false).unwrap_or_else(|| unchanged_adjustment(points.to_vec()));
    }

    insert_endpoint_direction_stub(
        points,
        heading,
        locals.neighbor,
        false,
        resolved_padding,
        is_start,
    )
}

fn adjust_free_neighbor(
    points: &[DrawPoint],
    locals: EndpointLocals,
    heading: ElbowHeading,
    resolved_padding: f64,
    direction_padding: Option<f64>,
    fixed_segments: &[ElbowFixedSegment],
    aligned: bool,
    direction_ok: bool,
    is_start: bool,
) -> PerpendicularAdjustment {
    let EndpointLocals {
        endpoint,
        neighbor,
        neighbor_index,
        last_index,
        desired_horizontal,
    } = locals;

    let mut stub_padding = resolved_padding;
    if !fixed_segments.is_empty() {
        let want_horizontal = !heading.is_horizontal();
        let iter: Box<dyn Iterator<Item = &ElbowFixedSegment>> = if is_start {
            Box::new(fixed_segments.iter())
        } else {
            Box::new(fixed_segments.iter().rev())
        };

        for segment in iter {
            if segment.index == 0 || segment.index >= points.len() {
                continue;
            }
            if segment_is_horizontal(segment.start, segment.end) != want_horizontal {
                continue;
            }
            let axis = segment_axis_value(segment.start, segment.end, want_horizontal);
            if stub_padding.is_finite() && stub_padding > 0.0 && axis.is_finite() {
                let max_padding = match heading {
                    ElbowHeading::Left => endpoint.x - axis,
                    ElbowHeading::Right => axis - endpoint.x,
                    ElbowHeading::Up => endpoint.y - axis,
                    ElbowHeading::Down => axis - endpoint.y,
                };
                if max_padding > ElbowConstants::DEDUP_THRESHOLD {
                    stub_padding = stub_padding.min(max_padding);
                }
            }
            break;
        }
    }

    if aligned && direction_ok {
        return slide_endpoint_to_padding(points, heading, direction_padding, is_start, None)
            .or_else(|| {
                let corner = if is_start {
                    Some(2)
                } else {
                    Some(last_index.saturating_sub(2))
                };
                slide_endpoint_to_padding(points, heading, direction_padding, is_start, corner)
            })
            .unwrap_or_else(|| unchanged_adjustment(points.to_vec()));
    }

    if aligned && !direction_ok {
        let mut updated = points.to_vec();
        updated[neighbor_index] =
            apply_endpoint_direction(neighbor, endpoint, heading, resolved_padding);
        return PerpendicularAdjustment {
            points: updated,
            moved: true,
            inserted: false,
        };
    }

    if points.len() > 2 {
        let adjacent_index = if is_start {
            neighbor_index + 1
        } else {
            neighbor_index.saturating_sub(1)
        };
        let adjacent_horizontal = if is_start {
            segment_is_horizontal(neighbor, points[adjacent_index])
        } else {
            segment_is_horizontal(points[adjacent_index], neighbor)
        };
        if adjacent_horizontal != desired_horizontal && direction_ok {
            let mut updated = points.to_vec();
            updated[neighbor_index] = if desired_horizontal {
                with_y(neighbor, endpoint.y)
            } else {
                with_x(neighbor, endpoint.x)
            };
            return PerpendicularAdjustment {
                points: updated,
                moved: true,
                inserted: false,
            };
        }
    }

    insert_endpoint_direction_stub(points, heading, neighbor, true, stub_padding, is_start)
}

fn slide_endpoint_to_padding(
    points: &[DrawPoint],
    heading: ElbowHeading,
    desired_length: Option<f64>,
    is_start: bool,
    corner_index: Option<usize>,
) -> Option<PerpendicularAdjustment> {
    let Some(desired_length) = desired_length else {
        return None;
    };
    if !desired_length.is_finite() || desired_length <= ElbowConstants::DEDUP_THRESHOLD {
        return None;
    }

    let horizontal = heading.is_horizontal();
    let last = points.len().saturating_sub(1);
    let neighbor = if is_start { 1 } else { last.saturating_sub(1) };

    if corner_index.is_none() {
        if points.len() > 2 {
            let adjacent = if is_start {
                neighbor + 1
            } else {
                neighbor.saturating_sub(1)
            };
            if segment_is_horizontal(points[neighbor], points[adjacent]) != horizontal {
                return None;
            }
        }
        return slide_along_heading_axis(
            points,
            heading,
            desired_length,
            is_start,
            neighbor,
            None,
            None,
        );
    }

    if points.len() < 4 {
        return None;
    }

    let corner = corner_index.unwrap_or(0);
    let outer = if is_start {
        corner + 1
    } else {
        corner.saturating_sub(1)
    };
    if outer >= points.len() {
        return None;
    }

    let main = |p: DrawPoint| if horizontal { p.x } else { p.y };
    let cross = |p: DrawPoint| if horizontal { p.y } else { p.x };
    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };

    if (cross(points[neighbor]) - cross(endpoint)).abs() > ElbowConstants::DEDUP_THRESHOLD
        || (main(points[corner]) - main(points[neighbor])).abs() > ElbowConstants::DEDUP_THRESHOLD
        || (cross(points[outer]) - cross(points[corner])).abs() > ElbowConstants::DEDUP_THRESHOLD
    {
        return None;
    }

    slide_along_heading_axis(
        points,
        heading,
        desired_length,
        is_start,
        neighbor,
        Some(corner),
        Some(outer),
    )
}

fn slide_along_heading_axis(
    points: &[DrawPoint],
    heading: ElbowHeading,
    desired_length: f64,
    is_start: bool,
    neighbor_index: usize,
    corner_index: Option<usize>,
    reference_index: Option<usize>,
) -> Option<PerpendicularAdjustment> {
    if points.len() < 2 || neighbor_index >= points.len() {
        return None;
    }
    if corner_index.is_some_and(|idx| idx >= points.len())
        || reference_index.is_some_and(|idx| idx >= points.len())
    {
        return None;
    }

    let horizontal = heading.is_horizontal();
    let main = |p: DrawPoint| if horizontal { p.x } else { p.y };
    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };
    let neighbor = points[neighbor_index];
    let target_main = main(offset_point(endpoint, heading, desired_length));

    if (main(neighbor) - target_main).abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return None;
    }

    if let Some(reference_index) = reference_index {
        let reference = points[reference_index];
        let original_delta = if is_start {
            main(reference) - main(neighbor)
        } else {
            main(neighbor) - main(reference)
        };
        let new_delta = if is_start {
            main(reference) - target_main
        } else {
            target_main - main(reference)
        };
        if original_delta.abs() <= ElbowConstants::DEDUP_THRESHOLD
            || new_delta.abs() <= ElbowConstants::DEDUP_THRESHOLD
            || original_delta.signum() != new_delta.signum()
            || new_delta.abs() <= original_delta.abs() * 0.5
        {
            return None;
        }
    }

    let mut updated = points.to_vec();
    updated[neighbor_index] = if horizontal {
        with_x(neighbor, target_main)
    } else {
        with_y(neighbor, target_main)
    };
    if let Some(corner_index) = corner_index {
        updated[corner_index] = if horizontal {
            with_x(points[corner_index], target_main)
        } else {
            with_y(points[corner_index], target_main)
        };
    }

    Some(PerpendicularAdjustment {
        points: updated,
        moved: true,
        inserted: false,
    })
}
fn direction_matches(from: DrawPoint, to: DrawPoint, heading: ElbowHeading) -> bool {
    match heading {
        ElbowHeading::Right => to.x - from.x > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Left => from.x - to.x > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Down => to.y - from.y > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Up => from.y - to.y > ElbowConstants::DEDUP_THRESHOLD,
    }
}

fn apply_endpoint_direction(
    neighbor: DrawPoint,
    endpoint: DrawPoint,
    heading: ElbowHeading,
    padding: f64,
) -> DrawPoint {
    let target = offset_point(endpoint, heading, padding);
    let horizontal = heading.is_horizontal();
    let neighbor_val = if horizontal { neighbor.x } else { neighbor.y };
    let target_val = if horizontal { target.x } else { target.y };
    let endpoint_val = if horizontal { endpoint.x } else { endpoint.y };

    let delta_neighbor = neighbor_val - endpoint_val;
    let delta_target = target_val - endpoint_val;
    let already_past = delta_neighbor.signum() == delta_target.signum()
        && delta_neighbor.abs() >= delta_target.abs();

    if already_past {
        neighbor
    } else if horizontal {
        with_x(neighbor, target_val)
    } else {
        with_y(neighbor, target_val)
    }
}

fn slide_endpoint_neighbor_to_padding(
    points: &[DrawPoint],
    heading: ElbowHeading,
    desired_length: Option<f64>,
    corner_inserted: bool,
    is_start: bool,
) -> Option<PerpendicularAdjustment> {
    let min_points = if corner_inserted { 4 } else { 3 };
    let Some(desired_length) = desired_length else {
        return None;
    };
    if points.len() < min_points
        || !desired_length.is_finite()
        || desired_length <= ElbowConstants::DEDUP_THRESHOLD
    {
        return None;
    }

    let last = points.len() - 1;
    let neighbor = if is_start {
        if corner_inserted {
            2
        } else {
            1
        }
    } else if corner_inserted {
        last.saturating_sub(2)
    } else {
        last.saturating_sub(1)
    };
    if neighbor == 0 || neighbor >= last {
        return None;
    }

    let reference = if is_start {
        neighbor + 1
    } else {
        neighbor.saturating_sub(1)
    };
    if reference > last {
        return None;
    }

    let corner = if corner_inserted {
        Some(if is_start { 1 } else { last - 1 })
    } else {
        None
    };

    slide_along_heading_axis(
        points,
        heading,
        desired_length,
        is_start,
        neighbor,
        corner,
        Some(reference),
    )
}

fn insert_endpoint_direction_stub(
    points: &[DrawPoint],
    heading: ElbowHeading,
    neighbor: DrawPoint,
    allow_extend: bool,
    padding: f64,
    is_start: bool,
) -> PerpendicularAdjustment {
    if points.len() < 2 {
        return unchanged_adjustment(points.to_vec());
    }

    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };
    let stub = offset_point(endpoint, heading, padding);
    let connector = if heading.is_horizontal() {
        DrawPoint::new(stub.x, neighbor.y)
    } else {
        DrawPoint::new(neighbor.x, stub.y)
    };

    let mut updated = points.to_vec();
    let ni = if is_start { 1 } else { updated.len() - 2 };
    let mut insert_index = if is_start { 1 } else { updated.len() - 1 };
    let mut moved = false;
    let mut inserted = false;

    if allow_extend && points.len() > 2 {
        let adjacent = if is_start {
            points[2]
        } else {
            points[points.len() - 3]
        };
        let adj_h = segment_is_horizontal(neighbor, adjacent);
        let aligned = if adj_h {
            (connector.y - neighbor.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
        } else {
            (connector.x - neighbor.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        };
        if aligned {
            updated[ni] = connector;
            moved = true;
        }
    }

    let has_stub = manhattan_distance(stub, endpoint) > ElbowConstants::DEDUP_THRESHOLD;
    let has_connector = !moved
        && manhattan_distance(connector, neighbor) > ElbowConstants::DEDUP_THRESHOLD
        && manhattan_distance(connector, stub) > ElbowConstants::DEDUP_THRESHOLD;

    let mut to_insert = Vec::new();
    if is_start {
        if has_stub {
            to_insert.push(stub);
        }
        if has_connector {
            to_insert.push(connector);
        }
    } else {
        if has_connector {
            to_insert.push(connector);
        }
        if has_stub {
            to_insert.push(stub);
        }
    }

    for point in to_insert {
        updated.insert(insert_index, point);
        insert_index += 1;
        inserted = true;
    }

    PerpendicularAdjustment {
        points: updated,
        moved,
        inserted,
    }
}

fn insert_endpoint_corner(
    points: &[DrawPoint],
    heading: ElbowHeading,
    neighbor: DrawPoint,
    is_start: bool,
) -> PerpendicularAdjustment {
    if points.len() < 2 {
        return unchanged_adjustment(points.to_vec());
    }

    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };
    let corner = if heading.is_horizontal() {
        DrawPoint::new(neighbor.x, endpoint.y)
    } else {
        DrawPoint::new(endpoint.x, neighbor.y)
    };

    if manhattan_distance(corner, endpoint) <= ElbowConstants::DEDUP_THRESHOLD
        || manhattan_distance(corner, neighbor) <= ElbowConstants::DEDUP_THRESHOLD
    {
        return unchanged_adjustment(points.to_vec());
    }

    let mut updated = points.to_vec();
    let insert_index = if is_start { 1 } else { updated.len() - 1 };
    updated.insert(insert_index, corner);
    PerpendicularAdjustment {
        points: updated,
        moved: false,
        inserted: true,
    }
}

fn snap_end_point_to_fixed_axis_at_anchor(
    points: &[DrawPoint],
    neighbor_index: usize,
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, ElementState>,
) -> Option<PerpendicularAdjustment> {
    if neighbor_index == 0 || neighbor_index >= points.len().saturating_sub(1) {
        return None;
    }

    let element = elements_by_id.get(&binding.element_id)?;
    let anchor = ArrowBindingUtils::resolve_elbow_anchor_point(binding, element)?;
    if !anchor.x.is_finite() || !anchor.y.is_finite() {
        return None;
    }

    if (anchor.x - points[neighbor_index].x).abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return None;
    }

    let slid = slide_run(points, neighbor_index, false, anchor.x, 1);
    if !slid.moved {
        return None;
    }

    Some(PerpendicularAdjustment {
        points: slid.points,
        moved: true,
        inserted: false,
    })
}

fn resolve_endpoint_locals(
    points: &[DrawPoint],
    heading: ElbowHeading,
    is_start: bool,
) -> EndpointLocals {
    let last = points.len() - 1;
    let neighbor_index = if is_start { 1 } else { last - 1 };
    EndpointLocals {
        endpoint: if is_start { points[0] } else { points[last] },
        neighbor: points[neighbor_index],
        neighbor_index,
        last_index: last,
        desired_horizontal: heading.is_horizontal(),
    }
}

fn endpoint_has_corner(points: &[DrawPoint], is_start: bool) -> bool {
    if points.len() < 3 {
        return false;
    }
    let (a, b, c) = if is_start {
        (points[0], points[1], points[2])
    } else {
        (
            points[points.len() - 3],
            points[points.len() - 2],
            points[points.len() - 1],
        )
    };
    let ab_horizontal = (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
    let bc_horizontal = (b.y - c.y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
    ab_horizontal != bc_horizontal
}

fn resolve_bound_heading(
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, ElementState>,
    point: DrawPoint,
) -> Option<ElbowHeading> {
    let element = elements_by_id.get(&binding.element_id)?;
    let bounds = compute_element_world_aabb(element);
    let anchor = ArrowBindingUtils::resolve_elbow_anchor_point(binding, element).unwrap_or(point);
    Some(heading_for_point_on_bounds(bounds, anchor))
}

fn route_elbow_arrow_baseline(
    start: DrawPoint,
    end: DrawPoint,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    elements_by_id: &HashMap<String, ElementState>,
) -> Vec<DrawPoint> {
    if (start.x - end.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        || (start.y - end.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
    {
        return vec![start, end];
    }

    let mut prefer_horizontal = (start.x - end.x).abs() >= (start.y - end.y).abs();
    if let Some(binding) = start_binding {
        if let Some(heading) = resolve_bound_heading(binding, elements_by_id, start) {
            prefer_horizontal = heading.is_horizontal();
        }
    }

    let corner = if prefer_horizontal {
        DrawPoint::new(end.x, start.y)
    } else {
        DrawPoint::new(start.x, end.y)
    };
    vec![start, corner, end]
}
fn heading_for_point_on_bounds(bounds: DrawRect, point: DrawPoint) -> ElbowHeading {
    const EPS: f64 = 1e-6;
    let center = bounds.center();
    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let width = bounds.width().abs();
    let height = bounds.height().abs();

    if width <= EPS || height <= EPS {
        return ElbowHeading::Left;
    }

    let horizontal_weight = dx.abs() * height;
    let vertical_weight = dy.abs() * width;
    let tolerance = EPS * width * height;

    if dy <= EPS && dy >= -height - EPS && horizontal_weight <= vertical_weight + tolerance {
        return ElbowHeading::Up;
    }
    if dx >= -EPS && dx <= width + EPS && vertical_weight <= horizontal_weight + tolerance {
        return ElbowHeading::Right;
    }
    if dy >= -EPS && dy <= height + EPS && horizontal_weight <= vertical_weight + tolerance {
        return ElbowHeading::Down;
    }
    ElbowHeading::Left
}

fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }
    let rect = element.rect;
    let center = rect.center();
    let half_width = rect.width().abs() / 2.0;
    let half_height = rect.height().abs() / 2.0;
    let cos_theta = element.rotation.cos().abs();
    let sin_theta = element.rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;
    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

fn fixed_neighbor_padding(has_arrowhead: bool) -> f64 {
    let padding = head_padding(has_arrowhead);
    if !padding.is_finite() || padding <= ElbowConstants::DEDUP_THRESHOLD {
        ElbowConstants::DIRECTION_FIX_PADDING
    } else {
        ElbowConstants::DIRECTION_FIX_PADDING.max(padding)
    }
}

fn head_padding(has_arrowhead: bool) -> f64 {
    0.0f64.max(ElbowConstants::BASE_PADDING - binding_gap(has_arrowhead))
}

fn binding_gap(has_arrowhead: bool) -> f64 {
    ArrowBindingUtils::ELBOW_BINDING_GAP_BASE
        * if has_arrowhead {
            ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
        } else {
            ElbowConstants::ELBOW_NO_ARROWHEAD_GAP_MULTIPLIER
        }
}

fn baseline_len(a: DrawPoint, b: DrawPoint) -> Option<f64> {
    let d = manhattan_distance(a, b);
    if d.is_finite() && d > ElbowConstants::DEDUP_THRESHOLD {
        Some(d)
    } else {
        None
    }
}

fn fixed_segment_is_horizontal(fixed_segments: &[ElbowFixedSegment], index: usize) -> Option<bool> {
    fixed_segments
        .iter()
        .find(|segment| segment.index == index)
        .map(|segment| segment_is_horizontal(segment.start, segment.end))
}

fn merge_fixed_segments_with_collinear_neighbors(
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
    allow_direction_flip: bool,
) -> FixedSegmentPathResult {
    let cleaned = deduplicate_adjacent_points(&points);
    let reindexed = reindex_fixed_segments(&cleaned, &fixed_segments);
    let updated_fixed = if reindexed.len() == fixed_segments.len() {
        reindexed
    } else {
        sync_fixed_segments_to_points(&cleaned, &fixed_segments)
    };
    FixedSegmentPathResult::new(cleaned, updated_fixed)
}

fn sync_fixed_segments_to_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }
    let mut result = Vec::new();
    for segment in fixed_segments {
        if !is_interior_segment_index(segment.index, points.len()) {
            continue;
        }
        let start = points[segment.index - 1];
        let end = points[segment.index];
        if is_degenerate_segment(start, end) {
            continue;
        }
        result.push(ElbowFixedSegment {
            index: segment.index,
            start,
            end,
        });
    }
    result
}

fn reindex_fixed_segments(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }

    let mut result = Vec::new();
    let mut used = HashSet::new();
    for segment in fixed_segments {
        let horizontal = segment_is_horizontal(segment.start, segment.end);
        let axis_value = segment_axis_value(segment.start, segment.end, horizontal);
        let index = select_segment_index(
            points,
            horizontal,
            segment.index,
            axis_value,
            f64::INFINITY,
            &used,
        );

        let Some(index) = index else {
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
        used.insert(index);
        result.push(ElbowFixedSegment { index, start, end });
    }

    result
}

fn select_segment_index(
    points: &[DrawPoint],
    is_horizontal: bool,
    preferred_index: usize,
    axis_value: f64,
    axis_tolerance: f64,
    used_indices: &HashSet<usize>,
) -> Option<usize> {
    if points.len() < 2 {
        return None;
    }

    let mut best_index = None;
    let mut best_axis_delta = f64::INFINITY;
    let mut best_index_delta = f64::INFINITY;

    for i in 2..points.len().saturating_sub(1) {
        if used_indices.contains(&i) {
            continue;
        }
        if segment_is_horizontal(points[i - 1], points[i]) != is_horizontal {
            continue;
        }

        let candidate_axis = segment_axis_value(points[i - 1], points[i], is_horizontal);
        let axis_delta = (candidate_axis - axis_value).abs();
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

fn slide_run(
    points: &[DrawPoint],
    start_index: usize,
    horizontal: bool,
    target: f64,
    direction: i32,
) -> RunSlideResult {
    if start_index >= points.len() || (direction != 1 && direction != -1) {
        return RunSlideResult {
            points: points.to_vec(),
            moved: false,
        };
    }

    let current = if horizontal {
        points[start_index].y
    } else {
        points[start_index].x
    };
    if (current - target).abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return RunSlideResult {
            points: points.to_vec(),
            moved: false,
        };
    }

    let run = walk_run(points, start_index, direction, horizontal);
    let mut updated = points.to_vec();
    for idx in run {
        updated[idx] = if horizontal {
            with_y(updated[idx], target)
        } else {
            with_x(updated[idx], target)
        };
    }
    RunSlideResult {
        points: updated,
        moved: true,
    }
}

fn walk_run(
    points: &[DrawPoint],
    start_index: usize,
    direction: i32,
    horizontal: bool,
) -> Vec<usize> {
    let mut indices = vec![start_index];
    let mut i = start_index as isize;
    loop {
        let next = i + direction as isize;
        if next < 0 || next >= points.len() as isize {
            break;
        }
        let a = points[i as usize];
        let b = points[next as usize];
        let segment_h = (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
        if segment_h != horizontal {
            break;
        }
        indices.push(next as usize);
        i = next;
    }
    indices
}

#[derive(Clone, Debug)]
struct RunSlideResult {
    points: Vec<DrawPoint>,
    moved: bool,
}

fn deduplicate_adjacent_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.is_empty() {
        return Vec::new();
    }

    let mut cleaned = vec![points[0]];
    for &current in points.iter().skip(1) {
        let last = *cleaned.last().unwrap_or(&current);
        if current == last {
            continue;
        }
        if manhattan_distance(last, current) <= ElbowConstants::DEDUP_THRESHOLD {
            continue;
        }
        cleaned.push(current);
    }

    if cleaned.len() < 2 {
        vec![points[0], *points.last().unwrap_or(&points[0])]
    } else {
        cleaned
    }
}

fn is_interior_segment_index(index: usize, point_count: usize) -> bool {
    index > 1 && index < point_count.saturating_sub(1)
}

fn is_degenerate_segment(start: DrawPoint, end: DrawPoint) -> bool {
    manhattan_distance(start, end) <= ElbowConstants::DEDUP_THRESHOLD
}

fn segment_axis_value(start: DrawPoint, end: DrawPoint, horizontal: bool) -> f64 {
    if horizontal {
        (start.y + end.y) / 2.0
    } else {
        (start.x + end.x) / 2.0
    }
}

fn segment_is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
    let dx = (a.x - b.x).abs();
    let dy = (a.y - b.y).abs();
    if dy <= ElbowConstants::DEDUP_THRESHOLD {
        true
    } else if dx <= ElbowConstants::DEDUP_THRESHOLD {
        false
    } else {
        dy <= dx
    }
}

fn offset_point(point: DrawPoint, heading: ElbowHeading, distance: f64) -> DrawPoint {
    DrawPoint::new(
        point.x + heading.dx() * distance,
        point.y + heading.dy() * distance,
    )
}

fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
    (a.x - b.x).abs() + (a.y - b.y).abs()
}

fn with_x(point: DrawPoint, x: f64) -> DrawPoint {
    point.copy_with(Some(x), None, None, None)
}

fn with_y(point: DrawPoint, y: f64) -> DrawPoint {
    point.copy_with(None, Some(y), None, None)
}

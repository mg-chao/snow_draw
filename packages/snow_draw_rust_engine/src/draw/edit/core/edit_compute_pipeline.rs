#![allow(dead_code)]

use crate::draw::edit::core::arrow_binding_cleanup::unbind_arrow_like_elements;
use crate::draw::edit::core::edit_computed_result::EditComputedResult as DomainEditComputedResult;
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingMode, ArrowBindingUtils,
};
use crate::draw::elements::types::arrow::arrow_binding_resolver::{
    ArrowBindingResolver, ArrowBindingResolverDelegate, ArrowLikeData as ResolverArrowLikeData,
    ElbowEditResult as ResolverElbowEditResult, ElementStateLike,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowBindingMode as DomainArrowBindingMode, ArrowData,
    ArrowDataPatch, ElbowFixedSegment as ArrowElbowFixedSegment,
    NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::elbow::elbow_editing::{
    compute_elbow_edit as compute_domain_elbow_edit,
    transform_fixed_segments as transform_domain_fixed_segments,
    BindingOverride as ElbowBindingOverride,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment as LineElbowFixedSegment;
use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

/// Shared geometry result for edit preview and commit.
///
/// Mirrors the Dart `EditComputedResult` shape used by edit operations.
#[derive(Clone, Debug, PartialEq)]
pub struct EditComputedResult<E> {
    pub updated_elements: HashMap<String, E>,
    pub ordered_element_ids: Option<Vec<String>>,
    pub multi_select_bounds: Option<DrawRect>,
    pub multi_select_rotation: Option<f64>,
}

impl<E> EditComputedResult<E> {
    pub fn new(
        updated_elements: HashMap<String, E>,
        ordered_element_ids: Option<Vec<String>>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
    ) -> Self {
        Self {
            updated_elements,
            ordered_element_ids,
            multi_select_bounds,
            multi_select_rotation,
        }
    }
}

/// Minimum draw-state view required by [`EditComputePipeline`].
pub trait EditComputeState<E> {
    /// Returns the current document element map by element id.
    fn element_map(&self) -> &HashMap<String, E>;
}

/// Arrow-binding cleanup hook executed before binding resolution.
///
/// The dedicated cleanup module is translated separately, so the pipeline uses
/// this trait to stay composable and compile-friendly in the meantime.
pub trait ArrowBindingCleanup<E> {
    fn unbind_arrow_like_elements(
        &self,
        transformed_elements: &HashMap<String, E>,
        base_elements: &HashMap<String, E>,
    ) -> HashMap<String, E>;
}

/// Default cleanup strategy that leaves transformed elements unchanged.
#[derive(Clone, Copy, Debug, Default)]
pub struct NoopArrowBindingCleanup;

impl<E> ArrowBindingCleanup<E> for NoopArrowBindingCleanup {
    fn unbind_arrow_like_elements(
        &self,
        _transformed_elements: &HashMap<String, E>,
        _base_elements: &HashMap<String, E>,
    ) -> HashMap<String, E> {
        HashMap::new()
    }
}

/// Shared post-geometry pipeline for standard edit operations.
///
/// After an operation applies geometry (move/resize/rotate), the remaining
/// pipeline is identical: unbind arrows, resolve bindings, and package the
/// result.
#[derive(Clone, Copy, Debug, Default)]
pub struct EditComputePipeline;

impl EditComputePipeline {
    /// Runs the shared post-geometry pipeline on `updated_by_id`.
    ///
    /// Returns `None` when `updated_by_id` is empty.
    /// Uses [`NoopArrowBindingCleanup`] for the cleanup step.
    pub fn finalize<S, E, D>(
        state: &S,
        updated_by_id: HashMap<String, E>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
        skip_binding_update: Option<&dyn Fn(&str, &E) -> bool>,
        binding_delegate: &D,
    ) -> Option<EditComputedResult<E>>
    where
        S: EditComputeState<E>,
        E: ElementStateLike,
        D: ArrowBindingResolverDelegate<E>,
    {
        Self::finalize_with_cleanup(
            state,
            updated_by_id,
            multi_select_bounds,
            multi_select_rotation,
            skip_binding_update,
            binding_delegate,
            &NoopArrowBindingCleanup,
        )
    }

    /// Runs the shared post-geometry pipeline with an explicit cleanup hook.
    pub fn finalize_with_cleanup<S, E, D, C>(
        state: &S,
        updated_by_id: HashMap<String, E>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
        skip_binding_update: Option<&dyn Fn(&str, &E) -> bool>,
        binding_delegate: &D,
        cleanup: &C,
    ) -> Option<EditComputedResult<E>>
    where
        S: EditComputeState<E>,
        E: ElementStateLike,
        D: ArrowBindingResolverDelegate<E>,
        C: ArrowBindingCleanup<E>,
    {
        if updated_by_id.is_empty() {
            return None;
        }

        let base_elements = state.element_map();
        let mut merged = updated_by_id;

        let cleanup_updates = cleanup.unbind_arrow_like_elements(&merged, base_elements);
        merged.extend(cleanup_updates);

        let changed_element_ids = merged.keys().cloned().collect::<HashSet<_>>();
        let skip_arrow_ids = merged
            .iter()
            .filter_map(|(id, element)| element.arrow_like_data().is_some().then(|| id.clone()))
            .collect::<HashSet<_>>();
        let binding_updates = ArrowBindingResolver::INSTANCE.resolve_with_skip(
            base_elements,
            &merged,
            &changed_element_ids,
            binding_delegate,
            &skip_arrow_ids,
        );

        for (id, element) in binding_updates {
            let should_skip = skip_binding_update
                .map(|predicate| predicate(id.as_str(), &element))
                .unwrap_or(false);
            if should_skip {
                continue;
            }
            merged.insert(id, element);
        }

        Some(EditComputedResult::new(
            merged,
            None,
            multi_select_bounds,
            multi_select_rotation,
        ))
    }
}

/// Runs the finalized post-geometry pipeline for domain `ElementState`.
///
/// This mirrors Dart's `EditComputePipeline.finalize`: unbind transformed
/// arrow-like elements, resolve binding updates, optionally skip binding
/// updates for selected elements, and package the merged result.
pub fn finalize_domain_result(
    base_elements: &HashMap<String, DomainElementState>,
    updated_by_id: HashMap<String, DomainElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
    skip_binding_update: Option<&dyn Fn(&str, &DomainElementState) -> bool>,
) -> Option<DomainEditComputedResult> {
    if updated_by_id.is_empty() {
        return None;
    }

    let mut merged = updated_by_id;
    let cleanup_updates = unbind_arrow_like_elements(&merged, base_elements);
    merged.extend(cleanup_updates);

    let base_for_resolver = to_resolver_map(base_elements);
    let merged_for_resolver = to_resolver_map(&merged);
    let changed_element_ids = merged_for_resolver.keys().cloned().collect::<HashSet<_>>();
    let skip_arrow_ids = merged_for_resolver
        .iter()
        .filter_map(|(id, element)| element.arrow_like_data().is_some().then(|| id.clone()))
        .collect::<HashSet<_>>();
    let delegate = DomainArrowBindingResolverDelegate;
    let binding_updates = ArrowBindingResolver::INSTANCE.resolve_with_skip(
        &base_for_resolver,
        &merged_for_resolver,
        &changed_element_ids,
        &delegate,
        &skip_arrow_ids,
    );

    for (id, element) in binding_updates {
        let updated_element = element.into_domain();
        let should_skip = skip_binding_update
            .map(|predicate| predicate(id.as_str(), &updated_element))
            .unwrap_or(false);
        if should_skip {
            continue;
        }
        merged.insert(id, updated_element);
    }

    Some(DomainEditComputedResult::new(
        merged,
        None,
        multi_select_bounds,
        multi_select_rotation,
    ))
}

fn to_resolver_map(
    map: &HashMap<String, DomainElementState>,
) -> HashMap<String, ResolverElementState> {
    map.iter()
        .map(|(id, element)| {
            (
                id.clone(),
                ResolverElementState::from_domain(element.clone()),
            )
        })
        .collect()
}

#[derive(Clone, Debug, PartialEq)]
struct ResolverFixedSegment {
    index: usize,
    start: DrawPoint,
    end: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
enum ResolverDomainArrowData {
    Arrow {
        data: ArrowData,
        start_binding: Option<ArrowBinding>,
        end_binding: Option<ArrowBinding>,
        fixed_segments: Option<Vec<ResolverFixedSegment>>,
    },
    Line {
        data: LineData,
        fixed_segments: Option<Vec<ResolverFixedSegment>>,
    },
}

impl ResolverDomainArrowData {
    fn from_arrow(data: ArrowData) -> Self {
        let start_binding = data.start_binding.as_ref().map(domain_binding_to_resolver);
        let end_binding = data.end_binding.as_ref().map(domain_binding_to_resolver);
        let fixed_segments = data.fixed_segments.as_deref().map(|segments| {
            segments
                .iter()
                .cloned()
                .map(arrow_fixed_to_resolver)
                .collect()
        });
        Self::Arrow {
            data,
            start_binding,
            end_binding,
            fixed_segments,
        }
    }

    fn from_line(data: LineData) -> Self {
        let fixed_segments = data.fixed_segments.as_deref().map(|segments| {
            segments
                .iter()
                .cloned()
                .map(line_fixed_to_resolver)
                .collect()
        });
        Self::Line {
            data,
            fixed_segments,
        }
    }

    fn into_domain_arc(self) -> Arc<dyn CoreElementData> {
        match self {
            Self::Arrow { data, .. } => Arc::new(data),
            Self::Line { data, .. } => Arc::new(data),
        }
    }
}

impl ResolverArrowLikeData for ResolverDomainArrowData {
    type FixedSegment = ResolverFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        match self {
            Self::Arrow { data, .. } => &data.points,
            Self::Line { data, .. } => &data.points,
        }
    }

    fn arrow_type(&self) -> ArrowType {
        match self {
            Self::Arrow { data, .. } => data.arrow_type,
            Self::Line { data, .. } => data.arrow_type,
        }
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::Arrow { data, .. } => data.start_arrowhead,
            Self::Line { data, .. } => data.start_arrowhead,
        }
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::Arrow { data, .. } => data.end_arrowhead,
            Self::Line { data, .. } => data.end_arrowhead,
        }
    }

    fn start_binding(&self) -> Option<&ArrowBinding> {
        match self {
            Self::Arrow { start_binding, .. } => start_binding.as_ref(),
            Self::Line { data, .. } => data.start_binding.as_ref(),
        }
    }

    fn end_binding(&self) -> Option<&ArrowBinding> {
        match self {
            Self::Arrow { end_binding, .. } => end_binding.as_ref(),
            Self::Line { data, .. } => data.end_binding.as_ref(),
        }
    }

    fn fixed_segments(&self) -> Option<&[Self::FixedSegment]> {
        match self {
            Self::Arrow { fixed_segments, .. } => fixed_segments.as_deref(),
            Self::Line { fixed_segments, .. } => fixed_segments.as_deref(),
        }
    }

    fn with_points(&self, points: Vec<DrawPoint>) -> Self {
        match self {
            Self::Arrow { data, .. } => Self::from_arrow(data.copy_with(ArrowDataPatch {
                points: Some(points),
                ..ArrowDataPatch::default()
            })),
            Self::Line { data, .. } => Self::from_line(data.copy_with(LineDataPatch {
                points: Some(points),
                ..LineDataPatch::default()
            })),
        }
    }

    fn with_elbow_edit(
        &self,
        points: Vec<DrawPoint>,
        fixed_segments: Option<Vec<Self::FixedSegment>>,
        start_is_special: Option<bool>,
        end_is_special: Option<bool>,
    ) -> Self {
        match self {
            Self::Arrow { data, .. } => {
                let normalized_fixed_segments = fixed_segments.map(|segments| {
                    segments
                        .into_iter()
                        .map(resolver_fixed_to_arrow)
                        .collect::<Vec<_>>()
                });
                Self::from_arrow(data.copy_with(ArrowDataPatch {
                    points: Some(points),
                    fixed_segments: match normalized_fixed_segments {
                        Some(value) => ArrowNullableField::Value(value),
                        None => ArrowNullableField::Null,
                    },
                    start_is_special: match start_is_special {
                        Some(value) => ArrowNullableField::Value(value),
                        None => ArrowNullableField::Null,
                    },
                    end_is_special: match end_is_special {
                        Some(value) => ArrowNullableField::Value(value),
                        None => ArrowNullableField::Null,
                    },
                    ..ArrowDataPatch::default()
                }))
            }
            Self::Line { data, .. } => {
                let normalized_fixed_segments = fixed_segments.map(|segments| {
                    segments
                        .into_iter()
                        .map(resolver_fixed_to_line)
                        .collect::<Vec<_>>()
                });
                Self::from_line(data.copy_with(LineDataPatch {
                    points: Some(points),
                    fixed_segments: match normalized_fixed_segments {
                        Some(value) => ArrowLikeNullableField::Value(value),
                        None => ArrowLikeNullableField::Null,
                    },
                    start_is_special: match start_is_special {
                        Some(value) => ArrowLikeNullableField::Value(value),
                        None => ArrowLikeNullableField::Null,
                    },
                    end_is_special: match end_is_special {
                        Some(value) => ArrowLikeNullableField::Value(value),
                        None => ArrowLikeNullableField::Null,
                    },
                    ..LineDataPatch::default()
                }))
            }
        }
    }
}

#[derive(Clone, Debug)]
struct ResolverElementState {
    element: DomainElementState,
    arrow_data: Option<ResolverDomainArrowData>,
}

impl ResolverElementState {
    fn from_domain(element: DomainElementState) -> Self {
        let arrow_data = match element.type_id().as_str() {
            ArrowData::TYPE_ID_TOKEN => ArrowData::from_json_value(&element.data.to_json_value())
                .ok()
                .map(ResolverDomainArrowData::from_arrow),
            LineData::TYPE_ID_TOKEN => LineData::from_json_value(&element.data.to_json_value())
                .ok()
                .map(ResolverDomainArrowData::from_line),
            _ => None,
        };

        Self {
            element,
            arrow_data,
        }
    }

    fn into_domain(self) -> DomainElementState {
        self.element
    }
}

impl ElementStateLike for ResolverElementState {
    type ArrowData = ResolverDomainArrowData;

    fn id(&self) -> &str {
        self.element.id.as_str()
    }

    fn rect(&self) -> DrawRect {
        self.element.rect
    }

    fn rotation(&self) -> f64 {
        self.element.rotation
    }

    fn arrow_like_data(&self) -> Option<&Self::ArrowData> {
        self.arrow_data.as_ref()
    }

    fn copy_with_rect_and_data(&self, rect: DrawRect, data: Self::ArrowData) -> Self {
        let next_element = self.element.copy_with(
            None,
            Some(rect),
            None,
            None,
            None,
            Some(data.clone().into_domain_arc()),
        );
        Self {
            element: next_element,
            arrow_data: Some(data),
        }
    }
}

impl crate::draw::elements::types::arrow::elbow::elbow_edit_pipeline::ElbowPipelineElement
    for ResolverElementState
{
    fn rect(&self) -> DrawRect {
        self.element.rect
    }

    fn rotation(&self) -> f64 {
        self.element.rotation
    }

    fn model_element(&self) -> Option<&crate::draw::models::element_state::ElementState> {
        Some(&self.element)
    }

    fn previous_arrow_data(&self) -> Option<&ArrowData> {
        match &self.arrow_data {
            Some(ResolverDomainArrowData::Arrow { data, .. }) => Some(data),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct DomainArrowBindingResolverDelegate;

impl ArrowBindingResolverDelegate<ResolverElementState> for DomainArrowBindingResolverDelegate {
    fn resolve_world_points(
        &self,
        rect: DrawRect,
        normalized_points: &[DrawPoint],
    ) -> Vec<DrawPoint> {
        ArrowGeometry::resolve_world_points(rect, normalized_points)
    }

    fn resolve_arrow_geometry_update(
        &self,
        local_points: &[DrawPoint],
        old_rect: DrawRect,
        rotation: f64,
        arrow_type: ArrowType,
    ) -> crate::draw::elements::types::arrow::arrow_binding_resolver::ArrowGeometryUpdate {
        let geometry = resolve_arrow_geometry_update(local_points, old_rect, rotation, arrow_type);
        crate::draw::elements::types::arrow::arrow_binding_resolver::ArrowGeometryUpdate {
            rect: geometry.rect,
            normalized_points: geometry.normalized_points,
        }
    }

    fn resolve_bound_point(
        &self,
        binding: &ArrowBinding,
        target: &ResolverElementState,
        reference_point: Option<DrawPoint>,
    ) -> Option<DrawPoint> {
        ArrowBindingUtils::resolve_bound_point(binding, &target.element, reference_point)
    }

    fn resolve_elbow_bound_point(
        &self,
        binding: &ArrowBinding,
        target: &ResolverElementState,
        has_arrowhead: bool,
    ) -> Option<DrawPoint> {
        ArrowBindingUtils::resolve_elbow_bound_point(binding, &target.element, has_arrowhead)
    }

    fn compute_elbow_edit(
        &self,
        element: &ResolverElementState,
        data: &ResolverDomainArrowData,
        lookup: &crate::draw::utils::combined_element_lookup::CombinedElementLookup<
            '_,
            ResolverElementState,
        >,
        local_points_override: &[DrawPoint],
        fixed_segments_override: Option<&[ResolverFixedSegment]>,
    ) -> Option<ResolverElbowEditResult<ResolverFixedSegment>> {
        let ResolverDomainArrowData::Arrow {
            data: arrow_data, ..
        } = data
        else {
            return None;
        };

        let fixed_segments_override = fixed_segments_override.map(|segments| {
            segments
                .iter()
                .cloned()
                .map(resolver_fixed_to_arrow)
                .collect::<Vec<_>>()
        });
        let result = compute_domain_elbow_edit(
            element,
            arrow_data,
            lookup,
            Some(local_points_override.to_vec()),
            fixed_segments_override,
            ElbowBindingOverride::Unset,
            ElbowBindingOverride::Unset,
            true,
        );

        Some(ResolverElbowEditResult {
            local_points: result.local_points,
            fixed_segments: result
                .fixed_segments
                .map(|segments| segments.into_iter().map(arrow_fixed_to_resolver).collect()),
            start_is_special: result.start_is_special,
            end_is_special: result.end_is_special,
        })
    }

    fn transform_fixed_segments(
        &self,
        segments: Option<&[ResolverFixedSegment]>,
        old_rect: DrawRect,
        new_rect: DrawRect,
        rotation: f64,
    ) -> Option<Vec<ResolverFixedSegment>> {
        let fixed_segments = segments.map(|values| {
            values
                .iter()
                .cloned()
                .map(resolver_fixed_to_arrow)
                .collect::<Vec<_>>()
        });

        transform_domain_fixed_segments(fixed_segments.as_deref(), old_rect, new_rect, rotation)
            .map(|segments| segments.into_iter().map(arrow_fixed_to_resolver).collect())
    }
}

fn arrow_fixed_to_resolver(value: ArrowElbowFixedSegment) -> ResolverFixedSegment {
    ResolverFixedSegment {
        index: value.index,
        start: value.start,
        end: value.end,
    }
}

fn line_fixed_to_resolver(value: LineElbowFixedSegment) -> ResolverFixedSegment {
    ResolverFixedSegment {
        index: value.index,
        start: value.start,
        end: value.end,
    }
}

fn resolver_fixed_to_arrow(value: ResolverFixedSegment) -> ArrowElbowFixedSegment {
    ArrowElbowFixedSegment {
        index: value.index,
        start: value.start,
        end: value.end,
    }
}

fn resolver_fixed_to_line(value: ResolverFixedSegment) -> LineElbowFixedSegment {
    LineElbowFixedSegment {
        index: value.index,
        start: value.start,
        end: value.end,
    }
}

fn domain_binding_to_resolver(binding: &DomainArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        domain_binding_mode_to_resolver(binding.mode),
    )
}

fn domain_binding_mode_to_resolver(mode: DomainArrowBindingMode) -> ArrowBindingMode {
    match mode {
        DomainArrowBindingMode::Inside => ArrowBindingMode::Inside,
        DomainArrowBindingMode::Orbit => ArrowBindingMode::Orbit,
        DomainArrowBindingMode::Skip => ArrowBindingMode::Skip,
    }
}

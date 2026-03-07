#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::draw::config::draw_config::SelectionConfig;
use crate::draw::elements::core::element_data::{
    DynElementData, ElementTypeId as CoreElementTypeId,
};
use crate::draw::elements::core::element_registry::DefaultElementRegistry;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::resize_mode::ResizeMode;
use crate::draw::utils::arrow_point_metrics::{
    resolve_connector_point_handle_size, resolve_connector_point_loop_threshold,
};

/// Connector control-point kind.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectorPointKind {
    Turning,
    Addable,
    LoopStart,
    LoopEnd,
    FocusStart,
    FocusEnd,
}

pub type ArrowPointKind = ConnectorPointKind;

/// Connector control-point hit result.
#[derive(Clone, Debug, PartialEq)]
pub struct ConnectorPointHandle {
    pub element_id: String,
    pub kind: ConnectorPointKind,
    pub index: usize,
    pub position: DrawPoint,
}

pub type ArrowPointHandle = ConnectorPointHandle;

/// Simplified connector-like payload used by this module.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowLikeData {
    /// World-space control points for connector editing.
    pub points: Vec<DrawPoint>,
    /// Precomputed focus handles from the full connector overlay pipeline.
    pub focus_points: Vec<ConnectorPointHandle>,
}

/// Element payload variants required for edit-intent decisions.
#[derive(Clone, Debug, PartialEq)]
pub enum ElementData {
    ArrowLike(ArrowLikeData),
    Other,
}

/// Immutable element snapshot used by hit-testing/edit-detection.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementState {
    pub id: String,
    pub data: ElementData,
}

impl ElementState {
    pub fn new(id: impl Into<String>, data: ElementData) -> Self {
        Self {
            id: id.into(),
            data,
        }
    }
}

/// Document snapshot used by edit-intent detection.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DocumentState {
    elements_by_id: HashMap<String, ElementState>,
}

impl DocumentState {
    pub fn from_elements(elements: impl IntoIterator<Item = ElementState>) -> Self {
        let elements_by_id = elements
            .into_iter()
            .map(|element| (element.id.clone(), element))
            .collect();
        Self { elements_by_id }
    }

    pub fn get_element_by_id(&self, id: &str) -> Option<&ElementState> {
        self.elements_by_id.get(id)
    }
}

/// Selection snapshot used by edit-intent detection.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SelectionState {
    pub selected_ids: HashSet<String>,
}

/// Domain snapshot required by edit-intent detection.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DomainState {
    pub document: DocumentState,
    pub selection: SelectionState,
}

/// Draw state snapshot required by edit-intent detection.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DrawState {
    pub domain: DomainState,
}

/// Effective-state view used by hit testing and editing layers.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DrawStateView {
    pub state: DrawState,
    preview_elements_by_id: HashMap<String, ElementState>,
}

impl DrawStateView {
    pub fn new(state: DrawState) -> Self {
        Self {
            state,
            preview_elements_by_id: HashMap::new(),
        }
    }

    pub fn with_preview(
        state: DrawState,
        preview_elements_by_id: HashMap<String, ElementState>,
    ) -> Self {
        Self {
            state,
            preview_elements_by_id,
        }
    }

    pub fn effective_element(&self, element: &ElementState) -> ElementState {
        self.preview_elements_by_id
            .get(&element.id)
            .cloned()
            .unwrap_or_else(|| element.clone())
    }
}

/// Hit-test target bucket.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HitTestTarget {
    None,
    Handle,
    Element,
    SelectionPadding,
}

/// Selection-handle type from hit testing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HandleType {
    TopLeft,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
    Rotate,
}

/// Hit-test result consumed by edit-intent detection.
#[derive(Clone, Debug, PartialEq)]
pub struct HitTestResult {
    pub element_id: Option<String>,
    pub handle_type: Option<HandleType>,
    pub target: HitTestTarget,
    pub is_in_selection_padding: bool,
}

impl HitTestResult {
    pub const fn none() -> Self {
        Self {
            element_id: None,
            handle_type: None,
            target: HitTestTarget::None,
            is_in_selection_padding: false,
        }
    }

    pub fn is_handle_hit(&self) -> bool {
        self.target == HitTestTarget::Handle
    }

    pub fn is_selection_padding_hit(&self) -> bool {
        self.target == HitTestTarget::SelectionPadding
    }
}

impl Default for HitTestResult {
    fn default() -> Self {
        Self::none()
    }
}

/// Hit-test call input for detector integration.
pub struct HitTestRequest<'a> {
    pub state_view: &'a DrawStateView,
    pub position: DrawPoint,
    pub config: &'a SelectionConfig,
    pub registry: &'a DefaultElementRegistry,
    pub filter_type_id: Option<&'a CoreElementTypeId<DynElementData>>,
}

/// Hit-testing integration point for [`EditIntentDetector`].
pub trait HitTestService {
    fn test(&self, request: HitTestRequest<'_>) -> HitTestResult;
}

/// Arrow-point hit-test utilities used by edit-intent detection.
pub struct ArrowPointUtils;

impl ArrowPointUtils {
    pub fn hit_test(
        element: &ElementState,
        position: DrawPoint,
        hit_radius: f64,
        loop_threshold: f64,
        handle_size: f64,
    ) -> Option<ArrowPointHandle> {
        let ElementData::ArrowLike(data) = &element.data else {
            return None;
        };

        if data.points.len() < 2 {
            return None;
        }

        let visual_radius = if handle_size.is_finite() && handle_size > 0.0 {
            handle_size * 0.5
        } else {
            0.0
        };

        let turning_hit_radius = (hit_radius * 1.11).max(visual_radius);
        let turning_hit_radius_sq = turning_hit_radius * turning_hit_radius;

        if !data.focus_points.is_empty() {
            let mut nearest_focus: Option<(f64, ConnectorPointHandle)> = None;
            for handle in &data.focus_points {
                let distance_sq = position.distance_squared(handle.position);
                if distance_sq > turning_hit_radius_sq {
                    continue;
                }

                match &nearest_focus {
                    Some((best_sq, _)) if *best_sq <= distance_sq => {}
                    _ => nearest_focus = Some((distance_sq, handle.clone())),
                }
            }

            if let Some((_, handle)) = nearest_focus {
                return Some(handle);
            }
        }

        if Self::is_loop_active(&data.points, loop_threshold) {
            let start = data.points[0];
            let end = data.points[data.points.len() - 1];
            let loop_center = Self::midpoint(start, end);
            let distance_sq = position.distance_squared(loop_center);

            let loop_inner_radius = (hit_radius * 0.69).max(visual_radius);
            if distance_sq <= loop_inner_radius * loop_inner_radius {
                return Some(ConnectorPointHandle {
                    element_id: element.id.clone(),
                    kind: ConnectorPointKind::LoopStart,
                    index: 0,
                    position: start,
                });
            }

            let loop_outer_visual = if handle_size.is_finite() && handle_size > 0.0 {
                handle_size
            } else {
                0.0
            };
            let loop_outer_radius = (hit_radius * 1.18).max(loop_outer_visual);
            if distance_sq <= loop_outer_radius * loop_outer_radius {
                return Some(ConnectorPointHandle {
                    element_id: element.id.clone(),
                    kind: ConnectorPointKind::LoopEnd,
                    index: data.points.len() - 1,
                    position: end,
                });
            }
        }

        let has_start_focus = data
            .focus_points
            .iter()
            .any(|handle| handle.kind == ConnectorPointKind::FocusStart);
        let has_end_focus = data
            .focus_points
            .iter()
            .any(|handle| handle.kind == ConnectorPointKind::FocusEnd);
        let mut nearest_turning: Option<(usize, f64)> = None;
        for (index, point) in data.points.iter().copied().enumerate() {
            if (has_start_focus && index == 0) || (has_end_focus && index + 1 == data.points.len())
            {
                continue;
            }

            let distance_sq = position.distance_squared(point);
            if distance_sq > turning_hit_radius_sq {
                continue;
            }

            match nearest_turning {
                Some((_, best_sq)) if distance_sq >= best_sq => {}
                _ => {
                    nearest_turning = Some((index, distance_sq));
                }
            }
        }

        if let Some((index, _)) = nearest_turning {
            return Some(ConnectorPointHandle {
                element_id: element.id.clone(),
                kind: ConnectorPointKind::Turning,
                index,
                position: data.points[index],
            });
        }

        let addable_hit_radius = (hit_radius * 1.43).max(visual_radius);
        let addable_hit_radius_sq = addable_hit_radius * addable_hit_radius;

        for index in 0..(data.points.len() - 1) {
            let midpoint = Self::midpoint(data.points[index], data.points[index + 1]);
            if position.distance_squared(midpoint) <= addable_hit_radius_sq {
                return Some(ConnectorPointHandle {
                    element_id: element.id.clone(),
                    kind: ConnectorPointKind::Addable,
                    index,
                    position: midpoint,
                });
            }
        }

        None
    }

    fn is_loop_active(points: &[DrawPoint], loop_threshold: f64) -> bool {
        if loop_threshold <= 0.0 || !loop_threshold.is_finite() {
            return false;
        }
        points.len() > 2
            && points[0].distance_squared(points[points.len() - 1])
                <= loop_threshold * loop_threshold
    }

    fn midpoint(a: DrawPoint, b: DrawPoint) -> DrawPoint {
        DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
    }
}

/// Input-layer edit intent.
#[derive(Clone, Debug, PartialEq)]
pub enum EditIntent {
    Select(SelectIntent),
    StartMove(StartMoveIntent),
    StartResize(StartResizeIntent),
    StartRotate(StartRotateIntent),
    StartConnectorPoint(StartConnectorPointIntent),
    BoxSelect(BoxSelectIntent),
    ClearSelection(ClearSelectionIntent),
}

/// Select an element.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SelectIntent {
    pub element_id: String,
    pub add_to_selection: bool,
    pub defer_selection_for_drag: bool,
}

/// Start moving the current selection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StartMoveIntent {
    pub element_id: String,
    pub add_to_selection: bool,
}

/// Start resizing the current selection.
#[derive(Clone, Debug, PartialEq)]
pub struct StartResizeIntent {
    pub mode: ResizeMode,
    pub selection_padding: f64,
}

/// Start rotating the current selection.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StartRotateIntent;

/// Start connector-point editing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StartConnectorPointIntent {
    pub element_id: String,
    pub point_kind: ConnectorPointKind,
    pub point_index: usize,
    pub is_double_click: bool,
}

pub type StartArrowPointIntent = StartConnectorPointIntent;

/// Start box-selection interaction.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BoxSelectIntent {
    pub start_position: DrawPoint,
}

/// Clear the active selection.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ClearSelectionIntent;

impl fmt::Display for EditIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Select(intent) => write!(f, "{}", intent),
            Self::StartMove(intent) => write!(f, "{}", intent),
            Self::StartResize(intent) => write!(f, "{}", intent),
            Self::StartRotate(intent) => write!(f, "{}", intent),
            Self::StartConnectorPoint(intent) => write!(f, "{}", intent),
            Self::BoxSelect(intent) => write!(f, "{}", intent),
            Self::ClearSelection(intent) => write!(f, "{}", intent),
        }
    }
}

impl fmt::Display for SelectIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectIntent(id: {}, addToSelection: {}, deferSelectionForDrag: {})",
            self.element_id, self.add_to_selection, self.defer_selection_for_drag
        )
    }
}

impl fmt::Display for StartMoveIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "StartMoveIntent(id: {}, addToSelection: {})",
            self.element_id, self.add_to_selection
        )
    }
}

impl fmt::Display for StartResizeIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "StartResizeIntent(mode: {:?}, selectionPadding: {})",
            self.mode, self.selection_padding
        )
    }
}

impl fmt::Display for StartRotateIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "StartRotateIntent()")
    }
}

impl fmt::Display for StartConnectorPointIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "StartConnectorPointIntent(id: {}, kind: {:?}, index: {}, doubleClick: {})",
            self.element_id, self.point_kind, self.point_index, self.is_double_click
        )
    }
}

impl fmt::Display for BoxSelectIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "BoxSelectIntent(start: {})", self.start_position)
    }
}

impl fmt::Display for ClearSelectionIntent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ClearSelectionIntent()")
    }
}

/// Edit intent detector.
///
/// Determines user intent (select / start-move / start-resize / start-rotate)
/// based on hit-testing and modifier keys.
#[derive(Clone, Copy, Debug, Default)]
pub struct EditIntentDetector;

impl EditIntentDetector {
    pub const fn new() -> Self {
        Self
    }

    /// Determines the edit intent from hit-test results and modifiers.
    pub fn detect_intent(
        &self,
        state_view: &DrawStateView,
        position: DrawPoint,
        is_shift_pressed: bool,
        config: &SelectionConfig,
        registry: &DefaultElementRegistry,
        is_binding_enabled: bool,
        filter_type_id: Option<&CoreElementTypeId<DynElementData>>,
        hit_tester: &dyn HitTestService,
    ) -> Option<EditIntent> {
        self.detect_intent_with_hit_test(
            state_view,
            position,
            is_shift_pressed,
            config,
            registry,
            is_binding_enabled,
            filter_type_id,
            hit_tester,
        )
    }

    /// Determines the edit intent from hit-test results and modifiers.
    pub fn detect_intent_with_hit_test(
        &self,
        state_view: &DrawStateView,
        position: DrawPoint,
        is_shift_pressed: bool,
        config: &SelectionConfig,
        registry: &DefaultElementRegistry,
        is_binding_enabled: bool,
        filter_type_id: Option<&CoreElementTypeId<DynElementData>>,
        hit_tester: &dyn HitTestService,
    ) -> Option<EditIntent> {
        if let Some(intent) =
            self.detect_connector_point_intent(state_view, position, config, is_binding_enabled)
        {
            return Some(intent);
        }

        let hit_result = hit_tester.test(HitTestRequest {
            state_view,
            position,
            config,
            registry,
            filter_type_id,
        });

        if hit_result.is_handle_hit() {
            let handle_type = hit_result.handle_type?;
            return Some(self.get_handle_intent(handle_type, config.padding));
        }

        if let Some(element_id) = hit_result.element_id.as_deref() {
            return self.detect_element_intent(
                state_view,
                element_id,
                is_shift_pressed,
                hit_result.is_selection_padding_hit(),
                hit_result.is_in_selection_padding,
            );
        }

        if is_shift_pressed {
            None
        } else {
            Some(EditIntent::BoxSelect(BoxSelectIntent {
                start_position: position,
            }))
        }
    }

    fn detect_element_intent(
        &self,
        state_view: &DrawStateView,
        element_id: &str,
        is_shift_pressed: bool,
        is_selection_padding_hit: bool,
        is_in_selection_padding: bool,
    ) -> Option<EditIntent> {
        let state = &state_view.state;
        if state
            .domain
            .document
            .get_element_by_id(element_id)
            .is_none()
        {
            return None;
        }

        let selected_ids = &state.domain.selection.selected_ids;
        let is_selected = selected_ids.contains(element_id);

        if is_selected {
            if is_shift_pressed {
                if is_selection_padding_hit {
                    return None;
                }

                return Some(EditIntent::Select(SelectIntent {
                    element_id: element_id.to_string(),
                    add_to_selection: true,
                    defer_selection_for_drag: false,
                }));
            }

            return Some(EditIntent::StartMove(StartMoveIntent {
                element_id: element_id.to_string(),
                add_to_selection: false,
            }));
        }

        let defer_selection_for_drag =
            !is_shift_pressed && selected_ids.len() > 1 && is_in_selection_padding;

        Some(EditIntent::Select(SelectIntent {
            element_id: element_id.to_string(),
            add_to_selection: is_shift_pressed,
            defer_selection_for_drag,
        }))
    }

    fn get_handle_intent(&self, handle_type: HandleType, selection_padding: f64) -> EditIntent {
        match handle_type {
            HandleType::Rotate => EditIntent::StartRotate(StartRotateIntent),
            HandleType::TopLeft => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::TopLeft,
                selection_padding,
            }),
            HandleType::Top => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::Top,
                selection_padding,
            }),
            HandleType::TopRight => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::TopRight,
                selection_padding,
            }),
            HandleType::Right => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::Right,
                selection_padding,
            }),
            HandleType::BottomRight => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::BottomRight,
                selection_padding,
            }),
            HandleType::Bottom => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::Bottom,
                selection_padding,
            }),
            HandleType::BottomLeft => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::BottomLeft,
                selection_padding,
            }),
            HandleType::Left => EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::Left,
                selection_padding,
            }),
        }
    }

    fn detect_connector_point_intent(
        &self,
        state_view: &DrawStateView,
        position: DrawPoint,
        config: &SelectionConfig,
        is_binding_enabled: bool,
    ) -> Option<EditIntent> {
        let selected_ids = &state_view.state.domain.selection.selected_ids;
        if selected_ids.len() != 1 {
            return None;
        }

        let selected_id = selected_ids.iter().next()?;
        let element = state_view
            .state
            .domain
            .document
            .get_element_by_id(selected_id)?;

        if !matches!(element.data, ElementData::ArrowLike(_)) {
            return None;
        }

        let hit_radius = config.interaction.handle_tolerance;
        let handle_size = resolve_connector_point_handle_size(config.render.control_point_size);
        let loop_threshold = resolve_connector_point_loop_threshold(hit_radius);
        let effective_element = state_view.effective_element(element);
        let hit_test_element = if is_binding_enabled {
            effective_element
        } else {
            strip_connector_focus_handles(&effective_element)
        };

        let handle = ArrowPointUtils::hit_test(
            &hit_test_element,
            position,
            hit_radius,
            loop_threshold,
            handle_size,
        )?;

        Some(EditIntent::StartConnectorPoint(StartConnectorPointIntent {
            element_id: handle.element_id,
            point_kind: handle.kind,
            point_index: handle.index,
            is_double_click: false,
        }))
    }
}

fn strip_connector_focus_handles(element: &ElementState) -> ElementState {
    match &element.data {
        ElementData::ArrowLike(data) if !data.focus_points.is_empty() => ElementState {
            id: element.id.clone(),
            data: ElementData::ArrowLike(ArrowLikeData {
                points: data.points.clone(),
                focus_points: Vec::new(),
            }),
        },
        _ => element.clone(),
    }
}

/// Shared edit-intent detector instance.
pub const EDIT_INTENT_DETECTOR: EditIntentDetector = EditIntentDetector::new();

/// Dart-compatible shared detector name.
#[allow(non_upper_case_globals)]
pub const edit_intent_detector: EditIntentDetector = EditIntentDetector::new();

#[cfg(test)]
mod tests {
    use super::*;

    struct StaticHitTestService {
        result: HitTestResult,
    }

    impl HitTestService for StaticHitTestService {
        fn test(&self, _request: HitTestRequest<'_>) -> HitTestResult {
            self.result.clone()
        }
    }

    fn test_state(elements: Vec<ElementState>, selected_ids: &[&str]) -> DrawStateView {
        let document = DocumentState::from_elements(elements);
        let selection = SelectionState {
            selected_ids: selected_ids.iter().map(|id| (*id).to_string()).collect(),
        };

        DrawStateView::new(DrawState {
            domain: DomainState {
                document,
                selection,
            },
        })
    }

    #[test]
    fn returns_box_select_when_no_hit_without_shift() {
        let detector = EditIntentDetector::new();
        let state_view = test_state(vec![], &[]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult::none(),
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::new(10.0, 20.0),
            false,
            &SelectionConfig::default(),
            &registry,
            true,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::BoxSelect(BoxSelectIntent {
                start_position: DrawPoint::new(10.0, 20.0),
            }))
        );
    }

    #[test]
    fn returns_start_move_for_selected_element_hit() {
        let detector = EditIntentDetector::new();
        let element = ElementState::new("e1", ElementData::Other);
        let state_view = test_state(vec![element], &["e1"]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult {
                element_id: Some("e1".to_string()),
                handle_type: None,
                target: HitTestTarget::Element,
                is_in_selection_padding: false,
            },
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::ZERO,
            false,
            &SelectionConfig::default(),
            &registry,
            true,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::StartMove(StartMoveIntent {
                element_id: "e1".to_string(),
                add_to_selection: false,
            }))
        );
    }

    #[test]
    fn returns_resize_intent_for_handle_hit() {
        let detector = EditIntentDetector::new();
        let state_view = test_state(vec![], &[]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult {
                element_id: None,
                handle_type: Some(HandleType::BottomRight),
                target: HitTestTarget::Handle,
                is_in_selection_padding: false,
            },
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::ZERO,
            false,
            &SelectionConfig::default(),
            &registry,
            true,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::StartResize(StartResizeIntent {
                mode: ResizeMode::BottomRight,
                selection_padding: SelectionConfig::default().padding,
            }))
        );
    }

    #[test]
    fn prioritizes_connector_point_intent_for_single_selected_connector() {
        let detector = EditIntentDetector::new();
        let arrow = ElementState::new(
            "arrow-1",
            ElementData::ArrowLike(ArrowLikeData {
                points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(10.0, 0.0)],
                focus_points: Vec::new(),
            }),
        );
        let state_view = test_state(vec![arrow], &["arrow-1"]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult::none(),
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::new(0.0, 0.0),
            false,
            &SelectionConfig::default(),
            &registry,
            true,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::StartConnectorPoint(StartConnectorPointIntent {
                element_id: "arrow-1".to_string(),
                point_kind: ConnectorPointKind::Turning,
                point_index: 0,
                is_double_click: false,
            }))
        );
    }

    #[test]
    fn prioritizes_connector_focus_handle_when_present() {
        let detector = EditIntentDetector::new();
        let arrow = ElementState::new(
            "arrow-1",
            ElementData::ArrowLike(ArrowLikeData {
                points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(10.0, 0.0)],
                focus_points: vec![ConnectorPointHandle {
                    element_id: "arrow-1".to_string(),
                    kind: ConnectorPointKind::FocusStart,
                    index: 0,
                    position: DrawPoint::new(2.0, 2.0),
                }],
            }),
        );
        let state_view = test_state(vec![arrow], &["arrow-1"]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult::none(),
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::new(2.0, 2.0),
            false,
            &SelectionConfig::default(),
            &registry,
            true,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::StartConnectorPoint(StartConnectorPointIntent {
                element_id: "arrow-1".to_string(),
                point_kind: ConnectorPointKind::FocusStart,
                point_index: 0,
                is_double_click: false,
            }))
        );
    }

    #[test]
    fn binding_disabled_skips_focus_handle_intent() {
        let detector = EditIntentDetector::new();
        let arrow = ElementState::new(
            "arrow-1",
            ElementData::ArrowLike(ArrowLikeData {
                points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(10.0, 0.0)],
                focus_points: vec![ConnectorPointHandle {
                    element_id: "arrow-1".to_string(),
                    kind: ConnectorPointKind::FocusStart,
                    index: 0,
                    position: DrawPoint::new(20.0, 20.0),
                }],
            }),
        );
        let state_view = test_state(vec![arrow], &["arrow-1"]);
        let registry = DefaultElementRegistry::default();
        let hit_tester = StaticHitTestService {
            result: HitTestResult::none(),
        };

        let intent = detector.detect_intent_with_hit_test(
            &state_view,
            DrawPoint::new(20.0, 20.0),
            false,
            &SelectionConfig::default(),
            &registry,
            false,
            None,
            &hit_tester,
        );

        assert_eq!(
            intent,
            Some(EditIntent::BoxSelect(BoxSelectIntent {
                start_position: DrawPoint::new(20.0, 20.0),
            }))
        );
    }
}

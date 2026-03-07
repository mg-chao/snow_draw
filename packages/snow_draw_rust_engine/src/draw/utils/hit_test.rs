#![allow(dead_code)]

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, OnceLock};

use log::warn;

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;

const HIT_TEST_CACHE_SIZE: usize = 4;
const HIT_TEST_CACHE_GRID_SIZE: f64 = 4.0;

/// Hit test target.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum HitTestTarget {
    /// No target was hit.
    #[default]
    None,
    /// A resize/rotate handle was hit.
    Handle,
    /// An element body was hit.
    Element,
    /// Selection padding area was hit.
    SelectionPadding,
}

/// Selection handle type.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
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

/// Cursor type hint for hit test results.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CursorHint {
    Basic,
    Move,
    ResizeUpLeftDownRight,
    ResizeUpRightDownLeft,
    ResizeUp,
    ResizeDown,
    ResizeLeft,
    ResizeRight,
    Rotate,
}

/// Hit test result.
#[derive(Clone, Debug, PartialEq)]
pub struct HitTestResult {
    /// Hit element id.
    pub element_id: Option<String>,

    /// Hit handle type (when hitting selection handles).
    pub handle_type: Option<HandleType>,

    /// Suggested cursor type for the hit result.
    pub cursor_hint: Option<CursorHint>,

    /// Selection overlay rotation in radians (when hitting handles).
    pub selection_rotation: Option<f64>,

    /// Target type for the hit result.
    pub target: HitTestTarget,

    /// True if the position is inside the selection padded area.
    pub is_in_selection_padding: bool,
}

impl HitTestResult {
    /// Creates a result for "no hit".
    pub fn none() -> Self {
        Self {
            element_id: None,
            handle_type: None,
            cursor_hint: Some(CursorHint::Basic),
            selection_rotation: None,
            target: HitTestTarget::None,
            is_in_selection_padding: false,
        }
    }

    /// Returns true if either an element or a handle was hit.
    pub fn is_hit(&self) -> bool {
        self.target != HitTestTarget::None
    }

    /// Returns true if a handle was hit.
    pub fn is_handle_hit(&self) -> bool {
        self.target == HitTestTarget::Handle
    }

    /// Returns true if an element body was hit.
    pub fn is_element_hit(&self) -> bool {
        self.target == HitTestTarget::Element
    }

    /// Returns true if the selection padding area was hit.
    pub fn is_selection_padding_hit(&self) -> bool {
        self.target == HitTestTarget::SelectionPadding
    }
}

impl Default for HitTestResult {
    fn default() -> Self {
        Self::none()
    }
}

/// Interaction-specific selection settings.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct InteractionConfig {
    pub handle_tolerance: f64,
}

impl Default for InteractionConfig {
    fn default() -> Self {
        Self {
            handle_tolerance: 8.0,
        }
    }
}

/// Selection overlay hit-test settings.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SelectionConfig {
    pub padding: f64,
    pub rotate_handle_offset: f64,
    pub interaction: InteractionConfig,
}

impl Default for SelectionConfig {
    fn default() -> Self {
        Self {
            padding: 8.0,
            rotate_handle_offset: 20.0,
            interaction: InteractionConfig::default(),
        }
    }
}

/// Element type identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ElementTypeId(String);

impl ElementTypeId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for ElementTypeId {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for ElementTypeId {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

/// Marker type for serial number element data.
pub struct SerialNumberData;

impl SerialNumberData {
    pub const TYPE_ID_TOKEN: &'static str = "serial_number";
}

/// Marker type for text element data.
pub struct TextData;

/// Lightweight data classification used by this module.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum ElementDataKind {
    #[default]
    Generic,
    Text,
}

/// Element state needed for hit-testing.
#[derive(Clone, Debug)]
pub struct ElementState {
    pub id: String,
    pub type_id: ElementTypeId,
    pub data_kind: ElementDataKind,
    pub rect: DrawRect,
}

impl ElementState {
    pub fn new(id: impl Into<String>, type_id: impl Into<ElementTypeId>, rect: DrawRect) -> Self {
        Self {
            id: id.into(),
            type_id: type_id.into(),
            data_kind: ElementDataKind::Generic,
            rect,
        }
    }
}

/// Document state needed for hit-testing.
#[derive(Clone, Debug, Default)]
pub struct DocumentState {
    pub elements: Vec<ElementState>,
    pub bound_text_ids: HashSet<String>,
}

impl DocumentState {
    pub fn get_element_by_id(&self, id: &str) -> Option<&ElementState> {
        self.elements.iter().find(|element| element.id == id)
    }

    pub fn visit_elements_at_point_top_down<F>(
        &self,
        _position: DrawPoint,
        _tolerance: f64,
        mut visitor: F,
    ) where
        F: FnMut(&ElementState) -> bool,
    {
        for candidate in self.elements.iter().rev() {
            if !visitor(candidate) {
                break;
            }
        }
    }
}

/// Selection state needed for hit-testing.
#[derive(Clone, Debug, Default)]
pub struct SelectionState {
    pub selected_ids: Vec<String>,
}

/// Domain state needed for hit-testing.
#[derive(Clone, Debug, Default)]
pub struct DomainState {
    pub selection: SelectionState,
    pub document: DocumentState,
}

/// Draw state needed for hit-testing.
#[derive(Clone, Debug, Default)]
pub struct DrawState {
    pub domain: DomainState,
}

/// Effective selection overlay geometry.
#[derive(Clone, Copy, Debug, Default)]
pub struct EffectiveSelection {
    pub bounds: Option<DrawRect>,
    pub rotation: Option<f64>,
    pub center: Option<DrawPoint>,
}

impl EffectiveSelection {
    pub fn has_selection(self) -> bool {
        self.bounds.is_some()
    }
}

/// Single-selection profile flags used by hit-testing decisions.
#[derive(Clone, Copy, Debug, Default)]
pub struct SingleSelectionProfile {
    pub is_two_point_arrow: bool,
    pub is_elbow_arrow: bool,
    pub is_text: bool,
    pub corner_handle_offset: f64,
}

/// View wrapper that exposes effective draw state data for hit-testing.
#[derive(Clone, Debug)]
pub struct DrawStateView<'a> {
    pub state: &'a DrawState,
    pub effective_selection: EffectiveSelection,
    pub single_selection_profile: SingleSelectionProfile,
}

impl<'a> DrawStateView<'a> {
    pub fn effective_element(&self, element: &ElementState) -> ElementState {
        element.clone()
    }
}

/// Element hit-test callback contract.
pub trait ElementHitTester: Send + Sync {
    fn hit_test(&self, element: &ElementState, position: DrawPoint, tolerance: f64) -> bool;
}

/// Default rectangle-based hit tester.
#[derive(Debug, Default)]
pub struct RectHitTester;

impl ElementHitTester for RectHitTester {
    fn hit_test(&self, element: &ElementState, position: DrawPoint, tolerance: f64) -> bool {
        let rect = DrawRect::new(
            element.rect.min_x - tolerance,
            element.rect.min_y - tolerance,
            element.rect.max_x + tolerance,
            element.rect.max_y + tolerance,
        );
        rect.contains_point(position)
    }
}

/// Element definition entry in the registry.
pub struct ElementDefinition {
    pub hit_tester: Arc<dyn ElementHitTester>,
}

impl ElementDefinition {
    pub fn new(hit_tester: Arc<dyn ElementHitTester>) -> Self {
        Self { hit_tester }
    }
}

impl Clone for ElementDefinition {
    fn clone(&self) -> Self {
        Self {
            hit_tester: Arc::clone(&self.hit_tester),
        }
    }
}

/// Registry of element definitions.
#[derive(Default)]
pub struct DefaultElementRegistry {
    definitions: HashMap<ElementTypeId, ElementDefinition>,
}

impl DefaultElementRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register(
        &mut self,
        type_id: impl Into<ElementTypeId>,
        definition: ElementDefinition,
    ) -> Option<ElementDefinition> {
        self.definitions.insert(type_id.into(), definition)
    }

    pub fn get_definition(&self, type_id: &ElementTypeId) -> Option<&ElementDefinition> {
        self.definitions.get(type_id)
    }
}

/// Hit test utilities.
///
/// Detects whether a pointer position hits an element or selection handles.
#[derive(Clone, Copy, Debug, Default)]
pub struct HitTest;

impl HitTest {
    /// Returns true if `position` is inside the current selection overlay
    /// bounds, including the visual padding area.
    pub fn is_in_selection_padded_area(
        &self,
        state_view: &DrawStateView<'_>,
        position: DrawPoint,
        config: &SelectionConfig,
    ) -> bool {
        let selection = state_view.effective_selection;
        let single_selection = self.resolve_single_selection_profile_for_view(state_view);
        if single_selection.is_two_point_arrow {
            return false;
        }

        let Some(context) = self.build_selection_context(selection, position, config, 0.0) else {
            return false;
        };

        self.test_padded_selection_area_with_context(&context)
    }

    /// Performs hit testing on the canvas and returns the most relevant hit.
    pub fn test(
        &self,
        state_view: &DrawStateView<'_>,
        position: DrawPoint,
        config: &SelectionConfig,
        registry: &DefaultElementRegistry,
        tolerance: Option<f64>,
        filter_type_id: Option<&ElementTypeId>,
    ) -> HitTestResult {
        let state = state_view.state;
        let actual_tolerance = tolerance.unwrap_or(config.interaction.handle_tolerance);
        let quantized_x = self.quantize_position(position.x);
        let quantized_y = self.quantize_position(position.y);

        let cache_key = HitTestCacheKey::new(
            state,
            config,
            actual_tolerance,
            filter_type_id.cloned(),
            registry,
            quantized_x,
            quantized_y,
        );

        if let Some(cached_result) = get_cached_result(&cache_key) {
            return cached_result;
        }

        let selection = state_view.effective_selection;
        let selected_ids = &state.domain.selection.selected_ids;
        let document = &state.domain.document;
        let bound_text_ids = if matches!(
            filter_type_id,
            Some(type_id) if type_id.as_str() == SerialNumberData::TYPE_ID_TOKEN
        ) {
            Some(&document.bound_text_ids)
        } else {
            None
        };

        let single_selection = self.resolve_single_selection_profile_for_view(state_view);
        let corner_handle_offset = single_selection.corner_handle_offset;
        let is_single_two_point_arrow = single_selection.is_two_point_arrow;
        let is_single_elbow_arrow = single_selection.is_elbow_arrow;

        let mut selection_context: Option<SelectionHitContext> = None;
        let mut is_in_selection_padding = false;

        if selection.has_selection() && !is_single_two_point_arrow {
            selection_context =
                self.build_selection_context(selection, position, config, corner_handle_offset);
            if let Some(context) = selection_context {
                is_in_selection_padding = self.test_padded_selection_area_with_context(&context);
                if let Some(handle_result) = self.test_handles(
                    &context,
                    position,
                    actual_tolerance,
                    config,
                    is_in_selection_padding,
                    single_selection.is_text,
                    !is_single_elbow_arrow,
                ) {
                    return cache_result(cache_key, handle_result);
                }
            }
        }

        let mut hit_element: Option<ElementState> = None;
        document.visit_elements_at_point_top_down(position, actual_tolerance, |candidate| {
            let passes_filter = match filter_type_id {
                None => true,
                Some(filter) if candidate.type_id == *filter => true,
                Some(filter) if filter.as_str() == SerialNumberData::TYPE_ID_TOKEN => {
                    candidate.data_kind == ElementDataKind::Text
                        && bound_text_ids.is_some_and(|ids| ids.contains(&candidate.id))
                }
                Some(_) => false,
            };

            if !passes_filter {
                return true;
            }

            let element = state_view.effective_element(candidate);
            if !self.test_element(&element, position, registry, actual_tolerance) {
                return true;
            }

            hit_element = Some(element);
            false
        });

        if let Some(element) = hit_element {
            return cache_result(
                cache_key,
                HitTestResult {
                    element_id: Some(element.id),
                    handle_type: None,
                    cursor_hint: Some(CursorHint::Move),
                    selection_rotation: None,
                    target: HitTestTarget::Element,
                    is_in_selection_padding,
                },
            );
        }

        if selection_context.is_some() && is_in_selection_padding && !selected_ids.is_empty() {
            return cache_result(
                cache_key,
                HitTestResult {
                    element_id: selected_ids.first().cloned(),
                    handle_type: None,
                    cursor_hint: Some(CursorHint::Move),
                    selection_rotation: None,
                    target: HitTestTarget::SelectionPadding,
                    is_in_selection_padding: true,
                },
            );
        }

        cache_result(
            cache_key,
            HitTestResult {
                cursor_hint: HitTestResult::none().cursor_hint,
                is_in_selection_padding,
                ..HitTestResult::none()
            },
        )
    }

    fn test_handles(
        &self,
        context: &SelectionHitContext,
        position: DrawPoint,
        tolerance: f64,
        config: &SelectionConfig,
        is_in_selection_padding: bool,
        prioritize_move_in_selection_padding: bool,
        allow_rotate_handle: bool,
    ) -> Option<HitTestResult> {
        if prioritize_move_in_selection_padding && is_in_selection_padding {
            return None;
        }

        let bounds = context.bounds;
        let padded_bounds = context.padded_bounds;
        let handle_bounds = context.handle_bounds;
        let test_position = context.test_position;
        let rotation = context.rotation;
        let padding = config.padding;

        if allow_rotate_handle {
            let margin = config.rotate_handle_offset;
            let rotate_handle_x = bounds.center_x();
            let rotate_handle_y = bounds.min_y - padding - margin;
            if self.is_near_rotated_point(
                position,
                rotate_handle_x,
                rotate_handle_y,
                context,
                tolerance,
            ) {
                return Some(self.build_handle_hit_result(
                    HandleType::Rotate,
                    rotation,
                    is_in_selection_padding,
                ));
            }
        }

        if let Some(corner_handle) =
            self.resolve_corner_handle(handle_bounds, position, context, tolerance)
        {
            return Some(self.build_handle_hit_result(
                corner_handle,
                rotation,
                is_in_selection_padding,
            ));
        }

        if let Some(edge_handle) = self.resolve_edge_handle(padded_bounds, test_position, tolerance)
        {
            return Some(self.build_handle_hit_result(
                edge_handle,
                rotation,
                is_in_selection_padding,
            ));
        }

        None
    }

    fn build_handle_hit_result(
        &self,
        handle: HandleType,
        rotation: f64,
        is_in_selection_padding: bool,
    ) -> HitTestResult {
        HitTestResult {
            element_id: None,
            handle_type: Some(handle),
            cursor_hint: Some(self.cursor_hint_for_handle(handle)),
            selection_rotation: Some(rotation),
            target: HitTestTarget::Handle,
            is_in_selection_padding,
        }
    }

    fn resolve_corner_handle(
        &self,
        handle_bounds: DrawRect,
        position: DrawPoint,
        context: &SelectionHitContext,
        tolerance: f64,
    ) -> Option<HandleType> {
        let min_x = handle_bounds.min_x;
        let min_y = handle_bounds.min_y;
        let max_x = handle_bounds.max_x;
        let max_y = handle_bounds.max_y;

        if self.is_near_rotated_point(position, min_x, min_y, context, tolerance) {
            return Some(HandleType::TopLeft);
        }
        if self.is_near_rotated_point(position, max_x, min_y, context, tolerance) {
            return Some(HandleType::TopRight);
        }
        if self.is_near_rotated_point(position, max_x, max_y, context, tolerance) {
            return Some(HandleType::BottomRight);
        }
        if self.is_near_rotated_point(position, min_x, max_y, context, tolerance) {
            return Some(HandleType::BottomLeft);
        }

        None
    }

    fn resolve_edge_handle(
        &self,
        padded_bounds: DrawRect,
        position: DrawPoint,
        tolerance: f64,
    ) -> Option<HandleType> {
        if self.test_top_edge(padded_bounds, position, tolerance) {
            return Some(HandleType::Top);
        }
        if self.test_right_edge(padded_bounds, position, tolerance) {
            return Some(HandleType::Right);
        }
        if self.test_bottom_edge(padded_bounds, position, tolerance) {
            return Some(HandleType::Bottom);
        }
        if self.test_left_edge(padded_bounds, position, tolerance) {
            return Some(HandleType::Left);
        }
        None
    }

    fn resolve_single_selection_profile_for_view(
        &self,
        state_view: &DrawStateView<'_>,
    ) -> SingleSelectionProfile {
        state_view.single_selection_profile
    }

    fn build_selection_context(
        &self,
        selection: EffectiveSelection,
        position: DrawPoint,
        config: &SelectionConfig,
        corner_handle_offset: f64,
    ) -> Option<SelectionHitContext> {
        if !selection.has_selection() {
            return None;
        }

        let bounds = selection.bounds?;
        let rotation = selection.rotation.unwrap_or(0.0);
        let origin = selection.center.unwrap_or(bounds.center());
        let (cos, sin) = if rotation == 0.0 {
            (1.0, 0.0)
        } else {
            (rotation.cos(), rotation.sin())
        };

        let padding = config.padding;
        let padded_bounds = DrawRect::new(
            bounds.min_x - padding,
            bounds.min_y - padding,
            bounds.max_x + padding,
            bounds.max_y + padding,
        );

        let handle_bounds = DrawRect::new(
            padded_bounds.min_x - corner_handle_offset,
            padded_bounds.min_y - corner_handle_offset,
            padded_bounds.max_x + corner_handle_offset,
            padded_bounds.max_y + corner_handle_offset,
        );

        let test_position = if rotation == 0.0 {
            position
        } else {
            let dx = position.x - origin.x;
            let dy = position.y - origin.y;
            DrawPoint::new(
                origin.x + dx * cos + dy * sin,
                origin.y - dx * sin + dy * cos,
            )
        };

        Some(SelectionHitContext {
            bounds,
            rotation,
            origin,
            cos,
            sin,
            padded_bounds,
            handle_bounds,
            test_position,
        })
    }

    fn test_padded_selection_area_with_context(&self, context: &SelectionHitContext) -> bool {
        let test_position = context.test_position;
        let padded_bounds = context.padded_bounds;
        test_position.x >= padded_bounds.min_x
            && test_position.x <= padded_bounds.max_x
            && test_position.y >= padded_bounds.min_y
            && test_position.y <= padded_bounds.max_y
    }

    fn quantize_position(&self, value: f64) -> i64 {
        (value / HIT_TEST_CACHE_GRID_SIZE).floor() as i64
    }

    fn test_element(
        &self,
        element: &ElementState,
        position: DrawPoint,
        registry: &DefaultElementRegistry,
        tolerance: f64,
    ) -> bool {
        if let Some(definition) = registry.get_definition(&element.type_id) {
            return definition.hit_tester.hit_test(element, position, tolerance);
        }

        warn!(
            "Unknown element type '{}' encountered during hit test",
            element.type_id.as_str()
        );
        element.rect.contains_point(position)
    }

    fn is_near_rotated_point(
        &self,
        position: DrawPoint,
        local_x: f64,
        local_y: f64,
        context: &SelectionHitContext,
        tolerance: f64,
    ) -> bool {
        if context.rotation == 0.0 {
            return self.is_near_point_coordinates(position, local_x, local_y, tolerance);
        }

        let origin = context.origin;
        let dx = local_x - origin.x;
        let dy = local_y - origin.y;
        let world_x = origin.x + dx * context.cos - dy * context.sin;
        let world_y = origin.y + dx * context.sin + dy * context.cos;
        self.is_near_point_coordinates(position, world_x, world_y, tolerance)
    }

    fn is_near_point_coordinates(&self, point: DrawPoint, x: f64, y: f64, tolerance: f64) -> bool {
        let dx = point.x - x;
        let dy = point.y - y;
        (dx * dx + dy * dy) <= tolerance * tolerance
    }

    fn test_top_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_horizontal_edge(bounds, position, bounds.min_y, tolerance)
    }

    fn test_right_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_vertical_edge(bounds, position, bounds.max_x, tolerance)
    }

    fn test_bottom_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_horizontal_edge(bounds, position, bounds.max_y, tolerance)
    }

    fn test_left_edge(&self, bounds: DrawRect, position: DrawPoint, tolerance: f64) -> bool {
        self.test_vertical_edge(bounds, position, bounds.min_x, tolerance)
    }

    fn test_horizontal_edge(
        &self,
        bounds: DrawRect,
        position: DrawPoint,
        edge_y: f64,
        tolerance: f64,
    ) -> bool {
        self.is_near(position.y, edge_y, tolerance)
            && self.is_inside_edge_span(position.x, bounds.min_x, bounds.max_x, tolerance)
    }

    fn test_vertical_edge(
        &self,
        bounds: DrawRect,
        position: DrawPoint,
        edge_x: f64,
        tolerance: f64,
    ) -> bool {
        self.is_near(position.x, edge_x, tolerance)
            && self.is_inside_edge_span(position.y, bounds.min_y, bounds.max_y, tolerance)
    }

    fn is_inside_edge_span(&self, value: f64, min: f64, max: f64, tolerance: f64) -> bool {
        value > min + tolerance && value < max - tolerance
    }

    fn is_near(&self, value: f64, target: f64, tolerance: f64) -> bool {
        (value - target).abs() <= tolerance
    }

    /// Maps a handle to a resize mode.
    pub fn get_resize_mode_for_handle(&self, handle: HandleType) -> Option<ResizeMode> {
        match handle {
            HandleType::TopLeft => Some(ResizeMode::TopLeft),
            HandleType::Top => Some(ResizeMode::Top),
            HandleType::TopRight => Some(ResizeMode::TopRight),
            HandleType::Right => Some(ResizeMode::Right),
            HandleType::BottomRight => Some(ResizeMode::BottomRight),
            HandleType::Bottom => Some(ResizeMode::Bottom),
            HandleType::BottomLeft => Some(ResizeMode::BottomLeft),
            HandleType::Left => Some(ResizeMode::Left),
            HandleType::Rotate => None,
        }
    }

    /// Returns the cursor hint associated with a handle.
    pub fn cursor_hint_for_handle(&self, handle: HandleType) -> CursorHint {
        match handle {
            HandleType::TopLeft | HandleType::BottomRight => CursorHint::ResizeUpLeftDownRight,
            HandleType::TopRight | HandleType::BottomLeft => CursorHint::ResizeUpRightDownLeft,
            HandleType::Top => CursorHint::ResizeUp,
            HandleType::Bottom => CursorHint::ResizeDown,
            HandleType::Left => CursorHint::ResizeLeft,
            HandleType::Right => CursorHint::ResizeRight,
            HandleType::Rotate => CursorHint::Rotate,
        }
    }
}

/// Shared hit-test helper instance.
pub const HIT_TEST: HitTest = HitTest;

#[derive(Clone, Copy, Debug)]
struct SelectionHitContext {
    bounds: DrawRect,
    rotation: f64,
    origin: DrawPoint,
    cos: f64,
    sin: f64,
    padded_bounds: DrawRect,
    handle_bounds: DrawRect,
    test_position: DrawPoint,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct HitTestCacheKey {
    state_identity: usize,
    config_padding_bits: u64,
    config_rotate_handle_offset_bits: u64,
    config_handle_tolerance_bits: u64,
    tolerance_bits: u64,
    filter_type_id: Option<ElementTypeId>,
    registry_identity: usize,
    position_x: i64,
    position_y: i64,
}

impl HitTestCacheKey {
    fn new(
        state: &DrawState,
        config: &SelectionConfig,
        tolerance: f64,
        filter_type_id: Option<ElementTypeId>,
        registry: &DefaultElementRegistry,
        position_x: i64,
        position_y: i64,
    ) -> Self {
        Self {
            state_identity: state as *const DrawState as usize,
            config_padding_bits: config.padding.to_bits(),
            config_rotate_handle_offset_bits: config.rotate_handle_offset.to_bits(),
            config_handle_tolerance_bits: config.interaction.handle_tolerance.to_bits(),
            tolerance_bits: tolerance.to_bits(),
            filter_type_id,
            registry_identity: registry as *const DefaultElementRegistry as usize,
            position_x,
            position_y,
        }
    }
}

fn hit_test_cache() -> &'static Mutex<LruCache<HitTestCacheKey, HitTestResult>> {
    static CACHE: OnceLock<Mutex<LruCache<HitTestCacheKey, HitTestResult>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(LruCache::new(HIT_TEST_CACHE_SIZE)))
}

fn get_cached_result(key: &HitTestCacheKey) -> Option<HitTestResult> {
    let Ok(mut cache) = hit_test_cache().lock() else {
        return None;
    };
    cache.get(key)
}

fn cache_result(key: HitTestCacheKey, result: HitTestResult) -> HitTestResult {
    if let Ok(mut cache) = hit_test_cache().lock() {
        cache.put(key, result.clone());
    }
    result
}

#[derive(Debug)]
struct LruCache<K, V> {
    max_entries: usize,
    entries: HashMap<K, V>,
    usage_order: VecDeque<K>,
}

impl<K, V> LruCache<K, V>
where
    K: Eq + std::hash::Hash + Clone,
    V: Clone,
{
    fn new(max_entries: usize) -> Self {
        Self {
            max_entries: max_entries.max(1),
            entries: HashMap::new(),
            usage_order: VecDeque::new(),
        }
    }

    fn get(&mut self, key: &K) -> Option<V> {
        let value = self.entries.get(key).cloned()?;
        self.touch(key);
        Some(value)
    }

    fn put(&mut self, key: K, value: V) {
        self.entries.insert(key.clone(), value);
        self.touch(&key);
        self.evict_if_needed();
    }

    fn touch(&mut self, key: &K) {
        if let Some(index) = self.usage_order.iter().position(|entry| entry == key) {
            self.usage_order.remove(index);
        }
        self.usage_order.push_back(key.clone());
    }

    fn evict_if_needed(&mut self) {
        while self.entries.len() > self.max_entries {
            let Some(oldest_key) = self.usage_order.pop_front() else {
                break;
            };
            self.entries.remove(&oldest_key);
        }
    }
}

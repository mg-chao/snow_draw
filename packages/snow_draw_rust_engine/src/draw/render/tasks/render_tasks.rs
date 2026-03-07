#![allow(dead_code)]

use crate::draw::config::canvas_config::BoxSelectionConfig;
use crate::draw::config::draw_config::SelectionConfig;
use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::snap_config::SnapConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::connector::connector_points::ConnectorPointHandle;
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::draw_state_view::ElementState;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::snap_guides::SnapGuide;

/// Base type for backend-executable render tasks.
#[derive(Clone, Debug, PartialEq)]
pub enum RenderTask {
    Frame(FrameRenderTask),
    Element(ElementTask),
}

/// Base type for frame-level tasks consumed by the scene painter.
#[derive(Clone, Debug, PartialEq)]
pub enum FrameRenderTask {
    Background(BackgroundRenderTask),
    Grid(GridRenderTask),
    SelectionOutline(SelectionOutlineRenderTask),
    SelectionControls(SelectionControlsRenderTask),
    ConnectorPointOverlay(ConnectorPointOverlayRenderTask),
    ArrowPointOverlay(ArrowPointOverlayRenderTask),
    ArrowBindingHighlight(ArrowBindingHighlightRenderTask),
    HoverOutline(HoverOutlineRenderTask),
    SnapGuides(SnapGuidesRenderTask),
    BoxSelection(BoxSelectionRenderTask),
    HighlightMask(HighlightMaskRenderTask),
    Watermark(WatermarkRenderTask),
}

/// Base type for element render tasks produced by the engine.
#[derive(Clone, Debug, PartialEq)]
pub enum ElementTask {
    Rectangle(RectangleRenderTask),
    Line(LineRenderTask),
    Arrow(ArrowRenderTask),
    FreeDraw(FreeDrawRenderTask),
    Text(TextRenderTask),
    SerialNumber(SerialNumberRenderTask),
    Highlight(HighlightRenderTask),
    Filter(FilterRenderTask),
}

/// Shared payload for typed element rendering tasks.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementRenderTask<T> {
    /// Effective element state in world-space.
    pub element: ElementState,
    /// Typed element payload.
    pub data: T,
    /// Optional locale hint used by text-capable backends.
    pub locale_tag: Option<String>,
}

impl<T> ElementRenderTask<T> {
    pub fn new(element: ElementState, data: T, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

pub type RectangleRenderTask = ElementRenderTask<RectangleData>;
pub type LineRenderTask = ElementRenderTask<LineData>;
pub type ArrowRenderTask = ElementRenderTask<ArrowData>;
pub type FreeDrawRenderTask = ElementRenderTask<FreeDrawData>;
pub type TextRenderTask = ElementRenderTask<TextData>;
pub type SerialNumberRenderTask = ElementRenderTask<SerialNumberData>;
pub type HighlightRenderTask = ElementRenderTask<HighlightData>;
pub type FilterRenderTask = ElementRenderTask<FilterData>;

/// Background paint task.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct BackgroundRenderTask {
    pub color: DrawColor,
}

impl BackgroundRenderTask {
    pub const fn new(color: DrawColor) -> Self {
        Self { color }
    }
}

/// Grid paint task.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GridRenderTask {
    pub enabled: bool,
    pub size: f64,
    pub line_width: f64,
    pub line_color: DrawColor,
    pub line_opacity: f64,
    pub major_line_every: i64,
    pub major_line_opacity: f64,
    pub min_screen_spacing: f64,
    pub min_render_spacing: f64,
}

/// Selection-outline task.
#[derive(Clone, Debug, PartialEq)]
pub struct SelectionOutlineRenderTask {
    pub bounds: DrawRect,
    pub config: SelectionConfig,
    pub rotation: Option<f64>,
    pub rotation_center: Option<DrawPoint>,
    pub dashed: bool,
}

/// Selection controls task (outline + handles).
#[derive(Clone, Debug, PartialEq)]
pub struct SelectionControlsRenderTask {
    pub bounds: DrawRect,
    pub config: SelectionConfig,
    pub rotation: Option<f64>,
    pub rotation_center: Option<DrawPoint>,
    pub dashed: bool,
    pub corner_handle_offset: f64,
    pub show_rotation_handle: bool,
}

/// Connector-point overlay task.
#[derive(Clone, Debug, PartialEq)]
pub struct ConnectorPointOverlayRenderTask {
    pub handles: Vec<ConnectorPointHandle>,
    pub selection_config: SelectionConfig,
    pub active_handle: Option<ConnectorPointHandle>,
    pub hovered_handle: Option<ConnectorPointHandle>,
    pub delete_indicator_visible: bool,
}

pub type ArrowPointOverlayRenderTask = ConnectorPointOverlayRenderTask;

/// Arrow-binding highlight task.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ArrowBindingHighlightRenderTask {
    pub element_ids: Vec<String>,
    pub stroke_color: DrawColor,
}

/// Hover-outline task.
#[derive(Clone, Debug, PartialEq)]
pub struct HoverOutlineRenderTask {
    pub element: ElementState,
    pub config: SelectionConfig,
    pub use_text_underline_style: bool,
}

/// Snap-guides overlay task.
#[derive(Clone, Debug, PartialEq)]
pub struct SnapGuidesRenderTask {
    pub guides: Vec<SnapGuide>,
    pub snap_config: SnapConfig,
}

/// Box-select overlay task.
#[derive(Clone, Debug, PartialEq)]
pub struct BoxSelectionRenderTask {
    pub bounds: DrawRect,
    pub config: BoxSelectionConfig,
    pub selection_config: SelectionConfig,
    pub preview_elements: Vec<ElementState>,
}

/// Highlight-mask overlay task.
#[derive(Clone, Debug, PartialEq)]
pub struct HighlightMaskRenderTask {
    pub config: HighlightMaskConfig,
    pub highlights: Vec<ElementState>,
}

/// Watermark overlay task.
#[derive(Clone, Debug, PartialEq)]
pub struct WatermarkRenderTask {
    pub config: WatermarkConfig,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::config::draw_config::SelectionConfig;

    #[test]
    fn connector_overlay_variant_preserves_payload() {
        let task = ConnectorPointOverlayRenderTask {
            handles: Vec::new(),
            selection_config: SelectionConfig::default(),
            active_handle: None,
            hovered_handle: None,
            delete_indicator_visible: true,
        };

        let frame_task = FrameRenderTask::ConnectorPointOverlay(task.clone());

        assert_eq!(frame_task, FrameRenderTask::ConnectorPointOverlay(task));
    }

    #[test]
    fn legacy_arrow_overlay_alias_still_builds_variant() {
        let task = ArrowPointOverlayRenderTask {
            handles: Vec::new(),
            selection_config: SelectionConfig::default(),
            active_handle: None,
            hovered_handle: None,
            delete_indicator_visible: false,
        };

        let frame_task = FrameRenderTask::ArrowPointOverlay(task.clone());

        assert_eq!(frame_task, FrameRenderTask::ArrowPointOverlay(task));
    }
}

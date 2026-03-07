#![allow(dead_code)]

use std::f64::consts::PI;
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{
    ArrowType, ArrowheadStyle, CanvasFilterType, FillStyle, HighlightShape, StrokeStyle,
    TextHorizontalAlign, TextVerticalAlign,
};
use crate::draw::utils::snapping_mode::SnappingModeConfig;

/// Centralized defaults used by the drawing configuration domain.
pub struct ConfigDefaults;

impl ConfigDefaults {
    pub const PRIMARY_COLOR: DrawColor = DrawColor::new(0xFF16_77FF);
    pub const ACCENT_COLOR: DrawColor = DrawColor::new(0xFF40_96FF);
    pub const BACKGROUND_COLOR: DrawColor = DrawColor::new(0xFFFF_FFFF);
    pub const DEFAULT_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);
    pub const DEFAULT_FILL_COLOR: DrawColor = DrawColor::new(0x0000_0000);
    pub const DEFAULT_HIGHLIGHT_COLOR: DrawColor = DrawColor::new(0xFFF5_222D);
    pub const DEFAULT_HIGHLIGHT_STROKE_COLOR: DrawColor = DrawColor::new(0xFF00_0000);
    pub const DEFAULT_HIGHLIGHT_SHAPE: HighlightShape = HighlightShape::Rectangle;
    pub const DEFAULT_FILTER_TYPE: CanvasFilterType = CanvasFilterType::Mosaic;
    pub const DEFAULT_FILTER_STRENGTH: f64 = 0.5;
    pub const DEFAULT_MASK_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);
    pub const DEFAULT_WATERMARK_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);
    pub const DEFAULT_WATERMARK_TEXT: &'static str = "";
    pub const DEFAULT_WATERMARK_FONT_SIZE: f64 = 16.0;
    pub const DEFAULT_WATERMARK_FONT_FAMILY: &'static str = "";
    pub const DEFAULT_WATERMARK_ANGLE: f64 = 30.0;
    pub const DEFAULT_WATERMARK_GAP: f64 = 56.0;
    pub const MIN_WATERMARK_GAP: f64 = 10.0;
    pub const MAX_WATERMARK_GAP: f64 = 200.0;
    pub const DEFAULT_WATERMARK_OPACITY: f64 = 0.16;
    pub const DEFAULT_CORNER_RADIUS: f64 = 4.0;
    pub const DEFAULT_STROKE_STYLE: StrokeStyle = StrokeStyle::Solid;
    pub const DEFAULT_FILL_STYLE: FillStyle = FillStyle::Solid;
    pub const DEFAULT_ARROW_TYPE: ArrowType = ArrowType::Straight;
    pub const DEFAULT_START_ARROWHEAD: ArrowheadStyle = ArrowheadStyle::None;
    pub const DEFAULT_END_ARROWHEAD: ArrowheadStyle = ArrowheadStyle::Standard;
    pub const DEFAULT_TEXT_FONT_SIZE: f64 = 21.0;
    pub const DEFAULT_SERIAL_NUMBER_FONT_SIZE: f64 = 16.0;
    pub const DEFAULT_TEXT_FONT_FAMILY: Option<&'static str> = None;
    pub const DEFAULT_TEXT_STROKE_COLOR: DrawColor = DrawColor::new(0xFFF8_F4EC);
    pub const DEFAULT_TEXT_STROKE_WIDTH: f64 = 0.0;
    pub const DEFAULT_TEXT_CORNER_RADIUS: f64 = 0.0;
    pub const DEFAULT_SERIAL_NUMBER: i64 = 1;
    pub const DEFAULT_TEXT_HORIZONTAL_ALIGN: TextHorizontalAlign = TextHorizontalAlign::Left;
    pub const DEFAULT_TEXT_VERTICAL_ALIGN: TextVerticalAlign = TextVerticalAlign::Center;
    pub const DEFAULT_TEXT_AUTO_RESIZE: bool = true;
    pub const TEXT_MIN_WIDTH: f64 = 24.0;
    pub const TEXT_MAX_AUTO_WIDTH: f64 = 240.0;
    pub const CONTROL_POINT_FILL_COLOR: DrawColor = DrawColor::new(0xFFFF_FFFF);
    pub const DEFAULT_STROKE_WIDTH: f64 = 2.0;
    pub const CONTROL_POINT_SIZE: f64 = 8.0;
    pub const CONTROL_POINT_RADIUS: f64 = 2.0;
    pub const ARROW_POINT_SIZE_MULTIPLIER: f64 = 1.25;
    pub const SELECTION_PADDING: f64 = 3.0;
    pub const SELECTION_STROKE_WIDTH: f64 = 1.0;
    pub const ROTATE_HANDLE_OFFSET: f64 = 12.0;
    pub const HANDLE_TOLERANCE: f64 = 6.0;
    pub const FREE_DRAW_CLOSE_TOLERANCE_MULTIPLIER: f64 = 1.5;
    pub const DRAG_THRESHOLD: f64 = 0.0;
    pub const MIN_VALID_ELEMENT_SIZE: f64 = 5.0;
    pub const MIN_CREATE_ELEMENT_SIZE: f64 = 8.0;
    pub const MIN_RESIZE_ELEMENT_SIZE: f64 = Self::MIN_VALID_ELEMENT_SIZE;
    pub const DEFAULT_OPACITY: f64 = 1.0;
    pub const BOX_SELECTION_FILL_OPACITY: f64 = 0.2;
    pub const ROTATION_SNAP_ANGLE: f64 = PI / 12.0;
    pub const OBJECT_SNAP_ENABLED: bool = false;
    pub const OBJECT_SNAP_DISTANCE: f64 = 8.0;
    pub const OBJECT_SNAP_POINT_ENABLED: bool = true;
    pub const OBJECT_SNAP_GAP_ENABLED: bool = true;
    pub const OBJECT_SNAP_SHOW_GUIDES: bool = true;
    pub const OBJECT_SNAP_SHOW_GAP_SIZE: bool = false;
    pub const OBJECT_SNAP_LINE_COLOR: DrawColor = DrawColor::new(0xFFFF_6B6B);
    pub const OBJECT_SNAP_LINE_WIDTH: f64 = 1.0;
    pub const OBJECT_SNAP_MARKER_SIZE: f64 = 8.0;
    pub const OBJECT_SNAP_GAP_DASH_LENGTH: f64 = 4.0;
    pub const OBJECT_SNAP_GAP_DASH_GAP: f64 = 4.0;
    pub const ARROW_BINDING_ENABLED: bool = true;
    pub const ARROW_BINDING_DISTANCE: f64 = 10.0;
    pub const GRID_ENABLED: bool = false;
    pub const GRID_SIZE: f64 = 20.0;
    pub const GRID_MIN_SIZE: f64 = 5.0;
    pub const GRID_MAX_SIZE: f64 = 100.0;
    pub const GRID_LINE_COLOR: DrawColor = DrawColor::new(0xFFBD_BDBD);
    pub const GRID_LINE_OPACITY: f64 = 0.45;
    pub const GRID_MAJOR_LINE_OPACITY: f64 = 0.7;
    pub const GRID_LINE_WIDTH: f64 = 1.0;
    pub const GRID_MAJOR_LINE_EVERY: i64 = 5;
    pub const GRID_MIN_SCREEN_SPACING: f64 = 10.0;
    pub const GRID_MIN_RENDER_SPACING: f64 = 2.0;
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionRenderConfig {
    pub stroke_width: f64,
    pub stroke_color: DrawColor,
    pub corner_fill_color: DrawColor,
    pub corner_radius: f64,
    pub control_point_size: f64,
}

impl Default for SelectionRenderConfig {
    fn default() -> Self {
        Self {
            stroke_width: ConfigDefaults::SELECTION_STROKE_WIDTH,
            stroke_color: ConfigDefaults::ACCENT_COLOR,
            corner_fill_color: ConfigDefaults::CONTROL_POINT_FILL_COLOR,
            corner_radius: ConfigDefaults::CONTROL_POINT_RADIUS,
            control_point_size: ConfigDefaults::CONTROL_POINT_SIZE,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionInteractionConfig {
    pub handle_tolerance: f64,
    pub drag_threshold: f64,
}

impl Default for SelectionInteractionConfig {
    fn default() -> Self {
        Self {
            handle_tolerance: ConfigDefaults::HANDLE_TOLERANCE,
            drag_threshold: ConfigDefaults::DRAG_THRESHOLD,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionConfig {
    pub render: SelectionRenderConfig,
    pub interaction: SelectionInteractionConfig,
    pub padding: f64,
    pub rotate_handle_offset: f64,
}

impl Default for SelectionConfig {
    fn default() -> Self {
        Self {
            render: SelectionRenderConfig::default(),
            interaction: SelectionInteractionConfig::default(),
            padding: ConfigDefaults::SELECTION_PADDING,
            rotate_handle_offset: ConfigDefaults::ROTATE_HANDLE_OFFSET,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementConfig {
    pub min_valid_size: f64,
    pub min_create_size: f64,
    pub min_resize_size: f64,
    pub rotation_snap_angle: f64,
}

impl Default for ElementConfig {
    fn default() -> Self {
        Self {
            min_valid_size: ConfigDefaults::MIN_VALID_ELEMENT_SIZE,
            min_create_size: ConfigDefaults::MIN_CREATE_ELEMENT_SIZE,
            min_resize_size: ConfigDefaults::MIN_RESIZE_ELEMENT_SIZE,
            rotation_snap_angle: ConfigDefaults::ROTATION_SNAP_ANGLE,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementStyleConfig {
    pub opacity: f64,
    pub z_index: i64,
    pub serial_number: i64,
    pub stroke_width: f64,
    pub color: DrawColor,
    pub fill_color: DrawColor,
    pub stroke_style: StrokeStyle,
    pub fill_style: FillStyle,
    pub highlight_shape: HighlightShape,
    pub filter_type: CanvasFilterType,
    pub filter_strength: f64,
    pub corner_radius: f64,
    pub arrow_type: ArrowType,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
    pub font_size: f64,
    pub font_family: Option<String>,
    pub text_align: TextHorizontalAlign,
    pub vertical_align: TextVerticalAlign,
    pub text_stroke_color: DrawColor,
    pub text_stroke_width: f64,
}

impl Default for ElementStyleConfig {
    fn default() -> Self {
        Self {
            opacity: ConfigDefaults::DEFAULT_OPACITY,
            z_index: 1,
            serial_number: ConfigDefaults::DEFAULT_SERIAL_NUMBER,
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            color: ConfigDefaults::DEFAULT_COLOR,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
            highlight_shape: ConfigDefaults::DEFAULT_HIGHLIGHT_SHAPE,
            filter_type: ConfigDefaults::DEFAULT_FILTER_TYPE,
            filter_strength: ConfigDefaults::DEFAULT_FILTER_STRENGTH,
            corner_radius: ConfigDefaults::DEFAULT_CORNER_RADIUS,
            arrow_type: ConfigDefaults::DEFAULT_ARROW_TYPE,
            start_arrowhead: ConfigDefaults::DEFAULT_START_ARROWHEAD,
            end_arrowhead: ConfigDefaults::DEFAULT_END_ARROWHEAD,
            font_size: ConfigDefaults::DEFAULT_TEXT_FONT_SIZE,
            font_family: ConfigDefaults::DEFAULT_TEXT_FONT_FAMILY.map(str::to_owned),
            text_align: ConfigDefaults::DEFAULT_TEXT_HORIZONTAL_ALIGN,
            vertical_align: ConfigDefaults::DEFAULT_TEXT_VERTICAL_ALIGN,
            text_stroke_color: ConfigDefaults::DEFAULT_TEXT_STROKE_COLOR,
            text_stroke_width: ConfigDefaults::DEFAULT_TEXT_STROKE_WIDTH,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ElementStyleConfigPatch {
    pub opacity: Option<f64>,
    pub z_index: Option<i64>,
    pub serial_number: Option<i64>,
    pub stroke_width: Option<f64>,
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub stroke_style: Option<StrokeStyle>,
    pub fill_style: Option<FillStyle>,
    pub highlight_shape: Option<HighlightShape>,
    pub filter_type: Option<CanvasFilterType>,
    pub filter_strength: Option<f64>,
    pub corner_radius: Option<f64>,
    pub arrow_type: Option<ArrowType>,
    pub start_arrowhead: Option<ArrowheadStyle>,
    pub end_arrowhead: Option<ArrowheadStyle>,
    pub font_size: Option<f64>,
    pub font_family: Option<Option<String>>,
    pub text_align: Option<TextHorizontalAlign>,
    pub vertical_align: Option<TextVerticalAlign>,
    pub text_stroke_color: Option<DrawColor>,
    pub text_stroke_width: Option<f64>,
}

impl ElementStyleConfig {
    pub fn copy_with(&self, patch: ElementStyleConfigPatch) -> Self {
        Self {
            opacity: patch.opacity.unwrap_or(self.opacity),
            z_index: patch.z_index.unwrap_or(self.z_index),
            serial_number: patch.serial_number.unwrap_or(self.serial_number),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            color: patch.color.unwrap_or(self.color),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
            highlight_shape: patch.highlight_shape.unwrap_or(self.highlight_shape),
            filter_type: patch.filter_type.unwrap_or(self.filter_type),
            filter_strength: patch.filter_strength.unwrap_or(self.filter_strength),
            corner_radius: patch.corner_radius.unwrap_or(self.corner_radius),
            arrow_type: patch.arrow_type.unwrap_or(self.arrow_type),
            start_arrowhead: patch.start_arrowhead.unwrap_or(self.start_arrowhead),
            end_arrowhead: patch.end_arrowhead.unwrap_or(self.end_arrowhead),
            font_size: patch.font_size.unwrap_or(self.font_size),
            font_family: resolve_font_family(patch.font_family, &self.font_family),
            text_align: patch.text_align.unwrap_or(self.text_align),
            vertical_align: patch.vertical_align.unwrap_or(self.vertical_align),
            text_stroke_color: patch.text_stroke_color.unwrap_or(self.text_stroke_color),
            text_stroke_width: patch.text_stroke_width.unwrap_or(self.text_stroke_width),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CanvasConfig {
    pub background_color: DrawColor,
}

impl Default for CanvasConfig {
    fn default() -> Self {
        Self {
            background_color: ConfigDefaults::BACKGROUND_COLOR,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BoxSelectionConfig {
    pub fill_color: DrawColor,
    pub fill_opacity: f64,
    pub stroke_color: DrawColor,
    pub stroke_width: f64,
}

impl Default for BoxSelectionConfig {
    fn default() -> Self {
        Self {
            fill_color: ConfigDefaults::ACCENT_COLOR,
            fill_opacity: ConfigDefaults::BOX_SELECTION_FILL_OPACITY,
            stroke_color: ConfigDefaults::ACCENT_COLOR,
            stroke_width: ConfigDefaults::SELECTION_STROKE_WIDTH,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct GridConfig {
    pub enabled: bool,
    pub size: f64,
    pub line_color: DrawColor,
    pub line_opacity: f64,
    pub major_line_opacity: f64,
    pub line_width: f64,
    pub major_line_every: i64,
    pub min_screen_spacing: f64,
    pub min_render_spacing: f64,
}

impl Default for GridConfig {
    fn default() -> Self {
        Self {
            enabled: ConfigDefaults::GRID_ENABLED,
            size: ConfigDefaults::GRID_SIZE,
            line_color: ConfigDefaults::GRID_LINE_COLOR,
            line_opacity: ConfigDefaults::GRID_LINE_OPACITY,
            major_line_opacity: ConfigDefaults::GRID_MAJOR_LINE_OPACITY,
            line_width: ConfigDefaults::GRID_LINE_WIDTH,
            major_line_every: ConfigDefaults::GRID_MAJOR_LINE_EVERY,
            min_screen_spacing: ConfigDefaults::GRID_MIN_SCREEN_SPACING,
            min_render_spacing: ConfigDefaults::GRID_MIN_RENDER_SPACING,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SnapConfig {
    pub enabled: bool,
    pub distance: f64,
    pub enable_point_snaps: bool,
    pub enable_gap_snaps: bool,
    pub enable_arrow_binding: bool,
    pub arrow_binding_distance: f64,
    pub show_guides: bool,
    pub show_gap_size: bool,
    pub line_color: DrawColor,
    pub line_width: f64,
    pub marker_size: f64,
    pub gap_dash_length: f64,
    pub gap_dash_gap: f64,
}

impl Default for SnapConfig {
    fn default() -> Self {
        Self {
            enabled: ConfigDefaults::OBJECT_SNAP_ENABLED,
            distance: ConfigDefaults::OBJECT_SNAP_DISTANCE,
            enable_point_snaps: ConfigDefaults::OBJECT_SNAP_POINT_ENABLED,
            enable_gap_snaps: ConfigDefaults::OBJECT_SNAP_GAP_ENABLED,
            enable_arrow_binding: ConfigDefaults::ARROW_BINDING_ENABLED,
            arrow_binding_distance: ConfigDefaults::ARROW_BINDING_DISTANCE,
            show_guides: ConfigDefaults::OBJECT_SNAP_SHOW_GUIDES,
            show_gap_size: ConfigDefaults::OBJECT_SNAP_SHOW_GAP_SIZE,
            line_color: ConfigDefaults::OBJECT_SNAP_LINE_COLOR,
            line_width: ConfigDefaults::OBJECT_SNAP_LINE_WIDTH,
            marker_size: ConfigDefaults::OBJECT_SNAP_MARKER_SIZE,
            gap_dash_length: ConfigDefaults::OBJECT_SNAP_GAP_DASH_LENGTH,
            gap_dash_gap: ConfigDefaults::OBJECT_SNAP_GAP_DASH_GAP,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct DrawConfigInit {
    pub selection: Option<SelectionConfig>,
    pub element: Option<ElementConfig>,
    pub canvas: Option<CanvasConfig>,
    pub box_selection: Option<BoxSelectionConfig>,
    pub element_style: Option<ElementStyleConfig>,
    pub rectangle_style: Option<ElementStyleConfig>,
    pub arrow_style: Option<ElementStyleConfig>,
    pub line_style: Option<ElementStyleConfig>,
    pub free_draw_style: Option<ElementStyleConfig>,
    pub text_style: Option<ElementStyleConfig>,
    pub serial_number_style: Option<ElementStyleConfig>,
    pub filter_style: Option<ElementStyleConfig>,
    pub highlight_style: Option<ElementStyleConfig>,
    pub grid: Option<GridConfig>,
    pub snap: Option<SnapConfig>,
}

/// Top-level drawing configuration snapshot.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DrawConfig {
    pub selection: SelectionConfig,
    pub element: ElementConfig,
    pub canvas: CanvasConfig,
    pub box_selection: BoxSelectionConfig,
    pub element_style: ElementStyleConfig,
    pub rectangle_style: ElementStyleConfig,
    pub arrow_style: ElementStyleConfig,
    pub line_style: ElementStyleConfig,
    pub free_draw_style: ElementStyleConfig,
    pub text_style: ElementStyleConfig,
    pub serial_number_style: ElementStyleConfig,
    pub filter_style: ElementStyleConfig,
    pub highlight_style: ElementStyleConfig,
    pub grid: GridConfig,
    pub snap: SnapConfig,
}

impl Default for DrawConfig {
    fn default() -> Self {
        Self::new(DrawConfigInit::default())
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct DrawConfigPatch {
    pub selection: Option<SelectionConfig>,
    pub element: Option<ElementConfig>,
    pub canvas: Option<CanvasConfig>,
    pub box_selection: Option<BoxSelectionConfig>,
    pub element_style: Option<ElementStyleConfig>,
    pub rectangle_style: Option<ElementStyleConfig>,
    pub arrow_style: Option<ElementStyleConfig>,
    pub line_style: Option<ElementStyleConfig>,
    pub free_draw_style: Option<ElementStyleConfig>,
    pub text_style: Option<ElementStyleConfig>,
    pub serial_number_style: Option<ElementStyleConfig>,
    pub filter_style: Option<ElementStyleConfig>,
    pub highlight_style: Option<ElementStyleConfig>,
    pub grid: Option<GridConfig>,
    pub snap: Option<SnapConfig>,
}

impl DrawConfig {
    pub fn new(init: DrawConfigInit) -> Self {
        let element_style = init.element_style.unwrap_or_default();

        let rectangle_style = init
            .rectangle_style
            .unwrap_or_else(|| element_style.clone());
        let arrow_style = init.arrow_style.unwrap_or_else(|| element_style.clone());
        let line_style = init.line_style.unwrap_or_else(|| element_style.clone());
        let free_draw_style = init
            .free_draw_style
            .unwrap_or_else(|| element_style.clone());
        let text_style = init.text_style.unwrap_or_else(|| element_style.clone());
        let serial_number_style = init
            .serial_number_style
            .unwrap_or_else(|| Self::derive_serial_number_style(&element_style, None));
        let filter_style = init
            .filter_style
            .unwrap_or_else(|| Self::derive_filter_style(&element_style));
        let highlight_style = init
            .highlight_style
            .unwrap_or_else(|| Self::derive_highlight_style(&element_style));

        Self {
            selection: init.selection.unwrap_or_default(),
            element: init.element.unwrap_or_default(),
            canvas: init.canvas.unwrap_or_default(),
            box_selection: init.box_selection.unwrap_or_default(),
            element_style,
            rectangle_style,
            arrow_style,
            line_style,
            free_draw_style,
            text_style,
            serial_number_style,
            filter_style,
            highlight_style,
            grid: init.grid.unwrap_or_default(),
            snap: init.snap.unwrap_or_default(),
        }
    }

    pub fn copy_with(&self, patch: DrawConfigPatch) -> Self {
        Self {
            selection: patch.selection.unwrap_or_else(|| self.selection.clone()),
            element: patch.element.unwrap_or_else(|| self.element.clone()),
            canvas: patch.canvas.unwrap_or_else(|| self.canvas.clone()),
            box_selection: patch
                .box_selection
                .unwrap_or_else(|| self.box_selection.clone()),
            element_style: patch
                .element_style
                .unwrap_or_else(|| self.element_style.clone()),
            rectangle_style: patch
                .rectangle_style
                .unwrap_or_else(|| self.rectangle_style.clone()),
            arrow_style: patch
                .arrow_style
                .unwrap_or_else(|| self.arrow_style.clone()),
            line_style: patch.line_style.unwrap_or_else(|| self.line_style.clone()),
            free_draw_style: patch
                .free_draw_style
                .unwrap_or_else(|| self.free_draw_style.clone()),
            text_style: patch.text_style.unwrap_or_else(|| self.text_style.clone()),
            serial_number_style: patch
                .serial_number_style
                .unwrap_or_else(|| self.serial_number_style.clone()),
            filter_style: patch
                .filter_style
                .unwrap_or_else(|| self.filter_style.clone()),
            highlight_style: patch
                .highlight_style
                .unwrap_or_else(|| self.highlight_style.clone()),
            grid: patch.grid.unwrap_or_else(|| self.grid.clone()),
            snap: patch.snap.unwrap_or_else(|| self.snap.clone()),
        }
    }

    pub fn default_config() -> &'static Self {
        static DEFAULT_CONFIG: OnceLock<DrawConfig> = OnceLock::new();
        DEFAULT_CONFIG.get_or_init(Self::default)
    }

    fn derive_serial_number_style(
        element_style: &ElementStyleConfig,
        serial_number: Option<i64>,
    ) -> ElementStyleConfig {
        element_style.copy_with(ElementStyleConfigPatch {
            serial_number: Some(serial_number.unwrap_or(element_style.serial_number)),
            font_size: Some(ConfigDefaults::DEFAULT_SERIAL_NUMBER_FONT_SIZE),
            ..ElementStyleConfigPatch::default()
        })
    }

    fn derive_filter_style(element_style: &ElementStyleConfig) -> ElementStyleConfig {
        element_style.copy_with(ElementStyleConfigPatch {
            filter_type: Some(ConfigDefaults::DEFAULT_FILTER_TYPE),
            filter_strength: Some(ConfigDefaults::DEFAULT_FILTER_STRENGTH),
            ..ElementStyleConfigPatch::default()
        })
    }

    fn derive_highlight_style(element_style: &ElementStyleConfig) -> ElementStyleConfig {
        element_style.copy_with(ElementStyleConfigPatch {
            color: Some(ConfigDefaults::DEFAULT_HIGHLIGHT_COLOR),
            text_stroke_color: Some(ConfigDefaults::DEFAULT_HIGHLIGHT_STROKE_COLOR),
            text_stroke_width: Some(0.0),
            highlight_shape: Some(ConfigDefaults::DEFAULT_HIGHLIGHT_SHAPE),
            ..ElementStyleConfigPatch::default()
        })
    }
}

impl SnappingModeConfig for DrawConfig {
    fn grid_enabled(&self) -> bool {
        self.grid.enabled
    }

    fn object_enabled(&self) -> bool {
        self.snap.enabled
    }
}

fn resolve_font_family(update: Option<Option<String>>, current: &Option<String>) -> Option<String> {
    match update {
        None => current.clone(),
        Some(None) => None,
        Some(Some(value)) => {
            if value.trim().is_empty() {
                None
            } else {
                Some(value)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_constructor_derives_specialized_styles() {
        let config = DrawConfig::default();
        assert_eq!(
            config.serial_number_style.font_size,
            ConfigDefaults::DEFAULT_SERIAL_NUMBER_FONT_SIZE
        );
        assert_eq!(
            config.filter_style.filter_type,
            ConfigDefaults::DEFAULT_FILTER_TYPE
        );
        assert_eq!(
            config.highlight_style.color,
            ConfigDefaults::DEFAULT_HIGHLIGHT_COLOR
        );
    }

    #[test]
    fn copy_with_keeps_existing_specialized_styles_when_omitted() {
        let config = DrawConfig::default();
        let updated_element_style = config.element_style.copy_with(ElementStyleConfigPatch {
            color: Some(DrawColor::new(0xFFFF_0000)),
            ..ElementStyleConfigPatch::default()
        });

        let next = config.copy_with(DrawConfigPatch {
            element_style: Some(updated_element_style),
            ..DrawConfigPatch::default()
        });

        assert_eq!(next.serial_number_style, config.serial_number_style);
        assert_eq!(next.filter_style, config.filter_style);
        assert_eq!(next.highlight_style, config.highlight_style);
    }

    #[test]
    fn draw_config_implements_snapping_mode_config_trait() {
        let config = DrawConfig::default();
        assert!(!config.grid_enabled());
        assert!(!config.object_enabled());
    }

    #[test]
    fn copy_with_preserves_non_blank_font_family_whitespace() {
        let config = ElementStyleConfig::default().copy_with(ElementStyleConfigPatch {
            font_family: Some(Some("  Inter  ".to_owned())),
            ..ElementStyleConfigPatch::default()
        });

        assert_eq!(config.font_family.as_deref(), Some("  Inter  "));
    }

    #[test]
    fn copy_with_normalizes_blank_font_family_to_none() {
        let config = ElementStyleConfig::default().copy_with(ElementStyleConfigPatch {
            font_family: Some(Some("   ".to_owned())),
            ..ElementStyleConfigPatch::default()
        });

        assert_eq!(config.font_family, None);
    }
}

#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::elements::core::creation_strategy::{
    CreatingState, CreationFinishResult, CreationStrategy, CreationUpdateResult, DrawState,
    ElementData, PointCreationStrategy,
};
use crate::draw::elements::types::arrow::arrow_creation_strategy::ArrowCreationStrategy as SharedConnectorCreationStrategy;
use crate::draw::elements::types::arrow::arrow_data::ArrowData as DomainArrowData;
use crate::draw::elements::types::line::line_data::LineData as DomainLineData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_context::TextMetricsService;
use crate::draw::utils::snapping_mode::SnappingMode;

/// Shared creation strategy for connector-style elements.
///
/// This keeps the connector-facing API surface aligned with the Dart engine
/// while delegating the actual implementation to the shared translated
/// connector pipeline in `arrow_creation_strategy`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ConnectorCreationStrategy;

impl ConnectorCreationStrategy {
    pub const fn new() -> Self {
        Self
    }

    const fn delegate(self) -> SharedConnectorCreationStrategy {
        SharedConnectorCreationStrategy::new()
    }
}

impl PointCreationStrategy for ConnectorCreationStrategy {}

impl CreationStrategy for ConnectorCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        self.delegate()
            .start(data, start_position, text_metrics_service)
    }

    fn update(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        self.delegate().update(
            state,
            config,
            creating_state,
            current_position,
            maintain_aspect_ratio,
            create_from_center,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn update_batch(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        positions: &[DrawPoint],
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        self.delegate().update_batch(
            state,
            config,
            creating_state,
            positions,
            maintain_aspect_ratio,
            create_from_center,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn add_point(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        position: DrawPoint,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> Option<CreationUpdateResult> {
        self.delegate().add_point(
            state,
            config,
            creating_state,
            position,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        self.delegate()
            .finish(state, config, creating_state, text_metrics_service)
    }
}

/// Dedicated creation strategy for arrow elements.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ArrowCreationStrategy;

impl ArrowCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl PointCreationStrategy for ArrowCreationStrategy {}

impl CreationStrategy for ArrowCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        ConnectorCreationStrategy::new().start(data, start_position, text_metrics_service)
    }

    fn update(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        assert!(
            creating_state
                .element_data_ref()
                .as_ref()
                .as_any()
                .downcast_ref::<DomainArrowData>()
                .is_some(),
            "ArrowCreationStrategy.update only supports ArrowData"
        );
        ConnectorCreationStrategy::new().update(
            state,
            config,
            creating_state,
            current_position,
            maintain_aspect_ratio,
            create_from_center,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        ConnectorCreationStrategy::new().finish(state, config, creating_state, text_metrics_service)
    }
}

/// Dedicated creation strategy for line elements.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct LineCreationStrategy;

impl LineCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl PointCreationStrategy for LineCreationStrategy {}

impl CreationStrategy for LineCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        ConnectorCreationStrategy::new().start(data, start_position, text_metrics_service)
    }

    fn update(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        assert!(
            creating_state
                .element_data_ref()
                .as_ref()
                .as_any()
                .downcast_ref::<DomainLineData>()
                .is_some(),
            "LineCreationStrategy.update only supports LineData"
        );
        ConnectorCreationStrategy::new().update(
            state,
            config,
            creating_state,
            current_position,
            maintain_aspect_ratio,
            create_from_center,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn add_point(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        position: DrawPoint,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> Option<CreationUpdateResult> {
        ConnectorCreationStrategy::new().add_point(
            state,
            config,
            creating_state,
            position,
            snapping_mode,
            snap_override_active,
            text_metrics_service,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        ConnectorCreationStrategy::new().finish(state, config, creating_state, text_metrics_service)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::core::creation_strategy::{
        CreatingState, CreationMode, ElementState,
    };
    use crate::draw::elements::types::line::line_data::LineData;
    use crate::draw::types::draw_rect::DrawRect;
    use crate::draw::utils::snapping_mode::SnappingMode;

    fn creating_state_with_data(data: Arc<dyn ElementData>, type_id_value: &str) -> CreatingState {
        CreatingState {
            element: ElementState {
                id: "element-1".to_owned(),
                type_id_value: type_id_value.to_owned(),
                rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
                rotation: 0.0,
                opacity: 1.0,
                z_index: 0,
                data,
            },
            start_position: DrawPoint::new(0.0, 0.0),
            current_rect: DrawRect::new(0.0, 0.0, 10.0, 10.0),
            snap_guides: Vec::new(),
            creation_mode: CreationMode::default(),
        }
    }

    #[test]
    fn connector_strategies_are_distinct_public_types() {
        let connector = ConnectorCreationStrategy::new();
        let arrow = ArrowCreationStrategy::new();
        let line = LineCreationStrategy::new();

        assert_eq!(format!("{:?}", connector), "ConnectorCreationStrategy");
        assert_eq!(format!("{:?}", arrow), "ArrowCreationStrategy");
        assert_eq!(format!("{:?}", line), "LineCreationStrategy");
    }

    #[test]
    #[should_panic(expected = "ArrowCreationStrategy.update only supports ArrowData")]
    fn arrow_strategy_update_rejects_line_data() {
        let strategy = ArrowCreationStrategy::new();
        let creating_state =
            creating_state_with_data(Arc::new(LineData::default()), LineData::TYPE_ID_TOKEN);

        let _ = strategy.update(
            &DrawState::default(),
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(10.0, 10.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );
    }

    #[test]
    #[should_panic(expected = "LineCreationStrategy.update only supports LineData")]
    fn line_strategy_update_rejects_arrow_data() {
        let strategy = LineCreationStrategy::new();
        let creating_state = creating_state_with_data(
            Arc::new(DomainArrowData::default()),
            DomainArrowData::TYPE_ID_TOKEN,
        );

        let _ = strategy.update(
            &DrawState::default(),
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(10.0, 10.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );
    }
}

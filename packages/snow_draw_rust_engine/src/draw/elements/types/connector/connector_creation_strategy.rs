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
        assert!(
            creating_state
                .element_data_ref()
                .as_ref()
                .as_any()
                .downcast_ref::<DomainArrowData>()
                .is_some(),
            "ArrowCreationStrategy.add_point only supports ArrowData"
        );
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
        CreatingState, CreationMode, CreationStrategy, ElementData,
        ElementState as CreationElementState,
    };
    use crate::draw::elements::types::line::line_data::LineData;
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::models::draw_state::{DomainDocumentState, DomainState};
    use crate::draw::models::element_state::ElementState as DomainElementState;
    use crate::draw::types::draw_rect::DrawRect;
    use crate::draw::utils::snapping_mode::SnappingMode;

    fn creating_state_with_data(data: Arc<dyn ElementData>, type_id_value: &str) -> CreatingState {
        CreatingState {
            element: CreationElementState {
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

    fn rectangle_element(id: &str, rect: DrawRect, z_index: i64) -> DomainElementState {
        DomainElementState::new(
            id,
            rect,
            0.0,
            1.0,
            z_index,
            Arc::new(RectangleData::default()),
        )
    }

    fn state_with_elements(elements: Vec<DomainElementState>) -> DrawState {
        DrawState::new(
            Some(DomainState::new(
                DomainDocumentState::new(elements, 1, Default::default()),
                Default::default(),
            )),
            None,
        )
    }

    fn start_creating_with<S>(
        strategy: &S,
        data: Arc<dyn ElementData>,
        type_id_value: &str,
        id: &str,
        start_position: DrawPoint,
        z_index: i64,
    ) -> CreatingState
    where
        S: CreationStrategy,
    {
        let started = strategy.start(data, start_position, None);
        CreatingState {
            element: CreationElementState {
                id: id.to_owned(),
                type_id_value: type_id_value.to_owned(),
                rect: started.rect,
                rotation: 0.0,
                opacity: 1.0,
                z_index,
                data: Arc::clone(&started.data),
            },
            start_position,
            current_rect: started.rect,
            snap_guides: started.snap_guides,
            creation_mode: started.creation_mode,
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

    #[test]
    fn arrow_strategy_add_point_delegates_to_connector_strategy() {
        let shared = ConnectorCreationStrategy::new();
        let arrow = ArrowCreationStrategy::new();
        let started = shared.start(Arc::new(DomainArrowData::default()), DrawPoint::ZERO, None);
        let creating_state = CreatingState {
            element: CreationElementState {
                id: "arrow-1".to_owned(),
                type_id_value: DomainArrowData::TYPE_ID_TOKEN.to_owned(),
                rect: started.rect,
                rotation: 0.0,
                opacity: 1.0,
                z_index: 0,
                data: started.data,
            },
            start_position: DrawPoint::ZERO,
            current_rect: started.rect,
            snap_guides: started.snap_guides,
            creation_mode: started.creation_mode,
        };

        let result = arrow.add_point(
            &DrawState::default(),
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(24.0, 12.0),
            SnappingMode::None,
            false,
            None,
        );

        assert!(result.is_some());
    }

    #[test]
    fn arrow_strategy_update_binds_end_endpoint_to_nearby_bindable() {
        let strategy = ArrowCreationStrategy::new();
        let state = state_with_elements(vec![rectangle_element(
            "rect-target",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        )]);
        let creating_state = start_creating_with(
            &strategy,
            Arc::new(DomainArrowData::default()),
            DomainArrowData::TYPE_ID_TOKEN,
            "arrow-1",
            DrawPoint::new(20.0, 60.0),
            2,
        );

        let update = strategy.update(
            &state,
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(240.0, 60.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );

        let data = update
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<DomainArrowData>()
            .expect("arrow data after update");
        assert_eq!(
            data.end_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some("rect-target")
        );
    }

    #[test]
    fn arrow_strategy_update_binds_start_endpoint_to_nearby_bindable() {
        let strategy = ArrowCreationStrategy::new();
        let state = state_with_elements(vec![rectangle_element(
            "rect-start",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        )]);
        let creating_state = start_creating_with(
            &strategy,
            Arc::new(DomainArrowData::default()),
            DomainArrowData::TYPE_ID_TOKEN,
            "arrow-2",
            DrawPoint::new(260.0, 50.0),
            2,
        );

        let update = strategy.update(
            &state,
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(420.0, 50.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );

        let data = update
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<DomainArrowData>()
            .expect("arrow data after update");
        assert_eq!(
            data.start_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some("rect-start")
        );
    }

    #[test]
    fn new_arrow_start_binding_uses_inside_mode_during_initial_binding_pass() {
        let strategy = ArrowCreationStrategy::new();
        let state = state_with_elements(vec![rectangle_element(
            "rect-start",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        )]);
        let creating_state = start_creating_with(
            &strategy,
            Arc::new(DomainArrowData::default()),
            DomainArrowData::TYPE_ID_TOKEN,
            "arrow-3",
            DrawPoint::new(218.0, 60.0),
            2,
        );

        let update = strategy.update(
            &state,
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(440.0, 60.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );

        let data = update
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<DomainArrowData>()
            .expect("arrow data after update");
        let start_binding = data.start_binding.as_ref().expect("start binding");
        assert_eq!(start_binding.element_id, "rect-start");
        assert_eq!(
            start_binding.mode,
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Inside
        );
    }

    #[test]
    fn initial_start_binding_is_deterministic_regardless_of_first_drag_distance() {
        let strategy = ArrowCreationStrategy::new();
        let state = state_with_elements(vec![rectangle_element(
            "rect-start",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        )]);

        let resolve_start_binding = |current_position: DrawPoint| {
            let creating_state = start_creating_with(
                &strategy,
                Arc::new(DomainArrowData::default()),
                DomainArrowData::TYPE_ID_TOKEN,
                "arrow-deterministic",
                DrawPoint::new(218.0, 60.0),
                2,
            );
            let update = strategy.update(
                &state,
                &DrawConfig::default(),
                &creating_state,
                current_position,
                false,
                false,
                SnappingMode::None,
                false,
                None,
            );
            update
                .data
                .as_ref()
                .as_any()
                .downcast_ref::<DomainArrowData>()
                .expect("arrow data after update")
                .start_binding
                .clone()
                .expect("start binding")
        };

        let near_drag_binding = resolve_start_binding(DrawPoint::new(240.0, 60.0));
        let far_drag_binding = resolve_start_binding(DrawPoint::new(620.0, 90.0));

        assert_eq!(near_drag_binding, far_drag_binding);
    }

    #[test]
    fn line_strategy_update_preserves_line_payload_and_binds_endpoint() {
        let strategy = LineCreationStrategy::new();
        let state = state_with_elements(vec![rectangle_element(
            "rect-target",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        )]);
        let creating_state = start_creating_with(
            &strategy,
            Arc::new(DomainLineData::default()),
            DomainLineData::TYPE_ID_TOKEN,
            "line-1",
            DrawPoint::new(20.0, 60.0),
            2,
        );

        let update = strategy.update(
            &state,
            &DrawConfig::default(),
            &creating_state,
            DrawPoint::new(240.0, 60.0),
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );

        let data = update
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<DomainLineData>()
            .expect("line data after update");
        assert_eq!(
            data.end_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some("rect-target")
        );
    }
}

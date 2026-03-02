#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::arrow::arrow_hit_tester::{
    ArrowHitTestElement, ArrowHitTester, ArrowLikeData as ArrowLikeHitData,
};
use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::elements::types::filter::filter_hit_tester::{
    FilterHitTestElement, FilterHitTester,
};
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::free_draw::free_draw_hit_tester::{
    FreeDrawHitTestElement, FreeDrawHitTester, FreeDrawLikeData as FreeDrawLikeHitData,
};
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::highlight::highlight_hit_tester::{
    HighlightHitTestElement, HighlightHitTester,
};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::line::line_hit_tester::{
    LineHitTestElement, LineHitTester, LineLikeData as LineLikeHitData,
};
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::rectangle::rectangle_hit_tester::{
    RectangleHitTestElement, RectangleHitTester,
};
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_hit_tester::{
    SerialNumberHitTestElement, SerialNumberHitTester,
};
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::elements::types::text::text_hit_tester::{TextHitTestElement, TextHitTester};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

/// Hit-tests a single element using typed payload logic.
///
/// Mirrors Dart behavior by using per-type hit testers and only falling back
/// to a rotated-rect test when payload decoding fails or the type is unknown.
pub fn hit_test_element(element: &ElementState, position: DrawPoint, tolerance: f64) -> bool {
    let type_id = element.type_id();
    let payload = element.data.to_json_value();

    match type_id.as_str() {
        RectangleData::TYPE_ID_TOKEN => {
            let Ok(data) = RectangleData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            RectangleHitTester
                .hit_test_rectangle(
                    &RectangleHitTestElement {
                        rect: element.rect,
                        rotation: element.rotation,
                        opacity: element.opacity,
                        data: &data,
                    },
                    position,
                    tolerance,
                )
                .unwrap_or_else(|_| {
                    hit_test_rotated_rect(element.rect, element.rotation, position, tolerance)
                })
        }
        TextData::TYPE_ID_TOKEN => {
            let Ok(data) = TextData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            TextHitTester
                .hit_test_text(
                    &TextHitTestElement {
                        rect: element.rect,
                        rotation: element.rotation,
                        data: &data,
                    },
                    position,
                    tolerance,
                )
                .unwrap_or_else(|_| {
                    hit_test_rotated_rect(element.rect, element.rotation, position, tolerance)
                })
        }
        FilterData::TYPE_ID_TOKEN => {
            let Ok(data) = FilterData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            FilterHitTester
                .hit_test_filter(
                    &FilterHitTestElement {
                        rect: element.rect,
                        rotation: element.rotation,
                        data: &data,
                    },
                    position,
                    tolerance,
                )
                .unwrap_or_else(|_| {
                    hit_test_rotated_rect(element.rect, element.rotation, position, tolerance)
                })
        }
        HighlightData::TYPE_ID_TOKEN => {
            let Ok(data) = HighlightData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            HighlightHitTester
                .hit_test_highlight(
                    &HighlightHitTestElement {
                        rect: element.rect,
                        rotation: element.rotation,
                        data: &data,
                    },
                    position,
                    tolerance,
                )
                .unwrap_or_else(|_| {
                    hit_test_rotated_rect(element.rect, element.rotation, position, tolerance)
                })
        }
        SerialNumberData::TYPE_ID_TOKEN => {
            let Ok(data) = SerialNumberData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            SerialNumberHitTester
                .hit_test_serial_number(
                    &SerialNumberHitTestElement {
                        rect: element.rect,
                        data: &data,
                    },
                    position,
                    tolerance,
                )
                .unwrap_or_else(|_| {
                    hit_test_rotated_rect(element.rect, element.rotation, position, tolerance)
                })
        }
        ArrowData::TYPE_ID_TOKEN => {
            let Ok(data) = ArrowData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            let adapter = ArrowHitDataAdapter(&data);
            ArrowHitTester.hit_test_arrow(
                &ArrowHitTestElement {
                    id: &element.id,
                    rect: element.rect,
                    rotation: element.rotation,
                    data: &adapter,
                },
                position,
                tolerance,
            )
        }
        LineData::TYPE_ID_TOKEN => {
            let Ok(data) = LineData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            let adapter = LineHitDataAdapter(&data);
            LineHitTester.hit_test_line(
                &LineHitTestElement {
                    id: &element.id,
                    rect: element.rect,
                    rotation: element.rotation,
                    opacity: element.opacity,
                    data: &adapter,
                },
                position,
                tolerance,
            )
        }
        FreeDrawData::TYPE_ID_TOKEN => {
            let Ok(data) = FreeDrawData::from_json_value(&payload) else {
                return hit_test_rotated_rect(element.rect, element.rotation, position, tolerance);
            };

            let adapter = FreeDrawHitDataAdapter(&data);
            FreeDrawHitTester.hit_test_free_draw(
                &FreeDrawHitTestElement {
                    id: &element.id,
                    rect: element.rect,
                    rotation: element.rotation,
                    opacity: element.opacity,
                    data: &adapter,
                },
                position,
                tolerance,
            )
        }
        _ => hit_test_rotated_rect(element.rect, element.rotation, position, tolerance),
    }
}

/// Queries elements at a point from top-most to bottom-most z-order.
pub fn query_elements_at_point_top_down<'a>(
    elements: &'a [ElementState],
    position: DrawPoint,
    tolerance: f64,
) -> Vec<&'a ElementState> {
    let mut ordered = elements.iter().collect::<Vec<_>>();
    ordered.sort_by(|left, right| {
        left.z_index
            .cmp(&right.z_index)
            .then_with(|| left.id.cmp(&right.id))
    });

    ordered
        .into_iter()
        .rev()
        .filter(|element| hit_test_element(element, position, tolerance))
        .collect()
}

#[derive(Clone, Copy, Debug)]
struct ArrowHitDataAdapter<'a>(&'a ArrowData);

impl ArrowLikeHitData for ArrowHitDataAdapter<'_> {
    fn points(&self) -> &[DrawPoint] {
        &self.0.points
    }

    fn stroke_width(&self) -> f64 {
        self.0.stroke_width
    }

    fn arrow_type(&self) -> ArrowType {
        self.0.arrow_type
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        self.0.start_arrowhead
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        self.0.end_arrowhead
    }
}

#[derive(Clone, Copy, Debug)]
struct LineHitDataAdapter<'a>(&'a LineData);

impl LineLikeHitData for LineHitDataAdapter<'_> {
    fn points(&self) -> &[DrawPoint] {
        &self.0.points
    }

    fn stroke_width(&self) -> f64 {
        self.0.stroke_width
    }

    fn fill_alpha(&self) -> f64 {
        self.0.fill_color.a()
    }

    fn arrow_type(&self) -> ArrowType {
        self.0.arrow_type
    }
}

#[derive(Clone, Copy, Debug)]
struct FreeDrawHitDataAdapter<'a>(&'a FreeDrawData);

impl FreeDrawLikeHitData for FreeDrawHitDataAdapter<'_> {
    fn points(&self) -> &[DrawPoint] {
        &self.0.points
    }

    fn stroke_width(&self) -> f64 {
        self.0.stroke_width
    }

    fn fill_alpha(&self) -> f64 {
        self.0.fill_color.a()
    }
}

fn hit_test_rotated_rect(
    rect: DrawRect,
    rotation: f64,
    position: DrawPoint,
    tolerance: f64,
) -> bool {
    let local = if rotation == 0.0 {
        position
    } else {
        ElementSpace::new(rotation, rect.center()).from_world(position)
    };

    local.x >= rect.min_x - tolerance
        && local.x <= rect.max_x + tolerance
        && local.y >= rect.min_y - tolerance
        && local.y <= rect.max_y + tolerance
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::draw::types::draw_color::DrawColor;

    #[test]
    fn rectangle_hit_test_uses_typed_fill_logic() {
        let element = ElementState::new(
            "rect",
            DrawRect::new(0.0, 0.0, 100.0, 50.0),
            0.0,
            1.0,
            1,
            Arc::new(RectangleData {
                fill_color: DrawColor::new(0x0000_0000),
                stroke_width: 0.0,
                ..RectangleData::default()
            }),
        );

        assert!(!hit_test_element(&element, DrawPoint::new(20.0, 20.0), 0.0));
    }

    #[test]
    fn serial_number_hit_test_uses_circle_not_rect() {
        let element = ElementState::new(
            "serial",
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            1,
            Arc::new(SerialNumberData::default()),
        );

        assert!(!hit_test_element(&element, DrawPoint::new(1.0, 1.0), 0.0));
        assert!(hit_test_element(&element, DrawPoint::new(10.0, 10.0), 0.0));
    }

    #[test]
    fn text_hit_test_respects_rotation() {
        let rect = DrawRect::new(0.0, 0.0, 20.0, 10.0);
        let rotation = std::f64::consts::FRAC_PI_2;
        let world_inside =
            ElementSpace::new(rotation, rect.center()).to_world(DrawPoint::new(5.0, 5.0));

        let element = ElementState::new(
            "text",
            rect,
            rotation,
            1.0,
            1,
            Arc::new(TextData::default()),
        );

        assert!(hit_test_element(&element, world_inside, 0.0));
    }

    #[test]
    fn query_elements_at_point_top_down_orders_by_z_then_id() {
        let element_a = ElementState::new(
            "a",
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            1,
            Arc::new(TextData::default()),
        );
        let element_b = ElementState::new(
            "b",
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            2,
            Arc::new(TextData::default()),
        );

        let elements = [element_a.clone(), element_b.clone()];
        let hits = query_elements_at_point_top_down(&elements, DrawPoint::new(5.0, 5.0), 0.0);

        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].id, element_b.id);
        assert_eq!(hits[1].id, element_a.id);
    }

    #[test]
    fn unknown_element_type_falls_back_to_rotated_rect_hit() {
        #[derive(Clone, Debug, PartialEq)]
        struct UnknownData;

        impl crate::draw::elements::core::element_data::ElementData for UnknownData {
            fn type_id(
                &self,
            ) -> crate::draw::elements::core::element_data::ElementTypeId<
                crate::draw::elements::core::element_data::DynElementData,
            > {
                crate::draw::elements::core::element_data::ElementTypeId::new("unknown")
            }

            fn to_json(&self) -> serde_json::Map<String, serde_json::Value> {
                serde_json::Map::new()
            }
        }

        let element = ElementState::new(
            "unknown",
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            1,
            Arc::new(UnknownData),
        );

        assert!(hit_test_element(&element, DrawPoint::new(5.0, 5.0), 0.0));
        assert!(!hit_test_element(&element, DrawPoint::new(11.0, 5.0), 0.0));
    }
}

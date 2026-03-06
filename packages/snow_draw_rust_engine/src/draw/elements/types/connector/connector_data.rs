#![allow(dead_code)]

use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::arrow::arrow_like_data::{
    ArrowLikeData, ArrowLikeDataPatch, NullableField, UNSET,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle, StrokeStyle};

/// Shared patch payload for connector-style path elements.
pub type ConnectorDataPatch<Binding, FixedSegment> = ArrowLikeDataPatch<Binding, FixedSegment>;

/// Shared interface for connector-style path elements.
///
/// The Rust port still stores arrows and lines under older arrow-like helpers,
/// so this trait bridges the newer connector-facing API to the existing data
/// model without duplicating logic.
pub trait ConnectorData: ElementData + Clone + PartialEq + Sized {
    type ArrowBinding: Clone + PartialEq;
    type ElbowFixedSegment: Clone + PartialEq;

    fn points(&self) -> &[DrawPoint];
    fn stroke_width(&self) -> f64;
    fn stroke_style(&self) -> StrokeStyle;
    fn arrow_type(&self) -> ArrowType;
    fn start_arrowhead(&self) -> ArrowheadStyle;
    fn end_arrowhead(&self) -> ArrowheadStyle;
    fn start_binding(&self) -> Option<&Self::ArrowBinding>;
    fn end_binding(&self) -> Option<&Self::ArrowBinding>;
    fn fixed_segments(&self) -> Option<&[Self::ElbowFixedSegment]>;
    fn start_is_special(&self) -> Option<bool>;
    fn end_is_special(&self) -> Option<bool>;

    fn copy_with(
        &self,
        patch: ConnectorDataPatch<Self::ArrowBinding, Self::ElbowFixedSegment>,
    ) -> Self;
}

impl<T> ConnectorData for T
where
    T: ArrowLikeData,
{
    type ArrowBinding = T::ArrowBinding;
    type ElbowFixedSegment = T::ElbowFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        ArrowLikeData::points(self)
    }

    fn stroke_width(&self) -> f64 {
        ArrowLikeData::stroke_width(self)
    }

    fn stroke_style(&self) -> StrokeStyle {
        ArrowLikeData::stroke_style(self)
    }

    fn arrow_type(&self) -> ArrowType {
        ArrowLikeData::arrow_type(self)
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        ArrowLikeData::start_arrowhead(self)
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        ArrowLikeData::end_arrowhead(self)
    }

    fn start_binding(&self) -> Option<&Self::ArrowBinding> {
        ArrowLikeData::start_binding(self)
    }

    fn end_binding(&self) -> Option<&Self::ArrowBinding> {
        ArrowLikeData::end_binding(self)
    }

    fn fixed_segments(&self) -> Option<&[Self::ElbowFixedSegment]> {
        ArrowLikeData::fixed_segments(self)
    }

    fn start_is_special(&self) -> Option<bool> {
        ArrowLikeData::start_is_special(self)
    }

    fn end_is_special(&self) -> Option<bool> {
        ArrowLikeData::end_is_special(self)
    }

    fn copy_with(
        &self,
        patch: ConnectorDataPatch<Self::ArrowBinding, Self::ElbowFixedSegment>,
    ) -> Self {
        ArrowLikeData::copy_with(self, patch)
    }
}

pub type ConnectorNullableField<T> = NullableField<T>;
pub const CONNECTOR_UNSET: NullableField<()> = UNSET;

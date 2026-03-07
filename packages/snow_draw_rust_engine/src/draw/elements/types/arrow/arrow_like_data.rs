#![allow(dead_code)]

use crate::draw::elements::core::element_data::ElementData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle, StrokeStyle};

use super::arrow_data::{
    ArrowBinding as ArrowDataBinding, ArrowData, ArrowDataPatch,
    ElbowFixedSegment as ArrowDataElbowFixedSegment, NullableField as ArrowDataNullableField,
};

/// Nullable update state used by [`ArrowLikeDataPatch`].
///
/// Mirrors Dart's `ArrowLikeData.unset` sentinel in a type-safe way:
/// `Unset` keeps the existing value, `Null` clears the nullable field, and
/// `Value` writes a new value.
#[derive(Clone, Debug, PartialEq)]
pub enum NullableField<T> {
    Unset,
    Null,
    Value(T),
}

impl<T> Default for NullableField<T> {
    fn default() -> Self {
        Self::Unset
    }
}

/// Shared `unset` sentinel that matches `ArrowLikeData.unset` semantics.
pub const UNSET: NullableField<()> = NullableField::Unset;

/// Patch payload for immutable `copy_with` updates on arrow-like data.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowLikeDataPatch<Binding, FixedSegment> {
    pub points: Option<Vec<DrawPoint>>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub arrow_type: Option<ArrowType>,
    pub start_arrowhead: Option<ArrowheadStyle>,
    pub end_arrowhead: Option<ArrowheadStyle>,
    pub start_binding: NullableField<Binding>,
    pub end_binding: NullableField<Binding>,
    pub fixed_segments: NullableField<Vec<FixedSegment>>,
    pub start_is_special: NullableField<bool>,
    pub end_is_special: NullableField<bool>,
}

/// Shared interface for arrow-like path elements (arrows, curved lines).
///
/// This is the Rust translation of Dart's `abstract class ArrowLikeData`.
pub trait ArrowLikeData: ElementData + Clone + PartialEq + Sized {
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
        patch: ArrowLikeDataPatch<Self::ArrowBinding, Self::ElbowFixedSegment>,
    ) -> Self;
}

impl ArrowLikeData for ArrowData {
    type ArrowBinding = ArrowDataBinding;
    type ElbowFixedSegment = ArrowDataElbowFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn stroke_width(&self) -> f64 {
        self.stroke_width
    }

    fn stroke_style(&self) -> StrokeStyle {
        self.stroke_style
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        self.start_arrowhead
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        self.end_arrowhead
    }

    fn start_binding(&self) -> Option<&Self::ArrowBinding> {
        self.start_binding.as_ref()
    }

    fn end_binding(&self) -> Option<&Self::ArrowBinding> {
        self.end_binding.as_ref()
    }

    fn fixed_segments(&self) -> Option<&[Self::ElbowFixedSegment]> {
        self.fixed_segments.as_deref()
    }

    fn start_is_special(&self) -> Option<bool> {
        self.start_is_special
    }

    fn end_is_special(&self) -> Option<bool> {
        self.end_is_special
    }

    fn copy_with(
        &self,
        patch: ArrowLikeDataPatch<Self::ArrowBinding, Self::ElbowFixedSegment>,
    ) -> Self {
        ArrowData::copy_with(
            self,
            ArrowDataPatch {
                points: patch.points,
                stroke_width: patch.stroke_width,
                stroke_style: patch.stroke_style,
                arrow_type: patch.arrow_type,
                start_arrowhead: patch.start_arrowhead,
                end_arrowhead: patch.end_arrowhead,
                start_binding: map_nullable(patch.start_binding),
                end_binding: map_nullable(patch.end_binding),
                fixed_segments: map_nullable(patch.fixed_segments),
                start_is_special: map_nullable(patch.start_is_special),
                end_is_special: map_nullable(patch.end_is_special),
                ..ArrowDataPatch::default()
            },
        )
    }
}

fn map_nullable<T>(value: NullableField<T>) -> ArrowDataNullableField<T> {
    match value {
        NullableField::Unset => ArrowDataNullableField::Unset,
        NullableField::Null => ArrowDataNullableField::Null,
        NullableField::Value(value) => ArrowDataNullableField::Value(value),
    }
}

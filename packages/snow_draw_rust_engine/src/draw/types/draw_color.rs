#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use std::fmt;

/// Backend-agnostic color value stored as packed ARGB32 (`0xAARRGGBB`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DrawColor {
    /// Packed ARGB32 value (`0xAARRGGBB`).
    pub argb32: u32,
}

impl DrawColor {
    /// Creates a color from packed ARGB32 (`0xAARRGGBB`).
    pub const fn new(argb32: u32) -> Self {
        Self { argb32 }
    }

    /// Alpha channel in `[0, 255]`.
    pub const fn alpha(self) -> u8 {
        ((self.argb32 >> 24) & 0xFF) as u8
    }

    /// Red channel in `[0, 255]`.
    pub const fn red(self) -> u8 {
        ((self.argb32 >> 16) & 0xFF) as u8
    }

    /// Green channel in `[0, 255]`.
    pub const fn green(self) -> u8 {
        ((self.argb32 >> 8) & 0xFF) as u8
    }

    /// Blue channel in `[0, 255]`.
    pub const fn blue(self) -> u8 {
        (self.argb32 & 0xFF) as u8
    }

    /// Normalized alpha in `[0, 1]`.
    pub fn a(self) -> f64 {
        self.alpha() as f64 / 255.0
    }

    /// Normalized red in `[0, 1]`.
    pub fn r(self) -> f64 {
        self.red() as f64 / 255.0
    }

    /// Normalized green in `[0, 1]`.
    pub fn g(self) -> f64 {
        self.green() as f64 / 255.0
    }

    /// Normalized blue in `[0, 1]`.
    pub fn b(self) -> f64 {
        self.blue() as f64 / 255.0
    }

    /// Returns this color as packed ARGB32 (`0xAARRGGBB`).
    pub const fn to_argb32(self) -> u32 {
        self.argb32
    }

    /// Returns a copy with `alpha` (`0..=255`).
    pub fn with_alpha(self, alpha: i32) -> Self {
        let normalized_alpha = alpha.clamp(0, 255) as u32;
        Self::new((normalized_alpha << 24) | (self.argb32 & 0x00FF_FFFF))
    }

    /// Returns a copy with optional normalized channels in `[0, 1]`.
    pub fn with_values(
        self,
        alpha: Option<f64>,
        red: Option<f64>,
        green: Option<f64>,
        blue: Option<f64>,
    ) -> Self {
        let next_alpha = resolve_channel(alpha, self.alpha());
        let next_red = resolve_channel(red, self.red());
        let next_green = resolve_channel(green, self.green());
        let next_blue = resolve_channel(blue, self.blue());

        Self::new((next_alpha << 24) | (next_red << 16) | (next_green << 8) | next_blue)
    }
}

impl fmt::Display for DrawColor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "DrawColor(0x{:08x})", self.argb32)
    }
}

fn resolve_channel(value: Option<f64>, fallback: u8) -> u32 {
    match value {
        None => fallback as u32,
        Some(channel) => {
            if !channel.is_finite() {
                return fallback as u32;
            }
            (channel.clamp(0.0, 1.0) * 255.0).round().clamp(0.0, 255.0) as u32
        }
    }
}

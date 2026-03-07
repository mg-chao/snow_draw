#![allow(dead_code)]

/// Cardinal directions used by elbow routing and editing logic.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ElbowHeading {
    Right,
    Down,
    Left,
    Up,
}

impl ElbowHeading {
    /// Unit step along the X axis for this heading.
    pub const fn dx(self) -> i32 {
        match self {
            Self::Right => 1,
            Self::Down => 0,
            Self::Left => -1,
            Self::Up => 0,
        }
    }

    /// Unit step along the Y axis for this heading.
    pub const fn dy(self) -> i32 {
        match self {
            Self::Right => 0,
            Self::Down => 1,
            Self::Left => 0,
            Self::Up => -1,
        }
    }

    /// Whether the heading moves along the X axis.
    pub const fn is_horizontal(self) -> bool {
        matches!(self, Self::Right | Self::Left)
    }

    /// The opposite heading (used for backtracking checks).
    pub const fn opposite(self) -> Self {
        match self {
            Self::Right => Self::Left,
            Self::Left => Self::Right,
            Self::Up => Self::Down,
            Self::Down => Self::Up,
        }
    }
}

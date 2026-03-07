#![allow(dead_code)]

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

/// ID generator function type.
pub type IdGenerator = Arc<dyn Fn() -> String + Send + Sync + 'static>;

/// Random-string based ID generator.
#[derive(Clone, Debug)]
pub struct RandomStringIdGenerator {
    length: usize,
    chars: Vec<char>,
}

impl Default for RandomStringIdGenerator {
    fn default() -> Self {
        Self::new(
            16,
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
        )
    }
}

impl RandomStringIdGenerator {
    pub fn new(length: usize, chars: &str) -> Self {
        Self {
            length,
            chars: chars.chars().collect(),
        }
    }

    pub fn generate(&self) -> String {
        if self.length == 0 || self.chars.is_empty() {
            return String::new();
        }

        let mut state = seed();
        let mut out = String::with_capacity(self.length);
        for _ in 0..self.length {
            state = lcg_next(state);
            let index = (state as usize) % self.chars.len();
            out.push(self.chars[index]);
        }
        out
    }

    pub fn as_generator(self) -> IdGenerator {
        let this = Arc::new(self);
        Arc::new(move || this.generate())
    }
}

fn seed() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0x9E37_79B9_7F4A_7C15)
}

fn lcg_next(state: u64) -> u64 {
    state
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407)
}

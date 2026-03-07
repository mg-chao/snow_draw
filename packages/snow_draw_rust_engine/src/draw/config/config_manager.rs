#![allow(dead_code)]

use std::sync::mpsc::{self, Receiver, Sender};

/// Trait for draw configuration snapshots managed by [`ConfigManager`].
///
/// This mirrors the Dart `DrawConfig.copyWith(...)` usage from
/// `ConfigManager.updateSelection` and `ConfigManager.updateCanvas`.
pub trait DrawConfigLike: Clone + PartialEq {
    type SelectionConfig;
    type CanvasConfig;

    /// Returns a new snapshot with an updated selection config.
    fn copy_with_selection(&self, selection: Self::SelectionConfig) -> Self;

    /// Returns a new snapshot with an updated canvas config.
    fn copy_with_canvas(&self, canvas: Self::CanvasConfig) -> Self;
}

/// Configuration manager.
///
/// Manages configuration updates and change notifications.
/// Subscribers receive broadcast snapshots through `std::sync::mpsc`
/// channels obtained via [`ConfigManager::stream`].
#[derive(Debug)]
pub struct ConfigManager<C>
where
    C: DrawConfigLike,
{
    config: C,
    subscribers: Vec<Sender<C>>,
    pending_config: Option<C>,
    freeze_depth: usize,
    is_disposed: bool,
}

impl<C> ConfigManager<C>
where
    C: DrawConfigLike,
{
    /// Creates a new manager with an initial configuration snapshot.
    pub fn new(initial_config: C) -> Self {
        Self {
            config: initial_config,
            subscribers: Vec::new(),
            pending_config: None,
            freeze_depth: 0,
            is_disposed: false,
        }
    }

    fn writable_config(&self) -> &C {
        self.pending_config.as_ref().unwrap_or(&self.config)
    }

    /// Returns the current committed configuration.
    pub fn current(&self) -> &C {
        &self.config
    }

    /// Creates a new broadcast stream receiver for configuration updates.
    ///
    /// Each call returns an independent receiver subscribed to future updates.
    /// No initial snapshot is emitted automatically.
    pub fn stream(&mut self) -> Receiver<C> {
        let (sender, receiver) = mpsc::channel();
        if !self.is_disposed {
            self.subscribers.push(sender);
        }
        receiver
    }

    /// Updates the current configuration.
    ///
    /// Returns `true` if the configuration was committed immediately.
    /// When frozen, updates are buffered and this returns `false`.
    pub fn update(&mut self, new_config: C) -> bool {
        if self.is_disposed {
            return false;
        }

        if self.freeze_depth == 0 {
            return self.commit(new_config);
        }

        let should_update_pending = new_config != *self.writable_config();
        if should_update_pending {
            self.pending_config = Some(new_config);
        }
        false
    }

    /// Freezes commits during a dispatch phase.
    ///
    /// While frozen, updates are stored as pending and committed on the final
    /// matching [`ConfigManager::unfreeze`] call.
    pub fn freeze(&mut self) {
        if self.is_disposed {
            return;
        }
        self.freeze_depth += 1;
    }

    /// Unfreezes commits and applies the last buffered update, if any.
    pub fn unfreeze(&mut self) {
        if self.is_disposed || self.freeze_depth == 0 {
            return;
        }

        self.freeze_depth -= 1;
        if self.freeze_depth > 0 {
            return;
        }

        let pending = self.pending_config.take();
        if let Some(config) = pending {
            self.commit(config);
        }
    }

    fn commit(&mut self, new_config: C) -> bool {
        if new_config == self.config {
            return false;
        }

        self.config = new_config.clone();
        self.notify_subscribers(&new_config);
        true
    }

    fn notify_subscribers(&mut self, config: &C) {
        self.subscribers
            .retain(|subscriber| subscriber.send(config.clone()).is_ok());
    }

    /// Updates only the selection configuration section.
    ///
    /// Returns `true` if the update was committed immediately.
    pub fn update_selection(&mut self, selection: C::SelectionConfig) -> bool {
        let next = self.writable_config().copy_with_selection(selection);
        self.update(next)
    }

    /// Updates only the canvas configuration section.
    ///
    /// Returns `true` if the update was committed immediately.
    pub fn update_canvas(&mut self, canvas: C::CanvasConfig) -> bool {
        let next = self.writable_config().copy_with_canvas(canvas);
        self.update(next)
    }

    /// Releases resources and clears all pending/subscriber state.
    pub fn dispose(&mut self) {
        if self.is_disposed {
            return;
        }

        self.is_disposed = true;
        self.freeze_depth = 0;
        self.pending_config = None;
        self.subscribers.clear();
    }

    /// Returns `true` when the manager has been disposed.
    pub fn is_disposed(&self) -> bool {
        self.is_disposed
    }
}

#[cfg(test)]
mod tests {
    use super::{ConfigManager, DrawConfigLike};

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct TestConfig {
        selection: i32,
        canvas: i32,
    }

    impl DrawConfigLike for TestConfig {
        type SelectionConfig = i32;
        type CanvasConfig = i32;

        fn copy_with_selection(&self, selection: Self::SelectionConfig) -> Self {
            Self {
                selection,
                canvas: self.canvas,
            }
        }

        fn copy_with_canvas(&self, canvas: Self::CanvasConfig) -> Self {
            Self {
                selection: self.selection,
                canvas,
            }
        }
    }

    #[test]
    fn update_commits_and_broadcasts() {
        let mut manager = ConfigManager::new(TestConfig {
            selection: 1,
            canvas: 1,
        });
        let stream = manager.stream();

        assert!(manager.update(TestConfig {
            selection: 2,
            canvas: 1,
        }));
        assert_eq!(
            manager.current(),
            &TestConfig {
                selection: 2,
                canvas: 1,
            }
        );

        let received = stream
            .recv()
            .expect("stream should receive committed config");
        assert_eq!(
            received,
            TestConfig {
                selection: 2,
                canvas: 1,
            }
        );
    }

    #[test]
    fn freeze_buffers_until_final_unfreeze() {
        let mut manager = ConfigManager::new(TestConfig {
            selection: 1,
            canvas: 1,
        });
        let stream = manager.stream();

        manager.freeze();
        manager.freeze();
        assert!(!manager.update_selection(5));
        assert_eq!(
            manager.current(),
            &TestConfig {
                selection: 1,
                canvas: 1,
            }
        );

        manager.unfreeze();
        assert_eq!(
            manager.current(),
            &TestConfig {
                selection: 1,
                canvas: 1,
            }
        );

        manager.unfreeze();
        assert_eq!(
            manager.current(),
            &TestConfig {
                selection: 5,
                canvas: 1,
            }
        );

        let received = stream
            .recv()
            .expect("stream should receive buffered config");
        assert_eq!(
            received,
            TestConfig {
                selection: 5,
                canvas: 1,
            }
        );
    }

    #[test]
    fn dispose_blocks_future_updates() {
        let mut manager = ConfigManager::new(TestConfig {
            selection: 1,
            canvas: 1,
        });

        manager.dispose();
        assert!(manager.is_disposed());
        assert!(!manager.update_canvas(9));
        assert_eq!(
            manager.current(),
            &TestConfig {
                selection: 1,
                canvas: 1,
            }
        );

        manager.dispose();
        assert!(manager.is_disposed());
    }
}

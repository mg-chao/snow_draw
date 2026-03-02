#![allow(dead_code)]

use super::callbacks::VoidCallback;

/// Stable handle returned when registering a listener.
pub type ListenerId = u64;

/// Read-only value holder that notifies listeners when the value changes.
///
/// Dart's API removes listeners by callback identity. In Rust, trait-object
/// callbacks are not equatable, so listeners are removed by `ListenerId`.
pub trait ValueListenable<T> {
    /// Current value.
    fn value(&self) -> &T;

    /// Registers a listener for change notifications.
    fn add_listener(&mut self, listener: VoidCallback) -> ListenerId;

    /// Unregisters a listener by identifier.
    fn remove_listener(&mut self, listener_id: ListenerId) -> bool;
}

/// Mutable `ValueListenable` implementation for engine services.
pub struct ValueNotifier<T> {
    value: T,
    listeners: Vec<ListenerEntry>,
    next_listener_id: ListenerId,
}

struct ListenerEntry {
    id: ListenerId,
    callback: VoidCallback,
}

impl<T> ValueNotifier<T> {
    /// Creates a notifier with an initial value.
    pub fn new(value: T) -> Self {
        Self {
            value,
            listeners: Vec::new(),
            next_listener_id: 0,
        }
    }

    /// Returns the number of currently registered listeners.
    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    fn notify_listeners(&mut self) {
        for entry in &mut self.listeners {
            (entry.callback)();
        }
    }
}

impl<T> ValueNotifier<T>
where
    T: PartialEq,
{
    /// Updates the value and notifies listeners when it changes.
    pub fn set_value(&mut self, next_value: T) {
        if next_value == self.value {
            return;
        }
        self.value = next_value;
        self.notify_listeners();
    }
}

impl<T> ValueListenable<T> for ValueNotifier<T> {
    fn value(&self) -> &T {
        &self.value
    }

    fn add_listener(&mut self, listener: VoidCallback) -> ListenerId {
        let id = self.next_listener_id;
        self.next_listener_id = self.next_listener_id.wrapping_add(1);
        self.listeners.push(ListenerEntry {
            id,
            callback: listener,
        });
        id
    }

    fn remove_listener(&mut self, listener_id: ListenerId) -> bool {
        let before = self.listeners.len();
        self.listeners.retain(|entry| entry.id != listener_id);
        self.listeners.len() != before
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::rc::Rc;

    use super::{ValueListenable, ValueNotifier};

    #[test]
    fn does_not_notify_when_value_is_unchanged() {
        let calls = Rc::new(RefCell::new(0_u32));
        let mut notifier = ValueNotifier::new(10_i32);

        let calls_for_listener = Rc::clone(&calls);
        notifier.add_listener(Box::new(move || {
            *calls_for_listener.borrow_mut() += 1;
        }));

        notifier.set_value(10);

        assert_eq!(*calls.borrow(), 0);
    }

    #[test]
    fn notifies_when_value_changes() {
        let calls = Rc::new(RefCell::new(0_u32));
        let mut notifier = ValueNotifier::new(10_i32);

        let calls_for_listener = Rc::clone(&calls);
        notifier.add_listener(Box::new(move || {
            *calls_for_listener.borrow_mut() += 1;
        }));

        notifier.set_value(12);
        notifier.set_value(14);

        assert_eq!(*calls.borrow(), 2);
    }

    #[test]
    fn remove_listener_stops_notifications() {
        let calls = Rc::new(RefCell::new(0_u32));
        let mut notifier = ValueNotifier::new(10_i32);

        let calls_for_listener = Rc::clone(&calls);
        let listener_id = notifier.add_listener(Box::new(move || {
            *calls_for_listener.borrow_mut() += 1;
        }));
        notifier.remove_listener(listener_id);

        notifier.set_value(11);

        assert_eq!(*calls.borrow(), 0);
    }
}

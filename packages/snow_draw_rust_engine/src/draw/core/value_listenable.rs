#![allow(dead_code)]

use std::sync::Arc;

use super::callbacks::VoidCallback;

/// Read-only value holder that notifies listeners when the value changes.
pub trait ValueListenable<T> {
    /// Current value.
    fn value(&self) -> &T;

    /// Registers a listener for change notifications.
    fn add_listener(&mut self, listener: VoidCallback);

    /// Unregisters a listener by callback identity.
    fn remove_listener(&mut self, listener: &VoidCallback) -> bool;
}

/// Mutable `ValueListenable` implementation for engine services.
pub struct ValueNotifier<T> {
    value: T,
    listeners: Vec<VoidCallback>,
}

impl<T> ValueNotifier<T> {
    /// Creates a notifier with an initial value.
    pub fn new(value: T) -> Self {
        Self {
            value,
            listeners: Vec::new(),
        }
    }

    /// Returns the number of currently registered listeners.
    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    fn notify_listeners(&mut self) {
        let snapshot = self.listeners.clone();
        for listener in snapshot {
            listener();
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

    fn add_listener(&mut self, listener: VoidCallback) {
        self.listeners.push(listener);
    }

    fn remove_listener(&mut self, listener: &VoidCallback) -> bool {
        if let Some(index) = self
            .listeners
            .iter()
            .position(|registered| Arc::ptr_eq(registered, listener))
        {
            self.listeners.remove(index);
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::rc::Rc;

    use crate::draw::core::callbacks::void_callback;

    use super::{ValueListenable, ValueNotifier};

    #[test]
    fn does_not_notify_when_value_is_unchanged() {
        let calls = Rc::new(RefCell::new(0_u32));
        let mut notifier = ValueNotifier::new(10_i32);

        let calls_for_listener = Rc::clone(&calls);
        notifier.add_listener(void_callback(move || {
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
        notifier.add_listener(void_callback(move || {
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
        let listener = void_callback(move || {
            *calls_for_listener.borrow_mut() += 1;
        });
        notifier.add_listener(listener.clone());
        notifier.remove_listener(&listener);

        notifier.set_value(11);

        assert_eq!(*calls.borrow(), 0);
    }
}

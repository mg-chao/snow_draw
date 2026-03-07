#![allow(dead_code)]

use indexmap::IndexMap;
use serde_json::Number;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use thiserror::Error;

/// Root payload map used by draw events.
///
/// This mirrors Dart's `Map<String, dynamic>` shape for top-level event
/// payloads.
pub type EventPayloadMap = IndexMap<String, EventPayload>;

/// Frozen root payload map returned by [`freeze_event_payload_map`].
pub type FrozenEventPayloadMap = IndexMap<String, FrozenEventPayload>;

/// Shared map representation for nested dynamic payload maps.
///
/// A nested map is stored as ordered key/value entry pairs so keys can also be
/// dynamic values.
pub type EventPayloadEntries = Rc<RefCell<Vec<(EventPayload, EventPayload)>>>;

/// Shared sequence representation used by dynamic sets and iterables.
pub type EventPayloadSequence = Rc<RefCell<Vec<EventPayload>>>;

/// Mutable dynamic event payload value before freezing.
///
/// `Map`, `Set`, and `Iterable` are reference-counted to support graph-shaped
/// payloads, including cycle detection during freezing.
#[derive(Clone, Debug, PartialEq)]
pub enum EventPayload {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Map(EventPayloadEntries),
    Set(EventPayloadSequence),
    Iterable(EventPayloadSequence),
}

impl EventPayload {
    /// Creates a dynamic map payload from key/value entries.
    pub fn map(entries: Vec<(EventPayload, EventPayload)>) -> Self {
        Self::Map(Rc::new(RefCell::new(entries)))
    }

    /// Creates a dynamic set payload from values.
    pub fn set(items: Vec<EventPayload>) -> Self {
        Self::Set(Rc::new(RefCell::new(items)))
    }

    /// Creates a dynamic iterable payload from values.
    pub fn iterable(items: Vec<EventPayload>) -> Self {
        Self::Iterable(Rc::new(RefCell::new(items)))
    }
}

impl From<bool> for EventPayload {
    fn from(value: bool) -> Self {
        Self::Bool(value)
    }
}

impl From<String> for EventPayload {
    fn from(value: String) -> Self {
        Self::String(value)
    }
}

impl From<&str> for EventPayload {
    fn from(value: &str) -> Self {
        Self::String(value.to_owned())
    }
}

impl From<Number> for EventPayload {
    fn from(value: Number) -> Self {
        Self::Number(value)
    }
}

impl From<i64> for EventPayload {
    fn from(value: i64) -> Self {
        Self::Number(Number::from(value))
    }
}

impl From<u64> for EventPayload {
    fn from(value: u64) -> Self {
        Self::Number(Number::from(value))
    }
}

/// Immutable payload value returned by [`freeze_event_payload_map`].
///
/// `Iterable` sources are converted to [`FrozenEventPayload::List`], matching
/// Dart's `List.unmodifiable(...)` behavior.
#[derive(Clone, Debug, PartialEq)]
pub enum FrozenEventPayload {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Map(Vec<(FrozenEventPayload, FrozenEventPayload)>),
    Set(Vec<FrozenEventPayload>),
    List(Vec<FrozenEventPayload>),
}

/// Error returned when payload freezing fails.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
#[error("payload contains a cyclic reference")]
pub struct EventPayloadFreezeError;

/// Returns a recursively frozen snapshot of an event payload map.
///
/// Nested maps, sets, and iterables are copied into immutable Rust values so
/// emitted event payloads are detached from future mutations.
pub fn freeze_event_payload_map(
    payload: &EventPayloadMap,
) -> Result<FrozenEventPayloadMap, EventPayloadFreezeError> {
    let mut active = HashSet::new();
    let mut frozen_by_source = HashMap::new();
    freeze_root_payload_map(payload, &mut active, &mut frozen_by_source)
}

fn freeze_root_payload_map(
    payload: &EventPayloadMap,
    active: &mut HashSet<usize>,
    frozen_by_source: &mut HashMap<usize, FrozenEventPayload>,
) -> Result<FrozenEventPayloadMap, EventPayloadFreezeError> {
    payload
        .iter()
        .map(|(key, value)| {
            freeze_payload_value(value, active, frozen_by_source)
                .map(|frozen| (key.clone(), frozen))
        })
        .collect::<Result<FrozenEventPayloadMap, EventPayloadFreezeError>>()
}

fn freeze_payload_value(
    value: &EventPayload,
    active: &mut HashSet<usize>,
    frozen_by_source: &mut HashMap<usize, FrozenEventPayload>,
) -> Result<FrozenEventPayload, EventPayloadFreezeError> {
    match value {
        EventPayload::Null => Ok(FrozenEventPayload::Null),
        EventPayload::Bool(value) => Ok(FrozenEventPayload::Bool(*value)),
        EventPayload::Number(value) => Ok(FrozenEventPayload::Number(value.clone())),
        EventPayload::String(value) => Ok(FrozenEventPayload::String(value.clone())),
        EventPayload::Map(map_entries) => freeze_collection(
            source_id(map_entries),
            active,
            frozen_by_source,
            |active, frozen_by_source| {
                let entries = map_entries.borrow();
                let mut frozen_entries = Vec::with_capacity(entries.len());
                for (key, nested_value) in entries.iter() {
                    let frozen_key = freeze_payload_value(key, active, frozen_by_source)?;
                    let frozen_value =
                        freeze_payload_value(nested_value, active, frozen_by_source)?;
                    frozen_entries.push((frozen_key, frozen_value));
                }
                Ok(FrozenEventPayload::Map(frozen_entries))
            },
        ),
        EventPayload::Set(values) => freeze_collection(
            source_id(values),
            active,
            frozen_by_source,
            |active, frozen_by_source| {
                let values = values.borrow();
                let mut frozen_values = Vec::with_capacity(values.len());
                for item in values.iter() {
                    frozen_values.push(freeze_payload_value(item, active, frozen_by_source)?);
                }
                Ok(FrozenEventPayload::Set(frozen_values))
            },
        ),
        EventPayload::Iterable(values) => freeze_collection(
            source_id(values),
            active,
            frozen_by_source,
            |active, frozen_by_source| {
                let values = values.borrow();
                let mut frozen_values = Vec::with_capacity(values.len());
                for item in values.iter() {
                    frozen_values.push(freeze_payload_value(item, active, frozen_by_source)?);
                }
                Ok(FrozenEventPayload::List(frozen_values))
            },
        ),
    }
}

fn freeze_collection(
    source_id: usize,
    active: &mut HashSet<usize>,
    frozen_by_source: &mut HashMap<usize, FrozenEventPayload>,
    build_frozen: impl FnOnce(
        &mut HashSet<usize>,
        &mut HashMap<usize, FrozenEventPayload>,
    ) -> Result<FrozenEventPayload, EventPayloadFreezeError>,
) -> Result<FrozenEventPayload, EventPayloadFreezeError> {
    if let Some(frozen) = frozen_by_source.get(&source_id) {
        return Ok(frozen.clone());
    }

    if !active.insert(source_id) {
        return Err(EventPayloadFreezeError);
    }

    let frozen_result = build_frozen(active, frozen_by_source);
    active.remove(&source_id);

    let frozen = frozen_result?;
    frozen_by_source.insert(source_id, frozen.clone());
    Ok(frozen)
}

fn source_id<T>(source: &Rc<RefCell<T>>) -> usize {
    Rc::as_ptr(source) as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn freezes_nested_maps_sets_and_iterables() {
        let nested_map = EventPayload::map(vec![
            (EventPayload::from("enabled"), EventPayload::from(true)),
            (EventPayload::from("count"), EventPayload::from(3_i64)),
        ]);
        let nested_set = EventPayload::set(vec![EventPayload::from("a"), EventPayload::from("b")]);
        let nested_iterable = EventPayload::iterable(vec![nested_map.clone(), nested_set.clone()]);

        let mut payload = EventPayloadMap::new();
        payload.insert("items".to_string(), nested_iterable);
        payload.insert("details".to_string(), nested_map);

        let frozen = freeze_event_payload_map(&payload).expect("payload should freeze");

        assert_eq!(frozen.len(), 2);
        assert!(matches!(
            frozen.get("items"),
            Some(FrozenEventPayload::List(values)) if values.len() == 2
        ));
        assert!(matches!(
            frozen.get("details"),
            Some(FrozenEventPayload::Map(entries)) if entries.len() == 2
        ));
    }

    #[test]
    fn detects_cyclic_references() {
        let cyclic_iterable = Rc::new(RefCell::new(Vec::<EventPayload>::new()));
        let cyclic_value = EventPayload::Iterable(cyclic_iterable.clone());
        cyclic_iterable.borrow_mut().push(cyclic_value.clone());

        let mut payload = EventPayloadMap::new();
        payload.insert("cycle".to_string(), cyclic_value);

        let error = freeze_event_payload_map(&payload).expect_err("cycle should fail freezing");
        assert_eq!(error, EventPayloadFreezeError);
    }

    #[test]
    fn supports_shared_collection_references() {
        let shared_iterable = Rc::new(RefCell::new(vec![EventPayload::from("shared")]));
        let shared_value = EventPayload::Iterable(shared_iterable);

        let mut payload = EventPayloadMap::new();
        payload.insert("first".to_string(), shared_value.clone());
        payload.insert("second".to_string(), shared_value);

        let frozen = freeze_event_payload_map(&payload).expect("shared refs should freeze");
        assert_eq!(frozen.get("first"), frozen.get("second"));
    }
}

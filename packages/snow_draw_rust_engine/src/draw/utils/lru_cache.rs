#![allow(dead_code)]

use std::collections::{HashMap, VecDeque};
use std::hash::Hash;

/// Generic least-recently-used cache with optional disposal callback.
///
/// The eviction callback is called for every value that leaves the cache:
/// overflow eviction, explicit `remove`, `clear`, or key replacement via `put`.
///
/// Unlike the Dart implementation, replacement always triggers eviction for the
/// previous value because Rust does not provide a general-purpose object
/// identity check for arbitrary `V`.
pub struct LruCache<K, V>
where
    K: Eq + Hash + Clone,
{
    pub max_entries: usize,
    on_evict: Option<Box<dyn FnMut(V) + Send>>,
    entries: HashMap<K, V>,
    access_order: VecDeque<K>,
}

impl<K, V> LruCache<K, V>
where
    K: Eq + Hash + Clone,
{
    /// Creates an `LruCache` without an eviction callback.
    pub fn new(max_entries: usize) -> Self {
        Self {
            max_entries,
            on_evict: None,
            entries: HashMap::new(),
            access_order: VecDeque::new(),
        }
    }

    /// Creates an `LruCache` with an eviction callback.
    pub fn with_on_evict<F>(max_entries: usize, on_evict: F) -> Self
    where
        F: FnMut(V) + Send + 'static,
    {
        Self {
            max_entries,
            on_evict: Some(Box::new(on_evict)),
            entries: HashMap::new(),
            access_order: VecDeque::new(),
        }
    }

    /// Number of entries currently stored.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Returns whether the cache currently stores no entries.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Returns a reference to `key` and marks it as most recently used.
    pub fn get(&mut self, key: &K) -> Option<&V> {
        if !self.entries.contains_key(key) {
            return None;
        }

        self.touch(key);
        self.entries.get(key)
    }

    /// Gets `key` if present, otherwise builds and inserts a new value.
    ///
    /// The returned reference always points to the stored cache value.
    pub fn get_or_create<F>(&mut self, key: K, builder: F) -> &V
    where
        F: FnOnce() -> V,
    {
        if self.entries.contains_key(&key) {
            self.touch(&key);
        } else {
            let value = builder();
            self.put(key.clone(), value);
        }

        self.entries
            .get(&key)
            .expect("entry must exist after get_or_create")
    }

    /// Inserts or replaces a cache entry and enforces the LRU capacity.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(old_value) = self.entries.remove(&key) {
            self.remove_from_order(&key);
            self.call_on_evict(old_value);
        }

        self.entries.insert(key.clone(), value);
        self.access_order.push_back(key);

        while self.entries.len() > self.max_entries {
            if let Some(least_recent_key) = self.access_order.pop_front() {
                if let Some(least_recent_value) = self.entries.remove(&least_recent_key) {
                    self.call_on_evict(least_recent_value);
                }
            } else {
                break;
            }
        }
    }

    /// Removes `key` if present.
    ///
    /// Returns `true` when an entry was removed.
    pub fn remove(&mut self, key: &K) -> bool {
        if let Some(value) = self.entries.remove(key) {
            self.remove_from_order(key);
            self.call_on_evict(value);
            return true;
        }

        false
    }

    /// Clears the cache and runs eviction callbacks for all current entries.
    pub fn clear(&mut self) {
        if let Some(on_evict) = self.on_evict.as_mut() {
            for (_, value) in self.entries.drain() {
                on_evict(value);
            }
        } else {
            self.entries.clear();
        }

        self.access_order.clear();
    }

    fn touch(&mut self, key: &K) {
        self.remove_from_order(key);
        self.access_order.push_back(key.clone());
    }

    fn remove_from_order(&mut self, key: &K) {
        if let Some(index) = self.access_order.iter().position(|k| k == key) {
            self.access_order.remove(index);
        }
    }

    fn call_on_evict(&mut self, value: V) {
        if let Some(on_evict) = self.on_evict.as_mut() {
            on_evict(value);
        }
    }
}

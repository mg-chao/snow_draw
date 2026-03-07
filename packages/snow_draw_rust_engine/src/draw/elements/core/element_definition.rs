use std::fmt;
use std::sync::Arc;

use serde_json::{Map, Value};

use super::element_data::{ElementData, ElementTypeId};

/// Factory function that creates a default payload for an element type.
pub type CreateDefaultDataFn<T> = Arc<dyn Fn() -> T + Send + Sync + 'static>;

/// Decoder function that reconstructs typed payload data from JSON.
pub type ElementFromJsonFn<T> = Arc<dyn Fn(&Map<String, Value>) -> T + Send + Sync + 'static>;

/// Definition for a single element type.
///
/// Bundles type-specific behavior such as rendering, hit testing, and
/// (de)serialization.
///
/// `THitTester`, `TTaskEncoder`, and `TCreationStrategy` remain generic so this
/// module is usable while sibling core modules are translated incrementally.
pub struct ElementDefinition<T, THitTester, TTaskEncoder, TCreationStrategy = ()>
where
    T: ElementData,
{
    pub type_id: ElementTypeId<T>,
    pub display_name: String,
    pub hit_tester: THitTester,
    pub create_default_data: CreateDefaultDataFn<T>,
    pub from_json: ElementFromJsonFn<T>,
    pub creation_strategy: Option<TCreationStrategy>,
    pub task_encoder: TTaskEncoder,
}

impl<T, THitTester, TTaskEncoder, TCreationStrategy>
    ElementDefinition<T, THitTester, TTaskEncoder, TCreationStrategy>
where
    T: ElementData,
{
    /// Creates an immutable element definition.
    pub fn new(
        type_id: ElementTypeId<T>,
        display_name: impl Into<String>,
        hit_tester: THitTester,
        create_default_data: impl Fn() -> T + Send + Sync + 'static,
        from_json: impl Fn(&Map<String, Value>) -> T + Send + Sync + 'static,
        task_encoder: TTaskEncoder,
        creation_strategy: Option<TCreationStrategy>,
    ) -> Self {
        Self {
            type_id,
            display_name: display_name.into(),
            hit_tester,
            create_default_data: Arc::new(create_default_data),
            from_json: Arc::new(from_json),
            creation_strategy,
            task_encoder,
        }
    }

    /// Creates a default data payload using the registered factory.
    pub fn create_default(&self) -> T {
        (self.create_default_data)()
    }

    /// Recreates a typed payload from JSON input.
    pub fn decode_json(&self, json: &Map<String, Value>) -> T {
        (self.from_json)(json)
    }
}

impl<T, THitTester, TTaskEncoder, TCreationStrategy> Clone
    for ElementDefinition<T, THitTester, TTaskEncoder, TCreationStrategy>
where
    T: ElementData,
    THitTester: Clone,
    TTaskEncoder: Clone,
    TCreationStrategy: Clone,
{
    fn clone(&self) -> Self {
        Self {
            type_id: self.type_id.clone(),
            display_name: self.display_name.clone(),
            hit_tester: self.hit_tester.clone(),
            create_default_data: Arc::clone(&self.create_default_data),
            from_json: Arc::clone(&self.from_json),
            creation_strategy: self.creation_strategy.clone(),
            task_encoder: self.task_encoder.clone(),
        }
    }
}

impl<T, THitTester, TTaskEncoder, TCreationStrategy> fmt::Debug
    for ElementDefinition<T, THitTester, TTaskEncoder, TCreationStrategy>
where
    T: ElementData,
    THitTester: fmt::Debug,
    TTaskEncoder: fmt::Debug,
    TCreationStrategy: fmt::Debug,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ElementDefinition")
            .field("type_id", &self.type_id)
            .field("display_name", &self.display_name)
            .field("hit_tester", &self.hit_tester)
            .field("create_default_data", &"Fn() -> T")
            .field("from_json", &"Fn(&Map<String, Value>) -> T")
            .field("creation_strategy", &self.creation_strategy)
            .field("task_encoder", &self.task_encoder)
            .finish()
    }
}

use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;

use thiserror::Error;

use crate::draw::config::draw_config::ElementStyleConfig;
use crate::draw::elements::core::creation_strategy::{
    CreationStrategy, ElementData as CreationElementData,
};

use super::element_data::{DynElementData, ElementData, ElementTypeId};

/// Runtime definition contract used by the element registry.
///
/// The full translated `ElementDefinition<T>` will be able to implement this
/// trait directly while preserving the registry API.
pub trait ElementDefinition: Send + Sync {
    /// Raw element type identifier value used as map key.
    fn type_id_value(&self) -> &str;

    /// Creates a styled default element payload for this type.
    fn create_default_data(
        &self,
        style_defaults: &ElementStyleConfig,
    ) -> Arc<dyn CreationElementData>;

    /// Creates the creation strategy used by this element type.
    fn creation_strategy(&self) -> Option<Box<dyn CreationStrategy>>;

    /// Type-erased access for optional downcasting on read.
    fn as_any(&self) -> &dyn Any;
}

/// Errors returned by [`DefaultElementRegistry`].
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ElementRegistryError {
    /// Attempted to register the same element type twice.
    #[error("Element type \"{0}\" is already registered")]
    AlreadyRegistered(String),

    /// Required type was not found in the registry.
    #[error("Element type \"{0}\" is not registered")]
    NotRegistered(String),
}

/// Runtime registry for all element definitions.
///
/// Mirrors Dart's `DefaultElementRegistry` behavior: type definitions are
/// keyed by their string type value and registration enforces uniqueness.
#[derive(Clone, Default)]
pub struct DefaultElementRegistry {
    definitions_by_type_value: HashMap<String, Arc<dyn ElementDefinition>>,
}

impl std::fmt::Debug for DefaultElementRegistry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let registered_type_values: Vec<&str> = self
            .definitions_by_type_value
            .keys()
            .map(String::as_str)
            .collect();

        f.debug_struct("DefaultElementRegistry")
            .field("registered_type_values", &registered_type_values)
            .finish()
    }
}

impl DefaultElementRegistry {
    /// Creates a new empty registry.
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers all definitions in iteration order.
    pub fn register_all<I>(&mut self, definitions: I) -> Result<(), ElementRegistryError>
    where
        I: IntoIterator<Item = Arc<dyn ElementDefinition>>,
    {
        for definition in definitions {
            self.register_shared(definition)?;
        }
        Ok(())
    }

    /// Registers a definition by value.
    pub fn register<D>(&mut self, definition: D) -> Result<(), ElementRegistryError>
    where
        D: ElementDefinition + 'static,
    {
        self.register_shared(Arc::new(definition))
    }

    /// Registers an already shared definition.
    pub fn register_shared(
        &mut self,
        definition: Arc<dyn ElementDefinition>,
    ) -> Result<(), ElementRegistryError> {
        let type_value = definition.type_id_value().to_owned();

        if self.definitions_by_type_value.contains_key(&type_value) {
            return Err(ElementRegistryError::AlreadyRegistered(type_value));
        }

        self.definitions_by_type_value
            .insert(type_value, definition);
        Ok(())
    }

    /// Returns the definition for a type id.
    pub fn get<T: ElementData + ?Sized>(
        &self,
        type_id: &ElementTypeId<T>,
    ) -> Option<&Arc<dyn ElementDefinition>> {
        self.get_definition(type_id)
    }

    /// Returns the definition for a type id.
    pub fn get_definition<T: ElementData + ?Sized>(
        &self,
        type_id: &ElementTypeId<T>,
    ) -> Option<&Arc<dyn ElementDefinition>> {
        self.definitions_by_type_value.get(type_id.as_str())
    }

    /// Returns a downcasted definition for a type id when the concrete type
    /// matches `TDefinition`.
    pub fn get_definition_as<TData, TDefinition>(
        &self,
        type_id: &ElementTypeId<TData>,
    ) -> Option<&TDefinition>
    where
        TData: ElementData + ?Sized,
        TDefinition: ElementDefinition + 'static,
    {
        self.get_definition(type_id)
            .and_then(|definition| definition.as_ref().as_any().downcast_ref::<TDefinition>())
    }

    /// Returns the definition for a raw type value.
    pub fn get_definition_by_value(&self, type_value: &str) -> Option<&Arc<dyn ElementDefinition>> {
        self.definitions_by_type_value.get(type_value)
    }

    /// Returns true if the given type id is registered.
    pub fn supports<T: ElementData + ?Sized>(&self, type_id: &ElementTypeId<T>) -> bool {
        self.get_definition(type_id).is_some()
    }

    /// Returns true if the raw type value is registered.
    pub fn supports_type_value(&self, type_value: &str) -> bool {
        self.definitions_by_type_value.contains_key(type_value)
    }

    /// Returns the definition for `type_id` or an error when not registered.
    pub fn require<T: ElementData + ?Sized>(
        &self,
        type_id: &ElementTypeId<T>,
    ) -> Result<&Arc<dyn ElementDefinition>, ElementRegistryError> {
        self.get_definition(type_id)
            .ok_or_else(|| ElementRegistryError::NotRegistered(type_id.as_str().to_owned()))
    }

    /// Returns a downcasted required definition for `type_id`.
    pub fn require_as<TData, TDefinition>(
        &self,
        type_id: &ElementTypeId<TData>,
    ) -> Result<&TDefinition, ElementRegistryError>
    where
        TData: ElementData + ?Sized,
        TDefinition: ElementDefinition + 'static,
    {
        self.get_definition_as::<TData, TDefinition>(type_id)
            .ok_or_else(|| ElementRegistryError::NotRegistered(type_id.as_str().to_owned()))
    }

    /// Returns all registered type ids.
    pub fn registered_type_ids(&self) -> impl Iterator<Item = ElementTypeId<DynElementData>> + '_ {
        self.definitions_by_type_value
            .keys()
            .cloned()
            .map(ElementTypeId::new)
    }

    /// Clears all registrations.
    pub fn clear(&mut self) {
        self.definitions_by_type_value.clear();
    }

    /// Creates a cloned registry instance.
    pub fn clone_registry(&self) -> Self {
        self.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug)]
    struct TestDefinition {
        type_value: String,
    }

    impl TestDefinition {
        fn new(type_value: &str) -> Self {
            Self {
                type_value: type_value.to_owned(),
            }
        }
    }

    impl ElementDefinition for TestDefinition {
        fn type_id_value(&self) -> &str {
            &self.type_value
        }

        fn create_default_data(
            &self,
            _style_defaults: &ElementStyleConfig,
        ) -> Arc<dyn CreationElementData> {
            Arc::new(())
        }

        fn creation_strategy(&self) -> Option<Box<dyn CreationStrategy>> {
            None
        }

        fn as_any(&self) -> &dyn Any {
            self
        }
    }

    #[test]
    fn register_and_lookup_by_type_id() {
        let mut registry = DefaultElementRegistry::new();
        registry
            .register(TestDefinition::new("line"))
            .expect("line definition should register");

        let line_type_id: ElementTypeId<DynElementData> = ElementTypeId::new("line");
        assert!(registry.supports(&line_type_id));
        assert!(registry.get(&line_type_id).is_some());
        assert!(registry
            .get_definition_as::<DynElementData, TestDefinition>(&line_type_id)
            .is_some());
    }

    #[test]
    fn duplicate_registration_returns_error() {
        let mut registry = DefaultElementRegistry::new();
        registry
            .register(TestDefinition::new("text"))
            .expect("first registration should succeed");

        let duplicate = registry
            .register(TestDefinition::new("text"))
            .expect_err("duplicate registration should fail");

        assert_eq!(
            duplicate,
            ElementRegistryError::AlreadyRegistered("text".to_owned())
        );
    }

    #[test]
    fn require_missing_returns_error() {
        let registry = DefaultElementRegistry::new();
        let missing_type_id: ElementTypeId<DynElementData> = ElementTypeId::new("missing");

        let error = match registry.require(&missing_type_id) {
            Ok(_) => panic!("missing type should fail"),
            Err(error) => error,
        };

        assert_eq!(
            error,
            ElementRegistryError::NotRegistered("missing".to_owned())
        );
    }

    #[test]
    fn clone_preserves_registration_set() {
        let mut registry = DefaultElementRegistry::new();
        registry
            .register(TestDefinition::new("rect"))
            .expect("rect should register");

        let cloned = registry.clone_registry();
        assert!(cloned.supports_type_value("rect"));

        let cloned_type_ids: Vec<String> = cloned
            .registered_type_ids()
            .map(|type_id| type_id.as_str().to_owned())
            .collect();
        assert_eq!(cloned_type_ids, vec!["rect".to_owned()]);
    }
}

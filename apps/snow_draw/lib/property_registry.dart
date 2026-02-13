import 'property_descriptor.dart';

/// Registry of all style properties
///
/// This is the central place where all properties are registered and can be
/// queried based on the current selection context
class PropertyRegistry {
  PropertyRegistry._();

  static final instance = PropertyRegistry._();

  final Map<String, PropertyDescriptor<dynamic>> _propertiesById = {};

  /// Register a property descriptor.
  ///
  /// If a descriptor with the same [PropertyDescriptor.id] already exists,
  /// it is replaced in place to keep ordering stable and IDs unique.
  void register(PropertyDescriptor<dynamic> descriptor) =>
      _propertiesById[descriptor.id] = descriptor;

  /// Get all properties that are applicable for the given context
  List<PropertyDescriptor<dynamic>> getApplicableProperties(
    StylePropertyContext context,
  ) => _propertiesById.values
      .where((prop) => prop.isApplicable(context))
      .toList();

  /// Get a specific property by ID
  PropertyDescriptor<dynamic>? getProperty(String id) => _propertiesById[id];

  /// Clear all registered properties (useful for testing)
  void clear() {
    _propertiesById.clear();
  }

  /// Get all registered properties
  List<PropertyDescriptor<dynamic>> get allProperties =>
      List.unmodifiable(_propertiesById.values);
}

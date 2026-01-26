import 'property_descriptor.dart';

/// Registry of all style properties
///
/// This is the central place where all properties are registered and can be
/// queried based on the current selection context
class PropertyRegistry {
  PropertyRegistry._();

  static final PropertyRegistry instance = PropertyRegistry._();

  final List<PropertyDescriptor> _properties = [];

  /// Register a property descriptor
  void register(PropertyDescriptor descriptor) {
    _properties.add(descriptor);
  }

  /// Get all properties that are applicable for the given context
  List<PropertyDescriptor> getApplicableProperties(
    StylePropertyContext context,
  ) {
    return _properties
        .where((prop) => prop.isApplicable(context))
        .toList();
  }

  /// Get a specific property by ID
  PropertyDescriptor? getProperty(String id) {
    try {
      return _properties.firstWhere((prop) => prop.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Clear all registered properties (useful for testing)
  void clear() {
    _properties.clear();
  }

  /// Get all registered properties
  List<PropertyDescriptor> get allProperties => List.unmodifiable(_properties);
}

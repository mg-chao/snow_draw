import 'property_descriptor.dart';

/// Registry of all style properties
///
/// This is the central place where all properties are registered and can be
/// queried based on the current selection context
class PropertyRegistry {
  PropertyRegistry._();

  static final instance = PropertyRegistry._();

  final List<PropertyDescriptor<dynamic>> _properties = [];

  /// Register a property descriptor
  void register(PropertyDescriptor<dynamic> descriptor) {
    _properties.add(descriptor);
  }

  /// Get all properties that are applicable for the given context
  List<PropertyDescriptor<dynamic>> getApplicableProperties(
    StylePropertyContext context,
  ) => _properties.where((prop) => prop.isApplicable(context)).toList();

  /// Get a specific property by ID
  PropertyDescriptor<dynamic>? getProperty(String id) {
    for (final prop in _properties) {
      if (prop.id == id) {
        return prop;
      }
    }
    return null;
  }

  /// Clear all registered properties (useful for testing)
  void clear() {
    _properties.clear();
  }

  /// Get all registered properties
  List<PropertyDescriptor<dynamic>> get allProperties =>
      List.unmodifiable(_properties);
}

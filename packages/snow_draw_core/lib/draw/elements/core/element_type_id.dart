import 'package:meta/meta.dart';

/// Strongly typed identifier for element types.
@immutable
class ElementTypeId<T> {
  const ElementTypeId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ElementTypeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

import 'package:meta/meta.dart';

/// Strongly typed identifier for element types.
@immutable
class ElementTypeId<T> {
  const ElementTypeId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ElementTypeId<Object?> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

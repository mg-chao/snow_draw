import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'element_data.dart';
import 'element_type_id.dart';

/// Placeholder payload for unknown element types.
@immutable
class UnknownElementData extends ElementData {
  UnknownElementData({
    required this.originalType,
    required Map<String, dynamic> rawData,
  }) : _typeId = ElementTypeId<ElementData>(originalType),
       rawData = _deepFreezeMap(rawData);
  final String originalType;
  final ElementTypeId<ElementData> _typeId;
  final Map<String, dynamic> rawData;

  static const _deepEquality = DeepCollectionEquality();

  @override
  ElementTypeId<ElementData> get typeId => _typeId;

  @override
  Map<String, dynamic> toJson() => _deepCloneMap(rawData);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownElementData &&
          runtimeType == other.runtimeType &&
          originalType == other.originalType &&
          _deepEquality.equals(rawData, other.rawData);

  @override
  int get hashCode => Object.hash(originalType, _deepEquality.hash(rawData));

  static Map<String, dynamic> _deepFreezeMap(Map<String, dynamic> source) {
    final frozen = <String, dynamic>{};
    for (final entry in source.entries) {
      frozen[entry.key] = _deepFreezeValue(entry.value);
    }
    return Map<String, dynamic>.unmodifiable(frozen);
  }

  static Object? _deepFreezeValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return _deepFreezeMap(value);
    }
    if (value is Map) {
      final frozen = <Object?, Object?>{};
      for (final entry in value.entries) {
        frozen[entry.key] = _deepFreezeValue(entry.value);
      }
      return Map<Object?, Object?>.unmodifiable(frozen);
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map<Object?>(_deepFreezeValue));
    }
    return value;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> source) {
    final cloned = <String, dynamic>{};
    for (final entry in source.entries) {
      cloned[entry.key] = _deepCloneValue(entry.value);
    }
    return cloned;
  }

  static Object? _deepCloneValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return _deepCloneMap(value);
    }
    if (value is Map) {
      final cloned = <Object?, Object?>{};
      for (final entry in value.entries) {
        cloned[entry.key] = _deepCloneValue(entry.value);
      }
      return cloned;
    }
    if (value is List) {
      return value.map<Object?>(_deepCloneValue).toList();
    }
    return value;
  }
}

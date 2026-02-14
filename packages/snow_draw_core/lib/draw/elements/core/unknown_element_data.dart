import 'package:meta/meta.dart';

import 'element_data.dart';
import 'element_type_id.dart';

/// Placeholder payload for unknown element types.
@immutable
class UnknownElementData extends ElementData {
  UnknownElementData({
    required this.originalType,
    required Map<String, dynamic> rawData,
  }) : rawData = _deepFreezeMap(rawData);
  final String originalType;
  final Map<String, dynamic> rawData;

  @override
  ElementTypeId<ElementData> get typeId =>
      ElementTypeId<ElementData>(originalType);

  @override
  Map<String, dynamic> toJson() => _deepCloneMap(rawData);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownElementData &&
          runtimeType == other.runtimeType &&
          originalType == other.originalType &&
          _deepEquals(rawData, other.rawData);

  @override
  int get hashCode => Object.hash(originalType, _deepHash(rawData));

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

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) {
          return false;
        }
        if (!_deepEquals(entry.value, b[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  static int _deepHash(Object? value) {
    if (value is Map) {
      final entryHashes = <int>[];
      for (final entry in value.entries) {
        entryHashes.add(
          Object.hash(_deepHash(entry.key), _deepHash(entry.value)),
        );
      }
      entryHashes.sort();
      return Object.hashAll(entryHashes);
    }
    if (value is List) {
      return Object.hashAll(value.map(_deepHash));
    }
    return value.hashCode;
  }
}

import 'package:meta/meta.dart';

import 'element_data.dart';
import 'element_type_id.dart';

/// Placeholder payload for unknown element types.
@immutable
class UnknownElementData extends ElementData {
  UnknownElementData({
    required this.originalType,
    required Map<String, dynamic> rawData,
  }) : rawData = Map.unmodifiable(rawData);
  final String originalType;
  final Map<String, dynamic> rawData;

  @override
  ElementTypeId<ElementData> get typeId =>
      ElementTypeId<ElementData>(originalType);

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(rawData);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownElementData &&
          runtimeType == other.runtimeType &&
          originalType == other.originalType &&
          _mapsEqual(rawData, other.rawData);

  @override
  int get hashCode => Object.hash(originalType, _mapHash(rawData));

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static int _mapHash(Map<String, dynamic> map) {
    var hash = 0;
    for (final entry in map.entries) {
      hash = Object.hash(hash, entry.key, entry.value);
    }
    return hash;
  }
}

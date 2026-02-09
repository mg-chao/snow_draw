import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../../core/element_style_configurable_data.dart';
import '../../core/element_style_updatable_data.dart';
import '../../core/element_type_id.dart';

@immutable
final class FilterData extends ElementData
    with ElementStyleConfigurableData, ElementStyleUpdatableData {
  const FilterData({
    this.type = ConfigDefaults.defaultFilterType,
    this.strength = ConfigDefaults.defaultFilterStrength,
  }) : assert(strength >= 0 && strength <= 1, 'strength must be in [0, 1]');

  factory FilterData.fromJson(Map<String, dynamic> json) => FilterData(
    type: CanvasFilterType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => ConfigDefaults.defaultFilterType,
    ),
    strength: _normalizeStrength(
      (json['strength'] as num?)?.toDouble() ??
          ConfigDefaults.defaultFilterStrength,
    ),
  );

  static const typeIdToken = ElementTypeId<FilterData>('filter');

  final CanvasFilterType type;
  final double strength;

  @override
  ElementTypeId<FilterData> get typeId => FilterData.typeIdToken;

  FilterData copyWith({CanvasFilterType? type, double? strength}) => FilterData(
    type: type ?? this.type,
    strength: _normalizeStrength(strength ?? this.strength),
  );

  @override
  ElementData withElementStyle(ElementStyleConfig style) =>
      copyWith(type: style.filterType, strength: style.filterStrength);

  @override
  ElementData withStyleUpdate(ElementStyleUpdate update) => copyWith(
    type: update.filterType ?? type,
    strength: update.filterStrength ?? strength,
  );

  @override
  Map<String, dynamic> toJson() => {
    'typeId': typeId.value,
    'type': type.name,
    'strength': strength,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterData && other.type == type && other.strength == strength;

  @override
  int get hashCode => Object.hash(type, strength);

  static double _normalizeStrength(double value) => value.clamp(0.0, 1.0);
}

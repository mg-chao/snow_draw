import 'package:meta/meta.dart';

import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_type_id.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Element state (fully immutable).
@immutable
class ElementState {
  const ElementState({
    required this.id,
    required this.rect,
    required this.rotation,
    required this.opacity,
    required this.zIndex,
    required this.data,
  });
  final String id;
  final DrawRect rect;
  final double rotation;
  final double opacity;
  final int zIndex;
  final ElementData data;

  ElementTypeId<ElementData> get typeId => data.typeId;

  ElementState copyWith({
    String? id,
    DrawRect? rect,
    double? rotation,
    double? opacity,
    int? zIndex,
    ElementData? data,
  }) => ElementState(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    rotation: rotation ?? this.rotation,
    opacity: opacity ?? this.opacity,
    zIndex: zIndex ?? this.zIndex,
    data: data ?? this.data,
  );

  ElementState movedBy(double dx, double dy) => copyWith(
    rect: rect.translate(DrawPoint(x: dx, y: dy)),
  );

  DrawPoint get center => rect.center;

  bool isValidWith(ElementConfig config) =>
      rect.width >= config.minValidSize && rect.height >= config.minValidSize;

  bool get isValid => isValidWith(const ElementConfig());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementState &&
          other.id == id &&
          other.rect == rect &&
          other.rotation == rotation &&
          other.opacity == opacity &&
          other.zIndex == zIndex &&
          other.data == data;

  @override
  int get hashCode => Object.hash(id, rect, rotation, opacity, zIndex, data);

  @override
  String toString() =>
      'ElementState(id: $id, rect: $rect, rotation: $rotation, '
      'opacity: $opacity, zIndex: $zIndex, typeId: $typeId)';
}

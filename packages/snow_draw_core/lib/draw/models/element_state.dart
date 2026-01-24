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

  ElementState withPosition(double x, double y) => copyWith(
    rect: DrawRect(
      minX: x,
      minY: y,
      maxX: x + rect.width,
      maxY: y + rect.height,
    ),
  );

  ElementState withSize(double width, double height) => copyWith(
    rect: DrawRect(
      minX: rect.minX,
      minY: rect.minY,
      maxX: rect.minX + width,
      maxY: rect.minY + height,
    ),
  );

  ElementState movedBy(double dx, double dy) => copyWith(
    rect: rect.translate(DrawPoint(x: dx, y: dy)),
  );

  ElementState withRotation(double rotation) => copyWith(rotation: rotation);

  ElementState withOpacity(double opacity) => copyWith(opacity: opacity);

  DrawPoint get center => rect.center;

  double get width => rect.width;

  double get height => rect.height;

  bool isValidWith(ElementConfig config) =>
      width >= config.minValidSize && height >= config.minValidSize;

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

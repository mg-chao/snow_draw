import 'package:flutter/widgets.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';

/// Flutter visual metadata for a single element type.
///
/// This keeps backend-specific concerns out of core domain definitions.
@immutable
class ElementVisualDefinition<T extends ElementData> {
  /// Creates a visual definition for one element type.
  const ElementVisualDefinition({required this.typeId, this.icon});

  /// Element type identifier shared with domain definitions.
  final ElementTypeId<T> typeId;

  /// Optional toolbar/icon representation for this type.
  final IconData? icon;
}

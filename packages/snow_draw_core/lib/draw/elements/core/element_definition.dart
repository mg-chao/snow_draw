import 'package:flutter/widgets.dart';

import 'creation_strategy.dart';
import 'element_data.dart';
import 'element_hit_tester.dart';
import 'element_renderer.dart';
import 'element_type_id.dart';

/// Definition for a single element type.
///
/// Bundles together all type-specific behavior: data factory, renderer and hit
/// tester.
@immutable
class ElementDefinition<T extends ElementData> {
  const ElementDefinition({
    required this.typeId,
    required this.displayName,
    required this.renderer,
    required this.hitTester,
    required this.createDefaultData,
    required this.fromJson,
    this.creationStrategy,
    this.icon,
  });
  final ElementTypeId<T> typeId;
  final String displayName;
  final IconData? icon;
  final ElementTypeRenderer renderer;
  final ElementHitTester hitTester;
  final T Function() createDefaultData;
  final T Function(Map<String, dynamic> json) fromJson;
  final CreationStrategy? creationStrategy;
}

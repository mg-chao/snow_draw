import 'package:meta/meta.dart';

import 'creation_strategy.dart';
import 'element_data.dart';
import 'element_hit_tester.dart';
import 'element_scene_encoder.dart';
import 'element_type_id.dart';

/// Definition for a single element type.
///
/// Bundles type-specific behavior such as rendering, hit testing, and
/// (de)serialization.
@immutable
class ElementDefinition<T extends ElementData> {
  const ElementDefinition({
    required this.typeId,
    required this.displayName,
    required this.hitTester,
    required this.createDefaultData,
    required this.fromJson,
    required this.sceneEncoder,
    this.creationStrategy,
  });
  final ElementTypeId<T> typeId;
  final String displayName;
  final ElementHitTester hitTester;
  final T Function() createDefaultData;
  final T Function(Map<String, dynamic> json) fromJson;
  final CreationStrategy? creationStrategy;
  final ElementSceneEncoder<T> sceneEncoder;
}

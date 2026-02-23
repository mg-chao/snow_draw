import '../../core/element_definition.dart';
import 'arrow_creation_strategy.dart';
import 'arrow_data.dart';
import 'arrow_hit_tester.dart';
import 'arrow_scene_encoder.dart';

const arrowDefinition = ElementDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  displayName: 'Arrow',
  hitTester: ArrowHitTester(),
  createDefaultData: ArrowData.new,
  fromJson: ArrowData.fromJson,
  creationStrategy: ArrowCreationStrategy(),
  sceneEncoder: ArrowSceneEncoder(),
);

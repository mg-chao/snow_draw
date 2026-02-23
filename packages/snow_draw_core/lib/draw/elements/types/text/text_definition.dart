import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'text_data.dart';
import 'text_hit_tester.dart';
import 'text_scene_encoder.dart';

const textDefinition = ElementDefinition<TextData>(
  typeId: TextData.typeIdToken,
  displayName: 'Text',
  hitTester: TextHitTester(),
  createDefaultData: TextData.new,
  fromJson: TextData.fromJson,
  creationStrategy: RectCreationStrategy(),
  sceneEncoder: TextSceneEncoder(),
);

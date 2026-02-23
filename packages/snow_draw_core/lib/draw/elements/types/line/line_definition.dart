import '../../core/element_definition.dart';
import '../arrow/arrow_creation_strategy.dart';
import 'line_data.dart';
import 'line_hit_tester.dart';
import 'line_scene_encoder.dart';

const lineDefinition = ElementDefinition<LineData>(
  typeId: LineData.typeIdToken,
  displayName: 'Line',
  hitTester: LineHitTester(),
  createDefaultData: LineData.new,
  fromJson: LineData.fromJson,
  creationStrategy: ArrowCreationStrategy(),
  sceneEncoder: LineSceneEncoder(),
);

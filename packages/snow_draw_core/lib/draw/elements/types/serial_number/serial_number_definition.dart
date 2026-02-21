import '../../core/element_definition.dart';
import 'serial_number_creation_strategy.dart';
import 'serial_number_data.dart';
import 'serial_number_hit_tester.dart';
import 'serial_number_scene_encoder.dart';

const serialNumberDefinition = ElementDefinition<SerialNumberData>(
  typeId: SerialNumberData.typeIdToken,
  displayName: 'Serial Number',
  hitTester: SerialNumberHitTester(),
  createDefaultData: SerialNumberData.new,
  fromJson: SerialNumberData.fromJson,
  creationStrategy: SerialNumberCreationStrategy(),
  sceneEncoder: SerialNumberSceneEncoder(),
);

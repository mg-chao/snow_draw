import '../../core/element_definition.dart';
import 'free_draw_creation_strategy.dart';
import 'free_draw_data.dart';
import 'free_draw_hit_tester.dart';
import 'free_draw_task_encoder.dart';

const freeDrawDefinition = ElementDefinition<FreeDrawData>(
  typeId: FreeDrawData.typeIdToken,
  displayName: 'Free Draw',
  hitTester: FreeDrawHitTester(),
  createDefaultData: _createDefaultFreeDrawData,
  fromJson: FreeDrawData.fromJson,
  creationStrategy: FreeDrawCreationStrategy(),
  taskEncoder: FreeDrawTaskEncoder(),
);

FreeDrawData _createDefaultFreeDrawData() => const FreeDrawData();

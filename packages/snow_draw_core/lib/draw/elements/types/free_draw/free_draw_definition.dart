import '../../core/element_definition.dart';
import 'free_draw_creation_strategy.dart';
import 'free_draw_data.dart';
import 'free_draw_hit_tester.dart';
import 'free_draw_task_encoder.dart';

final freeDrawDefinition = ElementDefinition<FreeDrawData>(
  typeId: FreeDrawData.typeIdToken,
  displayName: 'Free Draw',
  hitTester: const FreeDrawHitTester(),
  createDefaultData: _createDefaultFreeDrawData,
  fromJson: FreeDrawData.fromJson,
  creationStrategy: const FreeDrawCreationStrategy(),
  taskEncoder: const FreeDrawTaskEncoder(),
);

FreeDrawData _createDefaultFreeDrawData() => const FreeDrawData();

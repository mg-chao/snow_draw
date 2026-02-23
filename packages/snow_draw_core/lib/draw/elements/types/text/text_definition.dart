import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'text_data.dart';
import 'text_hit_tester.dart';
import 'text_task_encoder.dart';

final textDefinition = ElementDefinition<TextData>(
  typeId: TextData.typeIdToken,
  displayName: 'Text',
  hitTester: const TextHitTester(),
  createDefaultData: TextData.new,
  fromJson: TextData.fromJson,
  creationStrategy: const RectCreationStrategy(),
  taskEncoder: const TextTaskEncoder(),
);

import '../../core/element_definition.dart';
import '../arrow/arrow_creation_strategy.dart';
import 'line_data.dart';
import 'line_hit_tester.dart';
import 'line_task_encoder.dart';

final lineDefinition = ElementDefinition<LineData>(
  typeId: LineData.typeIdToken,
  displayName: 'Line',
  hitTester: const LineHitTester(),
  createDefaultData: LineData.new,
  fromJson: LineData.fromJson,
  creationStrategy: const ArrowCreationStrategy(),
  taskEncoder: const LineTaskEncoder(),
);

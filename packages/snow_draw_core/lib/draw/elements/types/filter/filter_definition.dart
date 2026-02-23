import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'filter_data.dart';
import 'filter_hit_tester.dart';
import 'filter_task_encoder.dart';

final filterDefinition = ElementDefinition<FilterData>(
  typeId: FilterData.typeIdToken,
  displayName: 'Filter',
  hitTester: const FilterHitTester(),
  createDefaultData: FilterData.new,
  fromJson: FilterData.fromJson,
  creationStrategy: const RectCreationStrategy(),
  taskEncoder: const FilterTaskEncoder(),
);

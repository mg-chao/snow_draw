import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'rectangle_data.dart';
import 'rectangle_hit_tester.dart';
import 'rectangle_task_encoder.dart';

const rectangleDefinition = ElementDefinition<RectangleData>(
  typeId: RectangleData.typeIdToken,
  displayName: 'Rectangle',
  hitTester: RectangleHitTester(),
  createDefaultData: RectangleData.new,
  fromJson: RectangleData.fromJson,
  creationStrategy: RectCreationStrategy(),
  taskEncoder: RectangleTaskEncoder(),
);

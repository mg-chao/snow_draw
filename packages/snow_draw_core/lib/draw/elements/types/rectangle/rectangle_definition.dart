import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'rectangle_data.dart';
import 'rectangle_hit_tester.dart';
import 'rectangle_renderer.dart';

const rectangleDefinition = ElementDefinition<RectangleData>(
  typeId: RectangleData.typeIdToken,
  displayName: 'Rectangle',
  icon: Icons.rectangle_outlined,
  renderer: RectangleRenderer(),
  hitTester: RectangleHitTester(),
  createDefaultData: RectangleData.new,
  fromJson: RectangleData.fromJson,
  creationStrategy: RectCreationStrategy(),
);

import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'rectangle_data.dart';
import 'rectangle_hit_tester.dart';
import 'rectangle_renderer.dart';

final rectangleDefinition = ElementDefinition<RectangleData>(
  typeId: RectangleData.typeIdToken,
  displayName: 'Rectangle',
  icon: Icons.rectangle_outlined,
  renderer: const RectangleRenderer(),
  hitTester: const RectangleHitTester(),
  createDefaultData: () => const RectangleData(),
  fromJson: RectangleData.fromJson,
);

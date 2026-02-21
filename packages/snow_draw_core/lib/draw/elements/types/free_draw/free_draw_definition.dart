import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'free_draw_creation_strategy.dart';
import 'free_draw_data.dart';
import 'free_draw_hit_tester.dart';
import 'free_draw_renderer.dart';

const freeDrawDefinition = ElementDefinition<FreeDrawData>(
  typeId: FreeDrawData.typeIdToken,
  displayName: 'Free Draw',
  icon: Icons.brush_outlined,
  renderer: FreeDrawRenderer(),
  hitTester: FreeDrawHitTester(),
  createDefaultData: _createDefaultFreeDrawData,
  fromJson: FreeDrawData.fromJson,
  creationStrategy: FreeDrawCreationStrategy(),
);

FreeDrawData _createDefaultFreeDrawData() => const FreeDrawData();

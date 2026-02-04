import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'free_draw_creation_strategy.dart';
import 'free_draw_data.dart';
import 'free_draw_hit_tester.dart';
import 'free_draw_renderer.dart';

final freeDrawDefinition = ElementDefinition<FreeDrawData>(
  typeId: FreeDrawData.typeIdToken,
  displayName: 'Free Draw',
  icon: Icons.brush_outlined,
  renderer: const FreeDrawRenderer(),
  hitTester: const FreeDrawHitTester(),
  createDefaultData: () => const FreeDrawData(),
  fromJson: FreeDrawData.fromJson,
  creationStrategy: const FreeDrawCreationStrategy(),
);

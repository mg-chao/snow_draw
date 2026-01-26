import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'text_data.dart';
import 'text_hit_tester.dart';
import 'text_renderer.dart';

final textDefinition = ElementDefinition<TextData>(
  typeId: TextData.typeIdToken,
  displayName: 'Text',
  icon: Icons.text_fields,
  renderer: const TextRenderer(),
  hitTester: const TextHitTester(),
  createDefaultData: () => const TextData(),
  fromJson: TextData.fromJson,
  creationStrategy: const RectCreationStrategy(),
);

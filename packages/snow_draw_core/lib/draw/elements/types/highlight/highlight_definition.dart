import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'highlight_data.dart';
import 'highlight_hit_tester.dart';
import 'highlight_renderer.dart';

final highlightDefinition = ElementDefinition<HighlightData>(
  typeId: HighlightData.typeIdToken,
  displayName: 'Highlight',
  icon: Icons.highlight,
  renderer: const HighlightRenderer(),
  hitTester: const HighlightHitTester(),
  createDefaultData: () => const HighlightData(),
  fromJson: HighlightData.fromJson,
  creationStrategy: const RectCreationStrategy(),
);

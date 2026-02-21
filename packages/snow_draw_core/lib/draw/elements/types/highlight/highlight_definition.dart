import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'highlight_data.dart';
import 'highlight_hit_tester.dart';
import 'highlight_renderer.dart';

HighlightData _createDefaultHighlightData() => const HighlightData();

const highlightDefinition = ElementDefinition<HighlightData>(
  typeId: HighlightData.typeIdToken,
  displayName: 'Highlight',
  icon: Icons.highlight,
  renderer: HighlightRenderer(),
  hitTester: HighlightHitTester(),
  createDefaultData: _createDefaultHighlightData,
  fromJson: HighlightData.fromJson,
  creationStrategy: RectCreationStrategy(),
);

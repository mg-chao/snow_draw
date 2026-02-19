import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'arrow_creation_strategy.dart';
import 'arrow_data.dart';
import 'arrow_hit_tester.dart';
import 'arrow_renderer.dart';

const arrowDefinition = ElementDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  displayName: 'Arrow',
  icon: Icons.arrow_right_alt,
  renderer: ArrowRenderer(),
  hitTester: ArrowHitTester(),
  createDefaultData: ArrowData.new,
  fromJson: ArrowData.fromJson,
  creationStrategy: ArrowCreationStrategy(),
);

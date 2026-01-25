import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'arrow_data.dart';
import 'arrow_hit_tester.dart';
import 'arrow_renderer.dart';

final arrowDefinition = ElementDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  displayName: 'Arrow',
  icon: Icons.arrow_right_alt,
  renderer: const ArrowRenderer(),
  hitTester: const ArrowHitTester(),
  createDefaultData: () => const ArrowData(),
  fromJson: ArrowData.fromJson,
);

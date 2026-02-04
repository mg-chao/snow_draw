import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import 'serial_number_creation_strategy.dart';
import 'serial_number_data.dart';
import 'serial_number_hit_tester.dart';
import 'serial_number_renderer.dart';

final serialNumberDefinition = ElementDefinition<SerialNumberData>(
  typeId: SerialNumberData.typeIdToken,
  displayName: 'Serial Number',
  icon: Icons.looks_one_outlined,
  renderer: const SerialNumberRenderer(),
  hitTester: const SerialNumberHitTester(),
  createDefaultData: () => const SerialNumberData(),
  fromJson: SerialNumberData.fromJson,
  creationStrategy: const SerialNumberCreationStrategy(),
);

import 'package:flutter/material.dart';

import '../../core/element_definition.dart';
import '../../core/rect_creation_strategy.dart';
import 'filter_data.dart';
import 'filter_hit_tester.dart';
import 'filter_renderer.dart';

const filterDefinition = ElementDefinition<FilterData>(
  typeId: FilterData.typeIdToken,
  displayName: 'Filter',
  icon: Icons.auto_fix_high,
  renderer: FilterRenderer(),
  hitTester: FilterHitTester(),
  createDefaultData: FilterData.new,
  fromJson: FilterData.fromJson,
  creationStrategy: RectCreationStrategy(),
);

import 'dart:collection';

import '../../../models/element_state.dart';
import 'serial_number_data.dart';

/// Expands [seedIds] with transitive serial-number bound text dependencies.
///
/// Serial-number elements may own companion text elements via
/// [SerialNumberData.textElementId]. Delete/duplicate/history flows use this
/// helper so they all resolve the same dependency closure.
Set<String> expandSerialNumberBoundTextIds({
  required Iterable<ElementState> elements,
  required Iterable<String> seedIds,
}) {
  final serialBindings = <String, String>{};
  for (final element in elements) {
    final data = element.data;
    if (data is SerialNumberData && data.textElementId != null) {
      serialBindings[element.id] = data.textElementId!;
    }
  }

  final expandedIds = {...seedIds};
  final pending = ListQueue<String>.from(expandedIds);
  while (pending.isNotEmpty) {
    final id = pending.removeFirst();
    final boundId = serialBindings[id];
    if (boundId == null) {
      continue;
    }
    if (expandedIds.add(boundId)) {
      pending.add(boundId);
    }
  }

  return expandedIds;
}

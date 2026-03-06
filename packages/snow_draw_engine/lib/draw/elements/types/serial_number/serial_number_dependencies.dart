import 'dart:collection';

import '../../../models/element_state.dart';
import '../arrow/arrow_binding.dart';
import '../arrow/arrow_like_data.dart';
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

/// Returns whether [element] references any id in [targetIds].
///
/// References include serial-number text bindings and/or arrow endpoint
/// bindings based on the enabled flags.
bool isElementDependentOnIds({
  required ElementState element,
  required Set<String> targetIds,
  bool includeSerialBindings = true,
  bool includeArrowBindings = true,
}) {
  if (targetIds.isEmpty) {
    return false;
  }

  final data = element.data;
  if (includeSerialBindings && data is SerialNumberData) {
    final boundId = data.textElementId;
    if (boundId != null && targetIds.contains(boundId)) {
      return true;
    }
  }

  if (!includeArrowBindings || data is! ConnectorData) {
    return false;
  }

  return ArrowBindingUtils.isBoundToAnyTargets(
    startBinding: data.startBinding,
    endBinding: data.endBinding,
    targetIds: targetIds,
  );
}

/// Collects ids of elements that reference [targetIds].
///
/// Use [excludedIds] to skip source ids that are being removed.
Set<String> collectDependentElementIds({
  required Iterable<ElementState> elements,
  required Set<String> targetIds,
  Set<String> excludedIds = const <String>{},
  bool includeSerialBindings = true,
  bool includeArrowBindings = true,
}) {
  if (targetIds.isEmpty) {
    return const <String>{};
  }

  final dependentIds = <String>{};
  for (final element in elements) {
    if (excludedIds.contains(element.id)) {
      continue;
    }
    if (!isElementDependentOnIds(
      element: element,
      targetIds: targetIds,
      includeSerialBindings: includeSerialBindings,
      includeArrowBindings: includeArrowBindings,
    )) {
      continue;
    }
    dependentIds.add(element.id);
  }
  return dependentIds;
}

/// Clears references from [element] that target any id in [targetIds].
///
/// Serial-number text links and arrow endpoint bindings are both supported.
/// When no dependency points to [targetIds], the original [element] is
/// returned unchanged.
ElementState clearElementDependenciesForIds({
  required ElementState element,
  required Set<String> targetIds,
  bool includeSerialBindings = true,
  bool includeArrowBindings = true,
}) {
  if (targetIds.isEmpty) {
    return element;
  }

  final data = element.data;
  if (includeSerialBindings && data is SerialNumberData) {
    final boundId = data.textElementId;
    if (boundId != null && targetIds.contains(boundId)) {
      return element.copyWith(data: data.copyWith(textElementId: null));
    }
    return element;
  }

  if (!includeArrowBindings || data is! ConnectorData) {
    return element;
  }

  final startBinding = data.startBinding;
  final endBinding = data.endBinding;
  final clearStart =
      startBinding != null && targetIds.contains(startBinding.elementId);
  final clearEnd =
      endBinding != null && targetIds.contains(endBinding.elementId);
  if (!clearStart && !clearEnd) {
    return element;
  }

  return element.copyWith(
    data: data.copyWith(
      startBinding: clearStart ? null : startBinding,
      endBinding: clearEnd ? null : endBinding,
      startIsSpecial: clearStart ? null : data.startIsSpecial,
      endIsSpecial: clearEnd ? null : data.endIsSpecial,
    ),
  );
}

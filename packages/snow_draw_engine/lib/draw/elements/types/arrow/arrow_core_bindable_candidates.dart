import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';

/// Resolved bindable candidates projected for arrow-core operations.
///
/// [elements] and [bindables] contain matching candidates, keyed by id.
@immutable
final class ArrowCoreBindableCandidates {
  factory ArrowCoreBindableCandidates({
    required List<ElementState> elements,
    required List<core.BindableState> bindables,
  }) => ArrowCoreBindableCandidates._(
    elements: elements,
    bindables: bindables,
    elementById: Map<String, ElementState>.unmodifiable({
      for (final element in elements) element.id: element,
    }),
    bindableById: Map<String, core.BindableState>.unmodifiable({
      for (final bindable in bindables) bindable.id: bindable,
    }),
  );

  static const empty = ArrowCoreBindableCandidates._(
    elements: <ElementState>[],
    bindables: <core.BindableState>[],
    elementById: <String, ElementState>{},
    bindableById: <String, core.BindableState>{},
  );

  const ArrowCoreBindableCandidates._({
    required this.elements,
    required this.bindables,
    required this.elementById,
    required this.bindableById,
  });

  final List<ElementState> elements;
  final List<core.BindableState> bindables;

  /// Elements keyed by id for O(1) lookups in binding/focus hot paths.
  final Map<String, ElementState> elementById;

  /// Bindables keyed by id for O(1) lookups in binding/focus hot paths.
  final Map<String, core.BindableState> bindableById;

  bool get isEmpty => bindables.isEmpty;

  ElementState? elementForId(String id) => elementById[id];

  core.BindableState? bindableForId(String id) => bindableById[id];
}

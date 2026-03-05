import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';

/// Resolved bindable candidates projected for arrow-core operations.
///
/// [elements] and [bindables] contain matching candidates, keyed by id.
@immutable
final class ArrowCoreBindableCandidates {
  const ArrowCoreBindableCandidates({
    required this.elements,
    required this.bindables,
  });

  static const empty = ArrowCoreBindableCandidates(
    elements: <ElementState>[],
    bindables: <core.BindableState>[],
  );

  final List<ElementState> elements;
  final List<core.BindableState> bindables;

  bool get isEmpty => bindables.isEmpty;
}

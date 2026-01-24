import 'package:meta/meta.dart';

import '../../models/element_state.dart';
import '../../types/draw_rect.dart';

/// Shared geometry result for edit preview and commit.
@immutable
class EditComputedResult {
  const EditComputedResult({
    required this.updatedElements,
    this.multiSelectBounds,
    this.multiSelectRotation,
  });
  final Map<String, ElementState> updatedElements;
  final DrawRect? multiSelectBounds;
  final double? multiSelectRotation;
}

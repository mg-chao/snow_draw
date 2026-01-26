import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/snap_guides.dart';
import '../../utils/snapping_mode.dart';
import '../core/element_data.dart';

/// Result for creation start/update phases.
@immutable
class CreationUpdateResult {
  const CreationUpdateResult({
    required this.data,
    required this.rect,
    required this.creationMode,
    this.snapGuides = const [],
  });
  final ElementData data;
  final DrawRect rect;
  final CreationMode creationMode;
  final List<SnapGuide> snapGuides;
}

/// Result for creation finish.
@immutable
class CreationFinishResult {
  const CreationFinishResult({
    required this.data,
    required this.rect,
    required this.shouldCommit,
  });
  final ElementData data;
  final DrawRect rect;
  final bool shouldCommit;
}

/// Strategy for element creation.
@immutable
abstract class CreationStrategy {
  const CreationStrategy();

  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  });

  CreationUpdateResult update({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required SnappingMode snappingMode,
  });

  CreationUpdateResult? addPoint({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint position,
    required SnappingMode snappingMode,
  }) => null;

  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  });
}

/// Creation strategy that supports point-based workflows.
@immutable
abstract class PointCreationStrategy extends CreationStrategy {
  const PointCreationStrategy();
}

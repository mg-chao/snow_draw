import 'package:meta/meta.dart';

import '../../models/camera_state.dart';
import 'render_tasks.dart';

/// Immutable frame-level rendering plan produced by core.
@immutable
class FrameRenderPlan {
  const FrameRenderPlan({
    required this.tasks,
    required this.camera,
    required this.scaleFactor,
    this.localeTag,
  });

  /// Ordered tasks to execute for the frame.
  final List<RenderTask> tasks;

  /// Camera transform snapshot.
  final CameraState camera;

  /// Effective scale factor used for world/canvas transforms.
  final double scaleFactor;

  /// Optional locale hint for text layout/rendering.
  final String? localeTag;

  static const empty = FrameRenderPlan(
    tasks: <RenderTask>[],
    camera: CameraState.initial,
    scaleFactor: 1,
  );
}

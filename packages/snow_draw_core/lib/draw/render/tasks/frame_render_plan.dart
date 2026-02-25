import 'package:meta/meta.dart';

import '../../models/camera_state.dart';
import '../../utils/list_equality.dart';
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

  /// Ordered frame tasks to execute for the frame.
  final List<FrameRenderTask> tasks;

  /// Camera transform snapshot.
  final CameraState camera;

  /// Effective scale factor used for world/canvas transforms.
  final double scaleFactor;

  /// Optional locale hint for text layout/rendering.
  final String? localeTag;

  static const empty = FrameRenderPlan(
    tasks: <FrameRenderTask>[],
    camera: CameraState.initial,
    scaleFactor: 1,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameRenderPlan &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor &&
          other.localeTag == localeTag &&
          listEquals(other.tasks, tasks);

  @override
  int get hashCode =>
      Object.hash(listHash(tasks), camera, scaleFactor, localeTag);
}

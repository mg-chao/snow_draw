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
          _taskListEquals(other.tasks, tasks);

  @override
  int get hashCode =>
      Object.hash(_taskListHash(tasks), camera, scaleFactor, localeTag);
}

bool _taskListEquals(List<FrameRenderTask> a, List<FrameRenderTask> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

int _taskListHash(List<FrameRenderTask> tasks) => Object.hashAll(tasks);

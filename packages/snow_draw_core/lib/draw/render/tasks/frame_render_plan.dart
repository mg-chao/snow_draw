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
    this.sceneRevision = 0,
    this.localeTag,
  });

  /// Ordered tasks to execute for the frame.
  final List<RenderTask> tasks;

  /// Camera transform snapshot.
  final CameraState camera;

  /// Effective scale factor used for world/canvas transforms.
  final double scaleFactor;

  /// Monotonic scene revision for element-level invalidation.
  ///
  /// Backends that render element pixels outside of [tasks] can still use this
  /// revision to detect committed scene mutations deterministically.
  final int sceneRevision;

  /// Optional locale hint for text layout/rendering.
  final String? localeTag;

  static const empty = FrameRenderPlan(
    tasks: <RenderTask>[],
    camera: CameraState.initial,
    scaleFactor: 1,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameRenderPlan &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor &&
          other.sceneRevision == sceneRevision &&
          other.localeTag == localeTag &&
          _taskListEquals(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(
    _taskListHash(tasks),
    camera,
    scaleFactor,
    sceneRevision,
    localeTag,
  );
}

bool _taskListEquals(List<RenderTask> a, List<RenderTask> b) {
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

int _taskListHash(List<RenderTask> tasks) => Object.hashAll(tasks);

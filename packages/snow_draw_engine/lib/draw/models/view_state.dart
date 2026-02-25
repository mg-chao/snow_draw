import 'package:meta/meta.dart';

import 'camera_state.dart';

/// View/camera state (viewport layer).
@immutable
class ViewState {
  const ViewState({this.camera = CameraState.initial});

  final CameraState camera;

  ViewState copyWith({CameraState? camera}) =>
      ViewState(camera: camera ?? this.camera);

  @override
  bool operator ==(Object other) =>
      other is ViewState && other.camera == camera;

  @override
  int get hashCode => camera.hashCode;

  @override
  String toString() => 'ViewState(camera: $camera)';
}

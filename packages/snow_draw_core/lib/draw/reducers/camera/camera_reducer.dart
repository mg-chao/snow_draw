import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../models/camera_state.dart';
import '../../models/draw_state.dart';
import '../../types/draw_point.dart';

DrawState? cameraReducer(
  DrawState state,
  DrawAction action,
  DrawContext context,
) => switch (action) {
  final MoveCamera a => state.copyWith(
    application: state.application.copyWith(
      view: state.application.view.copyWith(
        camera: state.application.view.camera.translated(a.dx, a.dy),
      ),
    ),
  ),
  final ZoomCamera a => _handleZoomCamera(state, a, context),
  _ => null,
};

DrawState _handleZoomCamera(DrawState state, ZoomCamera action, DrawContext _) {
  final camera = state.application.view.camera;
  final currentZoom = camera.zoom <= 0 ? 1.0 : camera.zoom;
  final targetZoom = CameraState.clampZoom(currentZoom * action.scale);
  if (targetZoom == currentZoom) {
    return state;
  }
  final scale = targetZoom / currentZoom;
  final center = action.center ?? camera.position;
  final offset = DrawPoint(
    x: (center.x - camera.position.x) * (1 - scale),
    y: (center.y - camera.position.y) * (1 - scale),
  );
  return state.copyWith(
    application: state.application.copyWith(
      view: state.application.view.copyWith(
        camera: camera.copyWith(
          position: camera.position.translate(offset),
          zoom: targetZoom,
        ),
      ),
    ),
  );
}

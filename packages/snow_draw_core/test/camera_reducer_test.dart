import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/view_state.dart';
import 'package:snow_draw_core/draw/reducers/camera/camera_reducer.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  group('cameraReducer', () {
    test(
      'ZoomCamera keeps camera position finite when current zoom is invalid',
      () {
        final state = DrawState.initial(
          view: const ViewState(
            camera: CameraState(position: DrawPoint(x: 40, y: -12), zoom: 0),
          ),
        );

        final next = cameraReducer(
          state,
          const ZoomCamera(scale: 2),
          const _NoopCameraReducerDeps(),
        );

        expect(next, isNotNull);
        final camera = next!.application.view.camera;
        expect(camera.zoom, 2);
        expect(camera.position, const DrawPoint(x: 40, y: -12));
        expect(camera.position.x.isFinite, isTrue);
        expect(camera.position.y.isFinite, isTrue);
      },
    );
  });
}

class _NoopCameraReducerDeps implements CameraReducerDeps {
  const _NoopCameraReducerDeps();
}

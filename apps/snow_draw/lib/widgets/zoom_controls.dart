import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/store/selector.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

import '../l10n/app_localizations.dart';

class ZoomControls extends StatefulWidget {
  const ZoomControls({
    required this.strings,
    required this.store,
    required this.size,
    super.key,
  });

  final AppLocalizations strings;
  final DefaultDrawStore store;
  final Size size;

  @override
  State<ZoomControls> createState() => _ZoomControlsState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(DiagnosticsProperty<DefaultDrawStore>('store', store))
      ..add(DiagnosticsProperty<Size>('size', size));
  }
}

class _ZoomControlsState extends State<ZoomControls> {
  static const _zoomCompareTolerance = 0.01;
  static const _zoomBoundaryTolerance = 0.0001;
  static const _buttonShape = RoundedRectangleBorder();
  static final ButtonStyle _iconButtonStyle = IconButton.styleFrom(
    shape: _buttonShape,
    minimumSize: const Size(36, 36),
    fixedSize: const Size(36, 36),
    padding: EdgeInsets.zero,
  );
  static final ButtonStyle _textButtonStyle = TextButton.styleFrom(
    shape: _buttonShape,
    minimumSize: const Size(52, 36),
    fixedSize: const Size(52, 36),
    padding: EdgeInsets.zero,
  );

  VoidCallback? _unsubscribe;
  var _cameraZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _cameraZoom = widget.store.state.application.view.camera.zoom;
    _subscribe(widget.store);
  }

  @override
  void didUpdateWidget(ZoomControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _unsubscribe?.call();
      _cameraZoom = widget.store.state.application.view.camera.zoom;
      _subscribe(widget.store);
    }
  }

  void _subscribe(DefaultDrawStore store) {
    _unsubscribe = store.select<double>(
      SimpleSelector<DrawState, double>(
        (state) => state.application.view.camera.zoom,
        equals: _zoomEquals,
      ),
      _handleZoomChange,
    );
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.6,
    );
    final zoomPercent = (_cameraZoom * 100).round();
    final canZoomOut = !_isAtMinZoom(_cameraZoom);
    final canZoomIn = !_isAtMaxZoom(_cameraZoom);
    final canResetZoom = !_zoomEquals(_cameraZoom, 1);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: widget.strings.zoomOut,
                child: IconButton(
                  style: _iconButtonStyle,
                  onPressed: canZoomOut ? () => _handleZoom(0.9) : null,
                  icon: const Icon(Icons.remove, size: 20),
                ),
              ),
              _buildDivider(dividerColor),
              Tooltip(
                message: widget.strings.resetZoom,
                child: TextButton(
                  style: _textButtonStyle,
                  onPressed: canResetZoom ? () => _handleZoomTo(1) : null,
                  child: Text(
                    '$zoomPercent%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              _buildDivider(dividerColor),
              Tooltip(
                message: widget.strings.zoomIn,
                child: IconButton(
                  style: _iconButtonStyle,
                  onPressed: canZoomIn ? () => _handleZoom(1.1) : null,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleZoomTo(double targetZoom) => _dispatchZoom(targetZoom);

  Future<void> _handleZoom(double scale) => _dispatchZoom(_cameraZoom * scale);

  Future<void> _dispatchZoom(double targetZoom) async {
    final current = _cameraZoom;
    final next = _snapZoom(targetZoom);
    if (_zoomEquals(current, next)) {
      return;
    }
    final ratio = next / current;
    await widget.store.dispatch(
      ZoomCamera(scale: ratio, center: _viewportCenter),
    );
  }

  DrawPoint get _viewportCenter =>
      DrawPoint(x: widget.size.width / 2, y: widget.size.height / 2);

  bool _doubleEquals(
    double a,
    double b, {
    double tolerance = _zoomCompareTolerance,
  }) => (a - b).abs() <= tolerance;

  bool _zoomEquals(double a, double b) =>
      _doubleEquals(a, b) && _isZoomBoundary(a) == _isZoomBoundary(b);

  bool _isZoomBoundary(double zoom) => _isAtMinZoom(zoom) || _isAtMaxZoom(zoom);

  bool _isAtMinZoom(double zoom) => _doubleEquals(
    zoom,
    CameraState.minZoom,
    tolerance: _zoomBoundaryTolerance,
  );

  bool _isAtMaxZoom(double zoom) => _doubleEquals(
    zoom,
    CameraState.maxZoom,
    tolerance: _zoomBoundaryTolerance,
  );

  double _snapZoom(double zoom) {
    final clamped = CameraState.clampZoom(zoom);
    if (_doubleEquals(clamped, CameraState.minZoom)) {
      return CameraState.minZoom;
    }
    if (_doubleEquals(clamped, CameraState.maxZoom)) {
      return CameraState.maxZoom;
    }
    return clamped;
  }

  void _handleZoomChange(double zoom) {
    if (_zoomEquals(_cameraZoom, zoom)) {
      return;
    }
    if (!mounted) {
      _cameraZoom = zoom;
      return;
    }
    setState(() {
      _cameraZoom = zoom;
    });
  }

  Widget _buildDivider(Color color) =>
      Container(width: 1, height: 20, color: color);
}

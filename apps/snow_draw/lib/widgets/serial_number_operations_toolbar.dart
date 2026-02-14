import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

import '../l10n/app_localizations.dart';
import '../style_toolbar_state.dart';
import '../toolbar_adapter.dart';

class SerialNumberOperationsToolbar extends StatefulWidget {
  const SerialNumberOperationsToolbar({
    required this.strings,
    required this.store,
    required this.adapter,
    this.verticalGap = 8,
    super.key,
  });

  final AppLocalizations strings;
  final DrawStore store;
  final StyleToolbarAdapter adapter;
  final double verticalGap;

  @override
  State<SerialNumberOperationsToolbar> createState() =>
      _SerialNumberOperationsToolbarState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(DiagnosticsProperty<DrawStore>('store', store))
      ..add(DiagnosticsProperty<StyleToolbarAdapter>('adapter', adapter))
      ..add(DoubleProperty('verticalGap', verticalGap));
  }
}

class _SerialNumberOperationsToolbarState
    extends State<SerialNumberOperationsToolbar> {
  static const double _toolbarRadius = 12;
  static const double _buttonGapSmall = 0;
  static const double _buttonGapLarge = 0;
  static const double _buttonSize = 28;
  static const double _iconSize = 16;
  static const double _viewportPadding = 8;
  static const double _toolbarHeight = _buttonSize;
  static const double _toolbarWidth =
      (_buttonSize * 3) + _buttonGapSmall + _buttonGapLarge;

  VoidCallback? _unsubscribe;
  late DrawStateViewBuilder _stateViewBuilder;

  @override
  void initState() {
    super.initState();
    _stateViewBuilder = _buildStateViewBuilder(widget.store);
    _subscribe(widget.store);
  }

  @override
  void didUpdateWidget(covariant SerialNumberOperationsToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) {
      return;
    }
    _unsubscribe?.call();
    _stateViewBuilder = _buildStateViewBuilder(widget.store);
    _subscribe(widget.store);
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _unsubscribe = null;
    super.dispose();
  }

  void _handleStoreUpdate(DrawState _) {
    if (!widget.adapter.stateListenable.value.hasSelectedSerialNumbers) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _subscribe(DrawStore store) {
    _unsubscribe = store.listen(
      _handleStoreUpdate,
      changeTypes: {
        DrawStateChange.selection,
        DrawStateChange.document,
        DrawStateChange.view,
        DrawStateChange.interaction,
      },
    );
  }

  DrawStateViewBuilder _buildStateViewBuilder(DrawStore store) =>
      DrawStateViewBuilder(editOperations: store.context.editOperations);

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<StyleToolbarState>(
        valueListenable: widget.adapter.stateListenable,
        builder: (context, styleState, _) {
          if (!styleState.hasSelectedSerialNumbers) {
            return const SizedBox.shrink();
          }

          final state = widget.store.state;
          final selection = state.domain.selection;
          if (!selection.hasSelection || selection.selectedIds.length != 1) {
            return const SizedBox.shrink();
          }

          final selectionBounds = _resolveSelectionBounds(state);
          if (selectionBounds == null) {
            return const SizedBox.shrink();
          }

          final camera = state.application.view.camera;
          final zoom = camera.zoom == 0 ? 1.0 : camera.zoom;
          final screenBounds = _toScreenRect(
            selectionBounds,
            camera.position,
            zoom,
          );

          final selectionConfig = widget.store.config.selection;
          final extraPadding =
              selectionConfig.padding +
              selectionConfig.render.controlPointSize / 2;
          final desiredTop =
              screenBounds.bottom + extraPadding + widget.verticalGap;
          final viewportSize = MediaQuery.sizeOf(context);
          final left = _clampHorizontalCenter(
            screenBounds.center.dx,
            viewportSize.width,
          );
          final top = _resolveTopPosition(
            desiredTop: desiredTop,
            selectionTop: screenBounds.top,
            viewportHeight: viewportSize.height,
            extraPadding: extraPadding,
          );

          final value = styleState.serialNumberStyleValues.number;
          final defaultValue = styleState.serialNumberStyle.serialNumber;
          final resolvedValue = value.valueOr(defaultValue);
          final canDecrement = resolvedValue > 0;

          return Positioned(
            left: left,
            top: top,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(_toolbarRadius),
                color: Colors.white,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIconButton(
                        icon: Icons.remove_rounded,
                        tooltip: widget.strings.decrease,
                        onPressed: canDecrement
                            ? () => _commitSerialNumberValue(resolvedValue - 1)
                            : null,
                      ),
                      const SizedBox(width: _buttonGapSmall),
                      _buildIconButton(
                        icon: Icons.add_rounded,
                        tooltip: widget.strings.increase,
                        onPressed: () =>
                            _commitSerialNumberValue(resolvedValue + 1),
                      ),
                      const SizedBox(width: _buttonGapLarge),
                      _buildIconButton(
                        icon: Icons.text_fields,
                        tooltip: widget.strings.createText,
                        onPressed: _handleCreateSerialNumberText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;
    final iconColor = isEnabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _buttonSize,
        height: _buttonSize,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const RoundedRectangleBorder(),
            child: Center(
              child: Icon(icon, size: _iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  void _commitSerialNumberValue(int next) {
    final sanitized = next < 0 ? 0 : next;
    unawaited(widget.adapter.applyStyleUpdate(serialNumber: sanitized));
  }

  void _handleCreateSerialNumberText() {
    unawaited(widget.adapter.createSerialNumberTextElements());
  }

  DrawRect? _resolveSelectionBounds(DrawState state) {
    final view = _stateViewBuilder.build(state);
    final selection = view.effectiveSelection;
    if (!selection.hasSelection || selection.bounds == null) {
      return null;
    }

    final bounds = selection.bounds!;
    final rotation = selection.rotation;
    final center = selection.center ?? bounds.center;

    if (rotation == null || rotation == 0) {
      return bounds;
    }

    return _rotatedBoundsAabb(bounds, center, rotation);
  }

  DrawRect _rotatedBoundsAabb(
    DrawRect bounds,
    DrawPoint center,
    double rotation,
  ) {
    final corners = [
      DrawPoint(x: bounds.minX, y: bounds.minY),
      DrawPoint(x: bounds.maxX, y: bounds.minY),
      DrawPoint(x: bounds.maxX, y: bounds.maxY),
      DrawPoint(x: bounds.minX, y: bounds.maxY),
    ];

    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final corner in corners) {
      final dx = corner.x - center.x;
      final dy = corner.y - center.y;
      final rotated = DrawPoint(
        x: center.x + dx * cosR - dy * sinR,
        y: center.y + dx * sinR + dy * cosR,
      );
      minX = math.min(minX, rotated.x);
      minY = math.min(minY, rotated.y);
      maxX = math.max(maxX, rotated.x);
      maxY = math.max(maxY, rotated.y);
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  Rect _toScreenRect(DrawRect world, DrawPoint camera, double scale) =>
      Rect.fromLTRB(
        world.minX * scale + camera.x,
        world.minY * scale + camera.y,
        world.maxX * scale + camera.x,
        world.maxY * scale + camera.y,
      );

  double _clampHorizontalCenter(double centerX, double viewportWidth) {
    const halfWidth = _toolbarWidth / 2;
    const minCenter = halfWidth + _viewportPadding;
    final maxCenter = viewportWidth - halfWidth - _viewportPadding;

    if (minCenter >= maxCenter) {
      return viewportWidth / 2;
    }

    return centerX.clamp(minCenter, maxCenter);
  }

  double _resolveTopPosition({
    required double desiredTop,
    required double selectionTop,
    required double viewportHeight,
    required double extraPadding,
  }) {
    const minTop = _viewportPadding;
    final maxTop = math.max(
      minTop,
      viewportHeight - _toolbarHeight - _viewportPadding,
    );
    final belowTop = desiredTop.clamp(minTop, maxTop);
    if (desiredTop <= maxTop) {
      return belowTop;
    }

    final aboveTop =
        selectionTop - extraPadding - widget.verticalGap - _toolbarHeight;
    if (aboveTop >= minTop) {
      return aboveTop.clamp(minTop, maxTop);
    }

    return belowTop;
  }
}

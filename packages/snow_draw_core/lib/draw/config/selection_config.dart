part of 'draw_config.dart';

/// Selection rendering configuration.
///
/// Contains the styling/geometry parameters needed to render selection outlines
/// and handles, without depending on UI-layer config types.
@immutable
class SelectionRenderConfig {
  const SelectionRenderConfig({
    this.strokeWidth = ConfigDefaults.selectionStrokeWidth,
    this.strokeColor = ConfigDefaults.accentColor,
    this.cornerFillColor = ConfigDefaults.controlPointFillColor,
    this.cornerRadius = ConfigDefaults.controlPointRadius,
    this.controlPointSize = ConfigDefaults.controlPointSize,
  }) : assert(strokeWidth > 0, 'strokeWidth must be positive'),
       assert(cornerRadius >= 0, 'cornerRadius must be non-negative'),
       assert(controlPointSize > 0, 'controlPointSize must be positive');
  final double strokeWidth;
  final Color strokeColor;
  final Color cornerFillColor;
  final double cornerRadius;
  final double controlPointSize;

  SelectionRenderConfig copyWith({
    double? strokeWidth,
    Color? strokeColor,
    Color? cornerFillColor,
    double? cornerRadius,
    double? controlPointSize,
  }) {
    final nextStrokeWidth = strokeWidth ?? this.strokeWidth;
    final nextStrokeColor = strokeColor ?? this.strokeColor;
    final nextCornerFillColor = cornerFillColor ?? this.cornerFillColor;
    final nextCornerRadius = cornerRadius ?? this.cornerRadius;
    final nextControlPointSize = controlPointSize ?? this.controlPointSize;
    if (nextStrokeWidth == this.strokeWidth &&
        nextStrokeColor == this.strokeColor &&
        nextCornerFillColor == this.cornerFillColor &&
        nextCornerRadius == this.cornerRadius &&
        nextControlPointSize == this.controlPointSize) {
      return this;
    }
    return SelectionRenderConfig(
      strokeWidth: nextStrokeWidth,
      strokeColor: nextStrokeColor,
      cornerFillColor: nextCornerFillColor,
      cornerRadius: nextCornerRadius,
      controlPointSize: nextControlPointSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionRenderConfig &&
          other.strokeWidth == strokeWidth &&
          other.strokeColor == strokeColor &&
          other.cornerFillColor == cornerFillColor &&
          other.cornerRadius == cornerRadius &&
          other.controlPointSize == controlPointSize;

  @override
  int get hashCode => Object.hash(
    strokeWidth,
    strokeColor,
    cornerFillColor,
    cornerRadius,
    controlPointSize,
  );

  @override
  String toString() =>
      'SelectionRenderConfig('
      'strokeWidth: $strokeWidth, '
      'strokeColor: $strokeColor, '
      'cornerFillColor: $cornerFillColor, '
      'cornerRadius: $cornerRadius, '
      'controlPointSize: $controlPointSize'
      ')';
}

/// Selection interaction configuration.
///
/// Contains interaction/tolerance thresholds used by hit testing and input
/// handling logic.
@immutable
class SelectionInteractionConfig {
  const SelectionInteractionConfig({
    this.handleTolerance = ConfigDefaults.handleTolerance,
    this.dragThreshold = ConfigDefaults.dragThreshold,
  }) : assert(handleTolerance > 0, 'handleTolerance must be positive'),
       assert(dragThreshold >= 0, 'dragThreshold must be non-negative');
  final double handleTolerance;
  final double dragThreshold;

  SelectionInteractionConfig copyWith({
    double? handleTolerance,
    double? dragThreshold,
  }) {
    final nextHandleTolerance = handleTolerance ?? this.handleTolerance;
    final nextDragThreshold = dragThreshold ?? this.dragThreshold;
    if (nextHandleTolerance == this.handleTolerance &&
        nextDragThreshold == this.dragThreshold) {
      return this;
    }
    return SelectionInteractionConfig(
      handleTolerance: nextHandleTolerance,
      dragThreshold: nextDragThreshold,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionInteractionConfig &&
          other.handleTolerance == handleTolerance &&
          other.dragThreshold == dragThreshold;

  @override
  int get hashCode => Object.hash(handleTolerance, dragThreshold);

  @override
  String toString() =>
      'SelectionInteractionConfig('
      'handleTolerance: $handleTolerance, '
      'dragThreshold: $dragThreshold'
      ')';
}

/// Unified selection configuration.
///
/// Combines both rendering and interaction configuration for selections to
/// avoid duplicated/converted configs across layers.
@immutable
class SelectionConfig {
  const SelectionConfig({
    this.render = const SelectionRenderConfig(),
    this.interaction = const SelectionInteractionConfig(),
    this.padding = ConfigDefaults.selectionPadding,
    this.rotateHandleOffset = ConfigDefaults.rotateHandleOffset,
  }) : assert(padding >= 0, 'padding must be non-negative'),
       assert(
         rotateHandleOffset >= 0,
         'rotateHandleOffset must be non-negative',
       );
  final SelectionRenderConfig render;
  final SelectionInteractionConfig interaction;

  /// Padding around selection bounds.
  ///
  /// Used both for rendering the selection outline and hit testing/resizing.
  final double padding;

  /// Offset from the top of the selection bounds to the rotate handle.
  final double rotateHandleOffset;

  SelectionConfig copyWith({
    SelectionRenderConfig? render,
    SelectionInteractionConfig? interaction,
    double? padding,
    double? rotateHandleOffset,
  }) {
    final nextRender = render ?? this.render;
    final nextInteraction = interaction ?? this.interaction;
    final nextPadding = padding ?? this.padding;
    final nextRotateHandleOffset =
        rotateHandleOffset ?? this.rotateHandleOffset;
    if (nextRender == this.render &&
        nextInteraction == this.interaction &&
        nextPadding == this.padding &&
        nextRotateHandleOffset == this.rotateHandleOffset) {
      return this;
    }
    return SelectionConfig(
      render: nextRender,
      interaction: nextInteraction,
      padding: nextPadding,
      rotateHandleOffset: nextRotateHandleOffset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionConfig &&
          other.render == render &&
          other.interaction == interaction &&
          other.padding == padding &&
          other.rotateHandleOffset == rotateHandleOffset;

  @override
  int get hashCode =>
      Object.hash(render, interaction, padding, rotateHandleOffset);

  @override
  String toString() =>
      'SelectionConfig('
      'render: $render, '
      'interaction: $interaction, '
      'padding: $padding, '
      'rotateHandleOffset: $rotateHandleOffset'
      ')';
}

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../elements/core/element_data.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/filter/filter_data.dart';
import '../../elements/types/free_draw/free_draw_data.dart';
import '../../elements/types/highlight/highlight_data.dart';
import '../../elements/types/line/line_data.dart';
import '../../elements/types/rectangle/rectangle_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/element_state.dart';
import '../../types/draw_color.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/snap_guides.dart';

/// Base type for backend-executable render tasks.
sealed class RenderTask {
  const RenderTask();
}

/// Base type for element render tasks produced by core.
@immutable
sealed class ElementRenderTask<T extends ElementData> extends RenderTask {
  const ElementRenderTask({
    required this.element,
    required this.data,
    this.localeTag,
  });

  /// Effective element state in world-space.
  final ElementState element;

  /// Typed element payload.
  final T data;

  /// Optional locale hint used by text-capable backends.
  final String? localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ElementRenderTask &&
          other.element == element &&
          other.data == data &&
          other.localeTag == localeTag;

  @override
  int get hashCode => Object.hash(runtimeType, element, data, localeTag);
}

/// Rectangle rendering task.
@immutable
final class RectangleRenderTask extends ElementRenderTask<RectangleData> {
  const RectangleRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Line rendering task.
@immutable
final class LineRenderTask extends ElementRenderTask<LineData> {
  const LineRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Arrow rendering task.
@immutable
final class ArrowRenderTask extends ElementRenderTask<ArrowData> {
  const ArrowRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Free-draw rendering task.
@immutable
final class FreeDrawRenderTask extends ElementRenderTask<FreeDrawData> {
  const FreeDrawRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Text rendering task.
@immutable
final class TextRenderTask extends ElementRenderTask<TextData> {
  const TextRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Serial-number rendering task.
@immutable
final class SerialNumberRenderTask extends ElementRenderTask<SerialNumberData> {
  const SerialNumberRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Highlight rendering task.
@immutable
final class HighlightRenderTask extends ElementRenderTask<HighlightData> {
  const HighlightRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Filter rendering task.
@immutable
final class FilterRenderTask extends ElementRenderTask<FilterData> {
  const FilterRenderTask({
    required super.element,
    required super.data,
    super.localeTag,
  });
}

/// Background paint task.
@immutable
final class BackgroundRenderTask extends RenderTask {
  const BackgroundRenderTask({required this.color});

  final DrawColor color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundRenderTask && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Grid paint task.
@immutable
final class GridRenderTask extends RenderTask {
  const GridRenderTask({
    required this.enabled,
    required this.size,
    required this.lineWidth,
    required this.lineColor,
    required this.lineOpacity,
    required this.majorLineEvery,
    required this.majorLineOpacity,
    required this.minScreenSpacing,
    required this.minRenderSpacing,
  });

  final bool enabled;
  final double size;
  final double lineWidth;
  final DrawColor lineColor;
  final double lineOpacity;
  final int majorLineEvery;
  final double majorLineOpacity;
  final double minScreenSpacing;
  final double minRenderSpacing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridRenderTask &&
          other.enabled == enabled &&
          other.size == size &&
          other.lineWidth == lineWidth &&
          other.lineColor == lineColor &&
          other.lineOpacity == lineOpacity &&
          other.majorLineEvery == majorLineEvery &&
          other.majorLineOpacity == majorLineOpacity &&
          other.minScreenSpacing == minScreenSpacing &&
          other.minRenderSpacing == minRenderSpacing;

  @override
  int get hashCode => Object.hash(
    enabled,
    size,
    lineWidth,
    lineColor,
    lineOpacity,
    majorLineEvery,
    majorLineOpacity,
    minScreenSpacing,
    minRenderSpacing,
  );
}

/// Selection-outline task.
@immutable
final class SelectionOutlineRenderTask extends RenderTask {
  const SelectionOutlineRenderTask({
    required this.bounds,
    required this.config,
    this.rotation,
    this.rotationCenter,
    this.dashed = true,
  });

  final DrawRect bounds;
  final SelectionConfig config;
  final double? rotation;
  final DrawPoint? rotationCenter;
  final bool dashed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionOutlineRenderTask &&
          other.bounds == bounds &&
          other.config == config &&
          other.rotation == rotation &&
          other.rotationCenter == rotationCenter &&
          other.dashed == dashed;

  @override
  int get hashCode =>
      Object.hash(bounds, config, rotation, rotationCenter, dashed);
}

/// Selection controls task (outline + handles).
@immutable
final class SelectionControlsRenderTask extends RenderTask {
  const SelectionControlsRenderTask({
    required this.bounds,
    required this.config,
    this.rotation,
    this.rotationCenter,
    this.dashed = true,
    this.cornerHandleOffset = 0.0,
    this.showRotationHandle = true,
  });

  final DrawRect bounds;
  final SelectionConfig config;
  final double? rotation;
  final DrawPoint? rotationCenter;
  final bool dashed;
  final double cornerHandleOffset;
  final bool showRotationHandle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionControlsRenderTask &&
          other.bounds == bounds &&
          other.config == config &&
          other.rotation == rotation &&
          other.rotationCenter == rotationCenter &&
          other.dashed == dashed &&
          other.cornerHandleOffset == cornerHandleOffset &&
          other.showRotationHandle == showRotationHandle;

  @override
  int get hashCode => Object.hash(
    bounds,
    config,
    rotation,
    rotationCenter,
    dashed,
    cornerHandleOffset,
    showRotationHandle,
  );
}

/// Arrow-point overlay task.
@immutable
final class ArrowPointOverlayRenderTask extends RenderTask {
  const ArrowPointOverlayRenderTask({
    required this.handles,
    required this.selectionConfig,
    this.activeHandle,
    this.hoveredHandle,
    this.deleteIndicatorVisible = false,
  });

  final List<ArrowPointHandle> handles;
  final SelectionConfig selectionConfig;
  final ArrowPointHandle? activeHandle;
  final ArrowPointHandle? hoveredHandle;
  final bool deleteIndicatorVisible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowPointOverlayRenderTask &&
          _listEquals(other.handles, handles) &&
          other.selectionConfig == selectionConfig &&
          other.activeHandle == activeHandle &&
          other.hoveredHandle == hoveredHandle &&
          other.deleteIndicatorVisible == deleteIndicatorVisible;

  @override
  int get hashCode => Object.hash(
    _listHash(handles),
    selectionConfig,
    activeHandle,
    hoveredHandle,
    deleteIndicatorVisible,
  );
}

/// Arrow-binding highlight task.
@immutable
final class ArrowBindingHighlightRenderTask extends RenderTask {
  const ArrowBindingHighlightRenderTask({
    required this.elementIds,
    required this.strokeColor,
  });

  final List<String> elementIds;
  final DrawColor strokeColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowBindingHighlightRenderTask &&
          _listEquals(other.elementIds, elementIds) &&
          other.strokeColor == strokeColor;

  @override
  int get hashCode => Object.hash(_listHash(elementIds), strokeColor);
}

/// Hover-outline task.
@immutable
final class HoverOutlineRenderTask extends RenderTask {
  const HoverOutlineRenderTask({
    required this.element,
    required this.config,
    this.useTextUnderlineStyle = false,
  });

  final ElementState element;
  final SelectionConfig config;
  final bool useTextUnderlineStyle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoverOutlineRenderTask &&
          other.element == element &&
          other.config == config &&
          other.useTextUnderlineStyle == useTextUnderlineStyle;

  @override
  int get hashCode => Object.hash(element, config, useTextUnderlineStyle);
}

/// Snap-guides overlay task.
@immutable
final class SnapGuidesRenderTask extends RenderTask {
  const SnapGuidesRenderTask({required this.guides, required this.snapConfig});

  final List<SnapGuide> guides;
  final SnapConfig snapConfig;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapGuidesRenderTask &&
          _listEquals(other.guides, guides) &&
          other.snapConfig == snapConfig;

  @override
  int get hashCode => Object.hash(_listHash(guides), snapConfig);
}

/// Box-select overlay task.
@immutable
final class BoxSelectionRenderTask extends RenderTask {
  const BoxSelectionRenderTask({
    required this.bounds,
    required this.config,
    required this.selectionConfig,
    this.previewElements = const <ElementState>[],
  });

  final DrawRect bounds;
  final BoxSelectionConfig config;
  final SelectionConfig selectionConfig;
  final List<ElementState> previewElements;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxSelectionRenderTask &&
          other.bounds == bounds &&
          other.config == config &&
          other.selectionConfig == selectionConfig &&
          _listEquals(other.previewElements, previewElements);

  @override
  int get hashCode =>
      Object.hash(bounds, config, selectionConfig, _listHash(previewElements));
}

/// Highlight-mask overlay task.
@immutable
final class HighlightMaskRenderTask extends RenderTask {
  const HighlightMaskRenderTask({
    required this.config,
    required this.highlights,
  });

  final HighlightMaskConfig config;
  final List<ElementState> highlights;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlightMaskRenderTask &&
          other.config == config &&
          _listEquals(other.highlights, highlights);

  @override
  int get hashCode => Object.hash(config, _listHash(highlights));
}

/// Watermark overlay task.
@immutable
final class WatermarkRenderTask extends RenderTask {
  const WatermarkRenderTask({required this.config});

  final WatermarkConfig config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkRenderTask && other.config == config;

  @override
  int get hashCode => config.hashCode;
}

bool _listEquals<T>(List<T> a, List<T> b) {
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

int _listHash<T>(List<T> values) => Object.hashAll(values);

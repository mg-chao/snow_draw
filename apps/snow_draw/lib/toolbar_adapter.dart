import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'config_update_queue.dart';
import 'style_toolbar_state.dart';
import 'system_fonts.dart';
import 'tool_controller.dart';

enum StyleUpdateScope {
  allSelectedElements,
  highlightsOnly,
  filtersOnly,
  textsOnly,
}

class StyleToolbarAdapter {
  StyleToolbarAdapter({required DrawStore store}) : _store = store {
    _config = _store.config;
    _selectedIds = _store.state.domain.selection.selectedIds;
    _refreshSelectedElements();
    _resolveSelectedStyleValues();
    _stateNotifier = ValueNotifier<StyleToolbarState>(_buildState());
    _stateUnsubscribe = _store.listen(
      _handleStateChange,
      changeTypes: {DrawStateChange.selection, DrawStateChange.document},
    );
    _configSubscription = _store.configStream.listen(_handleConfigChange);
  }

  final DrawStore _store;
  late final ValueNotifier<StyleToolbarState> _stateNotifier;
  VoidCallback? _stateUnsubscribe;
  StreamSubscription<DrawConfig>? _configSubscription;

  late DrawConfig _config;
  Set<String> _selectedIds = const {};
  List<ElementState> _selectedElements = const [];
  List<ElementState> _selectedRectangles = const [];
  List<ElementState> _selectedHighlights = const [];
  List<ElementState> _selectedArrows = const [];
  List<ElementState> _selectedLines = const [];
  List<ElementState> _selectedFreeDraws = const [];
  List<ElementState> _selectedTexts = const [];
  List<ElementState> _selectedFilters = const [];
  List<ElementState> _selectedSerialNumbers = const [];
  Map<String, _ElementStyleSnapshot> _styleSnapshot = const {};
  late RectangleStyleValues _styleValues;
  late ArrowStyleValues _arrowStyleValues;
  late LineStyleValues _lineStyleValues;
  late LineStyleValues _freeDrawStyleValues;
  late TextStyleValues _textStyleValues;
  late HighlightStyleValues _highlightStyleValues;
  late FilterStyleValues _filterStyleValues;
  late SerialNumberStyleValues _serialNumberStyleValues;
  var _isDisposed = false;
  var _updateScheduled = false;
  var _pendingStyleUpdate = Future<void>.value();

  ValueListenable<StyleToolbarState> get stateListenable => _stateNotifier;

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _stateUnsubscribe?.call();
    unawaited(_configSubscription?.cancel());
    _stateNotifier.dispose();
  }

  Future<void> applyStyleUpdate({
    Color? color,
    Color? fillColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    String? fontFamily,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    double? opacity,
    Color? textStrokeColor,
    double? textStrokeWidth,
    HighlightShape? highlightShape,
    CanvasFilterType? filterType,
    double? filterStrength,
    Color? maskColor,
    double? maskOpacity,
    int? serialNumber,
    ToolType? toolType,
    StyleUpdateScope scope = StyleUpdateScope.allSelectedElements,
  }) => _enqueueStyleUpdate(
    () => _applyStyleUpdateInternal(
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      fillStyle: fillStyle,
      cornerRadius: cornerRadius,
      arrowType: arrowType,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      opacity: opacity,
      textStrokeColor: textStrokeColor,
      textStrokeWidth: textStrokeWidth,
      highlightShape: highlightShape,
      filterType: filterType,
      filterStrength: filterStrength,
      maskColor: maskColor,
      maskOpacity: maskOpacity,
      serialNumber: serialNumber,
      toolType: toolType,
      scope: scope,
    ),
  );

  Future<void> _applyStyleUpdateInternal({
    Color? color,
    Color? fillColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    String? fontFamily,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    double? opacity,
    Color? textStrokeColor,
    double? textStrokeWidth,
    HighlightShape? highlightShape,
    CanvasFilterType? filterType,
    double? filterStrength,
    Color? maskColor,
    double? maskOpacity,
    int? serialNumber,
    ToolType? toolType,
    StyleUpdateScope scope = StyleUpdateScope.allSelectedElements,
  }) async {
    if (_isDisposed) {
      return;
    }
    final normalizedFontFamily = _normalizeFontFamily(fontFamily);
    if (normalizedFontFamily != null && normalizedFontFamily.isNotEmpty) {
      await ensureSystemFontLoaded(normalizedFontFamily);
      if (_isDisposed) {
        return;
      }
    }
    _syncSelectionSnapshotFromStore();
    final ids = switch (scope) {
      StyleUpdateScope.highlightsOnly => {
        for (final element in _selectedHighlights) element.id,
      },
      StyleUpdateScope.filtersOnly => {
        for (final element in _selectedFilters) element.id,
      },
      StyleUpdateScope.textsOnly => {
        for (final element in _selectedTexts) element.id,
      },
      StyleUpdateScope.allSelectedElements => {..._selectedIds},
    };
    final interaction = _store.state.application.interaction;
    final updatesTextEditing =
        scope == StyleUpdateScope.allSelectedElements ||
        scope == StyleUpdateScope.textsOnly;
    if (updatesTextEditing && interaction is TextEditingState) {
      ids.add(interaction.elementId);
    }
    final hasElementStyleUpdate =
        color != null ||
        fillColor != null ||
        strokeWidth != null ||
        strokeStyle != null ||
        fillStyle != null ||
        cornerRadius != null ||
        arrowType != null ||
        startArrowhead != null ||
        endArrowhead != null ||
        fontSize != null ||
        normalizedFontFamily != null ||
        textAlign != null ||
        verticalAlign != null ||
        opacity != null ||
        textStrokeColor != null ||
        textStrokeWidth != null ||
        highlightShape != null ||
        filterType != null ||
        filterStrength != null ||
        serialNumber != null;
    if (ids.isNotEmpty && hasElementStyleUpdate) {
      await _store.dispatch(
        UpdateElementsStyle(
          elementIds: ids.toList(),
          color: color,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fillStyle: fillStyle,
          cornerRadius: cornerRadius,
          arrowType: arrowType,
          startArrowhead: startArrowhead,
          endArrowhead: endArrowhead,
          fontSize: fontSize,
          fontFamily: normalizedFontFamily,
          textAlign: textAlign,
          verticalAlign: verticalAlign,
          opacity: opacity,
          textStrokeColor: textStrokeColor,
          textStrokeWidth: textStrokeWidth,
          highlightShape: highlightShape,
          filterType: filterType,
          filterStrength: filterStrength,
          serialNumber: serialNumber,
        ),
      );
      if (_isDisposed) {
        return;
      }
    }

    await _updateStyleConfig(
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      fillStyle: fillStyle,
      cornerRadius: cornerRadius,
      arrowType: arrowType,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      fontSize: fontSize,
      fontFamily: normalizedFontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      opacity: opacity,
      textStrokeColor: textStrokeColor,
      textStrokeWidth: textStrokeWidth,
      highlightShape: highlightShape,
      filterType: filterType,
      filterStrength: filterStrength,
      maskColor: maskColor,
      maskOpacity: maskOpacity,
      serialNumber: serialNumber,
      toolType: toolType,
      scope: scope,
    );
  }

  Future<void> _enqueueStyleUpdate(Future<void> Function() update) {
    final next = _pendingStyleUpdate.then((_) => update());
    _pendingStyleUpdate = next.catchError((Object error, StackTrace st) {
      _store.context.log.configLog.error(
        'Queued style update failed',
        error,
        st,
      );
    });
    return next;
  }

  Future<void> copySelection() async {
    if (_isDisposed) {
      return;
    }
    _syncSelectionSnapshotFromStore();
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(
      DuplicateElements(elementIds: ids, offsetX: 12, offsetY: 12),
    );
  }

  Future<void> deleteSelection() async {
    if (_isDisposed) {
      return;
    }
    _syncSelectionSnapshotFromStore();
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(DeleteElements(elementIds: ids));
  }

  Future<void> createSerialNumberTextElements() async {
    if (_isDisposed) {
      return;
    }
    _syncSelectionSnapshotFromStore();
    if (_selectedSerialNumbers.isEmpty) {
      return;
    }
    await _store.dispatch(
      CreateSerialNumberTextElements(
        elementIds: _selectedSerialNumbers.map((e) => e.id).toList(),
      ),
    );
  }

  Future<void> changeZOrder(ZIndexOperation operation) async {
    if (_isDisposed) {
      return;
    }
    _syncSelectionSnapshotFromStore();
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(
      ChangeElementsZIndex(elementIds: ids, operation: operation),
    );
  }

  void _handleStateChange(DrawState state) {
    if (_isDisposed) {
      return;
    }
    final nextSelectedIds = state.domain.selection.selectedIds;
    if (!setEquals(_selectedIds, nextSelectedIds)) {
      _selectedIds = nextSelectedIds;
      _refreshSelectedElements();
      _resolveSelectedStyleValues();
      _publishState();
      return;
    }

    if (_selectedIds.isEmpty) {
      return;
    }

    final elementsChanged = _refreshSelectedElements();
    if (!elementsChanged) {
      return;
    }
    _resolveSelectedStyleValues();
    _publishState();
  }

  void _resolveSelectedStyleValues() {
    _styleValues = _resolveRectangleStyles();
    _arrowStyleValues = _resolveArrowStyles();
    _lineStyleValues = _resolveLineStyles();
    _freeDrawStyleValues = _resolveFreeDrawStyles();
    _textStyleValues = _resolveTextStyles();
    _highlightStyleValues = _resolveHighlightStyles();
    _filterStyleValues = _resolveFilterStyles();
    _serialNumberStyleValues = _resolveSerialNumberStyles();
  }

  void _syncSelectionSnapshotFromStore() {
    if (_isDisposed) {
      return;
    }
    final nextSelectedIds = _store.state.domain.selection.selectedIds;
    final selectionChanged = !setEquals(_selectedIds, nextSelectedIds);
    if (selectionChanged) {
      _selectedIds = nextSelectedIds;
    }
    final elementsChanged = _refreshSelectedElements();
    if (selectionChanged || elementsChanged) {
      _resolveSelectedStyleValues();
    }
  }

  void _handleConfigChange(DrawConfig config) {
    if (_isDisposed || config == _config) {
      return;
    }
    final rectangleStyleChanged =
        config.rectangleStyle != _config.rectangleStyle;
    final arrowStyleChanged = config.arrowStyle != _config.arrowStyle;
    final lineStyleChanged = config.lineStyle != _config.lineStyle;
    final freeDrawStyleChanged = config.freeDrawStyle != _config.freeDrawStyle;
    final textStyleChanged = config.textStyle != _config.textStyle;
    final highlightStyleChanged =
        config.highlightStyle != _config.highlightStyle;
    final filterStyleChanged = config.filterStyle != _config.filterStyle;
    final serialNumberStyleChanged =
        config.serialNumberStyle != _config.serialNumberStyle;
    final highlightMaskChanged = config.highlight != _config.highlight;
    _config = config;
    if (!rectangleStyleChanged &&
        !arrowStyleChanged &&
        !lineStyleChanged &&
        !freeDrawStyleChanged &&
        !textStyleChanged &&
        !highlightStyleChanged &&
        !filterStyleChanged &&
        !serialNumberStyleChanged &&
        !highlightMaskChanged) {
      return;
    }
    if (_selectedRectangles.isEmpty && rectangleStyleChanged) {
      _styleValues = _resolveRectangleStyles();
    }
    if (_selectedArrows.isEmpty && arrowStyleChanged) {
      _arrowStyleValues = _resolveArrowStyles();
    }
    if (_selectedLines.isEmpty && lineStyleChanged) {
      _lineStyleValues = _resolveLineStyles();
    }
    if (_selectedFreeDraws.isEmpty && freeDrawStyleChanged) {
      _freeDrawStyleValues = _resolveFreeDrawStyles();
    }
    if (_selectedTexts.isEmpty && textStyleChanged) {
      _textStyleValues = _resolveTextStyles();
    }
    if (_selectedHighlights.isEmpty && highlightStyleChanged) {
      _highlightStyleValues = _resolveHighlightStyles();
    }
    if (_selectedFilters.isEmpty && filterStyleChanged) {
      _filterStyleValues = _resolveFilterStyles();
    }
    if (_selectedSerialNumbers.isEmpty && serialNumberStyleChanged) {
      _serialNumberStyleValues = _resolveSerialNumberStyles();
    }
    _publishState();
  }

  bool _refreshSelectedElements() {
    final selectedIds = _selectedIds;
    if (selectedIds.isEmpty) {
      final changed =
          _selectedElements.isNotEmpty ||
          _selectedRectangles.isNotEmpty ||
          _selectedHighlights.isNotEmpty ||
          _selectedFilters.isNotEmpty ||
          _selectedArrows.isNotEmpty ||
          _selectedLines.isNotEmpty ||
          _selectedFreeDraws.isNotEmpty ||
          _selectedTexts.isNotEmpty ||
          _selectedSerialNumbers.isNotEmpty ||
          _styleSnapshot.isNotEmpty;
      if (changed) {
        _selectedElements = const [];
        _selectedRectangles = const [];
        _selectedHighlights = const [];
        _selectedFilters = const [];
        _selectedArrows = const [];
        _selectedLines = const [];
        _selectedFreeDraws = const [];
        _selectedTexts = const [];
        _selectedSerialNumbers = const [];
        _styleSnapshot = const {};
      }
      return changed;
    }

    final document = _store.state.domain.document;
    final selectedElements = <ElementState>[];
    final selectedRectangles = <ElementState>[];
    final selectedHighlights = <ElementState>[];
    final selectedFilters = <ElementState>[];
    final selectedArrows = <ElementState>[];
    final selectedLines = <ElementState>[];
    final selectedFreeDraws = <ElementState>[];
    final selectedTexts = <ElementState>[];
    final selectedSerialNumbers = <ElementState>[];
    final nextSnapshot = <String, _ElementStyleSnapshot>{};
    var snapshotChanged = false;
    for (final id in selectedIds) {
      final element = document.getElementById(id);
      if (element == null) {
        snapshotChanged = true;
        continue;
      }
      selectedElements.add(element);
      switch (element.data) {
        case RectangleData _:
          selectedRectangles.add(element);
        case HighlightData _:
          selectedHighlights.add(element);
        case FilterData _:
          selectedFilters.add(element);
        case ArrowData _:
          selectedArrows.add(element);
        case LineData _:
          selectedLines.add(element);
        case FreeDrawData _:
          selectedFreeDraws.add(element);
        case TextData _:
          selectedTexts.add(element);
        case SerialNumberData _:
          selectedSerialNumbers.add(element);
        default:
          break;
      }
      final snapshot = _ElementStyleSnapshot.fromElement(element);
      nextSnapshot[id] = snapshot;
      final previous = _styleSnapshot[id];
      if (previous == null || !previous.matches(snapshot, _doubleEquals)) {
        snapshotChanged = true;
      }
    }

    if (_styleSnapshot.length != nextSnapshot.length) {
      snapshotChanged = true;
    }

    if (!snapshotChanged) {
      return false;
    }
    _selectedElements = selectedElements;
    _selectedRectangles = selectedRectangles;
    _selectedHighlights = selectedHighlights;
    _selectedFilters = selectedFilters;
    _selectedArrows = selectedArrows;
    _selectedLines = selectedLines;
    _selectedFreeDraws = selectedFreeDraws;
    _selectedTexts = selectedTexts;
    _selectedSerialNumbers = selectedSerialNumbers;
    _styleSnapshot = nextSnapshot;
    return true;
  }

  /// Resolves rectangle style values for the current selection.
  ///
  /// This method implements a multi-selection style resolution algorithm:
  /// 1. If no rectangles are selected, returns default values from config
  /// 2. If one rectangle is selected, returns its actual property values
  /// 3. If multiple rectangles are selected, compares each property across all
  ///    selected rectangles and marks properties as "mixed" when values differ
  ///
  /// The boolean flags (colorMixed, fillColorMixed, etc.) track
  ///  which properties
  /// have different values across the selection. When a property is mixed, the
  /// returned MixedValue has isMixed=true and value=null, allowing the UI to
  /// display "Mixed" instead of an arbitrary value.
  RectangleStyleValues _resolveRectangleStyles() {
    final defaults = _config.rectangleStyle;
    if (_selectedRectangles.isEmpty) {
      return RectangleStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        cornerRadius: MixedValue(value: defaults.cornerRadius, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedRectangles.first;
    final firstData = first.data;
    if (firstData is! RectangleData) {
      return RectangleStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        cornerRadius: MixedValue(value: defaults.cornerRadius, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedRectangles.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return RectangleStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        fillColor: MixedValue(value: firstData.fillColor, isMixed: false),
        strokeStyle: MixedValue(value: firstData.strokeStyle, isMixed: false),
        fillStyle: MixedValue(value: firstData.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: firstData.strokeWidth, isMixed: false),
        cornerRadius: MixedValue(value: firstData.cornerRadius, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final fillColor = firstData.fillColor;
    final strokeStyle = firstData.strokeStyle;
    final fillStyle = firstData.fillStyle;
    final strokeWidth = firstData.strokeWidth;
    final cornerRadius = firstData.cornerRadius;

    var colorMixed = false;
    var fillColorMixed = false;
    var strokeStyleMixed = false;
    var fillStyleMixed = false;
    var strokeWidthMixed = false;
    var cornerRadiusMixed = false;

    for (final element in _selectedRectangles.skip(1)) {
      final data = element.data;
      if (data is! RectangleData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!fillColorMixed && data.fillColor != fillColor) {
        fillColorMixed = true;
      }
      if (!strokeStyleMixed && data.strokeStyle != strokeStyle) {
        strokeStyleMixed = true;
      }
      if (!fillStyleMixed && data.fillStyle != fillStyle) {
        fillStyleMixed = true;
      }
      if (!strokeWidthMixed && !_doubleEquals(data.strokeWidth, strokeWidth)) {
        strokeWidthMixed = true;
      }
      if (!cornerRadiusMixed &&
          !_doubleEquals(data.cornerRadius, cornerRadius)) {
        cornerRadiusMixed = true;
      }
      if (colorMixed &&
          fillColorMixed &&
          strokeStyleMixed &&
          fillStyleMixed &&
          strokeWidthMixed &&
          cornerRadiusMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return RectangleStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      fillColor: MixedValue(
        value: fillColorMixed ? null : fillColor,
        isMixed: fillColorMixed,
      ),
      strokeStyle: MixedValue(
        value: strokeStyleMixed ? null : strokeStyle,
        isMixed: strokeStyleMixed,
      ),
      fillStyle: MixedValue(
        value: fillStyleMixed ? null : fillStyle,
        isMixed: fillStyleMixed,
      ),
      strokeWidth: MixedValue(
        value: strokeWidthMixed ? null : strokeWidth,
        isMixed: strokeWidthMixed,
      ),
      cornerRadius: MixedValue(
        value: cornerRadiusMixed ? null : cornerRadius,
        isMixed: cornerRadiusMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves arrow style values for the current selection.
  ArrowStyleValues _resolveArrowStyles() {
    final defaults = _config.arrowStyle;
    if (_selectedArrows.isEmpty) {
      return ArrowStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        arrowType: MixedValue(value: defaults.arrowType, isMixed: false),
        startArrowhead: MixedValue(
          value: defaults.startArrowhead,
          isMixed: false,
        ),
        endArrowhead: MixedValue(value: defaults.endArrowhead, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedArrows.first;
    final firstData = first.data;
    if (firstData is! ArrowData) {
      return ArrowStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        arrowType: MixedValue(value: defaults.arrowType, isMixed: false),
        startArrowhead: MixedValue(
          value: defaults.startArrowhead,
          isMixed: false,
        ),
        endArrowhead: MixedValue(value: defaults.endArrowhead, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedArrows.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return ArrowStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        strokeWidth: MixedValue(value: firstData.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: firstData.strokeStyle, isMixed: false),
        arrowType: MixedValue(value: firstData.arrowType, isMixed: false),
        startArrowhead: MixedValue(
          value: firstData.startArrowhead,
          isMixed: false,
        ),
        endArrowhead: MixedValue(value: firstData.endArrowhead, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final strokeWidth = firstData.strokeWidth;
    final strokeStyle = firstData.strokeStyle;
    final arrowType = firstData.arrowType;
    final startArrowhead = firstData.startArrowhead;
    final endArrowhead = firstData.endArrowhead;

    var colorMixed = false;
    var strokeWidthMixed = false;
    var strokeStyleMixed = false;
    var arrowTypeMixed = false;
    var startArrowheadMixed = false;
    var endArrowheadMixed = false;

    for (final element in _selectedArrows.skip(1)) {
      final data = element.data;
      if (data is! ArrowData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!strokeWidthMixed && !_doubleEquals(data.strokeWidth, strokeWidth)) {
        strokeWidthMixed = true;
      }
      if (!strokeStyleMixed && data.strokeStyle != strokeStyle) {
        strokeStyleMixed = true;
      }
      if (!arrowTypeMixed && data.arrowType != arrowType) {
        arrowTypeMixed = true;
      }
      if (!startArrowheadMixed && data.startArrowhead != startArrowhead) {
        startArrowheadMixed = true;
      }
      if (!endArrowheadMixed && data.endArrowhead != endArrowhead) {
        endArrowheadMixed = true;
      }
      if (colorMixed &&
          strokeWidthMixed &&
          strokeStyleMixed &&
          arrowTypeMixed &&
          startArrowheadMixed &&
          endArrowheadMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return ArrowStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      strokeWidth: MixedValue(
        value: strokeWidthMixed ? null : strokeWidth,
        isMixed: strokeWidthMixed,
      ),
      strokeStyle: MixedValue(
        value: strokeStyleMixed ? null : strokeStyle,
        isMixed: strokeStyleMixed,
      ),
      arrowType: MixedValue(
        value: arrowTypeMixed ? null : arrowType,
        isMixed: arrowTypeMixed,
      ),
      startArrowhead: MixedValue(
        value: startArrowheadMixed ? null : startArrowhead,
        isMixed: startArrowheadMixed,
      ),
      endArrowhead: MixedValue(
        value: endArrowheadMixed ? null : endArrowhead,
        isMixed: endArrowheadMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves line style values for the current selection.
  LineStyleValues _resolveLineStyles() {
    final defaults = _config.lineStyle;
    if (_selectedLines.isEmpty) {
      return LineStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedLines.first;
    final firstData = first.data;
    if (firstData is! LineData) {
      return LineStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedLines.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return LineStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        fillColor: MixedValue(value: firstData.fillColor, isMixed: false),
        fillStyle: MixedValue(value: firstData.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: firstData.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: firstData.strokeStyle, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final fillColor = firstData.fillColor;
    final fillStyle = firstData.fillStyle;
    final strokeWidth = firstData.strokeWidth;
    final strokeStyle = firstData.strokeStyle;

    var colorMixed = false;
    var fillColorMixed = false;
    var fillStyleMixed = false;
    var strokeWidthMixed = false;
    var strokeStyleMixed = false;

    for (final element in _selectedLines.skip(1)) {
      final data = element.data;
      if (data is! LineData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!fillColorMixed && data.fillColor != fillColor) {
        fillColorMixed = true;
      }
      if (!fillStyleMixed && data.fillStyle != fillStyle) {
        fillStyleMixed = true;
      }
      if (!strokeWidthMixed && !_doubleEquals(data.strokeWidth, strokeWidth)) {
        strokeWidthMixed = true;
      }
      if (!strokeStyleMixed && data.strokeStyle != strokeStyle) {
        strokeStyleMixed = true;
      }
      if (colorMixed &&
          fillColorMixed &&
          fillStyleMixed &&
          strokeWidthMixed &&
          strokeStyleMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return LineStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      fillColor: MixedValue(
        value: fillColorMixed ? null : fillColor,
        isMixed: fillColorMixed,
      ),
      fillStyle: MixedValue(
        value: fillStyleMixed ? null : fillStyle,
        isMixed: fillStyleMixed,
      ),
      strokeWidth: MixedValue(
        value: strokeWidthMixed ? null : strokeWidth,
        isMixed: strokeWidthMixed,
      ),
      strokeStyle: MixedValue(
        value: strokeStyleMixed ? null : strokeStyle,
        isMixed: strokeStyleMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves free draw style values for the current selection.
  LineStyleValues _resolveFreeDrawStyles() {
    final defaults = _config.freeDrawStyle;
    if (_selectedFreeDraws.isEmpty) {
      return LineStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedFreeDraws.first;
    final firstData = first.data;
    if (firstData is! FreeDrawData) {
      return LineStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: defaults.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: defaults.strokeStyle, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedFreeDraws.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return LineStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        fillColor: MixedValue(value: firstData.fillColor, isMixed: false),
        fillStyle: MixedValue(value: firstData.fillStyle, isMixed: false),
        strokeWidth: MixedValue(value: firstData.strokeWidth, isMixed: false),
        strokeStyle: MixedValue(value: firstData.strokeStyle, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final fillColor = firstData.fillColor;
    final fillStyle = firstData.fillStyle;
    final strokeWidth = firstData.strokeWidth;
    final strokeStyle = firstData.strokeStyle;

    var colorMixed = false;
    var fillColorMixed = false;
    var fillStyleMixed = false;
    var strokeWidthMixed = false;
    var strokeStyleMixed = false;

    for (final element in _selectedFreeDraws.skip(1)) {
      final data = element.data;
      if (data is! FreeDrawData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!fillColorMixed && data.fillColor != fillColor) {
        fillColorMixed = true;
      }
      if (!fillStyleMixed && data.fillStyle != fillStyle) {
        fillStyleMixed = true;
      }
      if (!strokeWidthMixed && !_doubleEquals(data.strokeWidth, strokeWidth)) {
        strokeWidthMixed = true;
      }
      if (!strokeStyleMixed && data.strokeStyle != strokeStyle) {
        strokeStyleMixed = true;
      }
      if (colorMixed &&
          fillColorMixed &&
          fillStyleMixed &&
          strokeWidthMixed &&
          strokeStyleMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return LineStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      fillColor: MixedValue(
        value: fillColorMixed ? null : fillColor,
        isMixed: fillColorMixed,
      ),
      fillStyle: MixedValue(
        value: fillStyleMixed ? null : fillStyle,
        isMixed: fillStyleMixed,
      ),
      strokeWidth: MixedValue(
        value: strokeWidthMixed ? null : strokeWidth,
        isMixed: strokeWidthMixed,
      ),
      strokeStyle: MixedValue(
        value: strokeStyleMixed ? null : strokeStyle,
        isMixed: strokeStyleMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves text style values for the current selection.
  ///
  /// This method implements a multi-selection style resolution algorithm:
  /// 1. If no text elements are selected, returns default values from config
  /// 2. If one text element is selected, returns its actual property values
  /// 3. If multiple text elements are selected, compares each
  ///  property across all
  ///    selected text elements and marks properties as "mixed" when
  ///  values differ
  ///
  /// The boolean flags (colorMixed, fontSizeMixed, etc.) track which properties
  /// have different values across the selection. When a property is mixed, the
  /// returned MixedValue has isMixed=true and value=null, allowing the UI to
  /// display "Mixed" instead of an arbitrary value.
  TextStyleValues _resolveTextStyles() {
    final defaults = _config.textStyle;
    if (_selectedTexts.isEmpty) {
      return TextStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fontSize: MixedValue(value: defaults.fontSize, isMixed: false),
        fontFamily: MixedValue(value: defaults.fontFamily, isMixed: false),
        horizontalAlign: MixedValue(value: defaults.textAlign, isMixed: false),
        verticalAlign: MixedValue(
          value: defaults.verticalAlign,
          isMixed: false,
        ),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        textStrokeColor: MixedValue(
          value: defaults.textStrokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: defaults.textStrokeWidth,
          isMixed: false,
        ),
        cornerRadius: MixedValue(value: defaults.cornerRadius, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedTexts.first;
    final firstData = first.data;
    if (firstData is! TextData) {
      return TextStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fontSize: MixedValue(value: defaults.fontSize, isMixed: false),
        fontFamily: MixedValue(value: defaults.fontFamily, isMixed: false),
        horizontalAlign: MixedValue(value: defaults.textAlign, isMixed: false),
        verticalAlign: MixedValue(
          value: defaults.verticalAlign,
          isMixed: false,
        ),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        textStrokeColor: MixedValue(
          value: defaults.textStrokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: defaults.textStrokeWidth,
          isMixed: false,
        ),
        cornerRadius: MixedValue(value: defaults.cornerRadius, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedTexts.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return TextStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        fontSize: MixedValue(value: firstData.fontSize, isMixed: false),
        fontFamily: MixedValue(value: firstData.fontFamily, isMixed: false),
        horizontalAlign: MixedValue(
          value: firstData.horizontalAlign,
          isMixed: false,
        ),
        verticalAlign: MixedValue(
          value: firstData.verticalAlign,
          isMixed: false,
        ),
        fillColor: MixedValue(value: firstData.fillColor, isMixed: false),
        fillStyle: MixedValue(value: firstData.fillStyle, isMixed: false),
        textStrokeColor: MixedValue(
          value: firstData.strokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: firstData.strokeWidth,
          isMixed: false,
        ),
        cornerRadius: MixedValue(value: firstData.cornerRadius, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final fontSize = firstData.fontSize;
    final fontFamily = firstData.fontFamily;
    final horizontalAlign = firstData.horizontalAlign;
    final verticalAlign = firstData.verticalAlign;
    final fillColor = firstData.fillColor;
    final fillStyle = firstData.fillStyle;
    final textStrokeColor = firstData.strokeColor;
    final textStrokeWidth = firstData.strokeWidth;
    final cornerRadius = firstData.cornerRadius;

    var colorMixed = false;
    var fontSizeMixed = false;
    var fontFamilyMixed = false;
    var horizontalAlignMixed = false;
    var verticalAlignMixed = false;
    var fillColorMixed = false;
    var fillStyleMixed = false;
    var textStrokeColorMixed = false;
    var textStrokeWidthMixed = false;
    var cornerRadiusMixed = false;

    for (final element in _selectedTexts.skip(1)) {
      final data = element.data;
      if (data is! TextData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!fontSizeMixed && !_doubleEquals(data.fontSize, fontSize)) {
        fontSizeMixed = true;
      }
      if (!fontFamilyMixed && data.fontFamily != fontFamily) {
        fontFamilyMixed = true;
      }
      if (!horizontalAlignMixed && data.horizontalAlign != horizontalAlign) {
        horizontalAlignMixed = true;
      }
      if (!verticalAlignMixed && data.verticalAlign != verticalAlign) {
        verticalAlignMixed = true;
      }
      if (!fillColorMixed && data.fillColor != fillColor) {
        fillColorMixed = true;
      }
      if (!fillStyleMixed && data.fillStyle != fillStyle) {
        fillStyleMixed = true;
      }
      if (!textStrokeColorMixed && data.strokeColor != textStrokeColor) {
        textStrokeColorMixed = true;
      }
      if (!textStrokeWidthMixed &&
          !_doubleEquals(data.strokeWidth, textStrokeWidth)) {
        textStrokeWidthMixed = true;
      }
      if (!cornerRadiusMixed &&
          !_doubleEquals(data.cornerRadius, cornerRadius)) {
        cornerRadiusMixed = true;
      }
      if (colorMixed &&
          fontSizeMixed &&
          fontFamilyMixed &&
          horizontalAlignMixed &&
          verticalAlignMixed &&
          fillColorMixed &&
          fillStyleMixed &&
          textStrokeColorMixed &&
          textStrokeWidthMixed &&
          cornerRadiusMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return TextStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      fontSize: MixedValue(
        value: fontSizeMixed ? null : fontSize,
        isMixed: fontSizeMixed,
      ),
      fontFamily: MixedValue(
        value: fontFamilyMixed ? null : fontFamily,
        isMixed: fontFamilyMixed,
      ),
      horizontalAlign: MixedValue(
        value: horizontalAlignMixed ? null : horizontalAlign,
        isMixed: horizontalAlignMixed,
      ),
      verticalAlign: MixedValue(
        value: verticalAlignMixed ? null : verticalAlign,
        isMixed: verticalAlignMixed,
      ),
      fillColor: MixedValue(
        value: fillColorMixed ? null : fillColor,
        isMixed: fillColorMixed,
      ),
      fillStyle: MixedValue(
        value: fillStyleMixed ? null : fillStyle,
        isMixed: fillStyleMixed,
      ),
      textStrokeColor: MixedValue(
        value: textStrokeColorMixed ? null : textStrokeColor,
        isMixed: textStrokeColorMixed,
      ),
      textStrokeWidth: MixedValue(
        value: textStrokeWidthMixed ? null : textStrokeWidth,
        isMixed: textStrokeWidthMixed,
      ),
      cornerRadius: MixedValue(
        value: cornerRadiusMixed ? null : cornerRadius,
        isMixed: cornerRadiusMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves highlight style values for the current selection.
  HighlightStyleValues _resolveHighlightStyles() {
    final defaults = _config.highlightStyle;
    if (_selectedHighlights.isEmpty) {
      return HighlightStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        highlightShape: MixedValue(
          value: defaults.highlightShape,
          isMixed: false,
        ),
        textStrokeColor: MixedValue(
          value: defaults.textStrokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: defaults.textStrokeWidth,
          isMixed: false,
        ),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedHighlights.first;
    final firstData = first.data;
    if (firstData is! HighlightData) {
      return HighlightStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        highlightShape: MixedValue(
          value: defaults.highlightShape,
          isMixed: false,
        ),
        textStrokeColor: MixedValue(
          value: defaults.textStrokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: defaults.textStrokeWidth,
          isMixed: false,
        ),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedHighlights.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return HighlightStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        highlightShape: MixedValue(value: firstData.shape, isMixed: false),
        textStrokeColor: MixedValue(
          value: firstData.strokeColor,
          isMixed: false,
        ),
        textStrokeWidth: MixedValue(
          value: firstData.strokeWidth,
          isMixed: false,
        ),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final highlightShape = firstData.shape;
    final textStrokeColor = firstData.strokeColor;
    final textStrokeWidth = firstData.strokeWidth;

    var colorMixed = false;
    var highlightShapeMixed = false;
    var textStrokeColorMixed = false;
    var textStrokeWidthMixed = false;

    for (final element in _selectedHighlights.skip(1)) {
      final data = element.data;
      if (data is! HighlightData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!highlightShapeMixed && data.shape != highlightShape) {
        highlightShapeMixed = true;
      }
      if (!textStrokeColorMixed && data.strokeColor != textStrokeColor) {
        textStrokeColorMixed = true;
      }
      if (!textStrokeWidthMixed &&
          !_doubleEquals(data.strokeWidth, textStrokeWidth)) {
        textStrokeWidthMixed = true;
      }
      if (colorMixed &&
          highlightShapeMixed &&
          textStrokeColorMixed &&
          textStrokeWidthMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return HighlightStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      highlightShape: MixedValue(
        value: highlightShapeMixed ? null : highlightShape,
        isMixed: highlightShapeMixed,
      ),
      textStrokeColor: MixedValue(
        value: textStrokeColorMixed ? null : textStrokeColor,
        isMixed: textStrokeColorMixed,
      ),
      textStrokeWidth: MixedValue(
        value: textStrokeWidthMixed ? null : textStrokeWidth,
        isMixed: textStrokeWidthMixed,
      ),
      opacity: opacity,
    );
  }

  /// Resolves filter style values for the current selection.
  FilterStyleValues _resolveFilterStyles() {
    final defaults = _config.filterStyle;
    if (_selectedFilters.isEmpty) {
      return FilterStyleValues(
        filterType: MixedValue(value: defaults.filterType, isMixed: false),
        filterStrength: MixedValue(
          value: defaults.filterStrength,
          isMixed: false,
        ),
      );
    }

    final first = _selectedFilters.first;
    final firstData = first.data;
    if (firstData is! FilterData) {
      return FilterStyleValues(
        filterType: MixedValue(value: defaults.filterType, isMixed: false),
        filterStrength: MixedValue(
          value: defaults.filterStrength,
          isMixed: false,
        ),
      );
    }

    if (_selectedFilters.length == 1) {
      return FilterStyleValues(
        filterType: MixedValue(value: firstData.type, isMixed: false),
        filterStrength: MixedValue(value: firstData.strength, isMixed: false),
      );
    }

    final filterType = firstData.type;
    final filterStrength = firstData.strength;

    var filterTypeMixed = false;
    var filterStrengthMixed = false;

    for (final element in _selectedFilters.skip(1)) {
      final data = element.data;
      if (data is! FilterData) {
        continue;
      }
      if (!filterTypeMixed && data.type != filterType) {
        filterTypeMixed = true;
      }
      if (!filterStrengthMixed &&
          !_doubleEquals(data.strength, filterStrength)) {
        filterStrengthMixed = true;
      }
      if (filterTypeMixed && filterStrengthMixed) {
        break;
      }
    }

    return FilterStyleValues(
      filterType: MixedValue(
        value: filterTypeMixed ? null : filterType,
        isMixed: filterTypeMixed,
      ),
      filterStrength: MixedValue(
        value: filterStrengthMixed ? null : filterStrength,
        isMixed: filterStrengthMixed,
      ),
    );
  }

  /// Resolves serial number style values for the current selection.
  SerialNumberStyleValues _resolveSerialNumberStyles() {
    final defaults = _config.serialNumberStyle;
    if (_selectedSerialNumbers.isEmpty) {
      return SerialNumberStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        fontSize: MixedValue(value: defaults.fontSize, isMixed: false),
        fontFamily: MixedValue(value: defaults.fontFamily, isMixed: false),
        number: MixedValue(value: defaults.serialNumber, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    final first = _selectedSerialNumbers.first;
    final firstData = first.data;
    if (firstData is! SerialNumberData) {
      return SerialNumberStyleValues(
        color: MixedValue(value: defaults.color, isMixed: false),
        fillColor: MixedValue(value: defaults.fillColor, isMixed: false),
        fillStyle: MixedValue(value: defaults.fillStyle, isMixed: false),
        fontSize: MixedValue(value: defaults.fontSize, isMixed: false),
        fontFamily: MixedValue(value: defaults.fontFamily, isMixed: false),
        number: MixedValue(value: defaults.serialNumber, isMixed: false),
        opacity: MixedValue(value: defaults.opacity, isMixed: false),
      );
    }

    if (_selectedSerialNumbers.length == 1) {
      final opacity = _resolveMixedOpacity(defaults.opacity);
      return SerialNumberStyleValues(
        color: MixedValue(value: firstData.color, isMixed: false),
        fillColor: MixedValue(value: firstData.fillColor, isMixed: false),
        fillStyle: MixedValue(value: firstData.fillStyle, isMixed: false),
        fontSize: MixedValue(value: firstData.fontSize, isMixed: false),
        fontFamily: MixedValue(value: firstData.fontFamily, isMixed: false),
        number: MixedValue(value: firstData.number, isMixed: false),
        opacity: opacity,
      );
    }

    final color = firstData.color;
    final fillColor = firstData.fillColor;
    final fillStyle = firstData.fillStyle;
    final fontSize = firstData.fontSize;
    final fontFamily = firstData.fontFamily;
    final number = firstData.number;

    var colorMixed = false;
    var fillColorMixed = false;
    var fillStyleMixed = false;
    var fontSizeMixed = false;
    var fontFamilyMixed = false;
    var numberMixed = false;

    for (final element in _selectedSerialNumbers.skip(1)) {
      final data = element.data;
      if (data is! SerialNumberData) {
        continue;
      }
      if (!colorMixed && data.color != color) {
        colorMixed = true;
      }
      if (!fillColorMixed && data.fillColor != fillColor) {
        fillColorMixed = true;
      }
      if (!fillStyleMixed && data.fillStyle != fillStyle) {
        fillStyleMixed = true;
      }
      if (!fontSizeMixed && !_doubleEquals(data.fontSize, fontSize)) {
        fontSizeMixed = true;
      }
      if (!fontFamilyMixed && data.fontFamily != fontFamily) {
        fontFamilyMixed = true;
      }
      if (!numberMixed && data.number != number) {
        numberMixed = true;
      }
      if (colorMixed &&
          fillColorMixed &&
          fillStyleMixed &&
          fontSizeMixed &&
          fontFamilyMixed &&
          numberMixed) {
        break;
      }
    }

    final opacity = _resolveMixedOpacity(defaults.opacity);

    return SerialNumberStyleValues(
      color: MixedValue(value: colorMixed ? null : color, isMixed: colorMixed),
      fillColor: MixedValue(
        value: fillColorMixed ? null : fillColor,
        isMixed: fillColorMixed,
      ),
      fillStyle: MixedValue(
        value: fillStyleMixed ? null : fillStyle,
        isMixed: fillStyleMixed,
      ),
      fontSize: MixedValue(
        value: fontSizeMixed ? null : fontSize,
        isMixed: fontSizeMixed,
      ),
      fontFamily: MixedValue(
        value: fontFamilyMixed ? null : fontFamily,
        isMixed: fontFamilyMixed,
      ),
      number: MixedValue(
        value: numberMixed ? null : number,
        isMixed: numberMixed,
      ),
      opacity: opacity,
    );
  }

  MixedValue<double> _resolveMixedOpacity(double fallback) {
    if (_selectedElements.isEmpty) {
      return MixedValue(value: fallback, isMixed: false);
    }
    if (_selectedElements.length == 1) {
      return MixedValue(value: _selectedElements.first.opacity, isMixed: false);
    }

    double? opacity;
    var isMixed = false;
    for (final element in _selectedElements) {
      if (opacity == null) {
        opacity = element.opacity;
        continue;
      }
      if (!_doubleEquals(element.opacity, opacity)) {
        isMixed = true;
        break;
      }
    }
    return MixedValue(value: isMixed ? null : opacity, isMixed: isMixed);
  }

  Future<void> _updateStyleConfig({
    Color? color,
    Color? fillColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    FillStyle? fillStyle,
    double? cornerRadius,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    double? fontSize,
    String? fontFamily,
    TextHorizontalAlign? textAlign,
    TextVerticalAlign? verticalAlign,
    double? opacity,
    Color? textStrokeColor,
    double? textStrokeWidth,
    HighlightShape? highlightShape,
    CanvasFilterType? filterType,
    double? filterStrength,
    Color? maskColor,
    double? maskOpacity,
    int? serialNumber,
    ToolType? toolType,
    StyleUpdateScope scope = StyleUpdateScope.allSelectedElements,
  }) {
    final highlightsOnlyScope = scope == StyleUpdateScope.highlightsOnly;
    final filtersOnlyScope = scope == StyleUpdateScope.filtersOnly;
    final textsOnlyScope = scope == StyleUpdateScope.textsOnly;
    final hasSelection = _selectedIds.isNotEmpty;
    final interaction = _store.state.application.interaction;
    final updateRectangleDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            _selectedRectangles.isNotEmpty) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            toolType == ToolType.rectangle);
    final updateArrowDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            _selectedArrows.isNotEmpty) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            toolType == ToolType.arrow);
    final updateLineDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            _selectedLines.isNotEmpty) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            toolType == ToolType.line);
    final updateFreeDrawDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            _selectedFreeDraws.isNotEmpty) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            toolType == ToolType.freeDraw);
    final updateTextDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            _selectedTexts.isNotEmpty) ||
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            interaction is TextEditingState) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            toolType == ToolType.text);
    final updateHighlightDefaults =
        !filtersOnlyScope &&
        !textsOnlyScope &&
        (_selectedHighlights.isNotEmpty ||
            (!hasSelection && toolType == ToolType.highlight));
    final updateFilterDefaults =
        !highlightsOnlyScope &&
        !textsOnlyScope &&
        (_selectedFilters.isNotEmpty ||
            (!hasSelection && toolType == ToolType.filter));
    final updateSerialNumberDefaults =
        (!highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            _selectedSerialNumbers.isNotEmpty) ||
        (!hasSelection &&
            !highlightsOnlyScope &&
            !filtersOnlyScope &&
            !textsOnlyScope &&
            toolType == ToolType.serialNumber);
    final updateHighlightMask =
        (maskColor != null || maskOpacity != null) && updateHighlightDefaults;

    if (!updateRectangleDefaults &&
        !updateArrowDefaults &&
        !updateLineDefaults &&
        !updateFreeDrawDefaults &&
        !updateTextDefaults &&
        !updateHighlightDefaults &&
        !updateFilterDefaults &&
        !updateSerialNumberDefaults &&
        !updateHighlightMask) {
      return Future<void>.value();
    }

    return _enqueueConfigUpdate(() async {
      if (_isDisposed) {
        return;
      }
      final currentConfig = _store.config;
      _config = currentConfig;

      var nextRectangleStyle = currentConfig.rectangleStyle;
      var nextArrowStyle = currentConfig.arrowStyle;
      var nextLineStyle = currentConfig.lineStyle;
      var nextFreeDrawStyle = currentConfig.freeDrawStyle;
      var nextTextStyle = currentConfig.textStyle;
      var nextHighlightStyle = currentConfig.highlightStyle;
      var nextFilterStyle = currentConfig.filterStyle;
      var nextSerialNumberStyle = currentConfig.serialNumberStyle;
      var nextHighlightMask = currentConfig.highlight;

      if (updateRectangleDefaults) {
        nextRectangleStyle = nextRectangleStyle.copyWith(
          color: color,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fillStyle: fillStyle,
          cornerRadius: cornerRadius,
          fontSize: fontSize,
          fontFamily: fontFamily,
          textAlign: textAlign,
          verticalAlign: verticalAlign,
          opacity: opacity,
          textStrokeColor: textStrokeColor,
          textStrokeWidth: textStrokeWidth,
        );
      }
      if (updateArrowDefaults) {
        nextArrowStyle = nextArrowStyle.copyWith(
          color: color,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          arrowType: arrowType,
          startArrowhead: startArrowhead,
          endArrowhead: endArrowhead,
          opacity: opacity,
        );
      }
      if (updateLineDefaults) {
        nextLineStyle = nextLineStyle.copyWith(
          color: color,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fillStyle: fillStyle,
          opacity: opacity,
        );
      }
      if (updateFreeDrawDefaults) {
        nextFreeDrawStyle = nextFreeDrawStyle.copyWith(
          color: color,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fillStyle: fillStyle,
          opacity: opacity,
        );
      }
      if (updateTextDefaults) {
        nextTextStyle = nextTextStyle.copyWith(
          color: color,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fillStyle: fillStyle,
          cornerRadius: cornerRadius,
          fontSize: fontSize,
          fontFamily: fontFamily,
          textAlign: textAlign,
          verticalAlign: verticalAlign,
          opacity: opacity,
          textStrokeColor: textStrokeColor,
          textStrokeWidth: textStrokeWidth,
        );
      }
      if (updateHighlightDefaults) {
        nextHighlightStyle = nextHighlightStyle.copyWith(
          color: color,
          highlightShape: highlightShape,
          textStrokeColor: textStrokeColor,
          textStrokeWidth: textStrokeWidth,
          opacity: opacity,
        );
      }
      if (updateFilterDefaults) {
        nextFilterStyle = nextFilterStyle.copyWith(
          filterType: filterType,
          filterStrength: filterStrength,
        );
      }
      if (updateHighlightMask) {
        nextHighlightMask = nextHighlightMask.copyWith(
          maskColor: maskColor,
          maskOpacity: maskOpacity,
        );
      }
      if (updateSerialNumberDefaults) {
        nextSerialNumberStyle = nextSerialNumberStyle.copyWith(
          serialNumber: serialNumber,
          color: color,
          fillColor: fillColor,
          fillStyle: fillStyle,
          strokeWidth: strokeWidth,
          strokeStyle: strokeStyle,
          fontSize: fontSize,
          fontFamily: fontFamily,
          opacity: opacity,
        );
      }

      if (nextRectangleStyle == currentConfig.rectangleStyle &&
          nextArrowStyle == currentConfig.arrowStyle &&
          nextLineStyle == currentConfig.lineStyle &&
          nextFreeDrawStyle == currentConfig.freeDrawStyle &&
          nextTextStyle == currentConfig.textStyle &&
          nextHighlightStyle == currentConfig.highlightStyle &&
          nextFilterStyle == currentConfig.filterStyle &&
          nextSerialNumberStyle == currentConfig.serialNumberStyle &&
          nextHighlightMask == currentConfig.highlight) {
        return;
      }

      final nextConfig = currentConfig.copyWith(
        rectangleStyle: nextRectangleStyle,
        arrowStyle: nextArrowStyle,
        lineStyle: nextLineStyle,
        freeDrawStyle: nextFreeDrawStyle,
        textStyle: nextTextStyle,
        highlightStyle: nextHighlightStyle,
        filterStyle: nextFilterStyle,
        serialNumberStyle: nextSerialNumberStyle,
        highlight: nextHighlightMask,
      );
      _handleConfigChange(nextConfig);
      try {
        await _store.dispatch(UpdateConfig(nextConfig));
      } on Object {
        if (_isDisposed) {
          return;
        }
        _handleConfigChange(_store.config);
        rethrow;
      }
    });
  }

  Future<void> _enqueueConfigUpdate(Future<void> Function() update) =>
      ConfigUpdateQueue.enqueue(_store, update);

  void _publishState() {
    if (_isDisposed) {
      return;
    }

    if (_updateScheduled) {
      return;
    }

    _updateScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _updateScheduled = false;
      if (_isDisposed) {
        return;
      }
      final nextState = _buildState();
      if (nextState == _stateNotifier.value) {
        return;
      }
      _stateNotifier.value = nextState;
    });
  }

  StyleToolbarState _buildState() => StyleToolbarState(
    rectangleStyle: _config.rectangleStyle,
    arrowStyle: _config.arrowStyle,
    lineStyle: _config.lineStyle,
    freeDrawStyle: _config.freeDrawStyle,
    textStyle: _config.textStyle,
    highlightStyle: _config.highlightStyle,
    filterStyle: _config.filterStyle,
    serialNumberStyle: _config.serialNumberStyle,
    styleValues: _styleValues,
    arrowStyleValues: _arrowStyleValues,
    lineStyleValues: _lineStyleValues,
    freeDrawStyleValues: _freeDrawStyleValues,
    textStyleValues: _textStyleValues,
    highlightStyleValues: _highlightStyleValues,
    filterStyleValues: _filterStyleValues,
    serialNumberStyleValues: _serialNumberStyleValues,
    highlightMask: _config.highlight,
    hasSelection: _selectedIds.isNotEmpty,
    hasSelectedRectangles: _selectedRectangles.isNotEmpty,
    hasSelectedArrows: _selectedArrows.isNotEmpty,
    hasSelectedLines: _selectedLines.isNotEmpty,
    hasSelectedFreeDraws: _selectedFreeDraws.isNotEmpty,
    hasSelectedTexts: _selectedTexts.isNotEmpty,
    hasSelectedHighlights: _selectedHighlights.isNotEmpty,
    hasSelectedFilters: _selectedFilters.isNotEmpty,
    hasSelectedSerialNumbers: _selectedSerialNumbers.isNotEmpty,
  );

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.01;

  String? _normalizeFontFamily(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? '' : trimmed;
  }
}

@immutable
class _ElementStyleSnapshot {
  const _ElementStyleSnapshot({
    required this.opacity,
    required this.dataIdentity,
  });

  final double opacity;
  final Object dataIdentity;

  factory _ElementStyleSnapshot.fromElement(ElementState element) =>
      _ElementStyleSnapshot(
        opacity: element.opacity,
        dataIdentity: element.data,
      );

  bool matches(
    _ElementStyleSnapshot other,
    bool Function(double, double) equals,
  ) =>
      identical(dataIdentity, other.dataIdentity) &&
      equals(opacity, other.opacity);
}

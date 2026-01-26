import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'style_toolbar_state.dart';
import 'system_fonts.dart';
import 'tool_controller.dart';

class StyleToolbarAdapter {
  StyleToolbarAdapter({required DrawStore store}) : _store = store {
    _config = _store.config;
    _selectedIds = _store.state.domain.selection.selectedIds;
    _refreshSelectedElements();
    _styleValues = _resolveRectangleStyles();
    _arrowStyleValues = _resolveArrowStyles();
    _textStyleValues = _resolveTextStyles();
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
  List<ElementState> _selectedArrows = const [];
  List<ElementState> _selectedTexts = const [];
  Map<String, _ElementStyleSnapshot> _styleSnapshot = const {};
  late RectangleStyleValues _styleValues;
  late ArrowStyleValues _arrowStyleValues;
  late TextStyleValues _textStyleValues;
  var _isDisposed = false;
  var _updateScheduled = false;

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
    ToolType? toolType,
  }) async {
    final resolvedFamily = fontFamily?.trim();
    if (resolvedFamily != null && resolvedFamily.isNotEmpty) {
      await ensureSystemFontLoaded(resolvedFamily);
    }
    final ids = {..._selectedIds};
    final interaction = _store.state.application.interaction;
    if (interaction is TextEditingState) {
      ids.add(interaction.elementId);
    }
    if (ids.isNotEmpty) {
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
          fontFamily: fontFamily,
          textAlign: textAlign,
          verticalAlign: verticalAlign,
          opacity: opacity,
          textStrokeColor: textStrokeColor,
          textStrokeWidth: textStrokeWidth,
        ),
      );
    }

    _updateStyleConfig(
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
      toolType: toolType,
    );
  }

  Future<void> copySelection() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(
      DuplicateElements(elementIds: ids, offsetX: 12, offsetY: 12),
    );
  }

  Future<void> deleteSelection() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(DeleteElements(elementIds: ids));
  }

  Future<void> changeZOrder(ZIndexOperation operation) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await _store.dispatch(
      ChangeElementsZIndex(elementIds: ids, operation: operation),
    );
  }

  void _handleStateChange(DrawState state) {
    final nextSelectedIds = state.domain.selection.selectedIds;
    if (!setEquals(_selectedIds, nextSelectedIds)) {
      _selectedIds = nextSelectedIds;
      _refreshSelectedElements();
      _styleValues = _resolveRectangleStyles();
      _arrowStyleValues = _resolveArrowStyles();
      _textStyleValues = _resolveTextStyles();
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
    _styleValues = _resolveRectangleStyles();
    _arrowStyleValues = _resolveArrowStyles();
    _textStyleValues = _resolveTextStyles();
    _publishState();
  }

  void _handleConfigChange(DrawConfig config) {
    if (config == _config) {
      return;
    }
    final rectangleStyleChanged =
        config.rectangleStyle != _config.rectangleStyle;
    final arrowStyleChanged = config.arrowStyle != _config.arrowStyle;
    final textStyleChanged = config.textStyle != _config.textStyle;
    _config = config;
    if (!rectangleStyleChanged && !arrowStyleChanged && !textStyleChanged) {
      return;
    }
    if (_selectedRectangles.isEmpty && rectangleStyleChanged) {
      _styleValues = _resolveRectangleStyles();
    }
    if (_selectedArrows.isEmpty && arrowStyleChanged) {
      _arrowStyleValues = _resolveArrowStyles();
    }
    if (_selectedTexts.isEmpty && textStyleChanged) {
      _textStyleValues = _resolveTextStyles();
    }
    _publishState();
  }

  bool _refreshSelectedElements() {
    final selectedIds = _selectedIds;
    if (selectedIds.isEmpty) {
      final changed =
          _selectedElements.isNotEmpty ||
          _selectedRectangles.isNotEmpty ||
          _selectedArrows.isNotEmpty ||
          _selectedTexts.isNotEmpty ||
          _styleSnapshot.isNotEmpty;
      if (changed) {
        _selectedElements = const [];
        _selectedRectangles = const [];
        _selectedArrows = const [];
        _selectedTexts = const [];
        _styleSnapshot = const {};
      }
      return changed;
    }

    final document = _store.state.domain.document;
    final selectedElements = <ElementState>[];
    final selectedRectangles = <ElementState>[];
    final selectedArrows = <ElementState>[];
    final selectedTexts = <ElementState>[];
    final nextSnapshot = <String, _ElementStyleSnapshot>{};
    var snapshotChanged = false;
    for (final id in selectedIds) {
      final element = document.getElementById(id);
      if (element == null) {
        snapshotChanged = true;
        continue;
      }
      selectedElements.add(element);
      if (element.data is RectangleData) {
        selectedRectangles.add(element);
      }
      if (element.data is ArrowData) {
        selectedArrows.add(element);
      }
      if (element.data is TextData) {
        selectedTexts.add(element);
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
    _selectedArrows = selectedArrows;
    _selectedTexts = selectedTexts;
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

  void _updateStyleConfig({
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
    ToolType? toolType,
  }) {
    final hasSelection = _selectedIds.isNotEmpty;
    final interaction = _store.state.application.interaction;
    final updateRectangleDefaults =
        _selectedRectangles.isNotEmpty ||
        (!hasSelection && toolType == ToolType.rectangle);
    final updateArrowDefaults =
        _selectedArrows.isNotEmpty ||
        (!hasSelection && toolType == ToolType.arrow);
    final updateTextDefaults =
        _selectedTexts.isNotEmpty ||
        interaction is TextEditingState ||
        (!hasSelection && toolType == ToolType.text);

    if (!updateRectangleDefaults &&
        !updateArrowDefaults &&
        !updateTextDefaults) {
      return;
    }

    var nextRectangleStyle = _config.rectangleStyle;
    var nextArrowStyle = _config.arrowStyle;
    var nextTextStyle = _config.textStyle;

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

    if (nextRectangleStyle == _config.rectangleStyle &&
        nextArrowStyle == _config.arrowStyle &&
        nextTextStyle == _config.textStyle) {
      return;
    }

    unawaited(
      _store.dispatch(
        UpdateConfig(
          _config.copyWith(
            rectangleStyle: nextRectangleStyle,
            arrowStyle: nextArrowStyle,
            textStyle: nextTextStyle,
          ),
        ),
      ),
    );
  }

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
    textStyle: _config.textStyle,
    styleValues: _styleValues,
    arrowStyleValues: _arrowStyleValues,
    textStyleValues: _textStyleValues,
    hasSelection: _selectedIds.isNotEmpty,
    hasSelectedRectangles: _selectedRectangles.isNotEmpty,
    hasSelectedArrows: _selectedArrows.isNotEmpty,
    hasSelectedTexts: _selectedTexts.isNotEmpty,
  );

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.01;
}

@immutable
class _ElementStyleSnapshot {
  const _ElementStyleSnapshot({
    required this.opacity,
    this.rectangleData,
    this.arrowData,
    this.textData,
  });

  final double opacity;
  final RectangleData? rectangleData;
  final ArrowData? arrowData;
  final TextData? textData;

  factory _ElementStyleSnapshot.fromElement(ElementState element) =>
      _ElementStyleSnapshot(
        opacity: element.opacity,
        rectangleData: element.data is RectangleData
            ? element.data as RectangleData
            : null,
        arrowData: element.data is ArrowData ? element.data as ArrowData : null,
        textData: element.data is TextData ? element.data as TextData : null,
      );

  bool matches(
    _ElementStyleSnapshot other,
    bool Function(double, double) equals,
  ) =>
      identical(rectangleData, other.rectangleData) &&
      identical(arrowData, other.arrowData) &&
      identical(textData, other.textData) &&
      equals(opacity, other.opacity);
}

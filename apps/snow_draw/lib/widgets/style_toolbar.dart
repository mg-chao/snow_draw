import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import '../icons/svg_icons.dart';
import '../l10n/app_localizations.dart';
import '../style_toolbar_state.dart';
import '../system_fonts.dart';
import '../tool_controller.dart';
import '../toolbar_adapter.dart';

class StyleToolbar extends StatefulWidget {
  const StyleToolbar({
    required this.strings,
    required this.adapter,
    required this.toolController,
    required this.size,
    required this.width,
    required this.topInset,
    required this.bottomInset,
    super.key,
  });

  final AppLocalizations strings;
  final StyleToolbarAdapter adapter;
  final ToolController toolController;
  final Size size;
  final double width;
  final double topInset;
  final double bottomInset;

  @override
  State<StyleToolbar> createState() => _StyleToolbarState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(DiagnosticsProperty<StyleToolbarAdapter>('adapter', adapter))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      )
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DoubleProperty('width', width))
      ..add(DoubleProperty('topInset', topInset))
      ..add(DoubleProperty('bottomInset', bottomInset));
  }
}

class _StyleToolbarState extends State<StyleToolbar> {
  static const double _toolbarRadius = 12;
  static const double _toolbarPadding = 12;
  static const double _toolbarVerticalPadding = 16;
  static const double _persistentVerticalPadding = 8;
  static const double _sectionSpacing = 16;
  static const double _sectionGap = 8;
  static const double _swatchSize = 24;
  static const double _iconSize = 18;
  static const double _smallIconSize = 12;
  static const double _toggleButtonHeight = 32;
  static const double _toggleButtonWidth = 40;
  static const double _toggleButtonRadius = 8;
  static const double _sliderTrackHeight = 2;
  static const double _sliderThumbRadius = 6;
  static const double _sliderOverlayRadius = 12;
  static const _sliderDebounceDuration = Duration(milliseconds: 180);
  static const double _fontSizeSmall = 16;
  static const double _fontSizeMedium = 21;
  static const double _fontSizeLarge = 27;
  static const double _fontSizeExtraLarge = 42;
  static final _fontFamilySystemKey = Object();
  static final _fontFamilyMixedKey = Object();
  static const _defaultColorPalette = [
    Color(0xFF1E1E1E),
    Color(0xFFF5222D),
    Color(0xFF52C41A),
    Color(0xFF1677FF),
    Color(0xFFFAAD14),
  ];

  late Listenable _mergedListenable;
  late final ScrollController _scrollController;
  Timer? _sliderUpdateTimer;
  double? _pendingCornerRadius;
  double? _pendingOpacity;
  List<String> _systemFontFamilies = const [];
  var _fontLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _mergedListenable = Listenable.merge([
      widget.toolController,
      widget.adapter.stateListenable,
    ]);
  }

  @override
  void dispose() {
    _sliderUpdateTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StyleToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolController != widget.toolController ||
        oldWidget.adapter != widget.adapter) {
      _mergedListenable = Listenable.merge([
        widget.toolController,
        widget.adapter.stateListenable,
      ]);
    }
  }

  void _requestSystemFonts() {
    if (_fontLoadRequested) {
      return;
    }
    _fontLoadRequested = true;
    unawaited(_loadSystemFonts());
  }

  Future<void> _loadSystemFonts() async {
    final families = await loadSystemFontFamilies();
    if (!mounted) {
      return;
    }
    setState(() {
      _systemFontFamilies = families;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _mergedListenable,
    builder: (context, _) {
      final tool = widget.toolController.value;
      final state = widget.adapter.stateListenable.value;
      final showRectangleControls =
          tool == ToolType.rectangle || state.hasSelectedRectangles;
      final showArrowControls =
          tool == ToolType.arrow || state.hasSelectedArrows;
      final showTextControls = tool == ToolType.text || state.hasSelectedTexts;
      final showToolbar =
          showRectangleControls || showArrowControls || showTextControls;
      if (showTextControls) {
        _requestSystemFonts();
      }
      final maxHeight = math
          .max(0, widget.size.height - widget.topInset - widget.bottomInset)
          .toDouble();
      final resolvedWidth = widget.width;
      final hasSelection = state.hasSelection;
      final hasSharedSelection =
          state.hasSelectedRectangles && state.hasSelectedTexts;
      final styleValues = state.styleValues;
      final arrowStyleValues = state.arrowStyleValues;
      final textStyleValues = state.textStyleValues;
      final rectangleDefaults = state.rectangleStyle;
      final arrowDefaults = state.arrowStyle;
      final textDefaults = state.textStyle;
      final sharedDefaults = tool == ToolType.text
          ? textDefaults
          : rectangleDefaults;
      final fillColorValue = styleValues.fillColor.value;
      final showFillStyle = fillColorValue == null || fillColorValue.a > 0;
      final textFillColorValue = textStyleValues.fillColor.value;
      final showTextFillStyle =
          textFillColorValue == null || textFillColorValue.a > 0;
      final showTextStrokeColor =
          textStyleValues.textStrokeWidth.isMixed ||
          (textStyleValues.textStrokeWidth.value ??
                  textDefaults.textStrokeWidth) >
              0;
      final sharedColorValues = hasSharedSelection
          ? _mergeMixedValues(
              styleValues.color,
              textStyleValues.color,
              _colorEquals,
            )
          : null;
      final sharedFillColorValues = hasSharedSelection
          ? _mergeMixedValues(
              styleValues.fillColor,
              textStyleValues.fillColor,
              _colorEquals,
            )
          : null;
      final sharedCornerRadius = hasSharedSelection
          ? _mergeMixedValues(
              styleValues.cornerRadius,
              textStyleValues.cornerRadius,
              _doubleEquals,
            )
          : null;
      final sharedOpacity = hasSharedSelection
          ? _mergeMixedValues(
              styleValues.opacity,
              textStyleValues.opacity,
              _doubleEquals,
            )
          : null;

      if (!showToolbar) {
        return const SizedBox.shrink();
      }

      return Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(_toolbarRadius),
        color: Colors.white,
        child: SizedBox(
          width: resolvedWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: _persistentVerticalPadding,
              ),
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: _toolbarPadding,
                    vertical:
                        _toolbarVerticalPadding - _persistentVerticalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasSharedSelection) ...[
                        _buildColorRow(
                          label: widget.strings.color,
                          colors: _defaultColorPalette,
                          value: sharedColorValues!,
                          customColor: sharedColorValues.valueOr(
                            sharedDefaults.color,
                          ),
                          onSelect: (color) => _applyStyleUpdate(color: color),
                          allowAlpha: true,
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildColorRow(
                          label: widget.strings.fillColor,
                          colors: const [
                            Colors.transparent,
                            Color(0xFFFFCCC7),
                            Color(0xFFD9F7BE),
                            Color(0xFFBAE0FF),
                            Color(0xFFFFF1B8),
                          ],
                          value: sharedFillColorValues!,
                          customColor: sharedFillColorValues.valueOr(
                            sharedDefaults.fillColor,
                          ),
                          onSelect: (color) =>
                              _applyStyleUpdate(fillColor: color),
                          allowAlpha: true,
                        ),
                      ],
                      if (showRectangleControls) ...[
                        if (!hasSharedSelection) ...[
                          _buildColorRow(
                            label: widget.strings.color,
                            colors: _defaultColorPalette,
                            value: styleValues.color,
                            customColor: styleValues.color.valueOr(
                              rectangleDefaults.color,
                            ),
                            onSelect: (color) =>
                                _applyStyleUpdate(color: color),
                            allowAlpha: true,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _buildColorRow(
                            label: widget.strings.fillColor,
                            colors: const [
                              Colors.transparent,
                              Color(0xFFFFCCC7),
                              Color(0xFFD9F7BE),
                              Color(0xFFBAE0FF),
                              Color(0xFFFFF1B8),
                            ],
                            value: styleValues.fillColor,
                            customColor: styleValues.fillColor.valueOr(
                              rectangleDefaults.fillColor,
                            ),
                            onSelect: (color) =>
                                _applyStyleUpdate(fillColor: color),
                            allowAlpha: true,
                          ),
                        ],
                        if (showFillStyle) ...[
                          const SizedBox(height: _sectionSpacing),
                          _buildStyleOptions(
                            label: widget.strings.fillStyle,
                            mixed: styleValues.fillStyle.isMixed,
                            mixedLabel: widget.strings.mixed,
                            options: [
                              _StyleOption(
                                value: FillStyle.line,
                                label: widget.strings.lineFill,
                                icon: const FillStyleLineIcon(),
                              ),
                              _StyleOption(
                                value: FillStyle.crossLine,
                                label: widget.strings.crossLineFill,
                                icon: const FillStyleCrossLineIcon(),
                              ),
                              _StyleOption(
                                value: FillStyle.solid,
                                label: widget.strings.solidFill,
                                icon: const FillStyleSolidIcon(),
                              ),
                            ],
                            selected: styleValues.fillStyle.value,
                            onSelect: (value) =>
                                _applyStyleUpdate(fillStyle: value),
                          ),
                        ],
                        const SizedBox(height: _sectionSpacing),
                        _buildStyleOptions(
                          label: widget.strings.strokeStyle,
                          mixed: styleValues.strokeStyle.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: StrokeStyle.solid,
                              label: widget.strings.solid,
                              icon: const StrokeStyleSolidIcon(),
                            ),
                            _StyleOption(
                              value: StrokeStyle.dashed,
                              label: widget.strings.dashed,
                              icon: const StrokeStyleDashedIcon(),
                            ),
                            _StyleOption(
                              value: StrokeStyle.dotted,
                              label: widget.strings.dotted,
                              icon: const StrokeStyleDottedIcon(),
                            ),
                          ],
                          selected: styleValues.strokeStyle.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(strokeStyle: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildNumericOptions(
                          label: widget.strings.strokeWidth,
                          mixed: styleValues.strokeWidth.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: 1,
                              label: widget.strings.thin,
                              icon: const StrokeWidthSmallIcon(),
                            ),
                            _StyleOption(
                              value: 3,
                              label: widget.strings.medium,
                              icon: const StrokeWidthMediumIcon(),
                            ),
                            _StyleOption(
                              value: 5,
                              label: widget.strings.thick,
                              icon: const StrokeWidthLargeIcon(),
                            ),
                          ],
                          selected: styleValues.strokeWidth.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(strokeWidth: value),
                        ),
                        if (!hasSharedSelection) ...[
                          const SizedBox(height: _sectionSpacing),
                          _buildSliderControl(
                            label: widget.strings.cornerRadius,
                            value: styleValues.cornerRadius,
                            defaultValue: rectangleDefaults.cornerRadius,
                            pendingValue: _pendingCornerRadius,
                            min: 0,
                            max: 83,
                            onChanged: (value) {
                              setState(() => _pendingCornerRadius = value);
                              _scheduleStyleUpdate(
                                () => _applyStyleUpdate(cornerRadius: value),
                              );
                            },
                            onChangeEnd: (value) async {
                              _flushStyleUpdate();
                              setState(() => _pendingCornerRadius = null);
                              await _applyStyleUpdate(cornerRadius: value);
                            },
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _buildOpacityControl(
                            styleValues.opacity,
                            rectangleDefaults.opacity,
                            pendingValue: _pendingOpacity,
                            onChanged: (value) {
                              setState(() => _pendingOpacity = value);
                              _scheduleStyleUpdate(
                                () => _applyStyleUpdate(opacity: value),
                              );
                            },
                            onChangeEnd: (value) async {
                              _flushStyleUpdate();
                              setState(() => _pendingOpacity = null);
                              await _applyStyleUpdate(opacity: value);
                            },
                          ),
                        ],
                      ],
                      if (showArrowControls) ...[
                        if (showRectangleControls)
                          const SizedBox(height: _sectionSpacing),
                        _buildColorRow(
                          label: widget.strings.color,
                          colors: _defaultColorPalette,
                          value: arrowStyleValues.color,
                          customColor: arrowStyleValues.color.valueOr(
                            arrowDefaults.color,
                          ),
                          onSelect: (color) => _applyStyleUpdate(color: color),
                          allowAlpha: true,
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildStyleOptions(
                          label: widget.strings.strokeStyle,
                          mixed: arrowStyleValues.strokeStyle.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: StrokeStyle.solid,
                              label: widget.strings.solid,
                              icon: const StrokeStyleSolidIcon(),
                            ),
                            _StyleOption(
                              value: StrokeStyle.dashed,
                              label: widget.strings.dashed,
                              icon: const StrokeStyleDashedIcon(),
                            ),
                            _StyleOption(
                              value: StrokeStyle.dotted,
                              label: widget.strings.dotted,
                              icon: const StrokeStyleDottedIcon(),
                            ),
                          ],
                          selected: arrowStyleValues.strokeStyle.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(strokeStyle: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildNumericOptions(
                          label: widget.strings.strokeWidth,
                          mixed: arrowStyleValues.strokeWidth.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: 1,
                              label: widget.strings.thin,
                              icon: const StrokeWidthSmallIcon(),
                            ),
                            _StyleOption(
                              value: 3,
                              label: widget.strings.medium,
                              icon: const StrokeWidthMediumIcon(),
                            ),
                            _StyleOption(
                              value: 8,
                              label: widget.strings.thick,
                              icon: const StrokeWidthLargeIcon(),
                            ),
                          ],
                          selected: arrowStyleValues.strokeWidth.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(strokeWidth: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildStyleOptions(
                          label: widget.strings.arrowType,
                          mixed: arrowStyleValues.arrowType.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: ArrowType.straight,
                              label: widget.strings.arrowTypeStraight,
                              icon: const _ArrowTypeIcon(
                                arrowType: ArrowType.straight,
                                size: _iconSize,
                              ),
                            ),
                            _StyleOption(
                              value: ArrowType.curved,
                              label: widget.strings.arrowTypeCurved,
                              icon: const _ArrowTypeIcon(
                                arrowType: ArrowType.curved,
                                size: _iconSize,
                              ),
                            ),
                            _StyleOption(
                              value: ArrowType.polyline,
                              label: widget.strings.arrowTypePolyline,
                              icon: const _ArrowTypeIcon(
                                arrowType: ArrowType.polyline,
                                size: _iconSize,
                              ),
                            ),
                          ],
                          selected: arrowStyleValues.arrowType.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(arrowType: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildArrowheadControls(
                          startArrowhead: arrowStyleValues.startArrowhead,
                          endArrowhead: arrowStyleValues.endArrowhead,
                          startDefault: arrowDefaults.startArrowhead,
                          endDefault: arrowDefaults.endArrowhead,
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildOpacityControl(
                          arrowStyleValues.opacity,
                          arrowDefaults.opacity,
                          pendingValue: _pendingOpacity,
                          onChanged: (value) {
                            setState(() => _pendingOpacity = value);
                            _scheduleStyleUpdate(
                              () => _applyStyleUpdate(opacity: value),
                            );
                          },
                          onChangeEnd: (value) async {
                            _flushStyleUpdate();
                            setState(() => _pendingOpacity = null);
                            await _applyStyleUpdate(opacity: value);
                          },
                        ),
                      ],
                      if (showTextControls) ...[
                        if (showRectangleControls || showArrowControls)
                          const SizedBox(height: _sectionSpacing),
                        if (!hasSharedSelection) ...[
                          _buildColorRow(
                            label: widget.strings.color,
                            colors: _defaultColorPalette,
                            value: textStyleValues.color,
                            customColor: textStyleValues.color.valueOr(
                              textDefaults.color,
                            ),
                            onSelect: (color) =>
                                _applyStyleUpdate(color: color),
                            allowAlpha: true,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _buildColorRow(
                            label: widget.strings.fillColor,
                            colors: const [
                              Colors.transparent,
                              Color(0xFFFFCCC7),
                              Color(0xFFD9F7BE),
                              Color(0xFFBAE0FF),
                              Color(0xFFFFF1B8),
                            ],
                            value: textStyleValues.fillColor,
                            customColor: textStyleValues.fillColor.valueOr(
                              textDefaults.fillColor,
                            ),
                            onSelect: (color) =>
                                _applyStyleUpdate(fillColor: color),
                            allowAlpha: true,
                          ),
                        ],
                        if (!hasSharedSelection && showTextFillStyle) ...[
                          const SizedBox(height: _sectionSpacing),
                          _buildStyleOptions(
                            label: widget.strings.fillStyle,
                            mixed: textStyleValues.fillStyle.isMixed,
                            mixedLabel: widget.strings.mixed,
                            options: [
                              _StyleOption(
                                value: FillStyle.line,
                                label: widget.strings.lineFill,
                                icon: const FillStyleLineIcon(),
                              ),
                              _StyleOption(
                                value: FillStyle.crossLine,
                                label: widget.strings.crossLineFill,
                                icon: const FillStyleCrossLineIcon(),
                              ),
                              _StyleOption(
                                value: FillStyle.solid,
                                label: widget.strings.solidFill,
                                icon: const FillStyleSolidIcon(),
                              ),
                            ],
                            selected: textStyleValues.fillStyle.value,
                            onSelect: (value) =>
                                _applyStyleUpdate(fillStyle: value),
                          ),
                        ],
                        if (!hasSharedSelection)
                          const SizedBox(height: _sectionSpacing),
                        _buildNumericOptions(
                          label: widget.strings.fontSize,
                          mixed: textStyleValues.fontSize.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            _StyleOption(
                              value: _fontSizeSmall,
                              label: widget.strings.small,
                              icon: const FontSizeSmallIcon(),
                            ),
                            _StyleOption(
                              value: _fontSizeMedium,
                              label: widget.strings.medium,
                              icon: const FontSizeMediumIcon(),
                            ),
                            _StyleOption(
                              value: _fontSizeLarge,
                              label: widget.strings.large,
                              icon: const FontSizeLargeIcon(),
                            ),
                            const _StyleOption(
                              value: _fontSizeExtraLarge,
                              label: 'Extra large',
                              icon: FontSizeVeryLargeIcon(),
                            ),
                          ],
                          selected: textStyleValues.fontSize.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(fontSize: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildFontFamilyControl(
                          value: textStyleValues.fontFamily,
                          onSelect: (value) =>
                              _applyStyleUpdate(fontFamily: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildTextAlignmentControl(
                          horizontalAlign: textStyleValues.horizontalAlign,
                          onHorizontalSelect: (value) =>
                              _applyStyleUpdate(textAlign: value),
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildNumericOptions(
                          label: widget.strings.textStrokeWidth,
                          mixed: textStyleValues.textStrokeWidth.isMixed,
                          mixedLabel: widget.strings.mixed,
                          options: [
                            const _StyleOption(
                              value: 0,
                              label: 'None',
                              icon: Icon(Icons.not_interested, size: _iconSize),
                            ),
                            _StyleOption(
                              value: 2,
                              label: widget.strings.thin,
                              icon: const StrokeWidthSmallIcon(),
                            ),
                            _StyleOption(
                              value: 3,
                              label: widget.strings.medium,
                              icon: const StrokeWidthMediumIcon(),
                            ),
                            _StyleOption(
                              value: 5,
                              label: widget.strings.thick,
                              icon: const StrokeWidthLargeIcon(),
                            ),
                          ],
                          selected: textStyleValues.textStrokeWidth.value,
                          onSelect: (value) =>
                              _applyStyleUpdate(textStrokeWidth: value),
                        ),
                        if (showTextStrokeColor) ...[
                          const SizedBox(height: _sectionSpacing),
                          _buildColorRow(
                            label: widget.strings.textStrokeColor,
                            colors: const [
                              Color(0xFFF8F4EC),
                              Color(0xFF1CA7A8),
                              Color(0xFFE45C9D),
                              Color(0xFFF4A261),
                              Color(0xFF1D3557),
                            ],
                            value: textStyleValues.textStrokeColor,
                            customColor: textStyleValues.textStrokeColor
                                .valueOr(textDefaults.textStrokeColor),
                            onSelect: (color) =>
                                _applyStyleUpdate(textStrokeColor: color),
                            allowAlpha: true,
                          ),
                        ],
                        if (!hasSharedSelection) ...[
                          if (showTextFillStyle) ...[
                            const SizedBox(height: _sectionSpacing),
                            _buildSliderControl(
                              label: widget.strings.cornerRadius,
                              value: textStyleValues.cornerRadius,
                              defaultValue: textDefaults.cornerRadius,
                              pendingValue: _pendingCornerRadius,
                              min: 0,
                              max: 83,
                              onChanged: (value) {
                                setState(() => _pendingCornerRadius = value);
                                _scheduleStyleUpdate(
                                  () => _applyStyleUpdate(cornerRadius: value),
                                );
                              },
                              onChangeEnd: (value) async {
                                _flushStyleUpdate();
                                setState(() => _pendingCornerRadius = null);
                                await _applyStyleUpdate(cornerRadius: value);
                              },
                            ),
                          ],
                          const SizedBox(height: _sectionSpacing),
                          _buildOpacityControl(
                            textStyleValues.opacity,
                            textDefaults.opacity,
                            pendingValue: _pendingOpacity,
                            onChanged: (value) {
                              setState(() => _pendingOpacity = value);
                              _scheduleStyleUpdate(
                                () => _applyStyleUpdate(opacity: value),
                              );
                            },
                            onChangeEnd: (value) async {
                              _flushStyleUpdate();
                              setState(() => _pendingOpacity = null);
                              await _applyStyleUpdate(opacity: value);
                            },
                          ),
                        ],
                      ],
                      if (hasSharedSelection) ...[
                        const SizedBox(height: _sectionSpacing),
                        _buildSliderControl(
                          label: widget.strings.cornerRadius,
                          value: sharedCornerRadius!,
                          defaultValue: sharedDefaults.cornerRadius,
                          pendingValue: _pendingCornerRadius,
                          min: 0,
                          max: 83,
                          onChanged: (value) {
                            setState(() => _pendingCornerRadius = value);
                            _scheduleStyleUpdate(
                              () => _applyStyleUpdate(cornerRadius: value),
                            );
                          },
                          onChangeEnd: (value) async {
                            _flushStyleUpdate();
                            setState(() => _pendingCornerRadius = null);
                            await _applyStyleUpdate(cornerRadius: value);
                          },
                        ),
                        const SizedBox(height: _sectionSpacing),
                        _buildOpacityControl(
                          sharedOpacity!,
                          sharedDefaults.opacity,
                          pendingValue: _pendingOpacity,
                          onChanged: (value) {
                            setState(() => _pendingOpacity = value);
                            _scheduleStyleUpdate(
                              () => _applyStyleUpdate(opacity: value),
                            );
                          },
                          onChangeEnd: (value) async {
                            _flushStyleUpdate();
                            setState(() => _pendingOpacity = null);
                            await _applyStyleUpdate(opacity: value);
                          },
                        ),
                      ],
                      if (hasSelection) ...[
                        const SizedBox(height: _sectionSpacing),
                        _buildLayerControls(hasSelection),
                        const SizedBox(height: _sectionSpacing),
                        _buildSelectionActions(hasSelection),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildSelectionActions(bool hasSelection) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader(widget.strings.operations),
      const SizedBox(height: _sectionGap),
      Row(
        children: [
          _buildOutlinedIconButton(
            icon: Icons.copy_all_outlined,
            message: widget.strings.copy,
            onPressed: hasSelection ? _handleCopy : null,
          ),
          const SizedBox(width: 12),
          _buildOutlinedIconButton(
            icon: Icons.delete_outline,
            message: widget.strings.delete,
            onPressed: hasSelection ? _handleDelete : null,
          ),
        ],
      ),
    ],
  );

  Widget _buildColorRow({
    required String label,
    required List<Color> colors,
    required MixedValue<Color> value,
    required Color customColor,
    required ValueChanged<Color> onSelect,
    required bool allowAlpha,
  }) {
    final theme = Theme.of(context);
    final isCustomSelected = !value.isMixed && !colors.contains(value.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label),
        const SizedBox(height: _sectionGap),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final color in colors)
                    Tooltip(
                      message: _quickColorName(color),
                      child: _buildColorSwatch(
                        color: color,
                        isSelected: !value.isMixed && value.value == color,
                        onTap: () => onSelect(color),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                width: 1.2,
                height: _swatchSize * 0.7,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(0.6),
                ),
              ),
            ),
            Tooltip(
              message: _colorToHex(customColor, allowAlpha),
              child: InkResponse(
                onTap: () async {
                  final picked = await _showColorPicker(
                    customColor,
                    allowAlpha: allowAlpha,
                    label: widget.strings.customColor,
                  );
                  if (picked != null) {
                    onSelect(picked);
                  }
                },
                radius: _swatchSize * 0.7,
                child: Container(
                  width: _swatchSize,
                  height: _swatchSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: customColor,
                    border: Border.all(
                      color: isCustomSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: isCustomSelected ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: _smallIconSize,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorSwatch({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return InkResponse(
      onTap: onTap,
      radius: _swatchSize * 0.7,
      child: Container(
        width: _swatchSize,
        height: _swatchSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.a == 0 ? Colors.white : color,
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: color.a == 0
            ? Icon(
                Icons.clear,
                size: _smallIconSize,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }

  Widget _buildStyleOptions<T>({
    required String label,
    required bool mixed,
    required String mixedLabel,
    required List<_StyleOption<T>> options,
    required T? selected,
    required ValueChanged<T> onSelect,
  }) {
    final selectedValues = options
        .map((option) => !mixed && selected == option.value)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label),
        const SizedBox(height: _sectionGap),
        ToggleButtons(
          isSelected: selectedValues,
          onPressed: (index) => onSelect(options[index].value),
          borderRadius: BorderRadius.circular(_toggleButtonRadius),
          constraints: const BoxConstraints.tightFor(
            height: _toggleButtonHeight,
            width: _toggleButtonWidth,
          ),
          children: options
              .map(
                (option) => Tooltip(message: option.label, child: option.icon),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildFontFamilyControl({
    required MixedValue<String> value,
    required ValueChanged<String?> onSelect,
  }) {
    final theme = Theme.of(context);
    final isMixed = value.isMixed;
    final fontFamilies = _resolveSupportedFontFamilies();
    final selectedFamily = value.value?.trim() ?? '';
    final hasSelectedFamily = !isMixed && selectedFamily.isNotEmpty;
    final selectedKey = isMixed
        ? _fontFamilyMixedKey
        : (hasSelectedFamily ? selectedFamily : _fontFamilySystemKey);
    final resolvedFamilies =
        hasSelectedFamily && !_containsFontFamily(fontFamilies, selectedFamily)
        ? [selectedFamily, ...fontFamilies]
        : fontFamilies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(widget.strings.fontFamily),
        const SizedBox(height: _sectionGap),
        DropdownButton<Object>(
          value: selectedKey,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          style: theme.textTheme.bodyMedium,
          items: [
            if (isMixed)
              DropdownMenuItem<Object>(
                value: _fontFamilyMixedKey,
                child: Text(widget.strings.mixed),
              ),
            DropdownMenuItem<Object>(
              value: _fontFamilySystemKey,
              child: Text(widget.strings.fontFamilySystem),
            ),
            ...resolvedFamilies.map(
              (family) =>
                  DropdownMenuItem<Object>(value: family, child: Text(family)),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == _fontFamilyMixedKey) {
              return;
            }
            if (value == _fontFamilySystemKey) {
              onSelect('');
              return;
            }
            onSelect(value as String);
          },
        ),
      ],
    );
  }

  Widget _buildTextAlignmentControl({
    required MixedValue<TextHorizontalAlign> horizontalAlign,
    required ValueChanged<TextHorizontalAlign> onHorizontalSelect,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader(widget.strings.textAlignment),
      const SizedBox(height: _sectionGap),
      _buildAlignmentOptions(
        mixed: horizontalAlign.isMixed,
        options: [
          _StyleOption(
            value: TextHorizontalAlign.left,
            label: widget.strings.alignLeft,
            icon: const Icon(Icons.format_align_left),
          ),
          _StyleOption(
            value: TextHorizontalAlign.center,
            label: widget.strings.alignCenter,
            icon: const Icon(Icons.format_align_center),
          ),
          _StyleOption(
            value: TextHorizontalAlign.right,
            label: widget.strings.alignRight,
            icon: const Icon(Icons.format_align_right),
          ),
        ],
        selected: horizontalAlign.value,
        onSelect: onHorizontalSelect,
      ),
    ],
  );

  Widget _buildArrowheadControls({
    required MixedValue<ArrowheadStyle> startArrowhead,
    required MixedValue<ArrowheadStyle> endArrowhead,
    required ArrowheadStyle startDefault,
    required ArrowheadStyle endDefault,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader(widget.strings.arrowheads),
      const SizedBox(height: _sectionGap),
      Row(
        children: [
          _buildArrowheadButton(
            label: widget.strings.startArrowhead,
            value: startArrowhead,
            defaultValue: startDefault,
            isStart: true,
            onSelect: (value) => _applyStyleUpdate(startArrowhead: value),
          ),
          const SizedBox(width: 12),
          _buildArrowheadButton(
            label: widget.strings.endArrowhead,
            value: endArrowhead,
            defaultValue: endDefault,
            isStart: false,
            onSelect: (value) => _applyStyleUpdate(endArrowhead: value),
          ),
        ],
      ),
    ],
  );

  Widget _buildArrowheadButton({
    required String label,
    required MixedValue<ArrowheadStyle> value,
    required ArrowheadStyle defaultValue,
    required bool isStart,
    required ValueChanged<ArrowheadStyle> onSelect,
  }) {
    final theme = Theme.of(context);
    final isMixed = value.isMixed;
    final selectedStyle = isMixed ? null : value.value ?? defaultValue;
    final borderColor = theme.colorScheme.outlineVariant;

    return PopupMenuButton<ArrowheadStyle>(
      tooltip: label,
      padding: EdgeInsets.zero,
      onSelected: onSelect,
      itemBuilder: (_) => _buildArrowheadMenuItems(
        selectedStyle: selectedStyle,
        isStart: isStart,
      ),
      child: Container(
        width: _toggleButtonWidth,
        height: _toggleButtonHeight,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(_toggleButtonRadius),
        ),
        child: Center(
          child:
              isMixed
                  ? const Icon(Icons.more_horiz, size: _iconSize)
                  : _ArrowheadIcon(
                    style: selectedStyle ?? defaultValue,
                    isStart: isStart,
                    size: _iconSize,
                  ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<ArrowheadStyle>> _buildArrowheadMenuItems({
    required ArrowheadStyle? selectedStyle,
    required bool isStart,
  }) => [
    for (final style in ArrowheadStyle.values)
      CheckedPopupMenuItem<ArrowheadStyle>(
        value: style,
        checked: selectedStyle == style,
        child: Row(
          children: [
            _ArrowheadIcon(style: style, isStart: isStart, size: _iconSize),
            const SizedBox(width: 8),
            Text(_arrowheadLabel(style)),
          ],
        ),
      ),
  ];

  String _arrowheadLabel(ArrowheadStyle style) {
    switch (style) {
      case ArrowheadStyle.none:
        return widget.strings.arrowheadNone;
      case ArrowheadStyle.standard:
        return widget.strings.arrowheadStandard;
      case ArrowheadStyle.triangle:
        return widget.strings.arrowheadTriangle;
      case ArrowheadStyle.square:
        return widget.strings.arrowheadSquare;
      case ArrowheadStyle.circle:
        return widget.strings.arrowheadCircle;
      case ArrowheadStyle.diamond:
        return widget.strings.arrowheadDiamond;
      case ArrowheadStyle.invertedTriangle:
        return widget.strings.arrowheadInvertedTriangle;
      case ArrowheadStyle.verticalLine:
        return widget.strings.arrowheadVerticalLine;
    }
  }

  Widget _buildAlignmentOptions<T>({
    required bool mixed,
    required List<_StyleOption<T>> options,
    required T? selected,
    required ValueChanged<T> onSelect,
  }) {
    final selectedValues = options
        .map((option) => !mixed && selected == option.value)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToggleButtons(
          isSelected: selectedValues,
          onPressed: (index) => onSelect(options[index].value),
          borderRadius: BorderRadius.circular(_toggleButtonRadius),
          constraints: const BoxConstraints.tightFor(
            height: _toggleButtonHeight,
            width: _toggleButtonWidth,
          ),
          children: options
              .map(
                (option) => Tooltip(message: option.label, child: option.icon),
              )
              .toList(),
        ),
      ],
    );
  }

  List<String> _resolveSupportedFontFamilies() => _systemFontFamilies;

  bool _containsFontFamily(List<String> families, String family) {
    final target = family.toLowerCase();
    return families.any((value) => value.toLowerCase() == target);
  }

  Widget _buildNumericOptions({
    required String label,
    required bool mixed,
    required String mixedLabel,
    required List<_StyleOption<double>> options,
    required double? selected,
    required ValueChanged<double> onSelect,
  }) {
    final selectedValues = options
        .map(
          (option) =>
              !mixed &&
              selected != null &&
              _doubleEquals(selected, option.value),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label),
        const SizedBox(height: _sectionGap),
        ToggleButtons(
          isSelected: selectedValues,
          onPressed: (index) => onSelect(options[index].value),
          borderRadius: BorderRadius.circular(_toggleButtonRadius),
          constraints: const BoxConstraints.tightFor(
            height: _toggleButtonHeight,
            width: _toggleButtonWidth,
          ),
          children: options
              .map(
                (option) => Tooltip(message: option.label, child: option.icon),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildOpacityControl(
    MixedValue<double> opacity,
    double defaultOpacity, {
    double? pendingValue,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    final baseOpacity = opacity.valueOr(defaultOpacity);
    final resolvedOpacity = pendingValue ?? baseOpacity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(widget.strings.opacity),
        const SizedBox(height: _sectionGap),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: _sliderTrackHeight,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: _sliderThumbRadius,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: _sliderOverlayRadius,
                  ),
                  trackShape: _NoPaddingTrackShape(),
                ),
                child: Slider(
                  value: resolvedOpacity.clamp(0, 1),
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayerControls(bool hasSelection) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader(widget.strings.layerOrder),
      const SizedBox(height: _sectionGap),
      Row(
        children: [
          _buildOutlinedIconButton(
            icon: Icons.keyboard_double_arrow_down,
            message: widget.strings.sendToBack,
            onPressed: hasSelection
                ? () => _handleZOrder(ZIndexOperation.sendToBack)
                : null,
          ),
          const SizedBox(width: 12),
          _buildOutlinedIconButton(
            icon: Icons.keyboard_arrow_down,
            message: widget.strings.sendBackward,
            onPressed: hasSelection
                ? () => _handleZOrder(ZIndexOperation.sendBackward)
                : null,
          ),
          const SizedBox(width: 12),
          _buildOutlinedIconButton(
            icon: Icons.keyboard_arrow_up,
            message: widget.strings.bringForward,
            onPressed: hasSelection
                ? () => _handleZOrder(ZIndexOperation.bringForward)
                : null,
          ),
          const SizedBox(width: 12),
          _buildOutlinedIconButton(
            icon: Icons.keyboard_double_arrow_up,
            message: widget.strings.bringToFront,
            onPressed: hasSelection
                ? () => _handleZOrder(ZIndexOperation.bringToFront)
                : null,
          ),
        ],
      ),
    ],
  );

  Widget _buildSliderControl({
    required String label,
    required double min,
    required double max,
    required MixedValue<double> value,
    required double defaultValue,
    required ValueChanged<double> onChanged,
    double? pendingValue,
    ValueChanged<double>? onChangeEnd,
  }) {
    final baseValue = value.valueOr(defaultValue);
    final resolvedValue = pendingValue ?? baseValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label),
        const SizedBox(height: _sectionGap),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: _sliderTrackHeight,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: _sliderThumbRadius,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: _sliderOverlayRadius,
                  ),
                  trackShape: _NoPaddingTrackShape(),
                ),
                child: Slider(
                  value: resolvedValue.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutlinedIconButton({
    required String message,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton.outlined(
    onPressed: onPressed,
    icon: Icon(icon, size: _iconSize),
    tooltip: message,
    visualDensity: VisualDensity.compact,
  );

  Widget _buildSectionHeader(String label) {
    final theme = Theme.of(context);
    return Row(children: [Text(label, style: theme.textTheme.labelMedium)]);
  }

  Future<Color?> _showColorPicker(
    Color initial, {
    required bool allowAlpha,
    required String label,
  }) => showDialog<Color>(
    context: context,
    builder: (context) {
      var current = initial;
      return AlertDialog(
        title: Text(label),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: current,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _colorToHex(current, allowAlpha),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildColorSlider(
                label: 'R',
                value: _channelToSlider(current.r),
                onChanged: (value) => setDialogState(() {
                  current = Color.fromARGB(
                    _channelFromUnit(current.a),
                    value.round(),
                    _channelFromUnit(current.g),
                    _channelFromUnit(current.b),
                  );
                }),
              ),
              _buildColorSlider(
                label: 'G',
                value: _channelToSlider(current.g),
                onChanged: (value) => setDialogState(() {
                  current = Color.fromARGB(
                    _channelFromUnit(current.a),
                    _channelFromUnit(current.r),
                    value.round(),
                    _channelFromUnit(current.b),
                  );
                }),
              ),
              _buildColorSlider(
                label: 'B',
                value: _channelToSlider(current.b),
                onChanged: (value) => setDialogState(() {
                  current = Color.fromARGB(
                    _channelFromUnit(current.a),
                    _channelFromUnit(current.r),
                    _channelFromUnit(current.g),
                    value.round(),
                  );
                }),
              ),
              if (allowAlpha)
                _buildColorSlider(
                  label: 'A',
                  value: _channelToSlider(current.a),
                  onChanged: (value) => setDialogState(() {
                    current = Color.fromARGB(
                      value.round(),
                      _channelFromUnit(current.r),
                      _channelFromUnit(current.g),
                      _channelFromUnit(current.b),
                    );
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(current),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      );
    },
  );

  Widget _buildColorSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: _sliderTrackHeight,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: _sliderThumbRadius,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: _sliderOverlayRadius,
                ),
                trackShape: _NoPaddingTrackShape(),
              ),
              child: Slider(
                value: value.clamp(0, 255),
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  bool _colorEquals(Color a, Color b) => a == b;

  MixedValue<T> _mergeMixedValues<T>(
    MixedValue<T> first,
    MixedValue<T> second,
    bool Function(T, T) equals,
  ) {
    if (first.isMixed || second.isMixed) {
      return const MixedValue(value: null, isMixed: true);
    }
    final firstValue = first.value;
    final secondValue = second.value;
    if (firstValue == null || secondValue == null) {
      return const MixedValue(value: null, isMixed: true);
    }
    if (!equals(firstValue, secondValue)) {
      return const MixedValue(value: null, isMixed: true);
    }
    return MixedValue(value: firstValue, isMixed: false);
  }

  bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.01;

  void _scheduleStyleUpdate(Future<void> Function() action) {
    _sliderUpdateTimer?.cancel();
    _sliderUpdateTimer = Timer(_sliderDebounceDuration, () async {
      if (!mounted) {
        return;
      }
      await action();
    });
  }

  void _flushStyleUpdate() {
    _sliderUpdateTimer?.cancel();
    _sliderUpdateTimer = null;
  }

  int _channelFromUnit(double value) => (value * 255).round().clamp(0, 255);

  double _channelToSlider(double value) => _channelFromUnit(value).toDouble();

  String _colorToHex(Color color, bool allowAlpha) {
    final r = _channelFromUnit(color.r).toRadixString(16).padLeft(2, '0');
    final g = _channelFromUnit(color.g).toRadixString(16).padLeft(2, '0');
    final b = _channelFromUnit(color.b).toRadixString(16).padLeft(2, '0');
    if (allowAlpha) {
      final a = _channelFromUnit(color.a).toRadixString(16).padLeft(2, '0');
      return '#$a$r$g$b'.toUpperCase();
    }
    return '#$r$g$b'.toUpperCase();
  }

  String _quickColorName(Color color) {
    switch (color.toARGB32()) {
      case 0x00000000:
        return 'Transparent';
      case 0xFF1E1E1E:
        return 'Black';
      case 0xFFF5222D:
        return 'Red';
      case 0xFF52C41A:
        return 'Green';
      case 0xFF1677FF:
        return 'Blue';
      case 0xFFFAAD14:
        return 'Yellow';
      case 0xFFFFCCC7:
        return 'Light red';
      case 0xFFD9F7BE:
        return 'Light green';
      case 0xFFBAE0FF:
        return 'Light blue';
      case 0xFFFFF1B8:
        return 'Light yellow';
      default:
        return _colorToHex(color, false);
    }
  }

  Future<void> _applyStyleUpdate({
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
  }) => widget.adapter.applyStyleUpdate(
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
    toolType: widget.toolController.value,
  );

  Future<void> _handleCopy() => widget.adapter.copySelection();

  Future<void> _handleDelete() => widget.adapter.deleteSelection();

  Future<void> _handleZOrder(ZIndexOperation operation) =>
      widget.adapter.changeZOrder(operation);
}

@immutable
class _StyleOption<T> {
  const _StyleOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final Widget icon;
}

class _ArrowTypeIcon extends StatelessWidget {
  const _ArrowTypeIcon({
    required this.arrowType,
    required this.size,
  });

  final ArrowType arrowType;
  final double size;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<ArrowType>('arrowType', arrowType))
      ..add(DoubleProperty('size', size));
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ArrowTypeIconPainter(
          arrowType: arrowType,
          color: color,
        ),
      ),
    );
  }
}

class _ArrowTypeIconPainter extends CustomPainter {
  const _ArrowTypeIconPainter({
    required this.arrowType,
    required this.color,
  });

  final ArrowType arrowType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(1, size.shortestSide * 0.08).toDouble();
    final padding = size.shortestSide * 0.2;
    final points = _buildPoints(size, padding);
    final path = ArrowGeometry.buildShaftPath(
      points: points,
      arrowType: arrowType,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);

    final direction =
        ArrowGeometry.resolveEndDirection(points, arrowType) ??
        const Offset(1, 0);
    final arrowheadPath = ArrowGeometry.buildArrowheadPath(
      tip: points.last,
      direction: direction,
      style: ArrowheadStyle.standard,
      strokeWidth: strokeWidth,
    );
    canvas.drawPath(arrowheadPath, paint);
  }

  List<Offset> _buildPoints(Size size, double padding) {
    final width = size.width;
    final height = size.height;
    switch (arrowType) {
      case ArrowType.straight:
        return [
          Offset(padding, height * 0.7),
          Offset(width - padding, height * 0.3),
        ];
      case ArrowType.curved:
        return [
          Offset(padding, height * 0.7),
          Offset(width * 0.5, height * 0.2),
          Offset(width - padding, height * 0.7),
        ];
      case ArrowType.polyline:
        return [
          Offset(padding, height * 0.75),
          Offset(width - padding, height * 0.25),
        ];
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowTypeIconPainter oldDelegate) =>
      oldDelegate.arrowType != arrowType || oldDelegate.color != color;
}

class _ArrowheadIcon extends StatelessWidget {
  const _ArrowheadIcon({
    required this.style,
    required this.isStart,
    required this.size,
  });

  final ArrowheadStyle style;
  final bool isStart;
  final double size;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<ArrowheadStyle>('style', style))
      ..add(DiagnosticsProperty<bool>('isStart', isStart))
      ..add(DoubleProperty('size', size));
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ArrowheadIconPainter(
          style: style,
          isStart: isStart,
          color: color,
        ),
      ),
    );
  }
}

class _ArrowheadIconPainter extends CustomPainter {
  const _ArrowheadIconPainter({
    required this.style,
    required this.isStart,
    required this.color,
  });

  final ArrowheadStyle style;
  final bool isStart;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(1, size.shortestSide * 0.08).toDouble();
    final padding = size.shortestSide * 0.2;
    final centerY = size.height / 2;
    final start = Offset(padding, centerY);
    final end = Offset(size.width - padding, centerY);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    canvas.drawLine(start, end, paint);
    if (style == ArrowheadStyle.none) {
      return;
    }

    final tip = isStart ? start : end;
    final direction = isStart ? const Offset(-1, 0) : const Offset(1, 0);
    final path = ArrowGeometry.buildArrowheadPath(
      tip: tip,
      direction: direction,
      style: style,
      strokeWidth: strokeWidth,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowheadIconPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.isStart != isStart ||
      oldDelegate.color != color;
}

class _NoPaddingTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    Offset offset = Offset.zero,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight!;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

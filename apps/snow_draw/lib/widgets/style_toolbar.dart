import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import '../icons/svg_icons.dart';
import '../l10n/app_localizations.dart';
import '../property_descriptor.dart';
import '../property_registry.dart';
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
  static const double _numberControlHeight = 32;
  static const double _numberControlRadius = 8;
  static const double _numberStepperWidth = 32;
  static const double _numberControlTargetWidth = 140;
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
  static const _highlightColorPalette = [
    Colors.transparent,
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
  double? _pendingMaskOpacity;
  int? _pendingSerialNumber;
  late final TextEditingController _serialNumberController;
  late final FocusNode _serialNumberFocusNode;
  List<String> _systemFontFamilies = const [];
  var _fontLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _serialNumberController = TextEditingController();
    _serialNumberFocusNode = FocusNode();
    _serialNumberFocusNode.addListener(_handleSerialNumberFocusChange);
    _mergedListenable = Listenable.merge([
      widget.toolController,
      widget.adapter.stateListenable,
    ]);
  }

  @override
  void dispose() {
    _sliderUpdateTimer?.cancel();
    _scrollController.dispose();
    _serialNumberController.dispose();
    _serialNumberFocusNode
      ..removeListener(_handleSerialNumberFocusChange)
      ..dispose();
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

  void _commitSerialNumberValue(int next) {
    final sanitized = next < 0 ? 0 : next;
    setState(() => _pendingSerialNumber = null);
    _serialNumberController.text = sanitized.toString();
    unawaited(_applyStyleUpdate(serialNumber: sanitized));
  }

  void _handleSerialNumberFocusChange() {
    if (_serialNumberFocusNode.hasFocus) {
      return;
    }
    if (_pendingSerialNumber == null) {
      return;
    }
    final parsed = int.tryParse(_serialNumberController.text);
    if (parsed != null) {
      _commitSerialNumberValue(parsed);
    } else {
      setState(() => _pendingSerialNumber = null);
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
      final showHighlightControls =
          tool == ToolType.highlight || state.hasSelectedHighlights;
      final showArrowControls =
          tool == ToolType.arrow || state.hasSelectedArrows;
      final showLineControls = tool == ToolType.line || state.hasSelectedLines;
      final showFreeDrawControls =
          tool == ToolType.freeDraw || state.hasSelectedFreeDraws;
      final showTextControls = tool == ToolType.text || state.hasSelectedTexts;
      final showSerialNumberControls =
          tool == ToolType.serialNumber || state.hasSelectedSerialNumbers;
      final showToolbar =
          showRectangleControls ||
          showHighlightControls ||
          showArrowControls ||
          showLineControls ||
          showFreeDrawControls ||
          showTextControls ||
          showSerialNumberControls;
      if (showTextControls || showSerialNumberControls) {
        _requestSystemFonts();
      }
      final maxHeight = math
          .max(0, widget.size.height - widget.topInset - widget.bottomInset)
          .toDouble();
      final resolvedWidth = widget.width;
      final hasSelection = state.hasSelection;

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
                    // This is the new children array content to replace
                    // lines 276-914
                    children: [
                      // Build property controls using the property-centric
                      // approach
                      ...() {
                        final propertyContext = _createPropertyContext(state);
                        final applicableProperties = _getApplicableProperties(
                          state,
                        );
                        final widgets = <Widget>[];

                        for (var i = 0; i < applicableProperties.length; i++) {
                          final property = applicableProperties[i];
                          final widget = _buildPropertyWidget(
                            property,
                            propertyContext,
                            state,
                          );

                          if (widget != null) {
                            if (widgets.isNotEmpty) {
                              widgets.add(
                                const SizedBox(height: _sectionSpacing),
                              );
                            }
                            widgets.add(widget);
                          }
                        }

                        return widgets;
                      }(),
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

  Widget _buildSerialNumberControl({
    required MixedValue<int> value,
    required int defaultValue,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMixed = value.isMixed && _pendingSerialNumber == null;
    final resolvedValue = _pendingSerialNumber ?? value.valueOr(defaultValue);
    final displayText = isMixed ? '' : resolvedValue.toString();

    if (!_serialNumberFocusNode.hasFocus &&
        _serialNumberController.text != displayText) {
      _serialNumberController.text = displayText;
    }

    final canDecrement = resolvedValue > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(widget.strings.number),
        const SizedBox(height: _sectionGap),
        LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: math.min(constraints.maxWidth, _numberControlTargetWidth),
              child: AnimatedBuilder(
                animation: _serialNumberFocusNode,
                builder: (context, _) {
                  final hasFocus = _serialNumberFocusNode.hasFocus;
                  final borderColor = hasFocus
                      ? scheme.primary
                      : scheme.outlineVariant;
                  final fillColor = hasFocus
                      ? Color.alphaBlend(
                          scheme.primary.withValues(alpha: 0.06),
                          scheme.surface,
                        )
                      : scheme.surface;
                  final dividerColor = hasFocus
                      ? scheme.primary.withValues(alpha: 0.55)
                      : scheme.outlineVariant.withValues(alpha: 0.7);

                  return Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) {
                        return;
                      }
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (event) {
                          if (event is! PointerScrollEvent) {
                            return;
                          }
                          if (event.scrollDelta.dy == 0) {
                            return;
                          }
                          final next = event.scrollDelta.dy < 0
                              ? resolvedValue + 1
                              : resolvedValue - 1;
                          _commitSerialNumberValue(next);
                        },
                      );
                    },
                    child: Container(
                      height: _numberControlHeight,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(
                          _numberControlRadius,
                        ),
                        border: Border.all(color: borderColor),
                        boxShadow: hasFocus
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.18),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          _buildSerialNumberStepperButton(
                            icon: Icons.remove_rounded,
                            tooltip: widget.strings.decrease,
                            onPressed: canDecrement
                                ? () => _commitSerialNumberValue(
                                    resolvedValue - 1,
                                  )
                                : null,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(_numberControlRadius),
                            ),
                          ),
                          _buildSerialNumberDivider(dividerColor),
                          Expanded(
                            child: TextField(
                              controller: _serialNumberController,
                              focusNode: _serialNumberFocusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: isMixed ? widget.strings.mixed : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                              onChanged: (text) {
                                final parsed = int.tryParse(text);
                                setState(() => _pendingSerialNumber = parsed);
                              },
                              onSubmitted: (text) {
                                final parsed = int.tryParse(text);
                                if (parsed != null) {
                                  _commitSerialNumberValue(parsed);
                                } else {
                                  setState(() => _pendingSerialNumber = null);
                                }
                              },
                              onEditingComplete: () {
                                final parsed = int.tryParse(
                                  _serialNumberController.text,
                                );
                                if (parsed != null) {
                                  _commitSerialNumberValue(parsed);
                                } else {
                                  setState(() => _pendingSerialNumber = null);
                                }
                              },
                            ),
                          ),
                          _buildSerialNumberDivider(dividerColor),
                          _buildSerialNumberStepperButton(
                            icon: Icons.add_rounded,
                            tooltip: widget.strings.increase,
                            onPressed: () =>
                                _commitSerialNumberValue(resolvedValue + 1),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(_numberControlRadius),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSerialNumberStepperButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required BorderRadius borderRadius,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;
    final fillColor = isEnabled
        ? scheme.surface
        : scheme.surface.withValues(alpha: 0.7);
    final iconColor = isEnabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _numberStepperWidth,
        height: double.infinity,
        child: Material(
          color: fillColor,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(icon, size: _iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSerialNumberDivider(Color color) =>
      Container(width: 1, height: double.infinity, color: color);

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

    return Tooltip(
      message: label,
      child: Builder(
        builder: (context) => InkWell(
          onTap: () async {
            final button = context.findRenderObject()! as RenderBox;
            final overlay =
                Navigator.of(context).overlay!.context.findRenderObject()!
                    as RenderBox;
            final position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(Offset.zero, ancestor: overlay),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );

            final result = await showMenu<ArrowheadStyle>(
              context: context,
              position: position,
              color: theme.colorScheme.surface,
              items: [
                PopupMenuItem<ArrowheadStyle>(
                  enabled: false,
                  padding: EdgeInsets.zero,
                  child: _buildArrowheadPopoverContent(
                    selectedStyle: selectedStyle,
                    isStart: isStart,
                    onSelect: (style) {
                      Navigator.of(context).pop(style);
                    },
                  ),
                ),
              ],
            );

            if (result != null) {
              onSelect(result);
            }
          },
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_toggleButtonRadius),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: borderColor,
              borderRadius: _toggleButtonRadius,
            ),
            child: Container(
              width: _toggleButtonHeight,
              height: _toggleButtonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_toggleButtonRadius),
              ),
              child: Center(
                child: isMixed
                    ? const Icon(Icons.more_horiz, size: _iconSize)
                    : _buildArrowheadIcon(
                        style: selectedStyle ?? defaultValue,
                        isStart: isStart,
                        size: _iconSize,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrowheadPopoverContent({
    required ArrowheadStyle? selectedStyle,
    required bool isStart,
    required ValueChanged<ArrowheadStyle> onSelect,
  }) {
    final theme = Theme.of(context);
    const styles = ArrowheadStyle.values;

    // Create 2 rows with 4 items each
    final rows = <List<ArrowheadStyle>>[];
    for (var i = 0; i < styles.length; i += 4) {
      rows.add(styles.sublist(i, math.min(i + 4, styles.length)));
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows[rowIndex].length; i++) ...[
                    Tooltip(
                      message: _arrowheadLabel(rows[rowIndex][i]),
                      child: InkWell(
                        onTap: () => onSelect(rows[rowIndex][i]),
                        borderRadius: BorderRadius.circular(
                          _toggleButtonRadius,
                        ),
                        child: Container(
                          width: _toggleButtonHeight,
                          height: _toggleButtonHeight,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedStyle == rows[rowIndex][i]
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: selectedStyle == rows[rowIndex][i] ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(
                              _toggleButtonRadius,
                            ),
                            color: selectedStyle == rows[rowIndex][i]
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  )
                                : null,
                          ),
                          child: Center(
                            child: _buildArrowheadIcon(
                              style: rows[rowIndex][i],
                              isStart: isStart,
                              size: _iconSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (i < rows[rowIndex].length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
              if (rowIndex < rows.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArrowheadIcon({
    required ArrowheadStyle style,
    required bool isStart,
    required double size,
  }) {
    Widget icon;
    switch (style) {
      case ArrowheadStyle.none:
        icon = ArrowheadNoneIcon(size: size);
      case ArrowheadStyle.standard:
        icon = ArrowheadStandardIcon(size: size);
      case ArrowheadStyle.triangle:
        icon = ArrowheadTriangleIcon(size: size);
      case ArrowheadStyle.square:
        icon = ArrowheadSquareIcon(size: size);
      case ArrowheadStyle.circle:
        icon = ArrowheadCircleIcon(size: size);
      case ArrowheadStyle.diamond:
        icon = ArrowheadDiamondIcon(size: size);
      case ArrowheadStyle.invertedTriangle:
        icon = ArrowheadInvertedTriangleIcon(size: size);
      case ArrowheadStyle.verticalLine:
        icon = ArrowheadVerticalLineIcon(size: size);
    }

    // Flip horizontally for start arrowheads
    if (isStart) {
      return Transform.scale(scaleX: -1, child: icon);
    }
    return icon;
  }

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
    return Text(label, style: theme.textTheme.labelMedium);
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

  /// Create a StylePropertyContext from the current state
  StylePropertyContext _createPropertyContext(StyleToolbarState state) {
    final selectedTypes = <ElementType>{};
    if (state.hasSelectedRectangles) {
      selectedTypes.add(ElementType.rectangle);
    }
    if (state.hasSelectedHighlights) {
      selectedTypes.add(ElementType.highlight);
    }
    if (state.hasSelectedArrows) {
      selectedTypes.add(ElementType.arrow);
    }
    if (state.hasSelectedLines) {
      selectedTypes.add(ElementType.line);
    }
    if (state.hasSelectedFreeDraws) {
      selectedTypes.add(ElementType.freeDraw);
    }
    if (state.hasSelectedTexts) {
      selectedTypes.add(ElementType.text);
    }
    if (state.hasSelectedSerialNumbers) {
      selectedTypes.add(ElementType.serialNumber);
    }

    // If no elements are selected, use the current tool to determine which
    // properties to show (for styling the element to be created)
    if (selectedTypes.isEmpty) {
      final tool = widget.toolController.value;
      switch (tool) {
        case ToolType.rectangle:
          selectedTypes.add(ElementType.rectangle);
        case ToolType.highlight:
          selectedTypes.add(ElementType.highlight);
        case ToolType.arrow:
          selectedTypes.add(ElementType.arrow);
        case ToolType.line:
          selectedTypes.add(ElementType.line);
        case ToolType.freeDraw:
          selectedTypes.add(ElementType.freeDraw);
        case ToolType.text:
          selectedTypes.add(ElementType.text);
        case ToolType.serialNumber:
          selectedTypes.add(ElementType.serialNumber);
        case ToolType.selection:
          break;
      }
    }

    return StylePropertyContext(
      rectangleStyleValues: state.styleValues,
      arrowStyleValues: state.arrowStyleValues,
      lineStyleValues: state.lineStyleValues,
      freeDrawStyleValues: state.freeDrawStyleValues,
      textStyleValues: state.textStyleValues,
      highlightStyleValues: state.highlightStyleValues,
      serialNumberStyleValues: state.serialNumberStyleValues,
      rectangleDefaults: state.rectangleStyle,
      arrowDefaults: state.arrowStyle,
      lineDefaults: state.lineStyle,
      freeDrawDefaults: state.freeDrawStyle,
      textDefaults: state.textStyle,
      highlightDefaults: state.highlightStyle,
      serialNumberDefaults: state.serialNumberStyle,
      highlightMask: state.highlightMask,
      selectedElementTypes: selectedTypes,
      currentTool: widget.toolController.value,
    );
  }

  /// Get the list of properties that should be shown for the current context
  List<PropertyDescriptor<dynamic>> _getApplicableProperties(
    StyleToolbarState state,
  ) {
    final context = _createPropertyContext(state);
    final allProperties = PropertyRegistry.instance.getApplicableProperties(
      context,
    );

    // Filter properties based on conditional visibility rules
    return allProperties.where((property) {
      // Hide fillStyle if fillColor is transparent
      if (property.id == 'fillStyle') {
        final fillColorProp = PropertyRegistry.instance.getProperty(
          'fillColor',
        );
        if (fillColorProp != null) {
          final fillColor =
              fillColorProp.extractValue(context) as MixedValue<Color>;
          final fillColorValue = fillColor.value;
          // Show fillStyle only if color is mixed or has alpha > 0
          if (!fillColor.isMixed &&
              fillColorValue != null &&
              fillColorValue.a == 0) {
            return false;
          }
        }
      }

      // Hide textStrokeColor if textStrokeWidth is 0
      if (property.id == 'textStrokeColor') {
        final textStrokeWidthProp = PropertyRegistry.instance.getProperty(
          'textStrokeWidth',
        );
        if (textStrokeWidthProp != null) {
          final textStrokeWidth =
              textStrokeWidthProp.extractValue(context) as MixedValue<double>;
          final defaultWidth =
              textStrokeWidthProp.getDefaultValue(context) as double;
          // Show textStrokeColor only if width is mixed or > 0
          if (!textStrokeWidth.isMixed &&
              (textStrokeWidth.value ?? defaultWidth) <= 0) {
            return false;
          }
        }
      }

      // Hide highlightTextStrokeColor if highlightTextStrokeWidth is 0
      if (property.id == 'highlightTextStrokeColor') {
        final textStrokeWidthProp = PropertyRegistry.instance.getProperty(
          'highlightTextStrokeWidth',
        );
        if (textStrokeWidthProp != null) {
          final textStrokeWidth =
              textStrokeWidthProp.extractValue(context) as MixedValue<double>;
          final defaultWidth =
              textStrokeWidthProp.getDefaultValue(context) as double;
          if (!textStrokeWidth.isMixed &&
              (textStrokeWidth.value ?? defaultWidth) <= 0) {
            return false;
          }
        }
      }

      // Hide cornerRadius for text if fillColor is transparent
      if (property.id == 'cornerRadius') {
        // Only apply this rule if we have text elements selected
        if (context.selectedElementTypes.contains(ElementType.text)) {
          final fillColorProp = PropertyRegistry.instance.getProperty(
            'fillColor',
          );
          if (fillColorProp != null) {
            final fillColor =
                fillColorProp.extractValue(context) as MixedValue<Color>;
            final fillColorValue = fillColor.value;
            // For text, show cornerRadius only if fillColor is mixed or has
            // alpha > 0
            if (!fillColor.isMixed &&
                fillColorValue != null &&
                fillColorValue.a == 0) {
              return false;
            }
          }
        }
      }

      return true;
    }).toList();
  }

  /// Build the widget for a specific property
  Widget? _buildPropertyWidget(
    PropertyDescriptor<dynamic> property,
    StylePropertyContext context,
    StyleToolbarState state,
  ) {
    switch (property.id) {
      case 'color':
        final value = property.extractValue(context) as MixedValue<Color>;
        final defaultValue = property.getDefaultValue(context) as Color;
        final colors = context.hasOnlySelected({ElementType.highlight})
            ? _highlightColorPalette
            : _defaultColorPalette;
        return _buildColorRow(
          label: widget.strings.color,
          colors: colors,
          value: value,
          customColor: value.valueOr(defaultValue),
          onSelect: (color) => _applyStyleUpdate(color: color),
          allowAlpha: true,
        );

      case 'highlightShape':
        final value =
            property.extractValue(context) as MixedValue<HighlightShape>;
        return _buildStyleOptions<HighlightShape>(
          label: widget.strings.highlightShape,
          mixed: value.isMixed,
          mixedLabel: widget.strings.mixed,
          options: [
            _StyleOption(
              value: HighlightShape.rectangle,
              label: widget.strings.highlightShapeRectangle,
              icon: const Icon(Icons.rectangle_outlined, size: _iconSize),
            ),
            _StyleOption(
              value: HighlightShape.ellipse,
              label: widget.strings.highlightShapeEllipse,
              icon: const Icon(Icons.circle_outlined, size: _iconSize),
            ),
          ],
          selected: value.isMixed ? null : value.value,
          onSelect: (shape) => _applyStyleUpdate(highlightShape: shape),
        );

      case 'highlightTextStrokeWidth':
        final value = property.extractValue(context) as MixedValue<double>;
        return _buildNumericOptions(
          label: widget.strings.highlightTextStrokeWidth,
          mixed: value.isMixed,
          mixedLabel: widget.strings.mixed,
          options: [
            const _StyleOption(
              value: 0,
              label: 'None',
              icon: Icon(Icons.not_interested, size: _iconSize),
            ),
            _StyleOption(
              value: 2,
              label: widget.strings.small,
              icon: const StrokeWidthSmallIcon(),
            ),
            _StyleOption(
              value: 3,
              label: widget.strings.medium,
              icon: const StrokeWidthMediumIcon(),
            ),
            _StyleOption(
              value: 5,
              label: widget.strings.large,
              icon: const StrokeWidthLargeIcon(),
            ),
          ],
          selected: value.value,
          onSelect: (value) => _applyStyleUpdate(textStrokeWidth: value),
        );

      case 'highlightTextStrokeColor':
        final value = property.extractValue(context) as MixedValue<Color>;
        final defaultValue = property.getDefaultValue(context) as Color;
        return _buildColorRow(
          label: widget.strings.highlightTextStrokeColor,
          colors: _defaultColorPalette,
          value: value,
          customColor: value.valueOr(defaultValue),
          onSelect: (color) => _applyStyleUpdate(textStrokeColor: color),
          allowAlpha: true,
        );

      case 'strokeWidth':
        final value = property.extractValue(context) as MixedValue<double>;
        return _buildNumericOptions(
          label: widget.strings.strokeWidth,
          mixed: value.isMixed,
          mixedLabel: widget.strings.mixed,
          options: [
            _StyleOption(
              value: 2,
              label: widget.strings.thin,
              icon: const StrokeWidthSmallIcon(),
            ),
            _StyleOption(
              value: 4,
              label: widget.strings.medium,
              icon: const StrokeWidthMediumIcon(),
            ),
            _StyleOption(
              value: 7,
              label: widget.strings.thick,
              icon: const StrokeWidthLargeIcon(),
            ),
          ],
          selected: value.value,
          onSelect: (value) => _applyStyleUpdate(strokeWidth: value),
        );

      case 'strokeStyle':
        final value = property.extractValue(context) as MixedValue<StrokeStyle>;
        return _buildStyleOptions<StrokeStyle>(
          label: widget.strings.strokeStyle,
          mixed: value.isMixed,
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
          selected: value.isMixed ? null : value.value,
          onSelect: (style) => _applyStyleUpdate(strokeStyle: style),
        );

      case 'fillColor':
        final value = property.extractValue(context) as MixedValue<Color>;
        final defaultValue = property.getDefaultValue(context) as Color;
        return _buildColorRow(
          label: widget.strings.fillColor,
          colors: const [
            Colors.transparent,
            Color(0xFFFFCCC7),
            Color(0xFFD9F7BE),
            Color(0xFFBAE0FF),
            Color(0xFFFFF1B8),
          ],
          value: value,
          customColor: value.valueOr(defaultValue),
          onSelect: (color) => _applyStyleUpdate(fillColor: color),
          allowAlpha: true,
        );

      case 'fillStyle':
        final value = property.extractValue(context) as MixedValue<FillStyle>;
        return _buildStyleOptions<FillStyle>(
          label: widget.strings.fillStyle,
          mixed: value.isMixed,
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
          selected: value.isMixed ? null : value.value,
          onSelect: (style) => _applyStyleUpdate(fillStyle: style),
        );

      case 'cornerRadius':
        final value = property.extractValue(context) as MixedValue<double>;
        final defaultValue = property.getDefaultValue(context) as double;
        return _buildSliderControl(
          label: widget.strings.cornerRadius,
          value: value,
          defaultValue: defaultValue,
          min: 0,
          max: 64,
          pendingValue: _pendingCornerRadius,
          onChanged: (newValue) {
            setState(() => _pendingCornerRadius = newValue);
            _scheduleStyleUpdate(
              () => _applyStyleUpdate(cornerRadius: newValue),
            );
          },
          onChangeEnd: (newValue) async {
            _flushStyleUpdate();
            setState(() => _pendingCornerRadius = null);
            await _applyStyleUpdate(cornerRadius: newValue);
          },
        );

      case 'opacity':
        final value = property.extractValue(context) as MixedValue<double>;
        final defaultValue = property.getDefaultValue(context) as double;
        return _buildSliderControl(
          label: widget.strings.opacity,
          value: value,
          defaultValue: defaultValue,
          min: 0,
          max: 1,
          pendingValue: _pendingOpacity,
          onChanged: (newValue) {
            setState(() => _pendingOpacity = newValue);
            _scheduleStyleUpdate(() => _applyStyleUpdate(opacity: newValue));
          },
          onChangeEnd: (newValue) async {
            _flushStyleUpdate();
            setState(() => _pendingOpacity = null);
            await _applyStyleUpdate(opacity: newValue);
          },
        );

      case 'maskColor':
        final value = property.extractValue(context) as MixedValue<Color>;
        final defaultValue = property.getDefaultValue(context) as Color;
        return _buildColorRow(
          label: widget.strings.maskColor,
          colors: _defaultColorPalette,
          value: value,
          customColor: value.valueOr(defaultValue),
          onSelect: (color) => _applyStyleUpdate(maskColor: color),
          allowAlpha: false,
        );

      case 'maskOpacity':
        final value = property.extractValue(context) as MixedValue<double>;
        final defaultValue = property.getDefaultValue(context) as double;
        return _buildSliderControl(
          label: widget.strings.maskOpacity,
          value: value,
          defaultValue: defaultValue,
          min: 0,
          max: 1,
          pendingValue: _pendingMaskOpacity,
          onChanged: (newValue) {
            setState(() => _pendingMaskOpacity = newValue);
            _scheduleStyleUpdate(
              () => _applyStyleUpdate(maskOpacity: newValue),
            );
          },
          onChangeEnd: (newValue) async {
            _flushStyleUpdate();
            setState(() => _pendingMaskOpacity = null);
            await _applyStyleUpdate(maskOpacity: newValue);
          },
        );

      case 'arrowType':
        final value = property.extractValue(context) as MixedValue<ArrowType>;
        return _buildStyleOptions<ArrowType>(
          label: widget.strings.arrowType,
          mixed: value.isMixed,
          mixedLabel: widget.strings.mixed,
          options: [
            _StyleOption(
              value: ArrowType.straight,
              label: widget.strings.arrowTypeStraight,
              icon: const ArrowTypeStraightIcon(),
            ),
            _StyleOption(
              value: ArrowType.curved,
              label: widget.strings.arrowTypeCurved,
              icon: const ArrowTypeCurvedIcon(),
            ),
            _StyleOption(
              value: ArrowType.elbow,
              label: widget.strings.arrowTypeElbow,
              icon: const ArrowTypeElbowIcon(),
            ),
          ],
          selected: value.value,
          onSelect: (value) => _applyStyleUpdate(arrowType: value),
        );

      case 'startArrowhead':
        // This case is handled together with endArrowhead
        return null;

      case 'endArrowhead':
        // Render both start and end arrowhead controls together
        final startProp = PropertyRegistry.instance.getProperty(
          'startArrowhead',
        );
        final endProp = property;

        if (startProp == null) {
          return null;
        }

        final startValue =
            startProp.extractValue(context) as MixedValue<ArrowheadStyle>;
        final endValue =
            endProp.extractValue(context) as MixedValue<ArrowheadStyle>;
        final startDefault =
            startProp.getDefaultValue(context) as ArrowheadStyle;
        final endDefault = endProp.getDefaultValue(context) as ArrowheadStyle;

        return _buildArrowheadControls(
          startArrowhead: startValue,
          endArrowhead: endValue,
          startDefault: startDefault,
          endDefault: endDefault,
        );

      case 'serialNumber':
        final value = property.extractValue(context) as MixedValue<int>;
        final defaultValue = property.getDefaultValue(context) as int;
        return _buildSerialNumberControl(
          value: value,
          defaultValue: defaultValue,
        );

      case 'fontSize':
        final value = property.extractValue(context) as MixedValue<double>;
        return _buildStyleOptions<double>(
          label: widget.strings.fontSize,
          mixed: value.isMixed,
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
          selected: value.isMixed ? null : value.value,
          onSelect: (size) => _applyStyleUpdate(fontSize: size),
        );

      case 'fontFamily':
        final value = property.extractValue(context) as MixedValue<String>;
        return _buildFontFamilyControl(
          value: value,
          onSelect: (family) => _applyStyleUpdate(fontFamily: family),
        );

      case 'textAlign':
        final value =
            property.extractValue(context) as MixedValue<TextHorizontalAlign>;
        return _buildTextAlignmentControl(
          horizontalAlign: value,
          onHorizontalSelect: (align) => _applyStyleUpdate(textAlign: align),
        );

      case 'textStrokeWidth':
        final value = property.extractValue(context) as MixedValue<double>;
        return _buildNumericOptions(
          label: widget.strings.textStrokeWidth,
          mixed: value.isMixed,
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
          selected: value.value,
          onSelect: (value) => _applyStyleUpdate(textStrokeWidth: value),
        );

      case 'textStrokeColor':
        final value = property.extractValue(context) as MixedValue<Color>;
        final defaultValue = property.getDefaultValue(context) as Color;
        return _buildColorRow(
          label: widget.strings.textStrokeColor,
          colors: const [
            Color(0xFFF8F4EC),
            Color(0xFF1CA7A8),
            Color(0xFFE45C9D),
            Color(0xFFF4A261),
            Color(0xFF1D3557),
          ],
          value: value,
          customColor: value.valueOr(defaultValue),
          onSelect: (color) => _applyStyleUpdate(textStrokeColor: color),
          allowAlpha: true,
        );

      default:
        return null;
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
    HighlightShape? highlightShape,
    Color? maskColor,
    double? maskOpacity,
    int? serialNumber,
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
    highlightShape: highlightShape,
    maskColor: maskColor,
    maskOpacity: maskOpacity,
    serialNumber: serialNumber,
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

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.borderRadius});

  final Color color;
  final double borderRadius;
  final strokeWidth = 1.0;
  final dashWidth = 4.0;
  final dashSpace = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(borderRadius),
        ),
      );

    final dashPath = _createDashedPath(path);
    canvas.drawPath(dashPath, paint);
  }

  Path _createDashedPath(Path source) {
    final dashedPath = Path();
    final metricsIterator = source.computeMetrics().iterator;

    while (metricsIterator.moveNext()) {
      final metric = metricsIterator.current;
      var distance = 0.0;

      while (distance < metric.length) {
        final nextDistance = distance + dashWidth;
        final extractPath = metric.extractPath(
          distance,
          nextDistance > metric.length ? metric.length : nextDistance,
        );
        dashedPath.addPath(extractPath, Offset.zero);
        distance = nextDistance + dashSpace;
      }
    }

    return dashedPath;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashSpace != dashSpace;
}

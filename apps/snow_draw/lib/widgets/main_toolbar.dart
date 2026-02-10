import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../tool_controller.dart';

class MainToolbar extends StatefulWidget {
  const MainToolbar({
    required this.strings,
    required this.toolController,
    super.key,
  });

  final AppLocalizations strings;
  final ToolController toolController;

  @override
  State<MainToolbar> createState() => _MainToolbarState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      );
  }
}

class _MainToolbarState extends State<MainToolbar> {
  static const double _buttonSize = 40;
  static const double _buttonRadius = 12;
  static const double _buttonGap = 2;
  static const double _dividerGap = 8;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.toolController,
    builder: (context, _) {
      final theme = Theme.of(context);
      final tool = widget.toolController.value;
      final isSelection = tool == ToolType.selection;
      final isRectangle = tool == ToolType.rectangle;
      final isHighlight = tool == ToolType.highlight;
      final isFilter = tool == ToolType.filter;
      final isArrow = tool == ToolType.arrow;
      final isLine = tool == ToolType.line;
      final isFreeDraw = tool == ToolType.freeDraw;
      final isText = tool == ToolType.text;
      final isSerialNumber = tool == ToolType.serialNumber;
      final selectedColor = theme.colorScheme.primary;
      final unselectedColor = theme.iconTheme.color ?? Colors.black;
      final selectedBackground = selectedColor.withValues(alpha: 0.12);
      final dividerColor = theme.colorScheme.outlineVariant.withValues(
        alpha: 0.6,
      );

      return Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolButton(
                tooltip: widget.strings.toolSelection,
                icon: Icons.near_me_outlined,
                selected: isSelection,
                onPressed: () =>
                    widget.toolController.setTool(ToolType.selection),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              _buildDivider(dividerColor),
              _buildToolButton(
                tooltip: widget.strings.toolRectangle,
                icon: Icons.rectangle_outlined,
                selected: isRectangle,
                onPressed: () =>
                    widget.toolController.setTool(ToolType.rectangle),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolArrow,
                icon: Icons.arrow_right_alt,
                selected: isArrow,
                onPressed: () => widget.toolController.setTool(ToolType.arrow),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolLine,
                icon: Icons.show_chart,
                selected: isLine,
                onPressed: () => widget.toolController.setTool(ToolType.line),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolFreeDraw,
                icon: Icons.brush_outlined,
                selected: isFreeDraw,
                onPressed: () =>
                    widget.toolController.setTool(ToolType.freeDraw),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolHighlight,
                icon: Icons.highlight,
                selected: isHighlight,
                onPressed: () =>
                    widget.toolController.setTool(ToolType.highlight),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolText,
                icon: Icons.text_fields,
                selected: isText,
                onPressed: () => widget.toolController.setTool(ToolType.text),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolSerialNumber,
                icon: Icons.looks_one_outlined,
                selected: isSerialNumber,
                onPressed: () =>
                    widget.toolController.setTool(ToolType.serialNumber),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              const SizedBox(width: _buttonGap),
              _buildToolButton(
                tooltip: widget.strings.toolFilter,
                icon: Icons.auto_fix_high,
                selected: isFilter,
                onPressed: () => widget.toolController.setTool(ToolType.filter),
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildToolButton({
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
    required Color selectedColor,
    required Color unselectedColor,
    required Color selectedBackground,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_buttonRadius),
      ),
      minimumSize: const Size(_buttonSize, _buttonSize),
      fixedSize: const Size(_buttonSize, _buttonSize),
      padding: EdgeInsets.zero,
      foregroundColor: selected ? selectedColor : unselectedColor,
      backgroundColor: selected ? selectedBackground : Colors.transparent,
    ),
  );

  Widget _buildDivider(Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _dividerGap),
    child: Container(width: 1, height: 20, color: color),
  );
}

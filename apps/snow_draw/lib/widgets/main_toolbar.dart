import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../tool_controller.dart';

class MainToolbar extends StatelessWidget {
  const MainToolbar({
    required this.strings,
    required this.toolController,
    super.key,
  });

  final AppLocalizations strings;
  final ToolController toolController;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      );
  }

  static const double _buttonSize = 40;
  static const double _buttonRadius = 12;
  static const double _buttonGap = 2;
  static const double _dividerGap = 8;
  static const double _iconSize = 18;
  static const _toolDescriptors = <_ToolDescriptor>[
    _ToolDescriptor(type: ToolType.selection, icon: Icons.near_me_outlined),
    _ToolDescriptor(type: ToolType.rectangle, icon: Icons.rectangle_outlined),
    _ToolDescriptor(type: ToolType.arrow, icon: Icons.arrow_right_alt),
    _ToolDescriptor(type: ToolType.line, icon: Icons.show_chart),
    _ToolDescriptor(type: ToolType.freeDraw, icon: Icons.brush_outlined),
    _ToolDescriptor(type: ToolType.highlight, icon: Icons.highlight),
    _ToolDescriptor(type: ToolType.text, icon: Icons.text_fields),
    _ToolDescriptor(
      type: ToolType.serialNumber,
      icon: Icons.looks_one_outlined,
    ),
    _ToolDescriptor(type: ToolType.filter, icon: Icons.auto_fix_high),
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: toolController,
    builder: (context, _) {
      final theme = Theme.of(context);
      final tool = toolController.value;
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
                descriptor: _toolDescriptors.first,
                currentTool: tool,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              _buildDivider(dividerColor),
              for (var i = 1; i < _toolDescriptors.length; i++) ...[
                if (i > 1) const SizedBox(width: _buttonGap),
                _buildToolButton(
                  descriptor: _toolDescriptors[i],
                  currentTool: tool,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  selectedBackground: selectedBackground,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _buildToolButton({
    required _ToolDescriptor descriptor,
    required ToolType currentTool,
    required Color selectedColor,
    required Color unselectedColor,
    required Color selectedBackground,
  }) {
    final selected = currentTool == descriptor.type;
    return IconButton(
      tooltip: _tooltipForTool(strings, descriptor.type),
      onPressed: () => toolController.setTool(descriptor.type),
      icon: Icon(descriptor.icon, size: _iconSize),
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
  }

  Widget _buildDivider(Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _dividerGap),
    child: Container(width: 1, height: 20, color: color),
  );

  String _tooltipForTool(AppLocalizations strings, ToolType toolType) {
    switch (toolType) {
      case ToolType.selection:
        return strings.toolSelection;
      case ToolType.rectangle:
        return strings.toolRectangle;
      case ToolType.arrow:
        return strings.toolArrow;
      case ToolType.line:
        return strings.toolLine;
      case ToolType.freeDraw:
        return strings.toolFreeDraw;
      case ToolType.highlight:
        return strings.toolHighlight;
      case ToolType.text:
        return strings.toolText;
      case ToolType.serialNumber:
        return strings.toolSerialNumber;
      case ToolType.filter:
        return strings.toolFilter;
    }
  }
}

@immutable
class _ToolDescriptor {
  const _ToolDescriptor({required this.type, required this.icon});

  final ToolType type;
  final IconData icon;
}
